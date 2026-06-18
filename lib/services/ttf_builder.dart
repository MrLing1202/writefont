import 'dart:typed_data';
import 'dart:convert';
import '../models/project.dart';

/// A complete TrueType font file builder.
/// Generates valid .ttf files from glyph contour data.
class TtfBuilder {
  final List<GlyphData> glyphs;
  final String familyName;
  final int unitsPerEm;

  late final ByteData _buffer;
  final List<int> _tableOffsets = [];
  final Map<String, List<int>> _tables = {};

  TtfBuilder({
    required this.glyphs,
    this.familyName = 'WriteFont',
    this.unitsPerEm = 1000,
  });

  /// Build a complete TTF file and return the bytes.
  Uint8List build() {
    // Ensure .notdef glyph exists at index 0
    _ensureNotdefGlyph();

    // Build all tables
    _buildHead();
    _buildMaxp();
    _buildGlyf();
    _buildLoca();
    _buildHhea();
    _buildHmtx();
    _buildCmap();
    _buildName();
    _buildOs2();
    _buildPost();

    // Calculate total size
    final numTables = _tables.length;
    final headerSize = 12 + numTables * 16;
    int totalSize = headerSize;

    // Align tables to 4-byte boundaries
    final tableInfos = <_TableInfo>[];
    int offset = headerSize;
    for (final entry in _tables.entries) {
      final paddedSize = (entry.value.length + 3) & ~3;
      tableInfos.add(_TableInfo(entry.key, offset, entry.value.length, paddedSize));
      offset += paddedSize;
    }
    totalSize = offset;

    // Write the file
    final data = ByteData(totalSize);
    int pos = 0;

    // Write offset table (header)
    data.setUint32(pos, 0x00010000); pos += 4; // sfVersion
    data.setUint16(pos, numTables); pos += 2; // numTables

    // Search range, entry selector, range shift
    int searchRange = 1;
    int entrySelector = 0;
    while (searchRange * 2 <= numTables) {
      searchRange *= 2;
      entrySelector++;
    }
    searchRange *= 16;
    data.setUint16(pos, searchRange); pos += 2;
    data.setUint16(pos, entrySelector); pos += 2;
    data.setUint16(pos, numTables * 16 - searchRange); pos += 2;

    // Write table directory
    for (final info in tableInfos) {
      // Tag (4 bytes ASCII)
      final tag = info.tag.padRight(4).substring(0, 4);
      for (int i = 0; i < 4; i++) {
        data.setUint8(pos++, tag.codeUnitAt(i));
      }
      data.setUint32(pos, _checksum(_tables[info.tag]!)); pos += 4; // checksum
      data.setUint32(pos, info.offset); pos += 4; // offset
      data.setUint32(pos, info.length); pos += 4; // length
    }

    // Write table data
    for (final info in tableInfos) {
      final tableData = _tables[info.tag]!;
      for (int i = 0; i < tableData.length; i++) {
        data.setUint8(pos++, tableData[i]);
      }
      // Pad to 4-byte boundary
      while (pos % 4 != 0 && pos < totalSize) {
        data.setUint8(pos++, 0);
      }
    }

    // Fix head checksum adjustment
    final headOffset = tableInfos.firstWhere((i) => i.tag == 'head').offset;
    data.setUint32(headOffset + 8, 0); // Clear checksumAdjustment
    int fileChecksum = 0;
    for (int i = 0; i < totalSize; i += 4) {
      if (i + 4 <= totalSize) {
        fileChecksum = (fileChecksum + data.getUint32(i)) & 0xFFFFFFFF;
      }
    }
    data.setUint32(headOffset + 8, (0xB1B0AFBA - fileChecksum) & 0xFFFFFFFF);

    return data.buffer.asUint8List();
  }

  void _ensureNotdefGlyph() {
    // .notdef is always at index 0, add it if not present
    if (glyphs.isEmpty || glyphs[0].unicode != 0) {
      glyphs.insert(0, GlyphData(
        character: '.notdef',
        unicode: 0,
        advanceWidth: 500,
        contours: [],
        xMin: 0, yMin: 0, xMax: 0, yMax: 0,
      ));
    }
  }

  // --- head table ---
  void _buildHead() {
    final w = _Writer();
    w.writeUint32(0x00010000); // version (Fixed 16.16)
    w.writeUint32(0x00010000); // fontRevision (Fixed 16.16)
    w.writeUint32(0);          // checksumAdjustment (filled later)
    w.writeUint32(0x5F0F3CF5); // magicNumber
    w.writeUint16(0x000B);     // flags
    w.writeUint16(unitsPerEm); // unitsPerEm
    w.writeInt64(0);           // created
    w.writeInt64(0);           // modified

    // Bounding box — initialize from first glyph's coordinates
    int xMin = glyphs.isNotEmpty ? glyphs.first.xMin : 0;
    int yMin = glyphs.isNotEmpty ? glyphs.first.yMin : 0;
    int xMax = glyphs.isNotEmpty ? glyphs.first.xMax : 0;
    int yMax = glyphs.isNotEmpty ? glyphs.first.yMax : 0;
    for (int i = 1; i < glyphs.length; i++) {
      final g = glyphs[i];
      if (g.xMin < xMin) xMin = g.xMin;
      if (g.yMin < yMin) yMin = g.yMin;
      if (g.xMax > xMax) xMax = g.xMax;
      if (g.yMax > yMax) yMax = g.yMax;
    }
    w.writeInt16(xMin);
    w.writeInt16(yMin);
    w.writeInt16(xMax);
    w.writeInt16(yMax);

    w.writeUint16(0); // macStyle
    w.writeUint16(8); // lowestRecPPEM
    w.writeInt16(2);  // fontDirectionHint
    w.writeInt16(1);  // indexToLocFormat (long)
    w.writeInt16(0);  // glyphDataFormat

    _tables['head'] = w.toBytes();
  }

  // --- maxp table ---
  void _buildMaxp() {
    // Compute max points and contours across all glyphs
    int maxPoints = 0;
    int maxContours = 0;
    for (final glyph in glyphs) {
      int points = 0;
      for (final contour in glyph.contours) {
        points += contour.points.length;
      }
      if (points > maxPoints) maxPoints = points;
      if (glyph.contours.length > maxContours) maxContours = glyph.contours.length;
    }

    final w = _Writer();
    w.writeUint32(0x00010000); // version
    w.writeUint32(glyphs.length); // numGlyphs
    w.writeUint16(maxPoints); // maxPoints
    w.writeUint16(maxContours); // maxContours
    w.writeUint16(0); // maxCompositePoints
    w.writeUint16(0); // maxCompositeContours
    w.writeUint16(2); // maxZones
    w.writeUint16(0); // maxTwilightPoints
    w.writeUint16(0); // maxStorage
    w.writeUint16(0); // maxFunctionDefs
    w.writeUint16(0); // maxInstructionDefs
    w.writeUint16(0); // maxStackElements
    w.writeUint16(0); // maxSizeOfInstructions
    w.writeUint16(0); // maxComponentElements
    w.writeUint16(0); // maxComponentDepth
    _tables['maxp'] = w.toBytes();
  }

  // --- glyf table ---
  void _buildGlyf() {
    final w = _Writer();
    final locaOffsets = <int>[];

    for (final glyph in glyphs) {
      locaOffsets.add(w.offset);

      if (glyph.contours.isEmpty) {
        // Empty glyph
        w.writeInt16(0); // numberOfContours
        w.writeInt16(0); // xMin
        w.writeInt16(0); // yMin
        w.writeInt16(0); // xMax
        w.writeInt16(0); // yMax
      } else {
        // Calculate bounds
        int xMin = 99999, yMin = 99999, xMax = -99999, yMax = -99999;
        for (final contour in glyph.contours) {
          for (final p in contour.points) {
            if (p.x < xMin) xMin = p.x;
            if (p.y < yMin) yMin = p.y;
            if (p.x > xMax) xMax = p.x;
            if (p.y > yMax) yMax = p.y;
          }
        }

        // Update glyph bounds
        glyph.xMin = xMin;
        glyph.yMin = yMin;
        glyph.xMax = xMax;
        glyph.yMax = yMax;

        w.writeInt16(glyph.contours.length); // numberOfContours
        w.writeInt16(xMin);
        w.writeInt16(yMin);
        w.writeInt16(xMax);
        w.writeInt16(yMax);

        // End points of contours
        int pointIndex = 0;
        for (final contour in glyph.contours) {
          pointIndex += contour.points.length;
          w.writeUint16(pointIndex - 1);
        }

        // Instruction length
        w.writeUint16(0);

        // Compute deltas and flags for all points
        // TrueType flag bits:
        //   0x01 = ON_CURVE (point is on-curve)
        //   0x02 = X_SHORT (X delta is 1 byte, not 2)
        //   0x04 = Y_SHORT (Y delta is 1 byte, not 2)
        //   0x10 = X_SHORT + positive direction
        //   0x20 = Y_SHORT + positive direction
        final flags = <int>[];
        final xDeltas = <int>[];
        final yDeltas = <int>[];
        int prevX = 0;
        int prevY = 0;

        for (final contour in glyph.contours) {
          for (final p in contour.points) {
            // 标志位：0x01=on-curve（曲线经过点），off-curve（贝塞尔控制点）无此标志
            int flag = p.onCurve ? 0x01 : 0x00;
            final dx = p.x - prevX;
            final dy = p.y - prevY;

            // X 坐标编码：优先使用 1 字节短格式以节省空间
            if (dx >= 0 && dx <= 255) {
              flag |= 0x12; // X_SHORT (0x02) + X_IS_POSITIVE (0x10)
              xDeltas.add(dx);
            } else if (dx >= -255 && dx < 0) {
              flag |= 0x02; // X_SHORT (0x02)，负方向
              xDeltas.add(-dx);
            } else {
              xDeltas.add(dx); // 16 位有符号差值
            }

            // Y 坐标编码：优先使用 1 字节短格式以节省空间
            if (dy >= 0 && dy <= 255) {
              flag |= 0x24; // Y_SHORT (0x04) + Y_IS_POSITIVE (0x20)
              yDeltas.add(dy);
            } else if (dy >= -255 && dy < 0) {
              flag |= 0x04; // Y_SHORT (0x04)，负方向
              yDeltas.add(-dy);
            } else {
              yDeltas.add(dy); // 16 位有符号差值
            }

            flags.add(flag);
            prevX = p.x;
            prevY = p.y;
          }
        }

        // Write flags
        for (final flag in flags) {
          w.writeUint8(flag);
        }

        // Write X coordinates (delta encoded, respecting short flag)
        for (int i = 0; i < xDeltas.length; i++) {
          if (flags[i] & 0x02 != 0) {
            w.writeUint8(xDeltas[i]); // single byte
          } else {
            w.writeInt16(xDeltas[i]); // signed 16-bit
          }
        }

        // Write Y coordinates (delta encoded, respecting short flag)
        for (int i = 0; i < yDeltas.length; i++) {
          if (flags[i] & 0x04 != 0) {
            w.writeUint8(yDeltas[i]); // single byte
          } else {
            w.writeInt16(yDeltas[i]); // signed 16-bit
          }
        }
      }

      // Align to 2-byte boundary
      while (w.offset % 2 != 0) {
        w.writeUint8(0);
      }
    }

    _tables['glyf'] = w.toBytes();

    // Build loca table (long format)
    final locaW = _Writer();
    for (final offset in locaOffsets) {
      locaW.writeUint32(offset);
    }
    locaW.writeUint32(w.offset); // Final entry
    _locaBytes = locaW.toBytes();
  }

  List<int>? _locaBytes;

  // --- loca table ---
  void _buildLoca() {
    // Will be set by _buildGlyf
    _tables['loca'] = _locaBytes ?? [];
  }

  // --- hhea table ---
  void _buildHhea() {
    final w = _Writer();
    w.writeInt16(1);  // majorVersion
    w.writeInt16(0);  // minorVersion
    w.writeInt16(unitsPerEm * 8 ~/ 10); // ascender
    w.writeInt16(-unitsPerEm ~/ 5);     // descender
    w.writeInt16(0);  // lineGap
    w.writeUint16(0); // advanceWidthMax (filled below)

    // Calculate max advance width
    int maxAdv = 0;
    for (final g in glyphs) {
      if (g.advanceWidth > maxAdv) maxAdv = g.advanceWidth;
    }

    // Rewrite advanceWidthMax
    final hheaBytes = w.toBytes();
    // We need to set it properly, let's redo
    final w2 = _Writer();
    w2.writeUint32(0x00010000); // version (Fixed 16.16)
    w2.writeInt16(unitsPerEm * 8 ~/ 10);
    w2.writeInt16(-unitsPerEm ~/ 5);
    w2.writeInt16(0);
    w2.writeUint16(maxAdv); // advanceWidthMax
    w2.writeInt16(0);  // minLeftSideBearing
    w2.writeInt16(0);  // minRightSideBearing
    w2.writeInt16(0);  // xMaxExtent
    w2.writeInt16(1);  // caretSlopeRise
    w2.writeInt16(0);  // caretSlopeRun
    w2.writeInt16(0);  // caretOffset
    w2.writeInt16(0);  // reserved
    w2.writeInt16(0);  // reserved
    w2.writeInt16(0);  // reserved
    w2.writeInt16(0);  // reserved
    w2.writeInt16(0);  // metricDataFormat
    w2.writeUint16(glyphs.length); // numberOfHMetrics

    _tables['hhea'] = w2.toBytes();
  }

  // --- hmtx table ---
  void _buildHmtx() {
    final w = _Writer();
    for (final glyph in glyphs) {
      w.writeUint16(glyph.advanceWidth);
      w.writeInt16(glyph.leftSideBearing);
    }
    _tables['hmtx'] = w.toBytes();
  }

  // --- cmap table ---
  void _buildCmap() {
    // Build format 4 subtable (covers BMP characters)
    final entries = <_CmapEntry>[];
    for (int i = 0; i < glyphs.length; i++) {
      if (glyphs[i].unicode > 0) {
        entries.add(_CmapEntry(glyphs[i].unicode, i));
      }
    }
    entries.sort((a, b) => a.charCode.compareTo(b.charCode));

    // Build format 4 subtable
    final segCount = entries.length + 1; // +1 for the .notdef segment
    final segCountX2 = segCount * 2;
    int searchRange = 1;
    int entrySelector = 0;
    while (searchRange * 2 <= segCount) {
      searchRange *= 2;
      entrySelector++;
    }
    searchRange *= 2;
    final rangeShift = segCountX2 - searchRange;

    final sub2 = _Writer();
    sub2.writeUint16(4); // format
    final lengthPos = sub2.offset;
    sub2.writeUint16(0); // length (fill later)
    sub2.writeUint16(0); // language

    sub2.writeUint16(segCountX2);
    sub2.writeUint16(searchRange);
    sub2.writeUint16(entrySelector);
    sub2.writeUint16(rangeShift);

    // endCode
    for (final e in entries) {
      sub2.writeUint16(e.charCode);
    }
    sub2.writeUint16(0xFFFF);

    // reservedPad
    sub2.writeUint16(0);

    // startCode
    for (final e in entries) {
      sub2.writeUint16(e.charCode);
    }
    sub2.writeUint16(0xFFFF); // terminator sentinel at end

    // idDelta
    for (final e in entries) {
      sub2.writeInt16(e.glyphIndex - e.charCode);
    }
    sub2.writeInt16(1); // terminator: (0xFFFF + 1) % 65536 = 0 (.notdef)

    // idRangeOffset - all zeros since we use idDelta
    for (int i = 0; i <= entries.length; i++) {
      sub2.writeUint16(0);
    }

    // Fix length
    final sub2Bytes = sub2.toBytes();
    sub2Bytes[lengthPos] = (sub2Bytes.length >> 8) & 0xFF;
    sub2Bytes[lengthPos + 1] = sub2Bytes.length & 0xFF;

    // Build cmap table header
    final cmap = _Writer();
    cmap.writeUint16(0); // version
    cmap.writeUint16(1); // numberSubtables
    // Platform 0 (Unicode BMP), encoding 3
    cmap.writeUint16(0); // platformID
    cmap.writeUint16(3); // encodingID
    cmap.writeUint32(12); // offset to subtable (header is 12 bytes for 1 subtable? No, 4+8=12)

    // Hmm, let me recalculate. cmap header: version(2) + numTables(2) = 4 bytes
    // Each encoding record: 4+4+4 = 12 bytes
    // So offset to subtable = 4 + 1*12 = 16... wait, that's wrong too.
    // offset(4) bytes each: platformID(2) + encodingID(2) + offset(4) = 8 bytes per record
    // So offset = 4 + 1*8 = 12

    final cmapBytes = [...cmap.toBytes(), ...sub2Bytes];
    // Fix the offset in the subtable offset field
    // The offset should be relative to the start of the cmap table
    // It's at position 8 (after version and numTables and platform/encoding)
    // Should be 4 + 8*1 = 12
    cmapBytes[8] = 0;
    cmapBytes[9] = 0;
    cmapBytes[10] = 0;
    cmapBytes[11] = 12;

    _tables['cmap'] = cmapBytes;
  }

  // --- name table ---
  void _buildName() {
    final records = <_NameRecord>[
      _NameRecord(1, 0, 0, 0, familyName), // Font Family
      _NameRecord(2, 0, 0, 0, 'Regular'), // Font Subfamily
      _NameRecord(3, 0, 0, 0, 'WriteFont:$familyName:Regular'), // Unique ID
      _NameRecord(4, 0, 0, 0, '$familyName Regular'), // Full Name
      _NameRecord(5, 0, 0, 0, 'Version 1.0'), // Version
      _NameRecord(6, 0, 0, 0, 'WriteFont-$familyName'), // PostScript Name
    ];

    final nameData = _Writer();
    int stringOffset = 6 + records.length * 12; // header + records

    // Write strings first to calculate offsets
    final stringBytes = <List<int>>[];
    for (final r in records) {
      final encoded = ascii.encode(r.value);
      stringBytes.add(encoded);
    }

    // Header
    nameData.writeUint16(0); // format
    nameData.writeUint16(records.length); // count
    nameData.writeUint16(stringOffset); // stringOffset

    // Name records
    int currentOffset = 0;
    for (int i = 0; i < records.length; i++) {
      final r = records[i];
      nameData.writeUint16(r.platformID);
      nameData.writeUint16(r.encodingID);
      nameData.writeUint16(r.languageID);
      nameData.writeUint16(r.nameID);
      nameData.writeUint16(stringBytes[i].length); // length
      nameData.writeUint16(currentOffset); // offset
      currentOffset += stringBytes[i].length;
    }

    // String data
    for (final bytes in stringBytes) {
      nameData.writeBytes(bytes);
    }

    _tables['name'] = nameData.toBytes();
  }

  // --- OS/2 table ---
  void _buildOs2() {
    final w = _Writer();
    w.writeUint16(4); // version

    // Average character width
    int totalWidth = 0;
    for (final g in glyphs) {
      if (g.advanceWidth > 0) totalWidth += g.advanceWidth;
    }
    final avgWidth = glyphs.isNotEmpty ? totalWidth ~/ glyphs.length : 500;
    w.writeInt16(avgWidth); // xAvgCharWidth

    w.writeUint16(400); // usWeightClass (Regular)
    w.writeUint16(5);   // usWidthClass (Normal)
    w.writeUint16(0);   // fsType
    w.writeInt16(0);    // ySubscriptXSize
    w.writeInt16(0);    // ySubscriptYSize
    w.writeInt16(0);    // ySubscriptXOffset
    w.writeInt16(0);    // ySubscriptYOffset
    w.writeInt16(0);    // ySuperscriptXSize
    w.writeInt16(0);    // ySuperscriptYSize
    w.writeInt16(0);    // ySuperscriptXOffset
    w.writeInt16(0);    // ySuperscriptYOffset
    w.writeInt16(0);    // yStrikeoutSize
    w.writeInt16(0);    // yStrikeoutPosition

    // Family class
    w.writeInt8(0);     // sFamilyClass
    w.writeInt8(0);

    // Panose
    for (int i = 0; i < 10; i++) w.writeUint8(0);

    // Unicode range
    w.writeUint32(0);   // ulUnicodeRange1
    w.writeUint32(0);   // ulUnicodeRange2
    w.writeUint32(0);   // ulUnicodeRange3
    w.writeUint32(0);   // ulUnicodeRange4

    // Vendor ID
    w.writeUint8(0x57); // 'W'
    w.writeUint8(0x52); // 'R'
    w.writeUint8(0x49); // 'I'
    w.writeUint8(0x54); // 'T'

    w.writeUint16(0);   // fsSelection
    w.writeUint16(0x0020); // usFirstCharIndex (space)
    w.writeUint16(0xFFFD); // usLastCharIndex
    w.writeInt16(unitsPerEm * 8 ~/ 10); // sTypoAscender
    w.writeInt16(-unitsPerEm ~/ 5);     // sTypoDescender
    w.writeInt16(0);    // sTypoLineGap
    w.writeUint16(unitsPerEm * 8 ~/ 10); // usWinAscent
    w.writeUint16(unitsPerEm ~/ 5);      // usWinDescent

    // Code page range
    w.writeUint32(1);   // ulCodePageRange1 (Latin 1)
    w.writeUint32(0);   // ulCodePageRange2

    w.writeInt16(0);    // sxHeight
    w.writeInt16(0);    // sCapHeight
    w.writeUint16(0);   // usDefaultChar
    w.writeUint16(0);   // usBreakChar
    w.writeUint16(glyphs.length); // usMaxContext

    _tables['OS/2'] = w.toBytes();
  }

  // --- post table ---
  void _buildPost() {
    final w = _Writer();
    w.writeUint32(0x00030000); // version 3.0 (no glyph names)
    w.writeInt32(0);    // italicAngle
    w.writeInt16(0);    // underlinePosition
    w.writeInt16(0);    // underlineThickness
    w.writeUint32(0);   // isFixedPitch
    w.writeUint32(0);   // minMemType42
    w.writeUint32(0);   // maxMemType42
    w.writeUint32(0);   // minMemType1
    w.writeUint32(0);   // maxMemType1
    _tables['post'] = w.toBytes();
  }

  /// Calculate checksum for a table.
  int _checksum(List<int> data) {
    int sum = 0;
    final padded = List<int>.from(data);
    while (padded.length % 4 != 0) {
      padded.add(0);
    }
    for (int i = 0; i < padded.length; i += 4) {
      sum = (sum +
        ((padded[i] << 24) |
         ((i + 1 < padded.length ? padded[i + 1] : 0) << 16) |
         ((i + 2 < padded.length ? padded[i + 2] : 0) << 8) |
         (i + 3 < padded.length ? padded[i + 3] : 0))) & 0xFFFFFFFF;
    }
    return sum;
  }
}

class _TableInfo {
  final String tag;
  final int offset;
  final int length;
  final int paddedLength;
  _TableInfo(this.tag, this.offset, this.length, this.paddedLength);
}

class _CmapEntry {
  final int charCode;
  final int glyphIndex;
  _CmapEntry(this.charCode, this.glyphIndex);
}

class _NameRecord {
  final int platformID;
  final int encodingID;
  final int languageID;
  final int nameID;
  final String value;
  _NameRecord(this.platformID, this.encodingID, this.languageID, this.nameID, this.value);
}

/// Helper for writing binary data in big-endian format.
class _Writer {
  final List<int> _data = [];
  int get offset => _data.length;

  void writeUint8(int value) {
    _data.add(value & 0xFF);
  }

  void writeInt8(int value) {
    _data.add(value & 0xFF);
  }

  void writeUint16(int value) {
    _data.add((value >> 8) & 0xFF);
    _data.add(value & 0xFF);
  }

  void writeInt16(int value) {
    if (value < 0) value = value + 65536;
    writeUint16(value);
  }

  void writeUint32(int value) {
    _data.add((value >> 24) & 0xFF);
    _data.add((value >> 16) & 0xFF);
    _data.add((value >> 8) & 0xFF);
    _data.add(value & 0xFF);
  }

  void writeInt32(int value) {
    if (value < 0) value = value + 4294967296;
    writeUint32(value);
  }

  void writeInt64(int value) {
    // Write as two 32-bit values
    if (value < 0) {
      writeUint32(0xFFFFFFFF);
      writeUint32((value + 4294967296) & 0xFFFFFFFF);
    } else {
      writeUint32(0);
      writeUint32(value & 0xFFFFFFFF);
    }
  }

  void writeBytes(List<int> bytes) {
    _data.addAll(bytes);
  }

  List<int> toBytes() => List<int>.from(_data);
}

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' show Offset;

import '../models/font_project.dart';

/// TTF 字体生成器
/// 实现 TrueType 字体格式的核心结构，生成标准 TTF 文件
class TtfBuilder {
  static const int _unitsPerEm = 1000;
  static const int _ascent = 800;
  static const int _descent = -200;
  static const int _lineGap = 0;

  /// 从字体项目生成 TTF 文件
  static Uint8List build(FontProject project) {
    final writer = _BinaryWriter();

    // 收集所有包含的字形
    final includedGlyphs =
        project.glyphs.where((g) => g.isIncluded && g.contours.isNotEmpty).toList();

    // 准备字形数据
    final List<_GlyphInfo> glyphInfos = [];

    // .notdef 字形 (index 0)
    glyphInfos.add(_GlyphInfo(
      characterCode: 0,
      advanceWidth: 500,
      leftSideBearing: 50,
      contours: [_notdefContours()],
      isComposite: false,
    ));

    // 空格字形 (index 1)
    glyphInfos.add(_GlyphInfo(
      characterCode: 0x0020,
      advanceWidth: 250,
      leftSideBearing: 0,
      contours: [],
      isComposite: false,
    ));

    // 用户字形
    for (final glyph in includedGlyphs) {
      final scaledContours = _scaleContours(glyph.contours);
      glyphInfos.add(_GlyphInfo(
        characterCode: glyph.character.codeUnitAt(0),
        advanceWidth: _unitsPerEm,
        leftSideBearing: 50,
        contours: scaledContours,
        isComposite: false,
      ));
    }

    // 计算表的偏移
    // 表顺序: head, hhea, maxp, OS/2, cmap, glyf, loca, hmtx, name, post
    const tableTags = ['head', 'hhea', 'maxp', 'OS/2', 'cmap', 'glyf', 'loca', 'hmtx', 'name', 'post'];
    const numTables = tableTags.length;

    // Offset table (12 bytes) + Table records (16 bytes each)
    int currentOffset = 12 + numTables * 16;

    // 计算每个表的数据
    final Map<String, Uint8List> tableData = {};
    final Map<String, int> tableOffsets = {};

    // 生成各个表
    final headData = _buildHeadTable(glyphInfos.length);
    final hheaData = _buildHheaTable(glyphInfos);
    final maxpData = _buildMaxpTable(glyphInfos.length);
    final os2Data = _buildOS2Table();
    final cmapData = _buildCmapTable(glyphInfos);
    final glyfData = _buildGlyfTable(glyphInfos);
    final locaData = _buildLocaTable(glyphInfos);
    final hmtxData = _buildHmtxTable(glyphInfos);
    final nameData = _buildNameTable(project.name);
    final postData = _buildPostTable();

    tableData['head'] = headData;
    tableData['hhea'] = hheaData;
    tableData['maxp'] = maxpData;
    tableData['OS/2'] = os2Data;
    tableData['cmap'] = cmapData;
    tableData['glyf'] = glyfData;
    tableData['loca'] = locaData;
    tableData['hmtx'] = hmtxData;
    tableData['name'] = nameData;
    tableData['post'] = postData;

    // 计算偏移（表数据需要4字节对齐）
    for (final tag in tableTags) {
      final paddedLength = _align4(tableData[tag]!.length);
      currentOffset = _align4(currentOffset);
      tableOffsets[tag] = currentOffset;
      currentOffset += tableData[tag]!.length;
      // 不需要额外 padding，因为我们已经保存了原始长度
      currentOffset += (paddedLength - tableData[tag]!.length);
    }

    // 写入文件
    // 1. Offset Table
    writer.writeFixed(0x00010000); // sfVersion
    writer.writeUint16(numTables);
    // searchRange, entrySelector, rangeShift
    final pwr2 = _maxPowerOf2(numTables);
    writer.writeUint16(pwr2 * 16); // searchRange
    writer.writeUint16(log(pwr2) ~/ log(2)); // entrySelector
    writer.writeUint16((numTables - pwr2) * 16); // rangeShift

    // 2. Table Records
    for (final tag in tableTags) {
      writer.writeTag(tag);
      writer.writeUint32(_checksum(tableData[tag]!));
      writer.writeUint32(tableOffsets[tag]!);
      writer.writeUint32(tableData[tag]!.length);
    }

    // 3. Table Data
    for (final tag in tableTags) {
      final data = tableData[tag]!;
      final alignedOffset = _align4(writer.offset);
      while (writer.offset < alignedOffset) {
        writer.writeUint8(0);
      }
      writer.writeBytes(data);
    }

    // 4. 更新 head checksum adjustment
    final result = writer.toBytes();
    _fixHeadChecksumAdjustment(result, tableOffsets['head']!);

    return result;
  }

  /// 缩放轮廓到字体坐标系 (0-1000)
  static List<List<Offset>> _scaleContours(List<List<Offset>> contours) {
    if (contours.isEmpty) return contours;

    // 计算边界
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;

    for (final contour in contours) {
      for (final p in contour) {
        minX = min(minX, p.dx);
        minY = min(minY, p.dy);
        maxX = max(maxX, p.dx);
        maxY = max(maxY, p.dy);
      }
    }

    final width = maxX - minX;
    final height = maxY - minY;
    if (width <= 0 || height <= 0) return contours;

    final scale = (_unitsPerEm - 100) / max(width, height);
    final offsetX = (_unitsPerEm - width * scale) / 2 - minX * scale;
    final offsetY = (_unitsPerEm - height * scale) / 2 - minY * scale + _descent.abs();

    return contours
        .map((contour) => contour
            .map((p) => Offset(
                  (p.dx * scale + offsetX).roundToDouble(),
                  (p.dy * scale + offsetY).roundToDouble(),
                ))
            .toList())
        .toList();
  }

  /// .notdef 字形轮廓（简单方框）
  static List<Offset> _notdefContours() {
    return [
      Offset(50, 0),
      Offset(450, 0),
      Offset(450, 700),
      Offset(50, 700),
    ];
  }

  // ===== Table Builders =====

  /// head 表
  static Uint8List _buildHeadTable(int numGlyphs) {
    final w = _BinaryWriter();
    w.writeFixed(0x00010000); // version
    w.writeFixed(0x00010000); // fontRevision
    w.writeUint32(0); // checksumAdjustment (will be patched)
    w.writeUint32(0x5F0F3CF5); // magicNumber
    w.writeUint16(0x000B); // flags
    w.writeUint16(_unitsPerEm); // unitsPerEm
    w.writeInt64(_dateTimeNow()); // created
    w.writeInt64(_dateTimeNow()); // modified
    w.writeInt16(0); // xMin
    w.writeInt16(_descent); // yMin
    w.writeInt16(_unitsPerEm); // xMax
    w.writeInt16(_ascent); // yMax
    w.writeUint16(0); // macStyle
    w.writeUint16(8); // lowestRecPPEM
    w.writeInt16(2); // fontDirectionHint
    w.writeInt16(1); // indexToLocFormat (long)
    w.writeInt16(0); // glyphDataFormat
    return w.toBytes();
  }

  /// hhea 表
  static Uint8List _buildHheaTable(List<_GlyphInfo> glyphs) {
    final w = _BinaryWriter();
    w.writeFixed(0x00010000); // version
    w.writeInt16(_ascent); // ascender
    w.writeInt16(_descent); // descender
    w.writeInt16(_lineGap); // lineGap
    w.writeUint16(_unitsPerEm); // advanceWidthMax
    w.writeInt16(0); // minLeftSideBearing
    w.writeInt16(0); // minRightSideBearing
    w.writeInt16(_unitsPerEm); // xMaxExtent
    w.writeInt16(1); // caretSlopeRise
    w.writeInt16(0); // caretSlopeRun
    w.writeInt16(0); // caretOffset
    w.writeInt16(0); // reserved
    w.writeInt16(0); // reserved
    w.writeInt16(0); // reserved
    w.writeInt16(0); // reserved
    w.writeInt16(0); // metricDataFormat
    w.writeUint16(glyphs.length); // numberOfHMetrics
    return w.toBytes();
  }

  /// maxp 表
  static Uint8List _buildMaxpTable(int numGlyphs) {
    final w = _BinaryWriter();
    w.writeFixed(0x00010000); // version
    w.writeUint16(numGlyphs); // numGlyphs
    w.writeUint16(0); // maxPoints
    w.writeUint16(0); // maxContours
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
    return w.toBytes();
  }

  /// OS/2 表 (version 4)
  static Uint8List _buildOS2Table() {
    final w = _BinaryWriter();
    w.writeUint16(4); // version
    w.writeInt16((_unitsPerEm * 0.6).round()); // xAvgCharWidth
    w.writeUint16(400); // usWeightClass (Regular)
    w.writeUint16(5); // usWidthClass (Medium/Normal)
    w.writeUint16(0); // fsType (Installable)
    w.writeInt16((_unitsPerEm * 0.5).round()); // ySubscriptXSize
    w.writeInt16((_unitsPerEm * 0.4).round()); // ySubscriptYSize
    w.writeInt16(0); // ySubscriptXOffset
    w.writeInt16(0); // ySubscriptYOffset
    w.writeInt16((_unitsPerEm * 0.5).round()); // ySuperscriptXSize
    w.writeInt16((_unitsPerEm * 0.4).round()); // ySuperscriptYSize
    w.writeInt16(0); // ySuperscriptXOffset
    w.writeInt16((_unitsPerEm * 0.4).round()); // ySuperscriptYOffset
    w.writeInt16(50); // yStrikeoutSize
    w.writeInt16(300); // yStrikeoutPosition
    w.writeInt16(0); // sFamilyClass
    // Panose (10 bytes)
    w.writeBytes(Uint8List(10));
    // ulUnicodeRange (4 uint32)
    w.writeUint32(0x00000001); // Basic Latin
    w.writeUint32(0x10000000); // CJK
    w.writeUint32(0);
    w.writeUint32(0);
    // achVendID (4 bytes)
    w.writeTag('WFON');
    w.writeUint16(0); // fsSelection
    w.writeUint16(0x0021); // usFirstCharIndex (space)
    w.writeUint16(0xFFE0); // usLastCharIndex
    w.writeInt16(_ascent); // sTypoAscender
    w.writeInt16(_descent); // sTypoDescender
    w.writeInt16(_lineGap); // sTypoLineGap
    w.writeUint16(_ascent); // usWinAscent
    w.writeUint16(_descent.abs()); // usWinDescent
    w.writeUint32(0); // ulCodePageRange1
    w.writeUint32(0); // ulCodePageRange2
    w.writeInt16((_unitsPerEm * 0.1).round()); // sxHeight
    w.writeInt16((_unitsPerEm * 0.7).round()); // sCapHeight
    w.writeUint16(0); // usDefaultChar
    w.writeUint16(0x0020); // usBreakChar
    w.writeUint16(2); // usMaxContext
    w.writeUint16(0); // usLowerOpticalPointSize
    w.writeUint16(0xFFFF); // usUpperOpticalPointSize
    return w.toBytes();
  }

  /// cmap 表 (Format 4 - BMP characters)
  static Uint8List _buildCmapTable(List<_GlyphInfo> glyphs) {
    final w = _BinaryWriter();

    // 构建字符到 glyph index 的映射
    final Map<int, int> charToGlyph = {};
    for (int i = 0; i < glyphs.length; i++) {
      if (glyphs[i].characterCode > 0) {
        charToGlyph[glyphs[i].characterCode] = i;
      }
    }

    // 编码记录
    // Platform 3 (Windows), Encoding 1 (Unicode BMP)
    const platformID = 3;
    const encodingID = 1;

    // Format 4 子表
    final subTable = _BinaryWriter();
    final segCount = charToGlyph.length + 1; // +1 for 0xFFFF segment
    final segCountX2 = segCount * 2;
    final searchRange = _maxPowerOf2(segCount) * 2;
    final entrySelector = log(_maxPowerOf2(segCount)) ~/ log(2);
    final rangeShift = segCountX2 - searchRange;

    subTable.writeUint16(4); // format
    subTable.writeUint16(0); // length (will patch)
    subTable.writeUint16(0); // language
    subTable.writeUint16(segCountX2);
    subTable.writeUint16(searchRange);
    subTable.writeUint16(entrySelector);
    subTable.writeUint16(rangeShift);

    // 排序字符码
    final sortedCodes = charToGlyph.keys.toList()..sort();

    // endCode
    for (final code in sortedCodes) {
      subTable.writeUint16(code);
    }
    subTable.writeUint16(0xFFFF);

    // reservedPad
    subTable.writeUint16(0);

    // startCode
    for (final code in sortedCodes) {
      subTable.writeUint16(code);
    }
    subTable.writeUint16(0xFFFF);

    // idDelta
    for (final code in sortedCodes) {
      final glyphIndex = charToGlyph[code]!;
      subTable.writeInt16(glyphIndex - code);
    }
    subTable.writeInt16(1); // for 0xFFFF

    // idRangeOffset - all zero (use idDelta)
    for (int i = 0; i < sortedCodes.length; i++) {
      subTable.writeUint16(0);
    }
    subTable.writeUint16(0); // for 0xFFFF segment

    // Patch length
    final subTableBytes = subTable.toBytes();
    ByteData.view(subTableBytes.buffer).setUint16(2, subTableBytes.length);

    // cmap 头
    w.writeUint16(0); // version
    w.writeUint16(2); // numTables (platform 3 + platform 0)
    
    // 平台记录 1: Platform 3, Encoding 1
    w.writeUint16(platformID);
    w.writeUint16(encodingID);
    w.writeUint32(12 + 8 * 2); // offset (after header + 2 encoding records)

    // 同时添加 Platform 0 (Unicode) 映射
    w.writeUint16(0); // platform 0
    w.writeUint16(3); // encoding 3 (Unicode BMP)
    w.writeUint32(12 + 8 * 2); // 同一个子表

    w.writeBytes(subTableBytes);

    return w.toBytes();
  }

  /// glyf 表
  static Uint8List _buildGlyfTable(List<_GlyphInfo> glyphs) {
    final w = _BinaryWriter();

    for (int i = 0; i < glyphs.length; i++) {
      glyphs[i].glyfOffset = w.offset;

      final contours = glyphs[i].contours;
      if (contours.isEmpty) {
        // 空字形
        w.writeInt16(0); // numberOfContours
        w.writeInt16(0); // xMin
        w.writeInt16(0); // yMin
        w.writeInt16(0); // xMax
        w.writeInt16(0); // yMax
      } else {
        // 计算边界
        int xMin = 99999, yMin = 99999;
        int xMax = -99999, yMax = -99999;
        for (final contour in contours) {
          for (final p in contour) {
            xMin = min(xMin, p.dx.round());
            yMin = min(yMin, p.dy.round());
            xMax = max(xMax, p.dx.round());
            yMax = max(yMax, p.dy.round());
          }
        }

        w.writeInt16(contours.length); // numberOfContours
        w.writeInt16(xMin);
        w.writeInt16(yMin);
        w.writeInt16(xMax);
        w.writeInt16(yMax);

        // 对每个轮廓，简化为仅用直线段
        for (final contour in contours) {
          _writeSimpleContour(w, contour);
        }
      }

      // 4字节对齐
      while (w.offset % 4 != 0) {
        w.writeUint8(0);
      }
    }

    return w.toBytes();
  }

  /// 写入简单轮廓（全部使用直线段）
  static void _writeSimpleContour(_BinaryWriter w, List<Offset> points) {
    if (points.isEmpty) return;

    // 简化：对每个轮廓点进行均匀采样，控制点数
    final sampled = _resampleContour(points, 50);
    final numPoints = sampled.length;

    w.writeUint16(numPoints - 1); // endPtsOfContours

    // instructionLength
    w.writeUint16(0);

    // flags - 全部使用简单坐标 (ON_CURVE)
    for (int i = 0; i < numPoints; i++) {
      w.writeUint8(0x01); // ON_CURVE
    }

    // xCoordinates (相对编码)
    int prevX = 0;
    for (int i = 0; i < numPoints; i++) {
      final x = sampled[i].dx.round();
      w.writeInt16(x - prevX);
      prevX = x;
    }

    // yCoordinates (相对编码)
    int prevY = 0;
    for (int i = 0; i < numPoints; i++) {
      final y = sampled[i].dy.round();
      w.writeInt16(y - prevY);
      prevY = y;
    }
  }

  /// 重新采样轮廓到指定点数
  static List<Offset> _resampleContour(List<Offset> points, int targetCount) {
    if (points.length <= targetCount) return points;

    // 计算总长度
    double totalLength = 0;
    for (int i = 0; i < points.length; i++) {
      final next = points[(i + 1) % points.length];
      totalLength += (next - points[i]).distance;
    }

    if (totalLength <= 0) return points;

    final step = totalLength / targetCount;
    List<Offset> result = [points.first];
    double accumulated = 0;
    int currentIndex = 0;

    for (int i = 1; i < targetCount; i++) {
      final targetDist = step * i;
      while (accumulated < targetDist && currentIndex < points.length) {
        final next = points[(currentIndex + 1) % points.length];
        final segLen = (next - points[currentIndex]).distance;
        if (accumulated + segLen >= targetDist) {
          final t = (targetDist - accumulated) / segLen;
          result.add(Offset(
            points[currentIndex].dx + (next.dx - points[currentIndex].dx) * t,
            points[currentIndex].dy + (next.dy - points[currentIndex].dy) * t,
          ));
          break;
        }
        accumulated += segLen;
        currentIndex++;
      }
    }

    return result;
  }

  /// loca 表 (long format)
  static Uint8List _buildLocaTable(List<_GlyphInfo> glyphs) {
    final w = _BinaryWriter();
    for (final glyph in glyphs) {
      w.writeUint32(glyph.glyfOffset);
    }
    // 最后一个偏移
    w.writeUint32(glyphs.last.glyfOffset +
        (glyphs.last.contours.isEmpty ? 10 : glyphs.last.contours.length * 100));
    return w.toBytes();
  }

  /// hmtx 表
  static Uint8List _buildHmtxTable(List<_GlyphInfo> glyphs) {
    final w = _BinaryWriter();
    for (final glyph in glyphs) {
      w.writeUint16(glyph.advanceWidth);
      w.writeInt16(glyph.leftSideBearing);
    }
    return w.toBytes();
  }

  /// name 表
  static Uint8List _buildNameTable(String fontName) {
    final w = _BinaryWriter();

    final records = <_NameRecord>[
      _NameRecord(1, 0, 0x0409, fontName), // fontFamily
      _NameRecord(2, 0, 0x0409, 'Regular'), // fontSubfamily
      _NameRecord(4, 0, 0x0409, '$fontName Regular'), // fullName
      _NameRecord(6, 0, 0x0409, 'WriteFont-${fontName.replaceAll(' ', '')}'), // postscriptName
    ];

    // name table header
    w.writeUint16(0); // format
    w.writeUint16(records.length); // count
    w.writeUint16(6 + records.length * 12); // stringOffset

    // 编码所有字符串
    final strings = <Uint8List>[];
    for (final record in records) {
      strings.add(Uint8List.fromList(ascii.encode(record.value)));
    }

    // Name records
    int stringOffset = 0;
    for (int i = 0; i < records.length; i++) {
      w.writeUint16(records[i].platformID);
      w.writeUint16(records[i].encodingID);
      w.writeUint16(records[i].languageID);
      w.writeUint16(records[i].nameID);
      w.writeUint16(strings[i].length);
      w.writeUint16(stringOffset);
      stringOffset += strings[i].length;
    }

    // String data
    for (final s in strings) {
      w.writeBytes(s);
    }

    return w.toBytes();
  }

  /// post 表
  static Uint8List _buildPostTable() {
    final w = _BinaryWriter();
    w.writeFixed(0x00030000); // version 3.0 (no glyph names)
    w.writeInt32((_ascent * 0.8 * 65536).toInt()); // italicAngle (fixed)
    w.writeInt16((_ascent * 0.25).round()); // underlinePosition
    w.writeUint16(50); // underlineThickness
    w.writeUint32(0); // isFixedPitch
    w.writeUint32(0); // minMemType42
    w.writeUint32(0); // maxMemType42
    w.writeUint32(0); // minMemType1
    w.writeUint32(0); // maxMemType1
    return w.toBytes();
  }

  // ===== Utility Functions =====

  static int _align4(int offset) => (offset + 3) & ~3;

  static int _maxPowerOf2(int n) {
    int p = 1;
    while (p * 2 <= n) {
      p *= 2;
    }
    return p;
  }

  static int _dateTimeNow() {
    // TTF 时间是从 1904-01-01 开始的秒数
    final epoch1904 = DateTime(1904, 1, 1);
    final now = DateTime.now();
    return now.difference(epoch1904).inSeconds;
  }

  static Uint8List _checksum(Uint8List data) {
    // 简化：返回数据本身用于计算
    return data;
  }

  static void _fixHeadChecksumAdjustment(Uint8List file, int headOffset) {
    // 计算整个文件的 checksum
    int sum = 0;
    for (int i = 0; i < file.length; i += 4) {
      int val = 0;
      for (int j = 0; j < 4 && i + j < file.length; j++) {
        val = (val << 8) | file[i + j];
      }
      sum = (sum + val) & 0xFFFFFFFF;
    }

    // checksumAdjustment 在 head 表的偏移 8
    final view = ByteData.view(file.buffer);
    final headChecksum = view.getUint32(headOffset + 8);
    final adjustment = (0xB1B0AFBA - sum + headChecksum) & 0xFFFFFFFF;
    view.setUint32(headOffset + 8, adjustment);
  }
}

/// 字形信息
class _GlyphInfo {
  final int characterCode;
  final int advanceWidth;
  final int leftSideBearing;
  final List<List<Offset>> contours;
  final bool isComposite;
  int glyfOffset = 0;

  _GlyphInfo({
    required this.characterCode,
    required this.advanceWidth,
    required this.leftSideBearing,
    required this.contours,
    required this.isComposite,
  });
}

/// 名称记录
class _NameRecord {
  final int platformID;
  final int encodingID;
  final int languageID;
  final int nameID;
  final String value;

  _NameRecord(this.nameID, this.platformID, this.languageID, this.value)
      : encodingID = platformID == 3 ? 1 : 0;
}

/// 二进制写入器
class _BinaryWriter {
  final List<int> _buffer = [];

  int get offset => _buffer.length;

  void writeUint8(int value) {
    _buffer.add(value & 0xFF);
  }

  void writeUint16(int value) {
    _buffer.add((value >> 8) & 0xFF);
    _buffer.add(value & 0xFF);
  }

  void writeInt16(int value) {
    if (value < 0) value = value + 65536;
    writeUint16(value);
  }

  void writeUint32(int value) {
    _buffer.add((value >> 24) & 0xFF);
    _buffer.add((value >> 16) & 0xFF);
    _buffer.add((value >> 8) & 0xFF);
    _buffer.add(value & 0xFF);
  }

  void writeInt32(int value) {
    if (value < 0) value = value + 4294967296;
    writeUint32(value);
  }

  void writeInt64(int value) {
    // 64-bit signed integer (big-endian)
    if (value < 0) {
      writeUint32(0xFFFFFFFF);
      writeUint32((value + 4294967296) & 0xFFFFFFFF);
    } else {
      writeUint32(0);
      writeUint32(value & 0xFFFFFFFF);
    }
  }

  void writeFixed(int value) {
    writeUint32(value);
  }

  void writeTag(String tag) {
    for (int i = 0; i < 4; i++) {
      _buffer.add(i < tag.length ? tag.codeUnitAt(i) : 0x20);
    }
  }

  void writeBytes(Uint8List bytes) {
    _buffer.addAll(bytes);
  }

  Uint8List toBytes() {
    return Uint8List.fromList(_buffer);
  }
}

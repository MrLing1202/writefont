import 'dart:io' show zlib;
import 'dart:typed_data';

/// WOFF 1.0 格式打包器
///
/// 将 TTF 二进制数据封装为 WOFF 格式（带 zlib 压缩）。
/// WOFF 是 OpenType/TrueType 字体的网页嵌入格式，通过压缩减小文件体积。
///
/// 参考规范：https://www.w3.org/TR/WOFF/
class WoffBuilder {
  /// TTF 原始字节
  final Uint8List ttfBytes;

  WoffBuilder({required this.ttfBytes});

  /// 构建 WOFF 文件并返回字节数据
  Uint8List build() {
    final reader = _SfntReader(ttfBytes);
    final tables = reader.readTables();

    // 对每个表进行 zlib 压缩
    final compressedTables = <_WoffTableEntry>[];
    for (final table in tables) {
      final compressed = Uint8List.fromList(zlib.encode(table.data));
      // 如果压缩后反而更大，使用原始数据（compLength == origLength 表示未压缩）
      final useCompressed = compressed.length < table.data.length;
      compressedTables.add(_WoffTableEntry(
        tag: table.tag,
        origData: table.data,
        compData: useCompressed ? compressed : Uint8List.fromList(table.data),
        origLength: table.data.length,
        compLength: useCompressed ? compressed.length : table.data.length,
        origChecksum: table.checksum,
        isCompressed: useCompressed,
      ));
    }

    // 计算 WOFF 文件大小
    const headerSize = 44;
    const tableDirEntrySize = 20;
    final tableDirSize = compressedTables.length * tableDirEntrySize;
    final dataOffset = headerSize + tableDirSize;

    // 计算表数据总大小（需 4 字节对齐）
    int tableDataSize = 0;
    for (final t in compressedTables) {
      tableDataSize += t.compLength;
      // 每个表数据按字节对齐到 4 字节边界（padding 不计入 compLength）
      final padding = (4 - (t.compLength % 4)) % 4;
      tableDataSize += padding;
    }

    final totalSize = dataOffset + tableDataSize;

    // 计算原始 sfnt 总大小（用于 totalSfntSize 字段）
    int totalSfntSize = 0;
    for (final t in tables) {
      totalSfntSize += t.data.length;
      totalSfntSize += (4 - (t.data.length % 4)) % 4; // 对齐填充
    }
    // 加上 offset table 和 table directory 的大小
    totalSfntSize += 12 + tables.length * 16;

    // 写入 WOFF 文件
    final result = Uint8List(totalSize);
    final bd = result.buffer.asByteData();
    int pos = 0;

    // ── WOFF Header (44 bytes) ──
    final bd_input = ttfBytes.buffer.asByteData(ttfBytes.offsetInBytes, ttfBytes.lengthInBytes);
    bd.setUint32(pos, 0x774F4646);             pos += 4; // signature: 'wOFF'
    // flavor: 从输入 TTF 头部读取原始 sfVersion，透传 TrueType(0x00010000) 或 OTTO(0x4F54544F)
    final flavor = bd_input.getUint32(0);
    bd.setUint32(pos, flavor);                 pos += 4; // flavor
    bd.setUint32(pos, totalSize);   pos += 4; // length
    bd.setUint16(pos, compressedTables.length); pos += 2; // numTables
    bd.setUint16(pos, 0);           pos += 2; // reserved
    bd.setUint32(pos, totalSfntSize); pos += 4; // totalSfntSize
    bd.setUint16(pos, 1);           pos += 2; // majorVersion
    bd.setUint16(pos, 0);           pos += 2; // minorVersion
    bd.setUint32(pos, 0);           pos += 4; // metaOffset
    bd.setUint32(pos, 0);           pos += 4; // metaLength
    bd.setUint32(pos, 0);           pos += 4; // metaOrigLength
    bd.setUint32(pos, 0);           pos += 4; // privOffset
    bd.setUint32(pos, 0);           pos += 4; // privLength

    // ── Table Directory ──
    int dataPos = dataOffset;
    for (final t in compressedTables) {
      // tag（4 字节 ASCII）
      final tagBytes = t.tag.codeUnits;
      result[pos]     = tagBytes[0];
      result[pos + 1] = tagBytes[1];
      result[pos + 2] = tagBytes[2];
      result[pos + 3] = tagBytes[3];
      pos += 4;

      bd.setUint32(pos, dataPos);        pos += 4; // offset
      bd.setUint32(pos, t.compLength);   pos += 4; // compLength
      bd.setUint32(pos, t.origLength);   pos += 4; // origLength
      bd.setUint32(pos, t.origChecksum); pos += 4; // origChecksum

      dataPos += t.compLength;
      dataPos += (4 - (t.compLength % 4)) % 4; // 对齐填充
    }

    // ── Table Data ──
    for (final t in compressedTables) {
      result.setRange(pos, pos + t.compLength, t.compData);
      pos += t.compLength;
      // 填充到 4 字节边界
      final padding = (4 - (t.compLength % 4)) % 4;
      for (int i = 0; i < padding; i++) {
        result[pos++] = 0;
      }
    }

    return result;
  }
}

/// WOFF 表目录条目
class _WoffTableEntry {
  final String tag;
  final Uint8List origData;
  final Uint8List compData;
  final int origLength;
  final int compLength;
  final int origChecksum;
  final bool isCompressed;

  const _WoffTableEntry({
    required this.tag,
    required this.origData,
    required this.compData,
    required this.origLength,
    required this.compLength,
    required this.origChecksum,
    required this.isCompressed,
  });
}

/// SFNT（TrueType/OpenType）表格信息
class _SfntTable {
  final String tag;
  final Uint8List data;
  final int checksum;

  const _SfntTable({
    required this.tag,
    required this.data,
    required this.checksum,
  });
}

/// SFNT 格式读取器 — 从 TTF 二进制中解析表目录和表数据
class _SfntReader {
  final Uint8List data;
  final ByteData _bd;

  _SfntReader(this.data) : _bd = data.buffer.asByteData(
    data.offsetInBytes,
    data.lengthInBytes,
  );

  /// 读取所有表的信息（tag、数据、校验和）
  List<_SfntTable> readTables() {
    // 校验 sfVersion：必须是 TrueType(0x00010000) 或 CFF/OTTO(0x4F54544F)
    final sfVersion = _bd.getUint32(0);
    if (sfVersion != 0x00010000 && sfVersion != 0x4F54544F) {
      throw FormatException(
        'Unsupported sfVersion: 0x${sfVersion.toRadixString(16).padLeft(8, '0')}，'
        'expected TrueType (0x00010000) or CFF (0x4F54544F)',
      );
    }

    // 读取 numTables(2)
    final numTables = _bd.getUint16(4);

    final tables = <_SfntTable>[];
    // Table directory 从偏移 12 开始，每条 16 字节
    int dirPos = 12;
    for (int i = 0; i < numTables; i++) {
      // 读取 tag（4 字节 ASCII）
      final tag = String.fromCharCodes([
        data[dirPos],
        data[dirPos + 1],
        data[dirPos + 2],
        data[dirPos + 3],
      ]);

      final checksum = _bd.getUint32(dirPos + 4);
      final offset = _bd.getUint32(dirPos + 8);
      final length = _bd.getUint32(dirPos + 12);

      // 提取表数据
      final tableData = Uint8List.view(
        data.buffer,
        data.offsetInBytes + offset,
        length,
      );

      tables.add(_SfntTable(
        tag: tag,
        data: Uint8List.fromList(tableData), // 复制为独立内存
        checksum: checksum,
      ));

      dirPos += 16;
    }

    return tables;
  }
}

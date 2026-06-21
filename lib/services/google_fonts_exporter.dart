import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import '../models/project.dart';
import 'ttf_builder.dart';

/// Google Fonts 格式导出器
///
/// 将字体项目导出为符合 Google Fonts 规范的 ZIP 包，
/// 包含 TTF 字体文件、METADATA.json 和 OFL.txt 许可证。
class GoogleFontsExporter {
  GoogleFontsExporter._();

  /// 导出字体项目为 Google Fonts 格式的 ZIP 字节
  ///
  /// ZIP 内容：
  /// - {family}.ttf — TTF 字体文件（复用现有 TtfBuilder）
  /// - METADATA.json — Google Fonts 元数据规范
  /// - OFL.txt — SIL Open Font License
  ///
  /// 返回 ZIP 文件的二进制数据。
  static Uint8List exportToZip(FontProject project) {
    final metadata = project.metadata;
    final familyName = metadata?.familyName ?? project.name;

    // 1. 构建 TTF 字节
    final glyphs = project.glyphs.values.toList();
    final builder = TtfBuilder(
      glyphs: glyphs,
      familyName: project.name,
      unitsPerEm: 1000,
      kerningPairs: project.kerningPairs,
      customFamilyName: familyName,
      customSubfamilyName: metadata?.subfamilyName ?? 'Regular',
      customVersion: metadata?.version ?? 'Version 1.0',
      customCopyright: metadata?.copyright ?? '',
      customDescription: metadata?.description ?? '',
    );
    final ttfBytes = builder.build();

    // 2. 构建 METADATA.json
    final metadataJson = _buildMetadataJson(project, familyName);
    final metadataBytes = utf8.encode(metadataJson);

    // 3. 构建 OFL.txt
    final oflBytes = utf8.encode(_oflText(familyName));

    // 4. 打包 ZIP
    final archive = Archive();

    // TTF 文件
    final safeName = familyName.replaceAll(RegExp(r'[^\w\-]'), '_');
    archive.addFile(ArchiveFile(
      '$safeName.ttf',
      ttfBytes.length,
      ttfBytes,
    ));

    // METADATA.json
    archive.addFile(ArchiveFile(
      'METADATA.json',
      metadataBytes.length,
      metadataBytes,
    ));

    // OFL.txt
    archive.addFile(ArchiveFile(
      'OFL.txt',
      oflBytes.length,
      oflBytes,
    ));

    return Uint8List.fromList(ZipEncoder().encode(archive)!);
  }

  /// 构建符合 Google Fonts 规范的 METADATA.json 内容
  static String _buildMetadataJson(FontProject project, String familyName) {
    final metadata = project.metadata;
    final author = metadata?.author ?? '';
    final description = metadata?.description ?? '';

    // 判断是否包含中文字符 → 决定 subsets
    final hasChinese = project.glyphs.keys.any((ch) =>
        ch.codeUnitAt(0) >= 0x4E00 && ch.codeUnitAt(0) <= 0x9FFF);
    final hasLatin = project.glyphs.keys.any((ch) =>
        ch.codeUnitAt(0) >= 0x0020 && ch.codeUnitAt(0) <= 0x007F);

    final subsets = <String>[];
    if (hasChinese) subsets.add('chinese-simplified');
    if (hasLatin) subsets.add('latin');
    if (subsets.isEmpty) subsets.add('latin');

    // 文件名（与 ZIP 内 TTF 文件名一致）
    final ttfFileName = '${familyName.replaceAll(RegExp(r'[^\w\-]'), '_')}.ttf';

    // Google Fonts METADATA.json 格式
    final map = <String, dynamic>{
      'name': familyName,
      'designer': author.isNotEmpty ? author : familyName,
      'license': 'OFL',
      'category': 'HANDWRITING',
      'subsets': subsets,
      'fonts': [
        {
          'fontFile': ttfFileName,
          'style': 'normal',
          'weight': '400',
        },
      ],
    };

    if (description.isNotEmpty) {
      map['description'] = description;
    }

    return const JsonEncoder.withIndent('  ').convert(map);
  }

  /// 生成 OFL.txt 许可证文本
  static String _oflText(String familyName) {
    return '''SIL Open Font License, Version 1.1
26 February 2007

PREAMBLE
The goals of the Open Font License (OFL) are to stimulate worldwide
development of collaborative font projects, to support the font creation
efforts of academic and linguistic communities, and to provide a free and
open framework in which fonts may be shared and improved in partnership
with others.

The OFL allows the licensed fonts to be used, studied, modified and
redistributed freely as long as they are not sold by themselves. The
fonts, including any derivative works, can be bundled, embedded,
redistributed and/or sold with any software provided that any reserved
names are not used by derivative works. The fonts and derivatives,
however, cannot be released under any other type of license. The
requirement for fonts to remain under this license does not apply to
any document created using the fonts or their derivatives.

DEFINITIONS
"Font Software" refers to the set of files released by the Copyright
Holder(s) under this license and clearly marked as such. This may
include source files, build scripts and documentation.

"Reserved Font Name" refers to any names specified as such after the
copyright statement(s).

"Original Version" refers to the collection of Font Software components
as distributed by the Copyright Holder(s).

"Modified Version" refers to any derivative made by adding to, deleting,
or substituting -- in part or in whole -- any of the components of the
Original Version, by changing formats or by porting the Font Software to
a new environment.

"Author" refers to any designer, engineer, programmer, technical writer
or other person who contributed to the Font Software.

PERMISSION AND CONDITIONS
Permission is hereby granted, free of charge, to any person obtaining a
copy of the Font Software, to use, study, copy, merge, embed, modify,
redistribute, and sell modified and unmodified copies of the Font
Software, subject to the following conditions:

1) Neither the Font Software nor any of its individual components, in
Original or Modified Versions, may be sold by itself.

2) Original or Modified Versions of the Font Software may be bundled,
redistributed and/or sold with any software, provided that each copy
contains the above copyright notice and this license. These can be
included either as stand-alone text files, human-readable headers or
in the appropriate machine-readable metadata fields within text or
binary files as long as those fields can be easily viewed by the user.

3) No Modified Version of the Font Software may use the Reserved Font
Name(s) unless explicit written permission is granted by the
corresponding Copyright Holder. This restriction only applies to the
primary font name as presented to the users.

4) The name(s) of the Copyright Holder(s) or the Author(s) of the Font
Software shall not be used to promote, endorse or advertise any
Modified Version, except to acknowledge the contribution(s) of the
Copyright Holder(s) and the Author(s) or with their explicit written
permission.

5) The Font Software, modified or unmodified, in part or in whole, must
be distributed entirely under this license, and must not be distributed
under any other license. The requirement for fonts to remain under this
license does not apply to any document created using the Font Software.

TERMINATION
This license becomes null and void if any of the above conditions are not met.

DISCLAIMER
THE FONT SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO ANY WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT
OF COPYRIGHT, PATENT, TRADEMARK, OR OTHER RIGHT. IN NO EVENT SHALL THE
COPYRIGHT HOLDER BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
INCLUDING ANY GENERAL, SPECIAL, INDIRECT, INCIDENTAL, OR CONSEQUENTIAL
DAMAGES, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF THE USE OR INABILITY TO USE THE FONT SOFTWARE OR FROM OTHER
DEALINGS IN THE FONT SOFTWARE.

---
Font: $familyName
Generated with WriteFont (手迹造字)
''';
  }

}

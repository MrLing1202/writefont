import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../models/project.dart';
import '../../services/recognition_service.dart';
import '../character_edit_screen.dart';

/// 重试单个字符的 AI 识别
/// 返回识别结果字符，失败返回 null
Future<String?> retryCharacterRecognition(Uint8List cellImage) async {
  final recognitionService = RecognitionService.instance;
  return await recognitionService.recognizeCharacter(cellImage);
}

/// 打开字符编辑对话框
void showCharacterEditDialog(
  BuildContext context, {
  required String currentChar,
  required String projectId,
  required VoidCallback onDeleted,
  required void Function(String newChar) onChanged,
}) {
  final tempGlyph = GlyphData(
    character: currentChar,
    unicode: currentChar.codeUnitAt(0),
    contours: [],
  );

  CharacterEditDialog.show(
    context,
    character: currentChar,
    glyph: tempGlyph,
    projectId: projectId,
    onCharacterChanged: () {
      final newChar = tempGlyph.character;
      if (newChar != currentChar && newChar.isNotEmpty) {
        onChanged(newChar);
      }
    },
    onCharacterDeleted: onDeleted,
  );
}

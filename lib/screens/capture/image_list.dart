import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// 已选图片列表
class CaptureImageList extends StatelessWidget {
  final List<XFile> images;
  final Function(int) onRemove;
  final ColorScheme colorScheme;

  const CaptureImageList({
    super.key,
    required this.images,
    required this.onRemove,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: images.length,
      itemBuilder: (context, index) {
        return Card(
          clipBehavior: Clip.antiAlias,
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                File(images[index].path),
                width: 56,
                height: 56,
                fit: BoxFit.cover,
                cacheWidth: 200,
                cacheHeight: 200,
              ),
            ),
            title: Text('图片 ${index + 1}'),
            subtitle: FutureBuilder<File>(
              future: Future.value(File(images[index].path)),
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  return FutureBuilder<int>(
                    future: snapshot.data!.length(),
                    builder: (context, sizeSnapshot) {
                      if (sizeSnapshot.hasData) {
                        return Text(
                          '${(sizeSnapshot.data! / 1024).toStringAsFixed(1)} KB',
                        );
                      }
                      return const SizedBox();
                    },
                  );
                }
                return const SizedBox();
              },
            ),
            trailing: IconButton(
              icon: Icon(Icons.delete_outline, color: colorScheme.error),
              onPressed: () => onRemove(index),
            ),
          ),
        );
      },
    );
  }
}

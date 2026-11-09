import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'storage.dart';

/// iPhone/iPad/Android: the photo is a file in the app's storage, saved by
/// its storage-relative path so it survives app updates (see
/// [AppStorage.storedPicturePath]) and is included in backups.
Future<String> savePhoto(Uint8List png) async {
  final storage = AppStorage.current ?? await AppStorage.instance();
  final dir = Directory(p.join(storage.root.path, 'photos'));
  await dir.create(recursive: true);
  final file =
      File(p.join(dir.path, 'photo_${DateTime.now().millisecondsSinceEpoch}.png'));
  await file.writeAsBytes(png, flush: true);
  return storage.storedPicturePath(file.path);
}

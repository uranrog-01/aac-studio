import 'dart:io';
import 'package:flutter/widgets.dart';

import 'storage_native.dart';

/// Draws a saved picture. Board paths inside the app's storage are relative
/// (see [AppStorage.storedPicturePath]) and are resolved against the
/// current data folder, which iOS may move between app versions.
/// Photos from the web app (data URLs, restored from a web backup) and
/// online picture links are drawn too, so boards move between devices.
Widget referenceImage(String path,
    {double? width,
    double? height,
    BoxFit? fit,
    ImageErrorWidgetBuilder? errorBuilder}) {
  final uri = Uri.tryParse(path);
  if (uri?.scheme == 'data') {
    try {
      return Image.memory(UriData.parse(path).contentAsBytes(),
          width: width, height: height, fit: fit, errorBuilder: errorBuilder);
    } catch (e) {
      return Builder(
          builder: (context) =>
              errorBuilder?.call(context, e, null) ?? const SizedBox.shrink());
    }
  }
  if (uri?.scheme == 'https' || uri?.scheme == 'http') {
    return Image.network(path,
        width: width, height: height, fit: fit, errorBuilder: errorBuilder);
  }
  return Image.file(File(AppStorage.current?.resolvePicturePath(path) ?? path),
      width: width, height: height, fit: fit, errorBuilder: errorBuilder);
}

/// The image behind [referenceImage] (to learn a photo's shape), or null.
ImageProvider? referenceImageProvider(String path) {
  final uri = Uri.tryParse(path);
  try {
    if (uri?.scheme == 'data') {
      return MemoryImage(UriData.parse(path).contentAsBytes());
    }
    if (uri?.scheme == 'https' || uri?.scheme == 'http') {
      return NetworkImage(path);
    }
    return FileImage(File(AppStorage.current?.resolvePicturePath(path) ?? path));
  } catch (_) {
    return null;
  }
}

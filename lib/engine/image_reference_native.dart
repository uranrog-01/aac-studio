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

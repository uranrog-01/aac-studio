import 'dart:io';
import 'package:flutter/widgets.dart';

import 'storage_native.dart';

/// Draws a saved picture. Board paths inside the app's storage are relative
/// (see [AppStorage.storedPicturePath]) and are resolved against the
/// current data folder, which iOS may move between app versions.
Widget referenceImage(String path,
        {double? width,
        double? height,
        BoxFit? fit,
        ImageErrorWidgetBuilder? errorBuilder}) =>
    Image.file(File(AppStorage.current?.resolvePicturePath(path) ?? path),
        width: width, height: height, fit: fit, errorBuilder: errorBuilder);

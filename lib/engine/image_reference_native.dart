import 'dart:io';
import 'package:flutter/widgets.dart';

Widget referenceImage(String path,
        {double? width,
        double? height,
        BoxFit? fit,
        ImageErrorWidgetBuilder? errorBuilder}) =>
    Image.file(File(path),
        width: width, height: height, fit: fit, errorBuilder: errorBuilder);

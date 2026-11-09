import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';

import 'photo_store_native.dart'
    if (dart.library.js_interop) 'photo_store_web.dart';

/// Lets a caregiver use their own photo on a button (family, school, a
/// favourite cup) on every device: iPhone/iPad, Android and the web app.
class PhotoPicker {
  /// Longest side of a stored photo, enough for the largest tablet button.
  static const maxSide = 512;

  /// Opens the photo library / files. Returns a picture path for
  /// [SymbolRef.imagePath], or null when the person cancelled.
  /// Throws when the photo cannot be read.
  static Future<String?> pick() async {
    final file = await FilePicker.pickFile(
        type: FileType.image,
        // iOS: hand over a JPEG (not HEIC), which every platform decodes.
        compressionQuality: 90,
        dialogTitle: 'Choose a photo');
    if (file == null) return null;
    final png = await shrink(await file.readAsBytes());
    return savePhoto(png);
  }

  /// Decodes any common image and re-encodes it as a PNG no larger than
  /// [maxSide] pixels on its longest side.
  static Future<Uint8List> shrink(Uint8List bytes) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final scale =
        math.min(1.0, maxSide / math.max(descriptor.width, descriptor.height));
    final codec = await descriptor.instantiateCodec(
        targetWidth: math.max(1, (descriptor.width * scale).round()),
        targetHeight: math.max(1, (descriptor.height * scale).round()));
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
    if (data == null) throw StateError('Photo could not be converted');
    return data.buffer.asUint8List();
  }
}

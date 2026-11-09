import 'dart:convert';
import 'dart:typed_data';

/// Web app: the browser has no app folder, so the (small) photo is kept in
/// the board itself as a data URL. It is saved and backed up with the board.
Future<String> savePhoto(Uint8List png) async =>
    'data:image/png;base64,${base64Encode(png)}';

import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../studio/studio_home.dart';

void initialize() {
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
}

Widget studioHome() => const StudioHome();

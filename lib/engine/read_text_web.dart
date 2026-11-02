import 'storage_web.dart';

Future<String> readTextFile(String path) =>
    BrowserStorageFile(path).readAsString();

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'speech.dart';

/// Tiny service locator for the speech engine.
class SpeechEngineProvider {
  static SpeechEngine of(BuildContext context) =>
      Provider.of<SpeechEngine>(context, listen: false);
}

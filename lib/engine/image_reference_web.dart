import 'package:flutter/widgets.dart';

Widget referenceImage(String path,
    {double? width,
    double? height,
    BoxFit? fit,
    ImageErrorWidgetBuilder? errorBuilder}) {
  final uri = Uri.tryParse(path);
  if (uri?.scheme == 'data') {
    return Image.memory(UriData.parse(path).contentAsBytes(),
        width: width, height: height, fit: fit, errorBuilder: errorBuilder);
  }
  if (uri?.scheme == 'https' || uri?.scheme == 'http') {
    return Image.network(path,
        width: width, height: height, fit: fit, errorBuilder: errorBuilder);
  }
  // A backup from a native app may contain an unavailable local file.
  return Builder(
      builder: (context) =>
          errorBuilder?.call(
              context, StateError('Local image unavailable'), null) ??
          const IconPlaceholder());
}

// Local paths from another device cannot be rendered by a browser.
class IconPlaceholder extends StatelessWidget {
  const IconPlaceholder({super.key});
  @override
  Widget build(BuildContext context) => const Text('▧');
}

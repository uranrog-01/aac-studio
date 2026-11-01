import 'package:flutter/material.dart';

/// M0 studio shell: physical device frames with correct logical sizes so the
/// SAME app can be previewed as iPhone / iPad / Android tablet on Windows.

class DeviceSpec {
  final String name;
  final Size logical;
  final double radius;
  final bool hasNotch;
  final String emoji;
  final int maxGridColumns;
  const DeviceSpec(this.name, this.logical,
      {required this.radius, this.hasNotch = false, this.emoji = '📱', this.maxGridColumns = 6});
}

const kDevices = <DeviceSpec>[
  DeviceSpec('iPhone 15', Size(393, 852), radius: 54, hasNotch: true, emoji: '📱', maxGridColumns: 6),
  DeviceSpec('iPhone SE', Size(375, 667), radius: 44, emoji: '📱', maxGridColumns: 5),
  DeviceSpec('iPad Air 11"', Size(820, 1184), radius: 20, emoji: '📲', maxGridColumns: 9),
  DeviceSpec('Android Tablet', Size(800, 1280), radius: 18, emoji: '🖥️', maxGridColumns: 9),
];

/// Selected device + orientation, shared app-wide via ValueNotifier.
class DeviceMode {
  final DeviceSpec spec;
  final bool landscape;
  const DeviceMode(this.spec, {this.landscape = false});
}

class DeviceFrame extends StatelessWidget {
  final DeviceSpec spec;
  final bool landscape;
  final Widget child;

  const DeviceFrame({
    super.key,
    required this.spec,
    this.landscape = false,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final portrait = spec.logical;
    final screen = landscape ? Size(portrait.height, portrait.width) : portrait;
    const bezel = 12.0;
    final outer = Size(screen.width + bezel * 2, screen.height + bezel * 2);

    return FittedBox(
      fit: BoxFit.contain,
      child: Container(
        width: outer.width,
        height: outer.height,
        decoration: BoxDecoration(
          color: const Color(0xFF17181C),
          borderRadius: BorderRadius.circular(spec.radius + bezel),
          boxShadow: const [
            BoxShadow(color: Colors.black38, blurRadius: 24, offset: Offset(0, 10)),
          ],
        ),
        padding: const EdgeInsets.all(bezel),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(spec.radius),
          child: SizedBox(
            width: screen.width,
            height: screen.height,
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(size: screen),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

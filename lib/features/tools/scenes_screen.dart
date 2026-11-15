import 'package:flutter/material.dart';

import '../../engine/i18n.dart';
import '../../engine/image_reference.dart';
import '../../engine/photo_picker.dart';
import '../../engine/storage.dart';
import '../grid/grid_screen.dart';
import 'tools.dart';

/// One talking spot on a photo; x and y are 0..1 of the photo's size.
class SceneSpot {
  double x, y;
  String text;
  SceneSpot(this.x, this.y, this.text);
  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'text': text};
  static SceneSpot fromJson(Map<String, dynamic> j) => SceneSpot(
      (j['x'] as num?)?.toDouble() ?? 0.5,
      (j['y'] as num?)?.toDouble() ?? 0.5,
      (j['text'] as String?) ?? '');
}

/// A visual scene: a real photo (the kitchen, grandma's garden) with spots
/// that speak when touched.
class Scene {
  String id, name, image;
  final List<SceneSpot> spots;
  Scene(this.id, this.name, this.image, [List<SceneSpot>? spots])
      : spots = spots ?? [];
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'image': image,
        'spots': [for (final s in spots) s.toJson()],
      };
  static Scene fromJson(Map<String, dynamic> j) => Scene(
        (j['id'] as String?) ?? '',
        (j['name'] as String?) ?? '',
        (j['image'] as String?) ?? '',
        [
          for (final s in (j['spots'] as List? ?? const []))
            if (s is Map<String, dynamic>) SceneSpot.fromJson(s),
        ],
      );
}

/// Saved scenes live in their own small file on the device.
class SceneStore {
  static Future<List<Scene>> load() async {
    try {
      final storage = await AppStorage.instance();
      final json = await storage.readJson(storage.dataFile('scenes.json'));
      return [
        for (final s in (json?['scenes'] as List? ?? const []))
          if (s is Map<String, dynamic>) Scene.fromJson(s),
      ];
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<Scene> scenes) async {
    final storage = await AppStorage.instance();
    await storage.writeJson(storage.dataFile('scenes.json'),
        {'scenes': [for (final s in scenes) s.toJson()]});
  }
}

class ScenesScreen extends StatefulWidget {
  final GridSession session;
  const ScenesScreen({super.key, required this.session});

  @override
  State<ScenesScreen> createState() => _ScenesScreenState();
}

class _ScenesScreenState extends State<ScenesScreen> {
  List<Scene>? _scenes;

  @override
  void initState() {
    super.initState();
    SceneStore.load().then((s) {
      if (mounted) setState(() => _scenes = s);
    });
  }

  Future<void> _add() async {
    if (!await caregiverAllowed(context) || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    String? image;
    try {
      image = await PhotoPicker.pick(maxSide: 1400);
    } catch (_) {
      messenger.showSnackBar(SnackBar(
          content: Text(I18n.t('This photo could not be opened.'))));
      return;
    }
    if (image == null || !mounted) return;
    final name = await _askText(context, 'Name of the photo', '');
    final scene = Scene('scene_${DateTime.now().millisecondsSinceEpoch}',
        (name == null || name.isEmpty) ? I18n.t('My photo') : name, image);
    setState(() => _scenes = [...?_scenes, scene]);
    await SceneStore.save(_scenes!);
    if (!mounted) return;
    await _open(scene, edit: true);
  }

  Future<void> _open(Scene scene, {bool edit = false}) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _SceneView(
          scene: scene,
          session: widget.session,
          startEditing: edit,
          onChanged: () => SceneStore.save(_scenes ?? [])),
    ));
    if (mounted) setState(() {});
  }

  Future<void> _delete(Scene scene) async {
    if (!await caregiverAllowed(context) || !mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(I18n.t('Delete this photo?')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(I18n.t('Cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(I18n.t('Delete'))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _scenes!.remove(scene));
    await SceneStore.save(_scenes!);
  }

  @override
  Widget build(BuildContext context) {
    final scenes = _scenes;
    return ToolPage(
      title: 'My photos',
      actions: [
        IconButton(
            tooltip: I18n.t('Add a photo'),
            onPressed: _add,
            icon: const Icon(Icons.add_a_photo_outlined)),
      ],
      body: scenes == null
          ? const Center(child: CircularProgressIndicator())
          : scenes.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.photo_library_outlined,
                          size: 64, color: Colors.white54),
                      const SizedBox(height: 12),
                      Text(
                          I18n.t('Add a real photo (the kitchen, the park, '
                              'family) and touch spots on it to make them talk.'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 17)),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                          onPressed: _add,
                          icon: const Icon(Icons.add_a_photo),
                          label: Text(I18n.t('Add a photo'))),
                    ]),
                  ),
                )
              : GridView.extent(
                  maxCrossAxisExtent: 260,
                  padding: const EdgeInsets.all(12),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1,
                  children: [
                    for (final s in scenes)
                      Material(
                        color: const Color(0xFF3A3F48),
                        borderRadius: BorderRadius.circular(14),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => _open(s),
                          onLongPress: () => _delete(s),
                          child: Column(children: [
                            Expanded(
                              child: SizedBox.expand(
                                child: referenceImage(s.image,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Icon(
                                        Icons.broken_image,
                                        color: Colors.white38)),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text(s.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700)),
                            ),
                          ]),
                        ),
                      ),
                  ],
                ),
    );
  }
}

Future<String?> _askText(BuildContext context, String title, String initial) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(I18n.t(title)),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        onSubmitted: (v) => Navigator.pop(c, v.trim()),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(c), child: Text(I18n.t('Cancel'))),
        FilledButton(
            onPressed: () => Navigator.pop(c, controller.text.trim()),
            child: Text(I18n.t('Save'))),
      ],
    ),
  );
}

class _SceneView extends StatefulWidget {
  final Scene scene;
  final GridSession session;
  final bool startEditing;
  final Future<void> Function() onChanged;
  const _SceneView(
      {required this.scene,
      required this.session,
      required this.startEditing,
      required this.onChanged});

  @override
  State<_SceneView> createState() => _SceneViewState();
}

class _SceneViewState extends State<_SceneView> {
  late bool _editing = widget.startEditing;
  int? _lit;

  Future<void> _toggleEdit() async {
    if (!_editing && !await caregiverAllowed(context)) return;
    setState(() => _editing = !_editing);
  }

  Future<void> _tapAt(Offset local, Size size) async {
    if (!_editing) return;
    final text = await _askText(context, 'What does this spot say?', '');
    if (text == null || text.isEmpty) return;
    setState(() => widget.scene.spots.add(SceneSpot(
        (local.dx / size.width).clamp(0.0, 1.0),
        (local.dy / size.height).clamp(0.0, 1.0),
        text)));
    await widget.onChanged();
  }

  Future<void> _spot(int i) async {
    final spot = widget.scene.spots[i];
    if (!_editing) {
      setState(() => _lit = i);
      widget.session.sayNow(spot.text);
      Future.delayed(const Duration(milliseconds: 900), () {
        if (mounted && _lit == i) setState(() => _lit = null);
      });
      return;
    }
    final text = await _askText(context, 'What does this spot say?', spot.text);
    if (text == null) return;
    setState(() {
      if (text.isEmpty) {
        widget.scene.spots.removeAt(i);
      } else {
        spot.text = text;
      }
    });
    await widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final scene = widget.scene;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF22262D),
        foregroundColor: Colors.white,
        title: Text(scene.name),
        actions: [
          TextButton.icon(
            onPressed: _toggleEdit,
            icon: Icon(_editing ? Icons.check : Icons.edit,
                color: Colors.white),
            label: Text(I18n.t(_editing ? 'Done' : 'Edit'),
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          if (_editing)
            Container(
              width: double.infinity,
              color: const Color(0xFFFFB300),
              padding: const EdgeInsets.all(8),
              child: Text(
                  I18n.t('Touch the photo to add a talking spot. Touch a spot '
                      'to change it; leave the text empty to remove it.'),
                  style: const TextStyle(
                      color: Colors.black87, fontWeight: FontWeight.w700)),
            ),
          Expanded(
            child: Center(
              child: _PhotoWithSpots(
                scene: scene,
                lit: _lit,
                editing: _editing,
                onTapPhoto: _tapAt,
                onTapSpot: _spot,
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// The photo at its own shape, with the spots placed on top of it.
class _PhotoWithSpots extends StatefulWidget {
  final Scene scene;
  final int? lit;
  final bool editing;
  final void Function(Offset local, Size size) onTapPhoto;
  final void Function(int index) onTapSpot;
  const _PhotoWithSpots(
      {required this.scene,
      required this.lit,
      required this.editing,
      required this.onTapPhoto,
      required this.onTapSpot});

  @override
  State<_PhotoWithSpots> createState() => _PhotoWithSpotsState();
}

class _PhotoWithSpotsState extends State<_PhotoWithSpots> {
  double? _aspect;

  @override
  void initState() {
    super.initState();
    _resolveAspect();
  }

  void _resolveAspect() {
    final provider = referenceImageProvider(widget.scene.image);
    if (provider == null) return;
    provider.resolve(const ImageConfiguration()).addListener(
        ImageStreamListener((info, _) {
      if (mounted) {
        setState(() => _aspect = info.image.width / info.image.height);
      }
    }, onError: (_, __) {}));
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: _aspect ?? 4 / 3,
      child: LayoutBuilder(builder: (context, c) {
        final size = c.biggest;
        return GestureDetector(
          onTapUp: (d) => widget.onTapPhoto(d.localPosition, size),
          child: Stack(children: [
            Positioned.fill(
              child: referenceImage(widget.scene.image, fit: BoxFit.fill),
            ),
            for (var i = 0; i < widget.scene.spots.length; i++)
              Positioned(
                left: widget.scene.spots[i].x * size.width - 34,
                top: widget.scene.spots[i].y * size.height - 34,
                child: GestureDetector(
                  onTap: () => widget.onTapSpot(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.lit == i
                          ? const Color(0xCCFFB300)
                          : const Color(0x55FFFFFF),
                      border: Border.all(
                          color: widget.editing
                              ? const Color(0xFFFFB300)
                              : Colors.white,
                          width: 3),
                    ),
                    alignment: Alignment.center,
                    child: widget.editing || widget.lit == i
                        ? Padding(
                            padding: const EdgeInsets.all(4),
                            child: Text(widget.scene.spots[i].text,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: Colors.black,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800)),
                          )
                        : null,
                  ),
                ),
              ),
          ]),
        );
      }),
    );
  }
}

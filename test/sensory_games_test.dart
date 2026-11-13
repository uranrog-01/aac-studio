import 'package:aac_studio/features/sensory/sensory_games.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every sensory game opens, animates and answers touches without errors,
/// on a phone and on a tablet.
void main() {
  // Tests have no audio player; the games are checked silently.
  sensorySoundsOn = false;
  for (final size in const [Size(390, 844), Size(1180, 820)]) {
    for (final game in kSensoryGames) {
      testWidgets('${game.id} plays at ${size.width.round()} wide',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
            MaterialApp(home: SensoryGamesScreen(game: game.id)));
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        final centre = size.center(Offset.zero);
        // Two fingers at once: tap, then drag across the screen.
        final a = await tester.startGesture(centre - const Offset(90, 40));
        final b = await tester.startGesture(centre + const Offset(80, 60));
        for (var i = 0; i < 12; i++) {
          await a.moveBy(const Offset(14, 9));
          await b.moveBy(const Offset(-12, 11));
          await tester.pump(const Duration(milliseconds: 40));
        }
        await a.up();
        await b.up();
        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(tester.takeException(), isNull);
        // Moving games keep animating by themselves.
        if (!const {'hear', 'pairs'}.contains(game.id)) {
          expect(tester.binding.hasScheduledFrame, isTrue);
        }
      });
    }
  }

  testWidgets('the menu lists every game and opens one', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SensoryGamesScreen()));
    await tester.pump();
    expect(kSensoryGames.map((g) => g.id), isNot(contains('breathe')));
    for (final game in kSensoryGames) {
      await tester.scrollUntilVisible(find.text(game.word), 200,
          scrollable: find.byType(Scrollable).first);
      expect(find.text(game.word), findsOneWidget);
    }
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 4000));
    await tester.pumpAndSettle();
    await tester.tap(find.text(kSensoryGames.first.word));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(kSensoryGames.last.word), findsNothing);
    // Back returns to the menu.
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(kSensoryGames.first.word), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

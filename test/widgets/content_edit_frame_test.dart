import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honoo/Widgets/content_edit_frame.dart';

void main() {
  testWidgets('owned conversation card lets swipes reach the timeline', (
    tester,
  ) async {
    var page = 0;
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PageView(
            scrollDirection: Axis.vertical,
            onPageChanged: (value) => page = value,
            children: [
              const ColoredBox(color: Colors.white),
              ContentEditFrame(
                width: 360,
                height: 600,
                overlayControls: true,
                onImage: () => taps++,
                onText: () {},
                child: const ColoredBox(color: Colors.black),
              ),
            ],
          ),
        ),
      ),
    );
    final pager = find.byType(PageView);
    for (final fromButton in [false, true]) {
      await tester.drag(pager, const Offset(0, -450));
      await tester.pumpAndSettle();
      expect(page, 1);
      final button = find.byKey(const Key('content-edit-image'));
      await tester.drag(fromButton ? button : pager, const Offset(0, 450));
      await tester.pumpAndSettle();
      expect(page, 0);
      expect(taps, 0);
    }
  });

  for (final size in [
    const Size(320, 480),
    const Size(390, 800),
    const Size(900, 700),
  ]) {
    testWidgets('editing actions preserve canvas dimensions at $size', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var imageTaps = 0;
      var textTaps = 0;
      final width = size.width < 360 ? size.width : 360.0;
      final height = size.height - 20;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContentEditFrame(
              width: width,
              height: height,
              onImage: () => imageTaps++,
              onText: () => textTaps++,
              child: const ColoredBox(key: Key('canvas'), color: Colors.white),
            ),
          ),
        ),
      );
      final canvas = tester.getRect(find.byKey(const Key('canvas')));
      final image = tester.getRect(find.byKey(const Key('content-edit-image')));
      final text = tester.getRect(find.byKey(const Key('content-edit-text')));
      expect(canvas.size, Size(width, height));
      expect(image.bottom, lessThanOrEqualTo(canvas.top));
      expect(text.bottom, lessThanOrEqualTo(canvas.top));
      expect(image.right, lessThan(text.left));
      await tester.tap(find.byKey(const Key('content-edit-image')));
      await tester.tap(find.byKey(const Key('content-edit-text')));
      expect(imageTaps, 1);
      expect(textTaps, 1);
      expect(tester.takeException(), isNull);
    });
  }
}

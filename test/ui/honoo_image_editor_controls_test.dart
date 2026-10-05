import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:honoo/UI/honoo_builder.dart';
import 'package:honoo/Utility/honoo_colors.dart';

void main() {
  testWidgets('i controlli immagine honoo hanno il nuovo posizionamento', (
    tester,
  ) async {
    final key = GlobalKey<HonooBuilderState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              height: 549,
              child: HonooBuilder(key: key, initialText: 'Testo iniziale'),
            ),
          ),
        ),
      ),
    );

    final emptyImageIcon = tester.widget<SvgPicture>(
      find.descendant(
        of: find.byKey(const Key('honoo-image-area')),
        matching: find.byType(SvgPicture),
      ),
    );
    expect(
      (emptyImageIcon.bytesLoader as SvgAssetLoader).assetName,
      'assets/icons/immagine.svg',
    );
    expect(
      emptyImageIcon.colorFilter,
      const ColorFilter.mode(HonooColor.primary, BlendMode.srcIn),
    );

    key.currentState!.setImageBytesForTesting(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      ),
    );
    await tester.pumpAndSettle();

    final panel = find.byKey(const Key('honoo-image-editing-controls'));
    final replace = find.byKey(const Key('honoo-replace-editing-image'));
    final editText = find.byKey(const Key('honoo-edit-text'));
    final save = find.byKey(const Key('honoo-save'));
    final zoomSlider = find.byKey(const Key('honoo-image-zoom-slider'));

    final textArea = find.byKey(const Key('honoo-text-area'));
    final imageArea = find.byKey(const Key('honoo-image-area'));
    final exportRect = tester.getRect(
      find.byKey(const Key('honoo-export-content')),
    );
    expect(exportRect.left, closeTo(tester.getRect(imageArea).left, 0.01));
    expect(exportRect.right, closeTo(tester.getRect(imageArea).right, 0.01));
    expect(exportRect.top, closeTo(tester.getRect(textArea).top, 0.01));
    expect(exportRect.bottom, closeTo(tester.getRect(imageArea).bottom, 0.01));
    expect(exportRect.top, greaterThanOrEqualTo(tester.getRect(panel).bottom));
    expect(textArea, findsOneWidget);
    expect(find.text('Testo iniziale'), findsOneWidget);
    expect(replace, findsOneWidget);
    expect(editText, findsOneWidget);
    expect(save, findsOneWidget);
    expect(zoomSlider, findsOneWidget);
    expect(
      tester.getRect(panel).bottom,
      lessThanOrEqualTo(tester.getRect(textArea).top),
    );
    expect(tester.getCenter(replace).dx, lessThan(tester.getCenter(panel).dx));
    expect(
      tester.getCenter(editText).dx,
      greaterThan(tester.getCenter(panel).dx),
    );
    expect(
      tester.getCenter(replace).dy,
      closeTo(tester.getCenter(editText).dy, 0.5),
    );
    expect(tester.getCenter(save).dx, closeTo(tester.getCenter(panel).dx, 0.5));
    expect(
      tester.getCenter(save).dy,
      closeTo(tester.getCenter(replace).dy, 0.5),
    );
    expect(find.text('Sostituisci immagine'), findsNothing);
    expect(find.text('Modifica testo'), findsNothing);
    expect(find.text('Salva honoo'), findsNothing);
    expect(
      find.descendant(of: imageArea, matching: find.byIcon(Icons.remove)),
      findsNothing,
    );
    expect(
      find.descendant(of: imageArea, matching: find.byIcon(Icons.add)),
      findsNothing,
    );

    final imageRect = tester.getRect(imageArea);
    final sliderRect = tester.getRect(zoomSlider);
    expect(imageRect.contains(sliderRect.topLeft), isTrue);
    expect(imageRect.contains(sliderRect.bottomRight), isTrue);
    expect(sliderRect.top - imageRect.top, lessThan(imageRect.height * 0.12));

    final slider = tester.widget<Slider>(zoomSlider);
    expect(slider.min, 1);
    expect(slider.max, 5);
    expect(slider.divisions, 40);
    final sliderTheme = tester.widget<SliderTheme>(
      find.ancestor(of: zoomSlider, matching: find.byType(SliderTheme)).first,
    );
    expect(sliderTheme.data.thumbColor, Colors.white);

    final replaceButton = tester.widget<IconButton>(replace);
    final editButton = tester.widget<IconButton>(editText);
    final replaceIcon = tester.widget<SvgPicture>(
      find.descendant(of: replace, matching: find.byType(SvgPicture)),
    );
    final editIcon = tester.widget<SvgPicture>(
      find.descendant(of: editText, matching: find.byType(SvgPicture)),
    );
    final saveIcon = tester.widget<SvgPicture>(
      find.descendant(of: save, matching: find.byType(SvgPicture)),
    );
    expect(replaceButton.iconSize, closeTo(saveIcon.width! * 0.82, 0.01));
    expect(editButton.iconSize, replaceButton.iconSize);
    expect(
      (replaceIcon.bytesLoader as SvgAssetLoader).assetName,
      'assets/icons/immagine.svg',
    );
    expect(
      (editIcon.bytesLoader as SvgAssetLoader).assetName,
      'assets/icons/modifica testo.svg',
    );
    for (final icon in [replaceIcon, editIcon]) {
      expect(
        icon.colorFilter,
        const ColorFilter.mode(HonooColor.onBackground, BlendMode.srcIn),
      );
    }

    expect(tester.widget<IconButton>(replace).color, isNotNull);
    expect(
      tester
          .widget<Tooltip>(
            find.ancestor(of: replace, matching: find.byType(Tooltip)),
          )
          .message,
      'Sostituisci immagine',
    );
    expect(
      tester
          .widget<Tooltip>(
            find.ancestor(of: save, matching: find.byType(Tooltip)),
          )
          .message,
      'Salva honoo',
    );
    expect(
      tester
          .widget<Tooltip>(
            find.ancestor(of: editText, matching: find.byType(Tooltip)),
          )
          .message,
      'Modifica testo',
    );
    for (final action in [replace, save, editText]) {
      expect(
        tester
            .widget<Tooltip>(
              find.ancestor(of: action, matching: find.byType(Tooltip)),
            )
            .preferBelow,
        isFalse,
      );
    }
  });

  for (final explicitConfirmation in [false, true]) {
    testWidgets(
      'image first allows direct text entry (confirmation: $explicitConfirmation)',
      (tester) async {
        final key = GlobalKey<HonooBuilderState>();
        String latestText = '';
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 360,
                  height: 549,
                  child: HonooBuilder(
                    key: key,
                    requireExplicitConfirmation: explicitConfirmation,
                    onHonooChanged: (text, _) => latestText = text,
                  ),
                ),
              ),
            ),
          ),
        );
        key.currentState!.setImageBytesForTesting(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
          ),
        );
        await tester.pumpAndSettle();
        final field = find.byType(TextField);
        await tester.tap(field);
        await tester.pump();
        expect(tester.widget<TextField>(field).readOnly, isFalse);
        expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
        await tester.enterText(field, 'Prima immagine, poi testo');
        expect(latestText, 'Prima immagine, poi testo');
        await tester.tap(find.byKey(const Key('honoo-image-area')));
        await tester.pump();
        expect(tester.widget<TextField>(field).focusNode!.hasFocus, isFalse);
        await tester.tap(field);
        await tester.enterText(field, 'Testo aggiornato');
        expect(latestText, 'Testo aggiornato');
        expect(
          find.byKey(const Key('honoo-image-zoom-slider')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Modifica testo conserva il testo e consente il ritorno', (
    tester,
  ) async {
    final key = GlobalKey<HonooBuilderState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              height: 549,
              child: HonooBuilder(key: key, initialText: 'Testo iniziale'),
            ),
          ),
        ),
      ),
    );

    key.currentState!.setImageBytesForTesting(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isFalse);

    await tester.tap(find.byKey(const Key('honoo-edit-text')));
    await tester.pump();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Testo iniziale'), findsOneWidget);
    expect(
      find.byKey(const Key('honoo-image-editing-controls')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('honoo-save-edited-text')), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isFalse);

    await tester.enterText(find.byType(TextField), 'Testo modificato');
    await tester.tap(find.byKey(const Key('honoo-image-area')));
    await tester.pump();

    expect(
      find.byKey(const Key('honoo-image-editing-controls')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('honoo-edit-text')), findsOneWidget);

    await tester.tap(find.byKey(const Key('honoo-edit-text')));
    await tester.pump();
    expect(find.text('Testo modificato'), findsOneWidget);
  });
}

import 'dart:ui' as ui;
import 'package:mocktail/mocktail.dart';
import 'package:honoo/Widgets/responsive_footer_bar.dart';
import '../test_supabase_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:honoo/Pages/new_hinoo_page.dart';
import 'package:honoo/UI/hinoo_builder.dart';
import 'package:honoo/UI/hinoo_typography.dart';
import 'package:honoo/Utility/honoo_colors.dart';
import 'package:honoo/Entities/hinoo.dart';
import 'package:sizer/sizer.dart';

void main() {
  setUpAll(registerSupabaseFallbacks);

  testWidgets('double save inserts one hinoo and unlocks after completion', (
    tester,
  ) async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.white, BlendMode.src);
    final picture = recorder.endRecording();
    final image = await tester.runAsync(() => picture.toImage(1, 1));
    picture.dispose();
    PaintingBinding.instance.imageCache.putIfAbsent(
      const NetworkImage('https://example.com/bg.png'),
      () =>
          OneFrameImageStreamCompleter(Future.value(ImageInfo(image: image!))),
    );
    final harness = SupabaseTestHarness(withAuthenticatedUser: true)
      ..enableOverrides();
    addTearDown(harness.disableOverrides);
    harness.stubTable('honoo').queueResponse([
      {'id': 'existing-root'},
    ]);
    final chain = harness.stubTable('hinoo');
    chain.queueResponse({'id': 'saved-hinoo'});
    await tester.pumpWidget(
      Sizer(
        builder: (_, _, _) => const MaterialApp(
          home: NewHinooPage(
            initialDraft: HinooDraft(
              pages: [
                HinooSlide(
                  backgroundImage: 'https://example.com/bg.png',
                  text: 'Testo',
                  isTextWhite: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final action = tester
        .widgetList<ResponsiveFooterBar>(find.byType(ResponsiveFooterBar))
        .expand((bar) => bar.actions)
        .firstWhere((action) => action.tooltip == 'Salva hinoo');
    action.onPressed!();
    action.onPressed!();
    await tester.pumpAndSettle();
    verify(() => chain.insert(any())).called(1);
    expect(
      find.text("L'hinoo è stato salvato nel tuo Scrigno"),
      findsOneWidget,
    );
    await tester.tap(find.text('No'));
    await tester.pumpAndSettle();
    final nextAction = tester
        .widgetList<ResponsiveFooterBar>(find.byType(ResponsiveFooterBar))
        .expand((bar) => bar.actions)
        .firstWhere((action) => action.tooltip == 'Salva hinoo');
    expect(nextAction.onPressed, isNotNull);
  });

  testWidgets(
    'il campanello mostra salva al centro solo dopo aver avviato una modifica',
    (tester) async {
      await tester.pumpWidget(
        Sizer(
          builder: (context, orientation, deviceType) {
            return const MaterialApp(
              home: NewHinooPage(
                isCampanello: true,
                editingCampanelloId: 'campanello-1',
                initialDraft: HinooDraft(
                  pages: [
                    HinooSlide(
                      backgroundImage: null,
                      text: 'Il mio campanello',
                      isTextWhite: true,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('campanello-edit-image')), findsOneWidget);
      expect(find.byKey(const Key('campanello-edit-text')), findsOneWidget);
      expect(find.byKey(const Key('campanello-save-changes')), findsNothing);

      await tester.tap(find.byKey(const Key('campanello-edit-text')));
      await tester.pump();

      expect(find.byKey(const Key('campanello-save-changes')), findsOneWidget);
      final textFieldFinder = find.byType(TextField);
      final textField = tester.widget<TextField>(textFieldFinder);
      expect(
        (textField.decoration!.contentPadding! as EdgeInsets).top,
        greaterThan(0),
      );
      final viewportPadding = tester.widget<Padding>(
        find.byKey(const ValueKey('builder-text-viewport-padding')),
      );
      final viewportWidth = tester
          .getSize(find.byKey(const ValueKey('builder-text-viewport-padding')))
          .width;
      expect(
        viewportPadding.padding,
        HinooTypography.campanelloTextViewportPadding(viewportWidth),
      );

      final twentyLines = List.generate(
        20,
        (index) => '${index + 1}',
      ).join('\n');
      await tester.enterText(textFieldFinder, twentyLines);
      await tester.pump();
      expect(
        tester.widget<TextField>(textFieldFinder).controller!.text,
        twentyLines,
      );

      await tester.enterText(textFieldFinder, '$twentyLines\n21');
      await tester.pump();
      expect(
        tester.widget<TextField>(textFieldFinder).controller!.text,
        twentyLines,
      );

      final imageX = tester
          .getCenter(find.byKey(const Key('campanello-edit-image')))
          .dx;
      final saveX = tester
          .getCenter(find.byKey(const Key('campanello-save-changes')))
          .dx;
      final textX = tester
          .getCenter(find.byKey(const Key('campanello-edit-text')))
          .dx;
      expect(imageX, lessThan(saveX));
      expect(saveX, lessThan(textX));
    },
  );

  testWidgets('il footer hinoo non mostra Scrivi honoo', (tester) async {
    await tester.pumpWidget(
      Sizer(
        builder: (context, orientation, deviceType) {
          return const MaterialApp(home: NewHinooPage());
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Scrivi honoo'), findsNothing);
    expect(find.byTooltip('Home'), findsOneWidget);
    expect(find.byTooltip('Apri il tuo Cuore'), findsOneWidget);
  });

  testWidgets('la tastiera mobile non ridimensiona la card hinoo', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);

    await tester.pumpWidget(
      Sizer(
        builder: (context, orientation, deviceType) {
          return const MaterialApp(
            home: NewHinooPage(
              initialDraft: HinooDraft(
                pages: [
                  HinooSlide(
                    backgroundImage: null,
                    text: 'Testo',
                    isTextWhite: true,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    final card = find.byKey(const Key('hinoo-editor-card'));
    final Size sizeBeforeKeyboard = tester.getSize(card);

    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    await tester.pump();

    expect(tester.getSize(card), sizeBeforeKeyboard);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('il cestino hinoo appare nella toolbar di modifica immagine', (
    tester,
  ) async {
    await tester.pumpWidget(
      Sizer(
        builder: (context, orientation, deviceType) {
          return const MaterialApp(home: NewHinooPage());
        },
      ),
    );
    await tester.pumpAndSettle();

    final dynamic pageState = tester.state(find.byType(NewHinooPage));
    pageState.setEditorStateForTesting(step: 'changeBg', hasBackground: true);
    await tester.pump();

    expect(find.byTooltip('Cancella hinoo'), findsOneWidget);
    expect(find.byType(HinooBuilder), findsOneWidget);
    final deleteIcon = tester.widget<SvgPicture>(
      find.descendant(
        of: find.byTooltip('Cancella hinoo'),
        matching: find.byType(SvgPicture),
      ),
    );
    expect(
      (deleteIcon.bytesLoader as SvgAssetLoader).assetName,
      'assets/Cestino.svg',
    );
    expect(
      deleteIcon.colorFilter,
      const ColorFilter.mode(HonooColor.onBackground, BlendMode.srcIn),
    );
  });

  testWidgets('il cestino conferma e riporta l editor hinoo allo stato vuoto', (
    tester,
  ) async {
    await tester.pumpWidget(
      Sizer(
        builder: (context, orientation, deviceType) {
          return const MaterialApp(home: NewHinooPage());
        },
      ),
    );
    await tester.pumpAndSettle();

    final dynamic pageState = tester.state(find.byType(NewHinooPage));
    pageState.setEditorStateForTesting(
      step: 'changeBg',
      hasBackground: true,
      textLength: 12,
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Cancella hinoo'));
    await tester.pumpAndSettle();

    expect(find.text('Vuoi davvero eliminare questo hinoo?'), findsOneWidget);
    expect(find.text('L’operazione non è reversibile'), findsOneWidget);
    expect(find.text('Sì'), findsOneWidget);
    expect(find.text('No'), findsOneWidget);

    await tester.tap(find.text('Sì'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Cancella hinoo'), findsNothing);
    expect(find.byTooltip('Salva immagine'), findsNothing);
  });

  testWidgets('controlli immagine allineati come nell editor honoo', (
    tester,
  ) async {
    await tester.pumpWidget(
      Sizer(
        builder: (context, orientation, deviceType) {
          return const MaterialApp(home: NewHinooPage());
        },
      ),
    );
    await tester.pumpAndSettle();

    final dynamic pageState = tester.state(find.byType(NewHinooPage));
    pageState.setEditorStateForTesting(step: 'changeBg', hasBackground: true);
    await tester.pump();

    final saveImage = find.byTooltip('Salva immagine');
    final replaceImage = find.byTooltip('Sostituisci immagine');
    final deleteContent = find.byTooltip('Cancella hinoo');
    expect(saveImage, findsOneWidget);
    expect(replaceImage, findsOneWidget);
    expect(deleteContent, findsOneWidget);
    final replaceIcon = tester.widget<SvgPicture>(
      find.descendant(of: replaceImage, matching: find.byType(SvgPicture)),
    );
    expect(
      (replaceIcon.bytesLoader as SvgAssetLoader).assetName,
      'assets/icons/immagine.svg',
    );
    expect(
      tester.getCenter(replaceImage).dx,
      lessThan(tester.getCenter(saveImage).dx),
    );
    expect(
      tester.getCenter(saveImage).dx,
      lessThan(tester.getCenter(deleteContent).dx),
    );

    pageState.setEditorStateForTesting(step: 'writeText', hasBackground: true);
    await tester.pump();

    expect(find.byTooltip('Salva sul dispositivo'), findsOneWidget);
    expect(find.byTooltip('Salva immagine'), findsNothing);
    expect(find.byTooltip('Salva hinoo'), findsNothing);

    pageState.setEditorStateForTesting(
      step: 'writeText',
      hasBackground: true,
      textLength: 1,
    );
    await tester.pump();

    expect(find.byTooltip('Salva hinoo'), findsOneWidget);
    expect(find.byTooltip('Salva sul dispositivo'), findsOneWidget);
    final downloadIcon = tester.widget<SvgPicture>(
      find.descendant(
        of: find.byTooltip('Salva sul dispositivo'),
        matching: find.byType(SvgPicture),
      ),
    );
    expect(
      (downloadIcon.bytesLoader as SvgAssetLoader).assetName,
      'assets/icons/download.svg',
    );
    expect(
      tester.getCenter(find.byTooltip('Salva hinoo')).dx,
      lessThan(tester.getCenter(find.byTooltip('Salva sul dispositivo')).dx),
    );
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honoo/Widgets/honoo_dialogs.dart';
import 'package:honoo/Widgets/storiestorie_access_dialog.dart';

void main() {
  test('riconosce solo il percorso di continuazione storiestorie', () {
    expect(
      isStorieStorieContinuation(
        Uri.parse('https://honoo.it/?continue=storiestorie-romanzo'),
      ),
      isTrue,
    );
    expect(isStorieStorieContinuation(Uri.parse('https://honoo.it/')), isFalse);
  });

  testWidgets('mostra il dialogo honoo con azione principale sopra Annulla', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: StorieStorieAccessDialog())),
    );

    expect(find.byType(HonooDialogShell), findsOneWidget);
    expect(find.textContaining('registrato su honoo'), findsOneWidget);
    expect(find.textContaining('registrato su Honoo'), findsNothing);
    expect(find.textContaining('come visualizzatore.'), findsNothing);
    expect(find.textContaining('come visualizzatore'), findsOneWidget);

    final title = tester.widget<Text>(find.text('Prima di entrare'));
    final continueText = tester.widget<Text>(
      find.text('Continua su Google Drive'),
    );
    final cancelText = tester.widget<Text>(find.text('Annulla'));

    expect(title.style?.fontFamily, contains('Arvo'));
    expect(continueText.style?.fontFamily, contains('Arvo'));
    expect(cancelText.style?.fontFamily, contains('Arvo'));

    final continueTop = tester.getTopLeft(
      find.widgetWithText(ElevatedButton, 'Continua su Google Drive'),
    );
    final cancelTop = tester.getTopLeft(
      find.widgetWithText(TextButton, 'Annulla'),
    );
    expect(continueTop.dy, lessThan(cancelTop.dy));
    expect(tester.takeException(), isNull);
  });
}

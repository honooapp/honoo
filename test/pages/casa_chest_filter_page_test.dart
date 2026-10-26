import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honoo/Entities/casa_share_mode.dart';
import 'package:honoo/Pages/casa_share_selection_page.dart';

void main() {
  for (final page in <Widget>[
    const CasaChestFilterPage(),
    const CasaShareSelectionPage(),
  ]) {
    testWidgets('${page.runtimeType} permette di annullare senza scegliere', (
      tester,
    ) async {
      Object? result = 'pending';
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await Navigator.of(
                  context,
                ).push<Object?>(MaterialPageRoute(builder: (_) => page));
              },
              child: const Text('apri'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('apri'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Indietro'));
      await tester.pumpAndSettle();
      expect(find.text('apri'), findsOneWidget);
      expect(result, isNull);
    });
  }

  testWidgets('il menu dello scrigno di casa sceglie subito il filtro', (
    tester,
  ) async {
    CasaChestFilter? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await Navigator.of(context).push<CasaChestFilter>(
                MaterialPageRoute(builder: (_) => const CasaChestFilterPage()),
              );
            },
            child: const Text('apri'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();

    expect(find.text('cosa vuoi mostrare?'), findsNothing);
    expect(find.byKey(const ValueKey('house-share-confirm')), findsNothing);
    expect(find.byKey(const ValueKey('house-chest-home')), findsOneWidget);
    expect(find.byKey(const ValueKey('house-chest-moon')), findsOneWidget);
    expect(find.byKey(const ValueKey('house-chest-all')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('house-chest-moon')));
    await tester.pumpAndSettle();
    expect(result, CasaChestFilter.moonSaved);
  });

  testWidgets('l’ultima icona apre tutte le categorie dello scrigno', (
    tester,
  ) async {
    CasaChestFilter? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await Navigator.of(context).push<CasaChestFilter>(
                MaterialPageRoute(builder: (_) => const CasaChestFilterPage()),
              );
            },
            child: const Text('apri'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('house-chest-all')));
    await tester.pumpAndSettle();

    expect(result, CasaChestFilter.all);
  });
}

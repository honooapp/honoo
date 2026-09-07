import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:honoo/Pages/shared_house_chest_page.dart';
import 'package:mocktail/mocktail.dart';

import '../test_supabase_helper.dart';

void main() {
  setUpAll(() {
    registerSupabaseFallbacks();
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  for (final kind in ['honoo', 'hinoo', 'empty']) {
    testWidgets('shared $kind exposes reply choice only with content', (
      tester,
    ) async {
      final harness = SupabaseTestHarness(withAuthenticatedUser: true)
        ..enableOverrides();
      addTearDown(harness.disableOverrides);
      final rpc = MockQueryChain()
        ..queueResponse(
          kind == 'empty'
              ? []
              : [
                  {
                    'kind': kind,
                    'data': {
                      'id': 'parent-id',
                      'conversation_id': 'thread-id',
                      'user_id': 'owner-id',
                      'text': 'Test',
                      'image_url': '',
                      'destination': 'chest',
                      'type': 'personal',
                      'pages': [
                        {'text': 'Test', 'backgroundImage': ''},
                      ],
                      'created_at': '2026-08-10T10:00:00Z',
                      'updated_at': '2026-08-10T10:00:00Z',
                    },
                  },
                ],
        );
      when(
        () => harness.client.rpc(
          'get_shared_house_chest',
          params: any(named: 'params'),
        ),
      ).thenAnswer((_) => rpc);
      await tester.pumpWidget(
        const MaterialApp(home: SharedHouseChestPage(ownerId: 'owner-id')),
      );
      await tester.pumpAndSettle();
      if (kind == 'empty') {
        expect(find.byTooltip('Rispondi'), findsNothing);
      } else {
        await tester.tap(find.byTooltip('Rispondi'));
        await tester.pumpAndSettle();
        expect(find.widgetWithText(ElevatedButton, 'honoo'), findsOneWidget);
        expect(find.text('hinoo'), findsOneWidget);
        await tester.tap(find.text('Annulla'));
        await tester.pumpAndSettle();
        expect(find.byTooltip('Rispondi'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }
}

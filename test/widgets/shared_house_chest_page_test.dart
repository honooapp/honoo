import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:honoo/Pages/shared_house_chest_page.dart';
import 'package:honoo/UI/unified_thread_view.dart';
import 'package:mocktail/mocktail.dart';
import 'package:honoo/Widgets/responsive_footer_bar.dart';
import 'package:honoo/Utility/chest_content_style.dart';
import 'package:honoo/Entities/conversation_entry.dart';
import 'package:honoo/Entities/hinoo.dart';

import '../test_supabase_helper.dart';

void main() {
  setUpAll(() {
    registerSupabaseFallbacks();
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  for (final failures in [1, 2]) {
    testWidgets('shared chest recovers after $failures failed loads', (
      tester,
    ) async {
      final harness = SupabaseTestHarness(withAuthenticatedUser: true)
        ..enableOverrides();
      addTearDown(harness.disableOverrides);
      var attempts = 0;
      final rpc = MockQueryChain()
        ..queueResponse([
          {
            'kind': 'honoo',
            'data': {
              'id': 'recovered-content',
              'user_id': 'owner-id',
              'text': 'Contenuto recuperato',
              'image_url': '',
              'destination': 'chest',
              'type': 'personal',
              'created_at': '2026-08-10T10:00:00Z',
            },
          },
        ]);
      when(
        () => harness.client.rpc(
          'get_shared_house_chest',
          params: any(named: 'params'),
        ),
      ).thenAnswer((_) {
        attempts++;
        if (attempts <= failures) throw StateError('Network unavailable');
        return rpc;
      });
      await tester.pumpWidget(
        const MaterialApp(home: SharedHouseChestPage(ownerId: 'owner-id')),
      );
      await tester.pumpAndSettle();
      for (var failure = 0; failure < failures; failure++) {
        expect(
          find.text('Non riesco ad aprire lo scrigno. Riprova.'),
          findsOneWidget,
        );
        expect(find.byTooltip('Rispondi'), findsNothing);
        await tester.tap(find.widgetWithText(TextButton, 'Riprova'));
        await tester.pumpAndSettle();
      }
      expect(attempts, failures + 1);
      expect(find.text('Contenuto recuperato'), findsWidgets);
      expect(find.byTooltip('Rispondi'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Riprova'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

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
        MaterialApp(
          home: SharedHouseChestPage(
            ownerId: 'owner-id',
            conversationLoader: (_) async => const [],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Home'), findsOneWidget);
      expect(find.byTooltip('Torna al campanello'), findsOneWidget);
      expect(find.byTooltip('Info'), findsOneWidget);
      if (kind == 'empty') {
        expect(find.byTooltip('Rispondi'), findsNothing);
      } else {
        expect(find.byType(UnifiedThreadView), findsOneWidget);
        expect(find.text('Conversazione vuota'), findsNothing);
        expect(find.text('Test'), findsWidgets);
        expect(
          tester
              .widget<UnifiedThreadView>(find.byType(UnifiedThreadView))
              .conversationId,
          'thread-id',
        );
        final thread = tester.widget<UnifiedThreadView>(
          find.byType(UnifiedThreadView),
        );
        thread.onSelect!(
          ConversationEntry.hinoo(
            const HinooDraft(pages: []),
            createdAt: DateTime(2026),
            ownerId: 'another-author',
            id: 'selected-reply',
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor,
          ChestContentStyle.receivedReply.backgroundColor,
        );
        final footer = tester.widget<ResponsiveFooterBar>(
          find.byType(ResponsiveFooterBar),
        );
        expect(
          footer.actions
              .firstWhere((action) => action.tooltip == 'Rispondi')
              .colorFilter,
          ColorFilter.mode(
            ChestContentStyle.receivedReply.foregroundColor,
            BlendMode.srcIn,
          ),
        );
        await tester.tap(find.byTooltip('Rispondi'));
        await tester.pumpAndSettle();
        expect(find.widgetWithText(ElevatedButton, 'honoo'), findsOneWidget);
        expect(find.text('hinoo'), findsOneWidget);
        await tester.tap(find.text('Annulla'));
        await tester.pumpAndSettle();
        expect(find.byTooltip('Rispondi'), findsOneWidget);
        thread.onSelect!(
          ConversationEntry.deleted(id: 'deleted', createdAt: DateTime(2026)),
        );
        await tester.pumpAndSettle();
        expect(find.byTooltip('Rispondi'), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honoo/Entities/conversation_entry.dart';
import 'package:honoo/Entities/honoo.dart';
import 'package:honoo/UI/unified_thread_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_supabase_helper.dart';

void main() {
  setUpAll(registerSupabaseFallbacks);

  late SupabaseTestHarness harness;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    harness = SupabaseTestHarness(withAuthenticatedUser: true)
      ..enableOverrides();
  });
  tearDown(() => harness.disableOverrides());

  ConversationEntry reply({
    required String id,
    required String owner,
    required String createdAt,
  }) {
    final honoo =
        Honoo(0, id, '', createdAt, createdAt, owner, HonooType.answer)
          ..dbId = id
          ..conversationId = 'conversation-1';
    return ConversationEntry.honoo(honoo);
  }

  ConversationEntry moonRoot() {
    final honoo =
        Honoo(
            0,
            'moon-root',
            '',
            '2026-07-20T10:00:00Z',
            '2026-07-20T10:00:00Z',
            'me',
            HonooType.personal,
          )
          ..dbId = 'moon-root'
          ..conversationId = 'conversation-1'
          ..isFromMoonSaved = true;
    return ConversationEntry.honoo(honoo);
  }

  testWidgets(
    'dal badge seleziona l’ultima risposta ricevuta, non quella inviata',
    (tester) async {
      final received = reply(
        id: 'received',
        owner: 'other',
        createdAt: '2026-07-20T11:00:00Z',
      );
      final sent = reply(
        id: 'sent',
        owner: 'me',
        createdAt: '2026-07-20T12:00:00Z',
      );
      ConversationEntry? selected;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UnifiedThreadView(
              conversationId: 'conversation-1',
              maxWidth: 600,
              maxHeight: 700,
              isActive: true,
              highlightLatest: true,
              preferLatestReceived: true,
              currentUserId: 'me',
              conversationLoader: (_) async => [received, sent],
              onSelect: (entry) => selected = entry,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(selected?.id, 'received');
    },
  );

  testWidgets(
    'se l’id notificato manca non ricade sul contenuto salvato dalla Luna',
    (tester) async {
      final received = reply(
        id: 'latest-received',
        owner: 'other',
        createdAt: '2026-07-20T11:00:00Z',
      );
      ConversationEntry? selected;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UnifiedThreadView(
              conversationId: 'conversation-1',
              maxWidth: 600,
              maxHeight: 700,
              isActive: true,
              highlightLatest: true,
              revealEntryId: 'reply-not-yet-loaded',
              currentUserId: 'me',
              conversationLoader: (_) async => [moonRoot(), received],
              onSelect: (entry) => selected = entry,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(selected?.id, 'latest-received');
      expect(selected?.isFromMoonSaved, isFalse);
    },
  );
}

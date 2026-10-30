import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honoo/Entities/conversation_entry.dart';
import 'package:honoo/Entities/hinoo.dart';
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

  testWidgets('la rotella completa una pagina anche con delta piccolo', (
    tester,
  ) async {
    final entries = [
      reply(id: 'older', owner: 'me', createdAt: '2026-07-20T10:00:00Z'),
      reply(id: 'latest', owner: 'me', createdAt: '2026-07-20T11:00:00Z'),
    ];
    ConversationEntry? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UnifiedThreadView(
            conversationId: 'conversation-1',
            maxWidth: 600,
            maxHeight: 600,
            isActive: true,
            currentUserId: 'me',
            conversationLoader: (_) async => entries,
            onSelect: (entry) => selected = entry,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final pager = tester.widget<PageView>(find.byType(PageView).first);
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(find.byType(PageView).first),
        scrollDelta: const Offset(0, 20),
      ),
    );
    await tester.pumpAndSettle();
    expect(selected?.id, 'older');
    expect(pager.controller!.page, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'la rotella sopra Hinoo scorre lo storico in entrambe le direzioni',
    (tester) async {
      final entries = [
        reply(id: 'older', owner: 'me', createdAt: '2026-07-20T10:00:00Z'),
        ConversationEntry.hinoo(
          const HinooDraft(
            pages: [
              HinooSlide(
                backgroundImage: null,
                text: 'prima',
                isTextWhite: true,
              ),
              HinooSlide(
                backgroundImage: null,
                text: 'seconda',
                isTextWhite: true,
              ),
            ],
            type: HinooType.answer,
            conversationId: 'conversation-1',
          ),
          id: 'latest',
          ownerId: 'me',
          createdAt: DateTime.parse('2026-07-20T11:00:00Z'),
        ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UnifiedThreadView(
              conversationId: 'conversation-1',
              maxWidth: 600,
              maxHeight: 600,
              isActive: true,
              currentUserId: 'me',
              conversationLoader: (_) async => entries,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final outer = tester.widget<PageView>(find.byType(PageView).first);
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(find.text('prima')),
          scrollDelta: const Offset(0, 500),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(outer.controller!.page, 1);
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(find.byType(PageView).first),
          scrollDelta: const Offset(0, -500),
        ),
      );
      await tester.pumpAndSettle();
      expect(outer.controller!.page, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('un arrivo retroattivo mantiene la prima risposta in lettura', (
    tester,
  ) async {
    var entries = [
      reply(id: 'old', owner: 'other', createdAt: '2026-07-20T10:00:00Z'),
    ];
    ConversationEntry? selected;
    Widget app(int token) => MaterialApp(
      home: Scaffold(
        body: UnifiedThreadView(
          conversationId: 'conversation-1',
          maxWidth: 600,
          maxHeight: 600,
          isActive: true,
          currentUserId: 'me',
          refreshToken: token,
          conversationLoader: (_) async => entries,
          onSelect: (entry) => selected = entry,
        ),
      ),
    );
    await tester.pumpWidget(app(0));
    await tester.pumpAndSettle();
    entries = [
      ...entries,
      reply(id: 'new', owner: 'other', createdAt: '2026-07-20T11:00:00Z'),
    ];
    await tester.pumpWidget(app(1));
    await tester.pumpAndSettle();
    expect(selected?.id, 'old');
    await tester.drag(find.byType(PageView).first, const Offset(0, 450));
    await tester.pumpAndSettle();
    expect(selected?.id, 'new');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'la cronologia resta scorribile senza notifiche, anche riaprendola',
    (tester) async {
      final entries = [
        moonRoot(),
        ConversationEntry.hinoo(
          const HinooDraft(
            pages: [
              HinooSlide(
                backgroundImage: null,
                text: 'older',
                isTextWhite: true,
              ),
            ],
            type: HinooType.answer,
            conversationId: 'conversation-1',
          ),
          id: 'older',
          ownerId: 'other',
          createdAt: DateTime.parse('2026-07-20T11:00:00Z'),
        ),
        reply(id: 'latest', owner: 'me', createdAt: '2026-07-20T12:00:00Z'),
      ];
      for (var opening = 0; opening < 2; opening++) {
        ConversationEntry? selected;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: UnifiedThreadView(
                conversationId: 'conversation-1',
                maxWidth: 600,
                maxHeight: 600,
                isActive: true,
                currentUserId: 'me',
                conversationLoader: (_) async => entries,
                onSelect: (entry) => selected = entry,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(selected?.id, 'latest');
        final pager = find.byType(PageView).first;
        expect(tester.widget<PageView>(pager).scrollDirection, Axis.vertical);
        for (final id in ['older', 'moon-root']) {
          await tester.drag(pager, const Offset(0, -450));
          await tester.pumpAndSettle();
          expect(selected?.id, id);
        }
        for (final id in ['older', 'latest']) {
          await tester.drag(pager, const Offset(0, 450));
          await tester.pumpAndSettle();
          expect(selected?.id, id);
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }
    },
  );

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
      expect(find.byType(PageView), findsWidgets);
      expect(
        find.text('La risposta notificata non è ancora disponibile.'),
        findsOneWidget,
      );
      expect(find.text('Riprova'), findsOneWidget);
    },
  );
  testWidgets('preloaded inactive thread honors received focus on activation', (
    tester,
  ) async {
    final entries = [
      reply(id: 'received', owner: 'other', createdAt: '2026-07-20T10:00:00Z'),
      reply(id: 'sent', owner: 'me', createdAt: '2026-07-20T11:00:00Z'),
    ];
    ConversationEntry? selected;
    Widget app(bool active) => MaterialApp(
      home: Scaffold(
        body: UnifiedThreadView(
          conversationId: 'conversation-1',
          maxWidth: 600,
          maxHeight: 600,
          isActive: active,
          currentUserId: 'me',
          preferLatestReceived: true,
          conversationLoader: (_) async => entries,
          onSelect: (entry) => selected = entry,
        ),
      ),
    );
    await tester.pumpWidget(app(false));
    await tester.pumpAndSettle();
    await tester.pumpWidget(app(true));
    await tester.pumpAndSettle();
    expect(selected?.id, 'received');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(selected?.id, 'sent');
    await tester.pumpWidget(app(false));
    await tester.pumpAndSettle();
    await tester.pumpWidget(app(true));
    await tester.pumpAndSettle();
    expect(selected?.id, 'sent');
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('arrows on single page hinoo navigate history', (tester) async {
    final entries = [
      reply(id: 'older', owner: 'me', createdAt: '2026-07-20T10:00:00Z'),
      ConversationEntry.hinoo(
        const HinooDraft(
          pages: [
            HinooSlide(
              backgroundImage: null,
              text: 'single',
              isTextWhite: true,
            ),
          ],
          type: HinooType.answer,
        ),
        id: 'latest',
        ownerId: 'me',
        createdAt: DateTime.parse('2026-07-20T11:00:00Z'),
      ),
    ];
    ConversationEntry? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UnifiedThreadView(
            conversationId: 'conversation-1',
            maxWidth: 600,
            maxHeight: 600,
            isActive: true,
            currentUserId: 'me',
            conversationLoader: (_) async => entries,
            onSelect: (entry) => selected = entry,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(selected?.id, 'older');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(selected?.id, 'latest');
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'Riprova apre la risposta notificata quando diventa disponibile',
    (tester) async {
      final received = reply(
        id: 'received',
        owner: 'other',
        createdAt: '2026-07-20T10:00:00Z',
      );
      final target = reply(
        id: 'target',
        owner: 'other',
        createdAt: '2026-07-20T11:00:00Z',
      );
      final sent = reply(
        id: 'sent',
        owner: 'me',
        createdAt: '2026-07-20T12:00:00Z',
      );
      var entries = [received, sent];
      ConversationEntry? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UnifiedThreadView(
              conversationId: 'conversation-1',
              maxWidth: 600,
              maxHeight: 600,
              isActive: true,
              currentUserId: 'me',
              revealEntryId: 'target',
              conversationLoader: (_) async => entries,
              onSelect: (entry) => selected = entry,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(selected?.id, 'received');
      entries = [received, target, sent];
      await tester.tap(find.text('Riprova'));
      await tester.pumpAndSettle();
      expect(selected?.id, 'target');
      expect(find.text('Riprova'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

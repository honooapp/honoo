import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honoo/Entities/conversation_entry.dart';
import 'package:honoo/Entities/hinoo.dart';
import 'package:honoo/Entities/honoo.dart';
import 'package:honoo/UI/unified_thread_view.dart';
import 'package:honoo/Utility/honoo_colors.dart';

import '../test_supabase_helper.dart';

void main() {
  late SupabaseTestHarness harness;

  setUpAll(registerSupabaseFallbacks);

  setUp(() {
    harness = SupabaseTestHarness(withAuthenticatedUser: true)
      ..enableOverrides();
  });

  tearDown(() => harness.disableOverrides());

  Honoo honoo({
    required String id,
    required String text,
    required String owner,
    required String createdAt,
    HonooType type = HonooType.personal,
    String? replyTo,
    bool fromMoon = false,
  }) {
    final value = Honoo(0, text, '', createdAt, createdAt, owner, type)
      ..dbId = id
      ..replyTo = replyTo
      ..isFromMoonSaved = fromMoon
      ..conversationId = 'conversation-1';
    return value;
  }

  ConversationEntry hinoo({
    required String id,
    required String text,
    required String owner,
    required String createdAt,
    HinooType type = HinooType.personal,
    String? replyTo,
    bool fromMoon = false,
  }) => ConversationEntry.hinoo(
    HinooDraft(
      pages: [HinooSlide(backgroundImage: null, text: text, isTextWhite: true)],
      type: type,
      replyTo: replyTo,
      conversationId: 'conversation-1',
    ),
    id: id,
    ownerId: owner,
    createdAt: DateTime.parse(createdAt),
    isFromMoonSaved: fromMoon,
  );

  Finder borderWithColor(Color color) => find.byWidgetPredicate((widget) {
    final Decoration? decoration = switch (widget) {
      Container(:final decoration) => decoration,
      DecoratedBox(:final decoration) => decoration,
      _ => null,
    };
    if (decoration is! BoxDecoration) return false;
    final border = decoration.border;
    return border is Border &&
        border.top.color == color &&
        border.top.width == 6;
  });

  Finder explicitSemanticsLabel(String label) => find.byWidgetPredicate(
    (widget) => widget is Semantics && widget.properties.label == label,
  );

  testWidgets('il bounce rivela il messaggio padre fino a metà schermo', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(600, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final root = ConversationEntry.honoo(
      honoo(
        id: 'root-1',
        text: 'Messaggio padre',
        owner: 'me',
        createdAt: '2026-07-20T10:00:00Z',
      ),
    );
    final reply = ConversationEntry.honoo(
      honoo(
        id: 'reply-1',
        text: 'Ultima risposta ricevuta',
        owner: 'other',
        createdAt: '2026-07-20T11:00:00Z',
        type: HonooType.answer,
        replyTo: 'root-1',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UnifiedThreadView(
            conversationId: 'conversation-1',
            maxWidth: 600,
            maxHeight: 700,
            isActive: true,
            currentUserId: 'me',
            conversationLoader: (_) async => [root, reply],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Ultima risposta ricevuta'), findsOneWidget);
    expect(find.text('Messaggio padre'), findsOneWidget);
    expect(find.byKey(const Key('reply_reveal_parent')), findsOneWidget);
    final foreground = tester.widget<Transform>(
      find.byKey(const Key('reply_reveal_foreground')),
    );
    expect(foreground.transform.getTranslation().y, lessThan(0));
    expect(foreground.transform.getTranslation().y, greaterThanOrEqualTo(-336));
  });

  testWidgets('il bounce mostra il segnaposto del contenuto eliminato', (
    tester,
  ) async {
    final deleted = ConversationEntry.deleted(
      id: 'root-1',
      createdAt: DateTime.parse('2026-07-20T10:00:00Z'),
    );
    final reply = ConversationEntry.honoo(
      honoo(
        id: 'reply-1',
        text: 'Risposta conservata',
        owner: 'other',
        createdAt: '2026-07-20T11:00:00Z',
        type: HonooType.answer,
        replyTo: 'root-1',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UnifiedThreadView(
            conversationId: 'conversation-1',
            maxWidth: 390,
            maxHeight: 700,
            isActive: true,
            conversationLoader: (_) async => [deleted, reply],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Risposta conservata'), findsOneWidget);
    expect(find.text('contenuto eliminato'), findsOneWidget);
    expect(find.byKey(const Key('reply_reveal_parent')), findsOneWidget);
  });

  testWidgets('una risposta orfana non avvia un rialzamento vuoto', (
    tester,
  ) async {
    final reply = ConversationEntry.honoo(
      honoo(
        id: 'reply-1',
        text: 'Risposta senza padre',
        owner: 'other',
        createdAt: '2026-07-20T11:00:00Z',
        type: HonooType.answer,
        replyTo: 'missing-root',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UnifiedThreadView(
            conversationId: 'conversation-1',
            maxWidth: 390,
            maxHeight: 700,
            isActive: true,
            conversationLoader: (_) async => [reply],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Risposta senza padre'), findsOneWidget);
    expect(find.byKey(const Key('reply_reveal_foreground')), findsNothing);
  });

  testWidgets('una conversazione senza messaggi non crea una pagina vuota', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UnifiedThreadView(
            conversationId: 'empty-conversation',
            maxWidth: 390,
            maxHeight: 700,
            conversationLoader: (_) async => const [],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Conversazione vuota'), findsOneWidget);
    expect(find.byType(PageView), findsNothing);
  });

  testWidgets('una nuova risposta propria resta blu dopo il refresh', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(600, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final root = ConversationEntry.honoo(
      honoo(
        id: 'root-refresh',
        text: 'Padre aggiornato',
        owner: 'me',
        createdAt: '2026-07-20T10:00:00Z',
      ),
    );
    final firstReply = ConversationEntry.honoo(
      honoo(
        id: 'reply-refresh-1',
        text: 'Prima risposta',
        owner: 'other',
        createdAt: '2026-07-20T11:00:00Z',
        type: HonooType.answer,
        replyTo: 'root-refresh',
      ),
    );
    final secondReply = ConversationEntry.honoo(
      honoo(
        id: 'reply-refresh-2',
        text: 'Seconda risposta appena salvata',
        owner: 'me',
        createdAt: '2026-07-20T12:00:00Z',
        type: HonooType.answer,
        replyTo: 'reply-refresh-1',
      ),
    );
    var entries = [root, firstReply];

    Widget app(int refreshToken) => MaterialApp(
      home: Scaffold(
        body: UnifiedThreadView(
          key: const Key('refreshable-thread'),
          conversationId: 'conversation-1',
          maxWidth: 600,
          maxHeight: 700,
          isActive: true,
          currentUserId: 'me',
          refreshToken: refreshToken,
          conversationLoader: (_) async => entries,
        ),
      ),
    );

    await tester.pumpWidget(app(0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));

    entries = [root, firstReply, secondReply];
    await tester.pumpWidget(app(1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('Seconda risposta appena salvata'), findsOneWidget);
    expect(find.byKey(const Key('reply_reveal_foreground')), findsNothing);
    expect(find.byKey(const Key('reply_reveal_parent')), findsNothing);
  });

  testWidgets('una nuova risposta non sposta la pagina scelta con lo swipe', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(600, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final root = ConversationEntry.honoo(
      honoo(
        id: 'root-scroll',
        text: 'Contenuto a cui si è risposto',
        owner: 'me',
        createdAt: '2026-07-20T10:00:00Z',
      ),
    );
    final reply = ConversationEntry.honoo(
      honoo(
        id: 'reply-scroll',
        text: 'Risposta inizialmente visibile',
        owner: 'other',
        createdAt: '2026-07-20T11:00:00Z',
        type: HonooType.answer,
        replyTo: 'root-scroll',
      ),
    );
    final newReply = ConversationEntry.honoo(
      honoo(
        id: 'reply-scroll-new',
        text: 'Nuova risposta realtime',
        owner: 'other',
        createdAt: '2026-07-20T12:00:00Z',
        type: HonooType.answer,
        replyTo: 'reply-scroll',
      ),
    );
    var entries = [root, reply];
    String? selectedId;

    Widget app(int refreshToken) => MaterialApp(
      home: Scaffold(
        body: UnifiedThreadView(
          key: const Key('scroll-refresh-thread'),
          conversationId: 'conversation-1',
          maxWidth: 600,
          maxHeight: 700,
          isActive: true,
          currentUserId: 'me',
          refreshToken: refreshToken,
          conversationLoader: (_) async => entries,
          onSelect: (entry) => selectedId = entry.id,
        ),
      ),
    );

    await tester.pumpWidget(app(0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));
    expect(selectedId, 'reply-scroll');

    await tester.drag(find.byType(PageView), const Offset(0, -650));
    await tester.pumpAndSettle();
    expect(selectedId, 'root-scroll');

    entries = [root, reply, newReply];
    await tester.pumpWidget(app(1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(selectedId, 'root-scroll');
    expect(tester.widget<PageView>(find.byType(PageView)).controller!.page, 2);
  });

  testWidgets(
    'da notifica: una nuova risposta non sposta la pagina scelta con lo swipe',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(600, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final root = ConversationEntry.honoo(
        honoo(
          id: 'root-scroll',
          text: 'Contenuto a cui si è risposto',
          owner: 'me',
          createdAt: '2026-07-20T10:00:00Z',
        ),
      );
      final reply = ConversationEntry.honoo(
        honoo(
          id: 'reply-scroll',
          text: 'Risposta inizialmente visibile',
          owner: 'other',
          createdAt: '2026-07-20T11:00:00Z',
          type: HonooType.answer,
          replyTo: 'root-scroll',
        ),
      );
      final newReply = ConversationEntry.honoo(
        honoo(
          id: 'reply-scroll-new',
          text: 'Nuova risposta realtime',
          owner: 'other',
          createdAt: '2026-07-20T12:00:00Z',
          type: HonooType.answer,
          replyTo: 'reply-scroll',
        ),
      );
      var entries = [root, reply];
      String? selectedId;

      Widget app(int refreshToken) => MaterialApp(
        home: Scaffold(
          body: UnifiedThreadView(
            key: const Key('scroll-refresh-thread'),
            revealEntryId: 'reply-scroll',
            conversationId: 'conversation-1',
            maxWidth: 600,
            maxHeight: 700,
            isActive: true,
            currentUserId: 'me',
            refreshToken: refreshToken,
            conversationLoader: (_) async => entries,
            onSelect: (entry) => selectedId = entry.id,
          ),
        ),
      );

      await tester.pumpWidget(app(0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1000));
      expect(selectedId, 'reply-scroll');

      await tester.drag(find.byType(PageView), const Offset(0, -650));
      await tester.pumpAndSettle();
      expect(selectedId, 'root-scroll');

      entries = [root, reply, newReply];
      await tester.pumpWidget(app(1));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(selectedId, 'root-scroll');
      expect(
        tester.widget<PageView>(find.byType(PageView)).controller!.page,
        2,
      );
    },
  );

  testWidgets('un errore di conversazione mostra Riprova', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UnifiedThreadView(
            conversationId: 'failed-conversation',
            maxWidth: 390,
            maxHeight: 700,
            conversationLoader: (_) async => throw Exception('offline'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Non riesco a caricare la conversazione.'),
      findsOneWidget,
    );
    expect(find.text('Riprova'), findsOneWidget);
    expect(find.byType(PageView), findsNothing);
  });

  testWidgets('le conversazioni usano pagine senza overscroll elastico', (
    tester,
  ) async {
    final entry = ConversationEntry.honoo(
      honoo(
        id: 'root-physics',
        text: 'Messaggio',
        owner: 'me',
        createdAt: '2026-07-20T10:00:00Z',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UnifiedThreadView(
            conversationId: 'conversation-physics',
            maxWidth: 390,
            maxHeight: 700,
            conversationLoader: (_) async => [entry],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final pageView = tester.widget<PageView>(find.byType(PageView));
    expect(pageView.physics, isA<PageScrollPhysics>());
    expect(pageView.physics?.parent, isA<ClampingScrollPhysics>());
  });

  testWidgets(
    'una risposta ricevuta mostra in rosso l’Honoo salvato dalla Luna',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(600, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final root = ConversationEntry.honoo(
        honoo(
          id: 'saved-root-1',
          text: 'Messaggio salvato dalla Luna',
          owner: 'test_user',
          createdAt: '2026-07-20T10:00:00Z',
          fromMoon: true,
        ),
      );
      final reply = ConversationEntry.honoo(
        honoo(
          id: 'reply-1',
          text: 'Risposta ricevuta',
          owner: 'other_user',
          createdAt: '2026-07-20T11:00:00Z',
          type: HonooType.answer,
          replyTo: 'moon-root-1',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UnifiedThreadView(
              conversationId: 'conversation-1',
              maxWidth: 600,
              maxHeight: 700,
              isActive: true,
              currentUserId: 'test_user',
              conversationLoader: (_) async => [root, reply],
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.byKey(const Key('reply_reveal_parent')), findsOneWidget);
      expect(
        tester
            .widget<ColoredBox>(find.byKey(const Key('reply_reveal_parent')))
            .color,
        HonooColor.secondary,
      );
      expect(borderWithColor(HonooColor.secondary), findsNothing);
    },
  );

  testWidgets(
    'una risposta ricevuta mostra in rosso l’Hinoo salvato dalla Luna',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(600, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final root = hinoo(
        id: 'saved-hinoo-root',
        text: 'Hinoo salvato dalla Luna',
        owner: 'test_user',
        createdAt: '2026-07-20T10:00:00Z',
        fromMoon: true,
      );
      final reply = ConversationEntry.honoo(
        honoo(
          id: 'reply-to-hinoo',
          text: 'Risposta ricevuta',
          owner: 'other_user',
          createdAt: '2026-07-20T11:00:00Z',
          type: HonooType.answer,
          replyTo: 'saved-hinoo-root',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UnifiedThreadView(
              conversationId: 'conversation-1',
              maxWidth: 600,
              maxHeight: 700,
              isActive: true,
              currentUserId: 'test_user',
              conversationLoader: (_) async => [root, reply],
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.byKey(const Key('reply_reveal_parent')), findsOneWidget);
      expect(
        tester
            .widget<ColoredBox>(find.byKey(const Key('reply_reveal_parent')))
            .color,
        HonooColor.secondary,
      );
    },
  );

  testWidgets(
    'revealEntryId anima la risposta richiesta, non quella più recente',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(600, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final root = ConversationEntry.honoo(
        honoo(
          id: 'root-exact',
          text: 'Padre esatto',
          owner: 'me',
          createdAt: '2026-07-20T10:00:00Z',
        ),
      );
      final requestedReply = ConversationEntry.honoo(
        honoo(
          id: 'reply-requested',
          text: 'Risposta richiesta',
          owner: 'other',
          createdAt: '2026-07-20T11:00:00Z',
          type: HonooType.answer,
          replyTo: 'root-exact',
        ),
      );
      final newerReply = ConversationEntry.honoo(
        honoo(
          id: 'reply-newer',
          text: 'Risposta più recente',
          owner: 'other',
          createdAt: '2026-07-20T12:00:00Z',
          type: HonooType.answer,
          replyTo: 'reply-requested',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UnifiedThreadView(
              conversationId: 'conversation-1',
              revealEntryId: 'reply-requested',
              maxWidth: 600,
              maxHeight: 700,
              isActive: true,
              conversationLoader: (_) async => [
                root,
                requestedReply,
                newerReply,
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('Risposta richiesta'), findsOneWidget);
      expect(find.text('Padre esatto'), findsOneWidget);
      expect(find.byKey(const Key('reply_reveal_parent')), findsOneWidget);
    },
  );

  testWidgets('un caricamento vecchio non sostituisce la nuova conversazione', (
    tester,
  ) async {
    final first = Completer<List<ConversationEntry>>();
    final second = Completer<List<ConversationEntry>>();
    Future<List<ConversationEntry>> loader(String conversationId) =>
        conversationId == 'conversation-old' ? first.future : second.future;

    Widget app(String conversationId) => MaterialApp(
      home: Scaffold(
        body: UnifiedThreadView(
          key: const Key('race-thread'),
          conversationId: conversationId,
          maxWidth: 390,
          maxHeight: 700,
          conversationLoader: loader,
        ),
      ),
    );

    await tester.pumpWidget(app('conversation-old'));
    await tester.pump();
    await tester.pumpWidget(app('conversation-new'));
    await tester.pump();

    second.complete([
      ConversationEntry.honoo(
        honoo(
          id: 'new-entry',
          text: 'Conversazione nuova',
          owner: 'me',
          createdAt: '2026-07-20T12:00:00Z',
        ),
      ),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Conversazione nuova'), findsOneWidget);

    first.complete([
      ConversationEntry.honoo(
        honoo(
          id: 'old-entry',
          text: 'Conversazione vecchia',
          owner: 'me',
          createdAt: '2026-07-20T10:00:00Z',
        ),
      ),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('Conversazione nuova'), findsOneWidget);
    expect(find.text('Conversazione vecchia'), findsNothing);
  });

  for (final combination in const [
    ('honoo', 'honoo'),
    ('honoo', 'hinoo'),
    ('hinoo', 'honoo'),
    ('hinoo', 'hinoo'),
  ]) {
    testWidgets(
      '${combination.$1} → ${combination.$2} rivela il padre e identifica il destinatario',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(600, 900);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);

        final root = combination.$1 == 'honoo'
            ? ConversationEntry.honoo(
                honoo(
                  id: 'root-cross',
                  text: 'Contenuto padre',
                  owner: 'me',
                  createdAt: '2026-07-20T10:00:00Z',
                ),
              )
            : hinoo(
                id: 'root-cross',
                text: 'Contenuto padre',
                owner: 'me',
                createdAt: '2026-07-20T10:00:00Z',
              );
        final reply = combination.$2 == 'honoo'
            ? ConversationEntry.honoo(
                honoo(
                  id: 'reply-cross',
                  text: 'Risposta incrociata',
                  owner: 'other',
                  createdAt: '2026-07-20T11:00:00Z',
                  type: HonooType.answer,
                  replyTo: 'root-cross',
                ),
              )
            : hinoo(
                id: 'reply-cross',
                text: 'Risposta incrociata',
                owner: 'other',
                createdAt: '2026-07-20T11:00:00Z',
                type: HinooType.answer,
                replyTo: 'root-cross',
              );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: UnifiedThreadView(
                conversationId: 'conversation-1',
                maxWidth: 600,
                maxHeight: 700,
                isActive: true,
                currentUserId: 'me',
                conversationLoader: (_) async => [root, reply],
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));

        expect(find.text('Risposta incrociata'), findsOneWidget);
        expect(find.text('Contenuto padre'), findsOneWidget);
        expect(find.byKey(const Key('reply_reveal_parent')), findsOneWidget);
        expect(explicitSemanticsLabel('Risposta ricevuta'), findsOneWidget);
        expect(borderWithColor(HonooColor.secondary), findsNothing);
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is ColoredBox && widget.color == HonooColor.secondary,
          ),
          findsWidgets,
        );
      },
    );
  }

  for (final combination in const [
    ('honoo', 'honoo'),
    ('honoo', 'hinoo'),
    ('hinoo', 'honoo'),
    ('hinoo', 'hinoo'),
  ]) {
    testWidgets(
      '${combination.$1} → ${combination.$2} identifica la risposta del mittente senza bordo rosso',
      (tester) async {
        final root = combination.$1 == 'honoo'
            ? ConversationEntry.honoo(
                honoo(
                  id: 'root-sender',
                  text: 'Contenuto ricevuto',
                  owner: 'other',
                  createdAt: '2026-07-20T10:00:00Z',
                ),
              )
            : hinoo(
                id: 'root-sender',
                text: 'Contenuto ricevuto',
                owner: 'other',
                createdAt: '2026-07-20T10:00:00Z',
              );
        final reply = combination.$2 == 'honoo'
            ? ConversationEntry.honoo(
                honoo(
                  id: 'reply-sender',
                  text: 'Risposta inviata',
                  owner: 'me',
                  createdAt: '2026-07-20T11:00:00Z',
                  type: HonooType.answer,
                  replyTo: 'root-sender',
                ),
              )
            : hinoo(
                id: 'reply-sender',
                text: 'Risposta inviata',
                owner: 'me',
                createdAt: '2026-07-20T11:00:00Z',
                type: HinooType.answer,
                replyTo: 'root-sender',
              );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: UnifiedThreadView(
                conversationId: 'conversation-1',
                maxWidth: 600,
                maxHeight: 700,
                isActive: true,
                currentUserId: 'me',
                conversationLoader: (_) async => [root, reply],
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));

        expect(explicitSemanticsLabel('Risposta inviata'), findsOneWidget);
        expect(borderWithColor(HonooColor.secondary), findsNothing);
        expect(find.byKey(const Key('reply_reveal_parent')), findsNothing);
      },
    );
  }

  testWidgets('l’apertura mostra il contenuto più recente anche se è proprio', (
    tester,
  ) async {
    final root = ConversationEntry.honoo(
      honoo(
        id: 'root-latest',
        text: 'Contenuto iniziale',
        owner: 'other',
        createdAt: '2026-07-20T10:00:00Z',
      ),
    );
    final receivedReply = ConversationEntry.honoo(
      honoo(
        id: 'received-latest',
        text: 'Risposta ricevuta precedente',
        owner: 'other',
        createdAt: '2026-07-20T11:00:00Z',
        type: HonooType.answer,
        replyTo: 'root-latest',
      ),
    );
    final latestOwnReply = ConversationEntry.honoo(
      honoo(
        id: 'own-latest',
        text: 'Ultima risposta inviata',
        owner: 'me',
        createdAt: '2026-07-20T12:00:00Z',
        type: HonooType.answer,
        replyTo: 'received-latest',
      ),
    );
    ConversationEntry? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UnifiedThreadView(
            conversationId: 'conversation-latest',
            maxWidth: 600,
            maxHeight: 700,
            isActive: true,
            currentUserId: 'me',
            conversationLoader: (_) async => [
              root,
              receivedReply,
              latestOwnReply,
            ],
            onSelect: (entry) => selected = entry,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(selected?.id, 'own-latest');
    expect(find.text('Ultima risposta inviata'), findsOneWidget);
    expect(find.byKey(const Key('reply_reveal_parent')), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is ColoredBox && widget.color == HonooColor.background,
      ),
      findsWidgets,
    );
  });

  testWidgets('un burst Realtime viene coalesciato in un solo refresh', (
    tester,
  ) async {
    final firstLoad = Completer<List<ConversationEntry>>();
    var calls = 0;
    final entry = ConversationEntry.honoo(
      honoo(
        id: 'root-burst',
        text: 'Timeline aggiornata',
        owner: 'me',
        createdAt: '2026-07-20T10:00:00Z',
      ),
    );
    Future<List<ConversationEntry>> loader(_) {
      calls++;
      return calls == 1 ? firstLoad.future : Future.value([entry]);
    }

    Widget app(int token) => MaterialApp(
      home: Scaffold(
        body: UnifiedThreadView(
          key: const Key('burst-thread'),
          conversationId: 'conversation-1',
          maxWidth: 390,
          maxHeight: 700,
          refreshToken: token,
          conversationLoader: loader,
        ),
      ),
    );

    await tester.pumpWidget(app(0));
    await tester.pump();
    for (var token = 1; token <= 100; token++) {
      await tester.pumpWidget(app(token));
    }
    expect(calls, 1);

    firstLoad.complete([entry]);
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.text('Timeline aggiornata'), findsOneWidget);
  });
}

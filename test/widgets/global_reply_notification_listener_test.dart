import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honoo/Entities/reply_notification_event.dart';
import 'package:honoo/Pages/chest_page.dart';
import 'package:honoo/Services/reply_system_notification.dart';
import 'package:honoo/Widgets/global_reply_notification_listener.dart';
import 'package:honoo/Utility/reply_notification_signal.dart';
import 'package:honoo/Utility/replies_seen_tracker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_supabase_helper.dart';

class _FakeReplySystemNotification extends ReplySystemNotification {
  VoidCallback? onTap;
  String? contentLabel;
  String? conversationId;
  int showCount = 0;
  int? replyCount;
  final List<String> closedConversations = [];

  @override
  void closeConversation(String conversationId) {
    closedConversations.add(conversationId);
  }

  @override
  ReplyNotificationPermission get permission =>
      ReplyNotificationPermission.granted;

  @override
  Future<ReplyNotificationPermission> requestPermission() async => permission;

  @override
  void show({
    required String contentLabel,
    required String conversationId,
    required VoidCallback onTap,
    int replyCount = 1,
  }) {
    showCount += 1;
    this.contentLabel = contentLabel;
    this.conversationId = conversationId;
    this.onTap = onTap;
    this.replyCount = replyCount;
  }
}

void main() {
  setUpAll(registerSupabaseFallbacks);

  late SupabaseTestHarness harness;
  late StreamController<ReplyNotificationEvent> events;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    harness = SupabaseTestHarness(withAuthenticatedUser: true)
      ..enableOverrides();
    harness.stubTable('honoo');
    harness.stubTable('hinoo');
    harness.stubTable('conversation_tombstones');
    events = StreamController<ReplyNotificationEvent>();
  });

  tearDown(() async {
    await events.close();
    harness.disableOverrides();
  });

  testWidgets(
    'la notifica apre lo Scrigno sulla conversazione della risposta',
    (tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      final notification = _FakeReplySystemNotification();
      final initialRevision = ReplyNotificationSignal.revision.value;

      await tester.pumpWidget(
        GlobalReplyNotificationListener(
          navigatorKey: navigatorKey,
          systemNotification: notification,
          replyEventStream: events.stream,
          child: MaterialApp(
            navigatorKey: navigatorKey,
            home: const Scaffold(body: Text('Luna')),
          ),
        ),
      );

      final event = ReplyNotificationEvent(
        kind: ReplyNotificationKind.hinoo,
        conversationId: 'conversation-42',
        senderId: 'other_user',
        recipientId: 'test_user',
        replyId: 'reply-42',
        createdAt: DateTime.utc(2026, 8, 3, 10),
      );
      events.add(event);
      events.add(event);
      await tester.pump(const Duration(milliseconds: 200));

      expect(notification.showCount, 1);
      expect(notification.contentLabel, 'hinoo');
      expect(notification.conversationId, 'conversation-42');
      expect(notification.replyCount, 1);
      expect(notification.onTap, isNotNull);
      expect(
        ReplyNotificationSignal.revision.value,
        greaterThan(initialRevision),
      );
      expect(find.text('Hai ricevuto una nuova risposta'), findsOneWidget);

      expect(find.text('Apri'), findsOneWidget);
      expect(find.text('Ignora'), findsOneWidget);

      await tester.tap(find.text('Apri'));
      await tester.pumpAndSettle();

      expect(navigatorKey.currentState!.canPop(), isTrue);
      expect(find.byType(ChestPage), findsOneWidget);
      final chestPage = tester.widget<ChestPage>(find.byType(ChestPage));
      expect(chestPage.focusConversationId, 'conversation-42');
      expect(chestPage.focusReplyId, 'reply-42');
      expect(notification.closedConversations, contains('conversation-42'));

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Ignora chiude il popup senza aprire né consumare la risposta', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final notification = _FakeReplySystemNotification();

    await tester.pumpWidget(
      GlobalReplyNotificationListener(
        navigatorKey: navigatorKey,
        systemNotification: notification,
        replyEventStream: events.stream,
        child: MaterialApp(
          navigatorKey: navigatorKey,
          home: const Scaffold(body: Text('Luna')),
        ),
      ),
    );

    events.add(
      ReplyNotificationEvent(
        kind: ReplyNotificationKind.honoo,
        conversationId: 'conversation-pending',
        senderId: 'other_user',
        recipientId: 'test_user',
        replyId: 'reply-pending',
        createdAt: DateTime.utc(2026, 8, 3, 10),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Ignora'), findsOneWidget);
    await tester.tap(find.text('Ignora'));
    await tester.pumpAndSettle();

    expect(find.byType(ChestPage), findsNothing);
    expect(find.text('Luna'), findsOneWidget);
    expect(notification.showCount, 1);
    expect(notification.onTap, isNotNull);
    final seenState = await RepliesSeenTracker.load(userId: 'test_user');
    expect(
      seenState.isSeen(
        conversationId: 'conversation-pending',
        createdAt: DateTime.utc(2026, 8, 3, 10),
      ),
      isFalse,
    );
  });

  testWidgets('una risposta già visualizzata non genera una nuova notifica', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final notification = _FakeReplySystemNotification();
    final createdAt = DateTime.utc(2026, 8, 3, 10);
    await RepliesSeenTracker.markAt(
      createdAt,
      userId: 'test_user',
      conversationId: 'conversation-seen',
    );

    await tester.pumpWidget(
      GlobalReplyNotificationListener(
        navigatorKey: navigatorKey,
        systemNotification: notification,
        replyEventStream: events.stream,
        child: MaterialApp(
          navigatorKey: navigatorKey,
          home: const Scaffold(body: Text('Luna')),
        ),
      ),
    );

    events.add(
      ReplyNotificationEvent(
        kind: ReplyNotificationKind.honoo,
        conversationId: 'conversation-seen',
        senderId: 'other_user',
        recipientId: 'test_user',
        replyId: 'reply-seen',
        createdAt: createdAt,
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();

    expect(notification.showCount, 0);
    expect(find.text('Hai ricevuto una nuova risposta'), findsNothing);
  });

  testWidgets('un nuovo listener non rinotifica un id letto senza timestamp', (
    tester,
  ) async {
    await RepliesSeenTracker.markReply(userId: 'test_user', replyId: 'seen-id');
    final navigatorKey = GlobalKey<NavigatorState>();
    final notification = _FakeReplySystemNotification();
    await tester.pumpWidget(
      GlobalReplyNotificationListener(
        navigatorKey: navigatorKey,
        systemNotification: notification,
        replyEventStream: events.stream,
        child: MaterialApp(
          navigatorKey: navigatorKey,
          home: const Scaffold(body: Text('Home')),
        ),
      ),
    );
    events.add(
      const ReplyNotificationEvent(
        kind: ReplyNotificationKind.honoo,
        conversationId: 'changed-conversation',
        senderId: 'other_user',
        recipientId: 'test_user',
        replyId: 'seen-id',
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(notification.showCount, 0);
    expect(find.text('Hai ricevuto una nuova risposta'), findsNothing);
  });

  testWidgets('visualizzare una risposta chiude la sua notifica attiva', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final notification = _FakeReplySystemNotification();
    final createdAt = DateTime.utc(2026, 8, 3, 11);

    await tester.pumpWidget(
      GlobalReplyNotificationListener(
        navigatorKey: navigatorKey,
        systemNotification: notification,
        replyEventStream: events.stream,
        child: MaterialApp(
          navigatorKey: navigatorKey,
          home: const Scaffold(body: Text('Luna')),
        ),
      ),
    );

    events.add(
      ReplyNotificationEvent(
        kind: ReplyNotificationKind.honoo,
        conversationId: 'conversation-now-seen',
        senderId: 'other_user',
        recipientId: 'test_user',
        replyId: 'reply-now-seen',
        createdAt: createdAt,
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(notification.showCount, 1);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'last_seen_reply_by_conversation_v1_test_user',
      '{"conversation-now-seen":"${createdAt.toIso8601String()}"}',
    );
    ReplyNotificationSignal.notifyChanged();
    await tester.pump();

    expect(notification.closedConversations, contains('conversation-now-seen'));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'un grande burst produce una sola notifica e un solo aggiornamento UI',
    (tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      final notification = _FakeReplySystemNotification();
      final initialRevision = ReplyNotificationSignal.revision.value;

      await tester.pumpWidget(
        GlobalReplyNotificationListener(
          navigatorKey: navigatorKey,
          systemNotification: notification,
          replyEventStream: events.stream,
          child: MaterialApp(
            navigatorKey: navigatorKey,
            home: const Scaffold(body: Text('Luna')),
          ),
        ),
      );

      for (var i = 0; i < 1000; i++) {
        events.add(
          ReplyNotificationEvent(
            kind: i.isEven
                ? ReplyNotificationKind.honoo
                : ReplyNotificationKind.hinoo,
            conversationId: 'conversation-$i',
            senderId: 'sender-${i % 200}',
            recipientId: 'test_user',
            replyId: 'reply-$i',
            createdAt: DateTime.utc(
              2026,
              8,
              3,
              10,
            ).add(Duration(milliseconds: i)),
          ),
        );
      }
      await tester.pump(const Duration(milliseconds: 200));

      expect(notification.showCount, 1);
      expect(notification.replyCount, 1000);
      expect(notification.conversationId, 'multiple-conversations');
      expect(ReplyNotificationSignal.revision.value, initialRevision + 1);
      expect(find.text('Hai ricevuto 1000 nuove risposte'), findsOneWidget);

      await tester.tap(find.text('Ignora'));
      await tester.pumpAndSettle();
      notification.onTap!();
      await tester.pumpAndSettle();
      final chestPage = tester.widget<ChestPage>(find.byType(ChestPage));
      expect(chestPage.focusConversationId, isNull);
      expect(chestPage.focusReplyId, isNull);
      expect(
        notification.closedConversations,
        contains('multiple-conversations'),
      );

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

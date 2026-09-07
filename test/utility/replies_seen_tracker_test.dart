import 'package:flutter_test/flutter_test.dart';
import 'package:honoo/Utility/replies_seen_tracker.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'ricarica gli id letti senza dipendere da data o conversazione',
    () async {
      await RepliesSeenTracker.markReply(userId: 'user-1', replyId: 'reply-1');
      final state = await RepliesSeenTracker.load(userId: 'user-1');
      expect(
        state.isSeen(
          conversationId: 'changed',
          createdAt: null,
          replyId: 'reply-1',
        ),
        isTrue,
      );
      expect(
        state.isSeen(
          conversationId: 'changed',
          createdAt: null,
          replyId: 'reply-2',
        ),
        isFalse,
      );
      final other = await RepliesSeenTracker.load(userId: 'user-2');
      expect(other.replyIds, isEmpty);
    },
  );

  test(
    'un vecchio cursore locale non annulla il cursore globale più recente',
    () async {
      await RepliesSeenTracker.markAt(
        DateTime.utc(2026, 8, 1),
        userId: 'user-1',
        conversationId: 'conversation-1',
      );
      await RepliesSeenTracker.markAt(
        DateTime.utc(2026, 8, 3),
        userId: 'user-1',
      );
      final state = await RepliesSeenTracker.load(userId: 'user-1');
      expect(
        state.isSeen(
          conversationId: 'conversation-1',
          createdAt: DateTime.utc(2026, 8, 2),
        ),
        isTrue,
      );
    },
  );

  test('mantiene un cursore separato per ogni utente', () async {
    final firstSeen = DateTime.parse('2026-08-03T10:00:00Z');
    final secondSeen = DateTime.parse('2026-08-03T11:00:00Z');

    await RepliesSeenTracker.markAt(firstSeen, userId: 'user-1');
    await RepliesSeenTracker.markAt(secondSeen, userId: 'user-2');

    expect(await RepliesSeenTracker.lastSeen(userId: 'user-1'), firstSeen);
    expect(await RepliesSeenTracker.lastSeen(userId: 'user-2'), secondSeen);
  });

  test('non arretra il cursore quando arriva un evento più vecchio', () async {
    final newest = DateTime.parse('2026-08-03T12:00:00Z');
    final older = DateTime.parse('2026-08-03T09:00:00Z');

    await RepliesSeenTracker.markAt(newest, userId: 'user-1');
    await RepliesSeenTracker.markAt(older, userId: 'user-1');

    expect(await RepliesSeenTracker.lastSeen(userId: 'user-1'), newest);
  });

  test('mantiene lo stato letto separato per ogni conversazione', () async {
    final baseline = DateTime.parse('2026-08-03T09:00:00Z');
    final openedAt = DateTime.parse('2026-08-03T12:00:00Z');
    await RepliesSeenTracker.markAt(baseline, userId: 'user-1');

    await RepliesSeenTracker.markAt(
      openedAt,
      userId: 'user-1',
      conversationId: 'conversation-new',
    );

    final state = await RepliesSeenTracker.load(userId: 'user-1');
    expect(
      state.isSeen(
        conversationId: 'conversation-new',
        createdAt: DateTime.parse('2026-08-03T11:00:00Z'),
      ),
      isTrue,
    );
    expect(
      state.isSeen(
        conversationId: 'conversation-unopened',
        createdAt: DateTime.parse('2026-08-03T11:00:00Z'),
      ),
      isFalse,
    );
  });

  test('ignora una preferenza per conversazione non valida', () async {
    SharedPreferences.setMockInitialValues({
      'last_seen_reply_by_conversation_v1_user-1': '{not-json',
    });

    final state = await RepliesSeenTracker.load(userId: 'user-1');

    expect(state.byConversation, isEmpty);
  });

  test('non perde marcature concorrenti di conversazioni diverse', () async {
    await Future.wait([
      RepliesSeenTracker.markAt(
        DateTime.parse('2026-08-03T10:00:00Z'),
        userId: 'user-1',
        conversationId: 'conversation-1',
      ),
      RepliesSeenTracker.markAt(
        DateTime.parse('2026-08-03T11:00:00Z'),
        userId: 'user-1',
        conversationId: 'conversation-2',
      ),
    ]);

    final state = await RepliesSeenTracker.load(userId: 'user-1');
    expect(
      state.byConversation.keys,
      containsAll(['conversation-1', 'conversation-2']),
    );
  });
}

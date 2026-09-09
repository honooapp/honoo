import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:honoo/Entities/reply_notification_event.dart';
import 'package:honoo/Services/reply_catch_up_service.dart';
import '../test_supabase_helper.dart';

void main() {
  setUpAll(registerSupabaseFallbacks);
  for (final kind in ReplyNotificationKind.values) {
    test('recovers more than 100 $kind replies with tied timestamps', () async {
      final harness = SupabaseTestHarness()..enableOverrides();
      addTearDown(harness.disableOverrides);
      final chain = harness.stubTable(kind.name);
      when(() => chain.lte(any(), any())).thenAnswer((_) => chain);
      const time = '2026-09-09T10:00:00Z';
      chain.queueResponse(
        List.generate(100, (i) => {'id': 'reply-$i', 'created_at': time}),
      );
      chain.queueResponse([
        {'id': 'reply-next', 'created_at': time},
      ]);
      final rows = await ReplyCatchUpService.fetchReplies(
        userId: 'user',
        kind: kind,
        since: '2026-09-08T00:00:00Z',
        until: DateTime.utc(2026, 9, 9, 11),
      );
      expect(rows.length, 101);
      expect(rows.last['id'], 'reply-next');
      verify(
        () => chain.or(
          'created_at.gt.$time,and(created_at.eq.$time,id.gt.reply-99)',
        ),
      ).called(1);
      verify(
        () => chain.lte('created_at', '2026-09-09T11:00:00.000Z'),
      ).called(2);
      verify(() => chain.gt('created_at', '2026-09-08T00:00:00Z')).called(2);
    });
  }
}

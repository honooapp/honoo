import '../Entities/reply_notification_event.dart';
import 'supabase_provider.dart';

class ReplyCatchUpService {
  /// Page through a bounded snapshot, including replies sharing a timestamp.
  static Future<List<Map<String, dynamic>>> fetchReplies({
    required String userId,
    required ReplyNotificationKind kind,
    required String? since,
    DateTime? until,
  }) async {
    final isHonoo = kind == ReplyNotificationKind.honoo;
    final rows = <Map<String, dynamic>>[];
    Map<String, dynamic>? cursor;
    while (true) {
      dynamic query = SupabaseProvider.client
          .from(isHonoo ? 'honoo' : 'hinoo')
          .select(
            'id,${isHonoo ? 'destination' : 'type'},reply_to,recipient_tag,created_at,user_id,conversation_id,admin_deleted_at',
          )
          .eq(isHonoo ? 'destination' : 'type', isHonoo ? 'reply' : 'answer')
          .eq('recipient_tag', userId)
          .is_('admin_deleted_at', null);
      if (until != null) {
        query = query.lte('created_at', until.toUtc().toIso8601String());
      }
      if (since != null) query = query.gt('created_at', since);
      if (cursor != null) {
        final time = cursor['created_at'];
        final id = cursor['id'];
        query = query.or(
          'created_at.gt.$time,and(created_at.eq.$time,id.gt.$id)',
        );
      }
      final page =
          (await query
                      .order('created_at', ascending: true)
                      .order('id', ascending: true)
                      .limit(100)
                  as List)
              .map((row) => Map<String, dynamic>.from(row as Map))
              .toList();
      rows.addAll(page);
      if (page.length < 100) return rows;
      cursor = page.last;
    }
  }
}

/// Per-kind database cursors; never use the device clock to exclude replies.
/// Every tenth successful poll revisits history for arbitrarily late commits.
class ReplyRecoveryWindow {
  final _latest = <ReplyNotificationKind, DateTime>{};
  int _polls = 0;

  String? since(ReplyNotificationKind kind, DateTime? baseline) {
    final latest = _latest[kind];
    final overlap = latest?.subtract(const Duration(minutes: 2));
    final start = _polls % 10 == 0 || overlap == null
        ? baseline
        : baseline != null && baseline.isAfter(overlap)
        ? baseline
        : overlap;
    return start?.toUtc().toIso8601String();
  }

  void record(List<List<Map<String, dynamic>>> results) {
    for (var i = 0; i < results.length; i++) {
      final kind = i == 0
          ? ReplyNotificationKind.honoo
          : ReplyNotificationKind.hinoo;
      for (final row in results[i]) {
        final time = DateTime.tryParse(row['created_at']?.toString() ?? '');
        if (time != null &&
            (_latest[kind] == null || time.isAfter(_latest[kind]!))) {
          _latest[kind] = time;
        }
      }
    }
    _polls++;
  }

  void reset() {
    _latest.clear();
    _polls = 0;
  }
}

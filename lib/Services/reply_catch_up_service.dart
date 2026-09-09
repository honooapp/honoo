import '../Entities/reply_notification_event.dart';
import 'supabase_provider.dart';

class ReplyCatchUpService {
  /// Page through a bounded snapshot, including replies sharing a timestamp.
  static Future<List<Map<String, dynamic>>> fetchReplies({
    required String userId,
    required ReplyNotificationKind kind,
    required String? since,
    required DateTime until,
  }) async {
    final isHonoo = kind == ReplyNotificationKind.honoo;
    final rows = <Map<String, dynamic>>[];
    Map<String, dynamic>? cursor;
    while (true) {
      dynamic query = SupabaseProvider.client
          .from(isHonoo ? 'honoo' : 'hinoo')
          .select(
            'id,${isHonoo ? 'destination' : 'type'},reply_to,recipient_tag,created_at,user_id,conversation_id',
          )
          .eq(isHonoo ? 'destination' : 'type', isHonoo ? 'reply' : 'answer')
          .eq('recipient_tag', userId)
          .lte('created_at', until.toUtc().toIso8601String());
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

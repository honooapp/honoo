import '../Utility/replies_seen_tracker.dart';
import 'reliability_policy.dart';
import 'supabase_provider.dart';

class HomeService {
  const HomeService({this.policy = const ReliabilityPolicy()});

  final ReliabilityPolicy policy;

  Future<int> fetchUnreadReplyCount(String userId) async {
    return policy.read(() async {
      final seenState = await RepliesSeenTracker.load(userId: userId);
      final rows = await Future.wait<dynamic>([
        SupabaseProvider.client
            .from('honoo')
            .select('id,created_at,user_id,conversation_id')
            .eq('destination', 'reply')
            .eq('recipient_tag', userId)
            .neq('user_id', userId),
        SupabaseProvider.client
            .from('hinoo')
            .select('id,created_at,user_id,conversation_id')
            .eq('type', 'answer')
            .eq('recipient_tag', userId)
            .neq('user_id', userId),
      ]);
      final honooRows = rows[0] as List;
      final hinooRows = rows[1] as List;

      int count = 0;
      for (final row in [...honooRows, ...hinooRows]) {
        final createdAt = DateTime.tryParse(
          (row['created_at'] ?? '').toString(),
        );
        final conversationId = (row['conversation_id'] ?? '').toString();
        if (createdAt != null &&
            !seenState.isSeen(
              conversationId: conversationId,
              createdAt: createdAt,
              replyId: row['id']?.toString(),
            )) {
          count++;
        }
      }
      return count;
    });
  }

  Future<void> recordVisit() =>
      policy.write(() => SupabaseProvider.client.rpc('increment_site_visit'));
}

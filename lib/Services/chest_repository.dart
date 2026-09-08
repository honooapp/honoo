import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_provider.dart';
import 'reliability_policy.dart';

/// Accesso dati dello Scrigno. Non contiene stato, mapping UI o ordinamento.
class ChestRepository {
  ChestRepository({
    SupabaseClient? client,
    ReliabilityPolicy reliabilityPolicy = const ReliabilityPolicy(),
  }) : _client = client ?? SupabaseProvider.client,
       _reliability = reliabilityPolicy;

  final SupabaseClient _client;
  final ReliabilityPolicy _reliability;

  Future<Set<String>> fetchHiddenConversationIds(String userId) async {
    final rows = await _client
        .from('chest_hidden_conversations')
        .select('conversation_id')
        .eq('user_id', userId);
    return _asList(rows)
        .map((row) => row is Map ? row['conversation_id']?.toString() : null)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  Future<void> hideConversation({
    required String userId,
    required String conversationId,
  }) async {
    await _reliability.write(
      () async => await _client.from('chest_hidden_conversations').upsert({
        'user_id': userId,
        'conversation_id': conversationId,
      }),
    );
  }

  Future<Set<String>> fetchHinooMoonFingerprints(String userId) async {
    final rows = await _client
        .from('hinoo')
        .select('fingerprint')
        .eq('user_id', userId)
        .eq('type', 'moon');
    return _asList(rows)
        .map((row) => row is Map ? row['fingerprint']?.toString() : null)
        .whereType<String>()
        .where((fingerprint) => fingerprint.isNotEmpty)
        .toSet();
  }

  Future<List<dynamic>> fetchHinooRows(String userId) async {
    final hidden = await fetchHiddenConversationIds(userId);
    try {
      final rows = await _client
          .from('hinoo')
          .select(
            'id,pages,type,reply_to,recipient_tag,created_at,is_from_moon_saved,user_id,conversation_id',
          )
          .in_('type', ['personal', 'answer'])
          .or(
            'user_id.eq.$userId,and(recipient_tag.eq.$userId,or(type.eq.answer,reply_to.not.is.null,conversation_id.not.is.null))',
          )
          .order('created_at', ascending: false);
      return _withoutHiddenConversations(rows, hidden);
    } on PostgrestException catch (error) {
      final combined =
          '${error.message} ${error.details ?? ''} ${error.hint ?? ''}';
      if (!combined.contains('is_from_moon_saved')) rethrow;

      final rows = await _client
          .from('hinoo')
          .select(
            'id,pages,type,reply_to,recipient_tag,created_at,user_id,conversation_id',
          )
          .in_('type', ['personal', 'answer'])
          .or(
            'user_id.eq.$userId,and(recipient_tag.eq.$userId,or(type.eq.answer,reply_to.not.is.null,conversation_id.not.is.null))',
          )
          .order('created_at', ascending: false);
      return _withoutHiddenConversations(rows, hidden);
    }
  }

  Future<List<dynamic>> fetchHonooReplyRows(String userId) async {
    final hidden = await fetchHiddenConversationIds(userId);
    final repliesToUser = await _client
        .from('honoo')
        .select('conversation_id,reply_to,created_at,user_id')
        .eq('destination', 'reply')
        .eq('recipient_tag', userId);
    final repliesFromUser = await _client
        .from('honoo')
        .select('conversation_id,reply_to,created_at,user_id')
        .eq('destination', 'reply')
        .eq('user_id', userId);
    return _withoutHiddenConversations([
      ..._asList(repliesToUser),
      ..._asList(repliesFromUser),
    ], hidden);
  }

  Future<List<dynamic>> fetchHinooReplyRows(
    String userId,
    List<String> _,
  ) async {
    final hidden = await fetchHiddenConversationIds(userId);
    final repliesToUser = await _client
        .from('hinoo')
        .select(
          'id,conversation_id,reply_to,pages,type,recipient_tag,created_at,user_id',
        )
        .or(
          'type.eq.answer,and(conversation_id.not.is.null,recipient_tag.not.is.null)',
        )
        .eq('recipient_tag', userId)
        .order('created_at', ascending: true);
    final repliesFromUser = await _client
        .from('hinoo')
        .select(
          'id,conversation_id,reply_to,pages,type,recipient_tag,created_at,user_id',
        )
        .or(
          'type.eq.answer,and(conversation_id.not.is.null,recipient_tag.not.is.null)',
        )
        .eq('user_id', userId)
        .order('created_at', ascending: true);
    return _withoutHiddenConversations([
      ..._asList(repliesToUser),
      ..._asList(repliesFromUser),
    ], hidden);
  }

  Future<void> deleteHinoo(String id) async {
    await _reliability.write(
      () async => await _client.from('hinoo').delete().eq('id', id),
    );
  }

  static List<dynamic> _asList(dynamic rows) {
    if (rows is List) return rows;
    if (rows is Map) return [rows];
    return const [];
  }

  static List<dynamic> _withoutHiddenConversations(
    dynamic rows,
    Set<String> hidden,
  ) {
    if (hidden.isEmpty) return _asList(rows);
    return _asList(rows)
        .where((row) {
          if (row is! Map) return true;
          final rowId = row['id']?.toString();
          final conversationId = row['conversation_id']?.toString();
          final fallbackId = row['reply_to']?.toString();
          return !hidden.contains(rowId) &&
              !hidden.contains(conversationId) &&
              !hidden.contains(fallbackId);
        })
        .toList(growable: false);
  }
}

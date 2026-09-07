import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'reply_notification_signal.dart';

class RepliesSeenTracker {
  static const _key = 'last_seen_reply_at_v1';
  static const _conversationKey = 'last_seen_reply_by_conversation_v1';
  static const _replyIdsKey = 'seen_reply_ids_v1';
  static Future<void>? _writeQueue;

  static Future<void> _serializeWrite(Future<void> Function() operation) {
    final pending = _writeQueue;
    final next = pending == null
        ? operation()
        : pending.then((_) => operation(), onError: (_) => operation());
    _writeQueue = next;
    void release() {
      if (identical(_writeQueue, next)) _writeQueue = null;
    }

    next.then<void>((_) => release(), onError: (_) => release());
    return next;
  }

  static String _keyFor(String? userId) {
    final normalized = userId?.trim() ?? '';
    return normalized.isEmpty ? _key : '${_key}_$normalized';
  }

  static String _conversationKeyFor(String? userId) {
    final normalized = userId?.trim() ?? '';
    return normalized.isEmpty
        ? _conversationKey
        : '${_conversationKey}_$normalized';
  }

  static Future<ReplySeenState> load({String? userId}) async {
    final prefs = await SharedPreferences.getInstance();
    final baseline = DateTime.tryParse(prefs.getString(_keyFor(userId)) ?? '');
    final encoded = prefs.getString(_conversationKeyFor(userId));
    final byConversation = <String, DateTime>{};
    if (encoded != null && encoded.isNotEmpty) {
      try {
        final decoded = jsonDecode(encoded);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            final parsed = DateTime.tryParse(entry.value.toString());
            if (parsed != null && entry.key.toString().isNotEmpty) {
              byConversation[entry.key.toString()] = parsed;
            }
          }
        }
      } catch (_) {
        // Una preferenza corrotta non deve impedire il caricamento dello Scrigno.
      }
    }
    return ReplySeenState(
      baseline: baseline,
      byConversation: Map.unmodifiable(byConversation),
      replyIds: Set.unmodifiable(
        prefs.getStringList('${_replyIdsKey}_${userId ?? ''}') ?? const [],
      ),
    );
  }

  /// Persist the actual displayed reply, even if it is later returned with a
  /// different conversation association or without its timestamp.
  static Future<void> markReply({
    required String userId,
    required String replyId,
  }) => _serializeWrite(() async {
    if (replyId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final key = '${_replyIdsKey}_$userId';
    final ids = (prefs.getStringList(key) ?? const <String>[]).toSet();
    if (!ids.add(replyId)) return;
    await prefs.setStringList(key, ids.toList());
    ReplyNotificationSignal.notifyChanged();
  });

  static Future<DateTime?> lastSeen({String? userId}) async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_keyFor(userId));
    if (s == null || s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  static Future<void> markNow({String? userId}) => _serializeWrite(() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _keyFor(userId),
      DateTime.now().toUtc().toIso8601String(),
    );
    ReplyNotificationSignal.notifyChanged();
  });

  static Future<void> markAt(
    DateTime dt, {
    String? userId,
    String? conversationId,
  }) => _serializeWrite(() async {
    final normalizedConversation = conversationId?.trim() ?? '';
    if (normalizedConversation.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      final state = await load(userId: userId);
      final current = state.byConversation[normalizedConversation];
      if (current != null && !dt.isAfter(current)) return;
      final updated = <String, String>{
        for (final entry in state.byConversation.entries)
          entry.key: entry.value.toUtc().toIso8601String(),
        normalizedConversation: dt.toUtc().toIso8601String(),
      };
      await prefs.setString(_conversationKeyFor(userId), jsonEncode(updated));
      ReplyNotificationSignal.notifyChanged();
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final key = _keyFor(userId);
    final current = DateTime.tryParse(prefs.getString(key) ?? '');
    if (current != null && !dt.isAfter(current)) return;
    await prefs.setString(key, dt.toUtc().toIso8601String());
    ReplyNotificationSignal.notifyChanged();
  });
}

class ReplySeenState {
  const ReplySeenState({
    required this.baseline,
    required this.byConversation,
    this.replyIds = const {},
  });

  final DateTime? baseline;
  final Map<String, DateTime> byConversation;
  final Set<String> replyIds;

  bool isSeen({
    required String conversationId,
    required DateTime? createdAt,
    String? replyId,
  }) {
    if (replyId != null && replyIds.contains(replyId)) return true;
    if (createdAt == null) return false;
    final conversationThreshold = byConversation[conversationId];
    final threshold =
        conversationThreshold == null ||
            (baseline != null && baseline!.isAfter(conversationThreshold))
        ? baseline
        : conversationThreshold;
    return threshold != null && !createdAt.isAfter(threshold);
  }
}

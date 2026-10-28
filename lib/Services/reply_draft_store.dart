import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// User-scoped local drafts, including the identity of an uncertain send.
class ReplyDraftStore {
  ReplyDraftStore(String userId, String parentId)
    : _key =
          'reply_draft:${Uri.encodeComponent(userId)}:${Uri.encodeComponent(parentId)}';
  final String _key;
  static final Map<String, Future<void>> _writes = {};

  Future<Map<String, dynamic>?> load() async {
    await _writes[_key];
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    return Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  Future<void> save(Map<String, dynamic>? draft) {
    final encoded = draft == null ? null : jsonEncode(draft);
    final operation = (_writes[_key] ?? Future<void>.value()).then((_) async {
      final prefs = await SharedPreferences.getInstance();
      final saved = encoded == null
          ? await prefs.remove(_key)
          : await prefs.setString(_key, encoded);
      if (!saved) throw StateError('Unable to save reply draft');
    });
    // A failed write must not prevent a subsequent save or removal.
    late final Future<void> tail;
    tail = operation.catchError((Object _) {}).then((_) {
      if (identical(_writes[_key], tail)) _writes.remove(_key);
    });
    _writes[_key] = tail;
    return operation;
  }
}

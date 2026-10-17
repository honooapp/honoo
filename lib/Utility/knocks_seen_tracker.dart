import 'package:shared_preferences/shared_preferences.dart';
import 'reply_notification_signal.dart';

/// Opening a request is independent of accepting the visitor into the house.
class KnocksSeenTracker {
  static String _key(String userId) => 'seen_knock_ids_v1_$userId';

  static Future<Set<String>> load(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_key(userId)) ?? const <String>[]).toSet();
  }

  static Future<void> mark(String userId, String knockId) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = (prefs.getStringList(_key(userId)) ?? const <String>[]).toSet();
    if (ids.add(knockId)) {
      await prefs.setStringList(_key(userId), ids.toList());
      ReplyNotificationSignal.notifyChanged();
    }
  }
}

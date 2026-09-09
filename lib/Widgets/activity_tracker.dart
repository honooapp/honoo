import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../Services/supabase_provider.dart';

/// A short-lived, authenticated presence signal; background tabs expire.
class ActivityTracker extends StatefulWidget {
  const ActivityTracker({super.key, required this.child});
  final Widget child;

  @override
  State<ActivityTracker> createState() => _ActivityTrackerState();
}

class _ActivityTrackerState extends State<ActivityTracker>
    with WidgetsBindingObserver {
  Timer? _timer;
  StreamSubscription<AuthState>? _auth;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _auth = SupabaseProvider.client.auth.onAuthStateChange.listen(
      (_) => _send(),
    );
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _send());
    _send();
  }

  Future<void> _send() async {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (!mounted ||
        _sending ||
        (lifecycle != null && lifecycle != AppLifecycleState.resumed) ||
        SupabaseProvider.client.auth.currentUser == null) {
      return;
    }
    _sending = true;
    try {
      await SupabaseProvider.client.rpc('record_activity');
    } catch (_) {
      // A failed heartbeat expires naturally and is retried on the next tick.
    } finally {
      _sending = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _send();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _auth?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

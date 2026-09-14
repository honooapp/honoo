import 'dart:async';

import 'package:flutter/material.dart';
import 'package:honoo/Pages/new_hinoo_page.dart';
import 'package:honoo/Services/house_invite_service.dart';
import 'package:honoo/Services/house_invite_prompt_controller.dart';
import 'package:honoo/Services/supabase_provider.dart';
import 'package:honoo/Widgets/honoo_dialogs.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GlobalInviteListener extends StatefulWidget {
  const GlobalInviteListener({
    super.key,
    required this.child,
    required this.navigatorKey,
    required this.enabled,
  });

  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;
  final bool enabled;

  @override
  State<GlobalInviteListener> createState() => _GlobalInviteListenerState();
}

class _GlobalInviteListenerState extends State<GlobalInviteListener>
    with WidgetsBindingObserver {
  HouseInviteService? _inviteService;
  StreamSubscription<AuthState>? _authSub;
  Timer? _inviteRefreshTimer;
  bool _checkingInviteFlow = false;
  bool _dialogOpen = false;
  bool _inviteDeferred = false;
  bool _started = false;
  RealtimeChannel? _inviteChannel;
  String? _inviteChannelUserId;
  RealtimeChannel? _inviteEmailChannel;
  String? _inviteChannelEmail;
  DateTime? _lastInviteToastAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HouseInvitePromptController.requests.addListener(_resumeInviteFlow);
    if (widget.enabled) {
      _start();
    }
  }

  @override
  void didUpdateWidget(GlobalInviteListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.enabled && widget.enabled) {
      _start();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _inviteRefreshTimer?.cancel();
    _inviteChannel?.unsubscribe();
    _inviteEmailChannel?.unsubscribe();
    _authSub?.cancel();
    HouseInvitePromptController.requests.removeListener(_resumeInviteFlow);
    super.dispose();
  }

  void _resumeInviteFlow() {
    _inviteDeferred = false;
    unawaited(_checkInviteFlow());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.enabled) {
      _inviteDeferred = false;
      unawaited(_checkInviteFlow());
    }
  }

  void _handleAuthChange(Session? session) {
    _inviteRefreshTimer?.cancel();
    _inviteChannel?.unsubscribe();
    _inviteEmailChannel?.unsubscribe();
    _inviteChannel = null;
    _inviteEmailChannel = null;
    _inviteChannelUserId = null;
    _inviteChannelEmail = null;
    _dialogOpen = false;
    _inviteDeferred = false;
    if (session == null) return;

    _inviteService ??= HouseInviteService();

    _subscribeInviteChannel(session.user.id);
    final email = session.user.email;
    if (email != null && email.isNotEmpty) {
      _subscribeInviteEmailChannel(email);
    }
    _inviteRefreshTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _checkInviteFlow(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkInviteFlow());
  }

  void _start() {
    if (_started) return;
    _started = true;
    _authSub = SupabaseProvider.client.auth.onAuthStateChange.listen((state) {
      _handleAuthChange(state.session);
    });
    _handleAuthChange(SupabaseProvider.client.auth.currentSession);
  }

  void _subscribeInviteChannel(String userId) {
    if (_inviteChannel != null && _inviteChannelUserId == userId) return;
    try {
      _inviteChannel?.unsubscribe();
      _inviteChannelUserId = userId;
      _inviteChannel = SupabaseProvider.client.channel('house-invites-$userId');
      _inviteChannel!
          .on(
            RealtimeListenTypes.postgresChanges,
            ChannelFilter(
              event: '*',
              schema: 'public',
              table: 'house_invites',
              filter: 'user_id=eq.$userId',
            ),
            _handleInviteChange,
          )
          .subscribe();
    } catch (_) {
      // In test or when Realtime not available, safely ignore
    }
  }

  void _subscribeInviteEmailChannel(String email) {
    if (_inviteEmailChannel != null && _inviteChannelEmail == email) return;
    try {
      _inviteEmailChannel?.unsubscribe();
      _inviteChannelEmail = email;
      _inviteEmailChannel = SupabaseProvider.client.channel(
        'house-invites-email-$email',
      );
      _inviteEmailChannel!
          .on(
            RealtimeListenTypes.postgresChanges,
            ChannelFilter(
              event: '*',
              schema: 'public',
              table: 'house_invites',
              filter: 'email=eq.$email',
            ),
            _handleInviteChange,
          )
          .subscribe();
    } catch (_) {
      // In test or when Realtime not available, safely ignore
    }
  }

  void _handleInviteChange(dynamic payload, [dynamic _]) {
    final eventType = payload is Map
        ? (payload['eventType'] ?? payload['event_type'])
        : null;
    final event = eventType?.toString().toLowerCase();
    if (event != null && event != 'insert' && event != 'update') {
      return;
    }
    final record = payload is Map
        ? (payload['new'] ?? payload['newRecord'] ?? payload['record'])
        : null;
    final status = record is Map ? record['status']?.toString() : null;
    if (status != null && status != 'pending' && status != 'accepted') {
      return;
    }
    if (status == 'pending') _inviteDeferred = false;
    _checkInviteFlow();
    final now = DateTime.now();
    if (_lastInviteToastAt != null &&
        now.difference(_lastInviteToastAt!) < const Duration(seconds: 3)) {
      return;
    }
    _lastInviteToastAt = now;
    final context = widget.navigatorKey.currentContext;
    if (context == null) return;
    showHonooToast(
      context,
      message: 'Invito ricevuto',
      duration: const Duration(milliseconds: 2000),
    );
  }

  Future<void> _checkInviteFlow() async {
    if (!mounted ||
        !widget.enabled ||
        _checkingInviteFlow ||
        _dialogOpen ||
        _inviteDeferred) {
      return;
    }
    _checkingInviteFlow = true;

    final user = SupabaseProvider.client.auth.currentUser;
    if (user == null) {
      _checkingInviteFlow = false;
      return;
    }

    final inviteService = _inviteService ??= HouseInviteService();

    final email = user.email;
    try {
      if (email != null && email.isNotEmpty) {
        try {
          await inviteService.syncInvitesForEmail(email);
        } catch (_) {}
      }

      final hasCasa = await inviteService.hasCasa(user.id);
      if (hasCasa) {
        return;
      }

      var hasInvite = await inviteService.hasAuthorizedInvite(user.id);
      if (!hasInvite && email != null && email.isNotEmpty) {
        try {
          await inviteService.syncInvitesForEmail(email);
        } catch (_) {}
        hasInvite = await inviteService.hasAuthorizedInvite(user.id);
      }
      if (!hasInvite ||
          !mounted ||
          !widget.enabled ||
          SupabaseProvider.client.auth.currentUser?.id != user.id) {
        return;
      }

      final bool? accepted = await _showCasaInviteDialog();
      if (accepted != true) {
        _inviteDeferred = true;
        return;
      }

      await inviteService.markInvitesAccepted(user.id);
      _inviteDeferred = true;

      if (!mounted || SupabaseProvider.client.auth.currentUser?.id != user.id) {
        return;
      }
      final navigator = widget.navigatorKey.currentState;
      if (navigator == null) return;
      await navigator.push(
        MaterialPageRoute(
          builder: (_) => const NewHinooPage(isCampanello: true),
        ),
      );
    } catch (_) {
    } finally {
      _checkingInviteFlow = false;
    }
  }

  Future<bool?> _showCasaInviteDialog() async {
    final context = widget.navigatorKey.currentContext;
    if (context == null) return null;
    _dialogOpen = true;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => HonooDialogShell(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Complimenti!',
                style: HonooDialogStyles.title(),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Ecco la tua casa sull\'Isola, crea il tuo campanello!',
                style: HonooDialogStyles.body(),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: Column(
                  children: [
                    ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        'Crea il campanello',
                        style: HonooDialogStyles.primaryAction(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white70,
                      ),
                      child: Text(
                        'Non ora',
                        style: HonooDialogStyles.tertiaryAction(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    _dialogOpen = false;
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

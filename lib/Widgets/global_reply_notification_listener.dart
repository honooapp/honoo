import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../Entities/reply_notification_event.dart';
import '../Pages/chest_page.dart';
import '../Services/reply_system_notification.dart';
import '../Services/supabase_provider.dart';
import '../Utility/reply_notification_signal.dart';
import '../Utility/replies_seen_tracker.dart';
import 'honoo_dialogs.dart';

class GlobalReplyNotificationListener extends StatefulWidget {
  const GlobalReplyNotificationListener({
    super.key,
    required this.child,
    required this.navigatorKey,
    this.enabled = true,
    this.systemNotification,
    this.replyEventStream,
    this.notificationBatchWindow = const Duration(milliseconds: 180),
    this.catchUpInterval = const Duration(seconds: 30),
  });

  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;
  final bool enabled;
  final ReplySystemNotification? systemNotification;
  @visibleForTesting
  final Stream<ReplyNotificationEvent>? replyEventStream;
  @visibleForTesting
  final Duration notificationBatchWindow;
  @visibleForTesting
  final Duration catchUpInterval;

  @override
  State<GlobalReplyNotificationListener> createState() =>
      _GlobalReplyNotificationListenerState();
}

class _GlobalReplyNotificationListenerState
    extends State<GlobalReplyNotificationListener>
    with WidgetsBindingObserver {
  late final ReplySystemNotification _systemNotification =
      widget.systemNotification ?? ReplySystemNotification.platform();
  StreamSubscription<AuthState>? _authSubscription;
  StreamSubscription<ReplyNotificationEvent>? _replyEventSubscription;
  RealtimeChannel? _replyChannel;
  Timer? _reconnectTimer;
  Timer? _notificationTimer;
  Timer? _catchUpTimer;
  int? _catchUpInFlightGeneration;
  DateTime? _lastCatchUpAt;
  int _reconnectAttempt = 0;
  int _channelGeneration = 0;
  String? _activeUserId;
  final Set<String> _deliveredEventKeys = <String>{};
  final Map<String, ReplyNotificationEvent> _pendingEvents =
      <String, ReplyNotificationEvent>{};
  final Map<String, ReplyNotificationEvent> _shownEventsByConversation =
      <String, ReplyNotificationEvent>{};
  bool _multipleNotificationShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ReplyNotificationSignal.revision.addListener(_reconcileSeenNotifications);
    if (widget.enabled) _start();
  }

  @override
  void didUpdateWidget(GlobalReplyNotificationListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.catchUpInterval != widget.catchUpInterval) {
      _catchUpTimer?.cancel();
      _catchUpTimer = null;
      final userId = _activeUserId;
      if (widget.enabled && userId != null) _startCatchUpTimer(userId);
    }
    if (!oldWidget.enabled && widget.enabled) {
      _start();
    } else if (oldWidget.enabled && !widget.enabled) {
      _stop();
    }
  }

  void _start() {
    final testEvents = widget.replyEventStream;
    if (testEvents != null) {
      _replyEventSubscription ??= testEvents.listen(_handleEvent);
      return;
    }
    _authSubscription ??= SupabaseProvider.client.auth.onAuthStateChange.listen(
      (state) {
        _handleSession(state.session);
      },
    );
    _handleSession(SupabaseProvider.client.auth.currentSession);
  }

  void _handleSession(Session? session) {
    final userId = session?.user.id;
    final accessToken = session?.accessToken;
    if (accessToken != null) {
      SupabaseProvider.client.realtime.setAuth(accessToken);
    }
    if (userId == _activeUserId) {
      if (userId != null && _replyChannel == null) {
        _connectChannels(userId);
      }
      if (userId != null) _startCatchUpTimer(userId);
      return;
    }
    _closeRealtime(clearUser: false);
    _deliveredEventKeys.clear();
    _lastCatchUpAt = null;
    _activeUserId = userId;
    if (userId == null) return;
    _connectChannels(userId);
    _startCatchUpTimer(userId);
  }

  void _startCatchUpTimer(String userId) {
    _catchUpTimer ??= Timer.periodic(widget.catchUpInterval, (_) {
      if (_activeUserId == userId && _replyChannel != null) {
        unawaited(_catchUpMissedReplies(userId, _channelGeneration));
      }
    });
  }

  void _connectChannels(String userId) {
    _reconnectTimer?.cancel();
    final generation = ++_channelGeneration;
    try {
      final channel =
          SupabaseProvider.client.channel('reply-events-$userId-$generation')
            ..on(
              RealtimeListenTypes.postgresChanges,
              ChannelFilter(
                event: 'INSERT',
                schema: 'public',
                table: 'honoo',
                filter: 'recipient_tag=eq.$userId',
              ),
              (dynamic payload, [dynamic _]) =>
                  _handlePayload(payload, ReplyNotificationKind.honoo, userId),
            )
            ..on(
              RealtimeListenTypes.postgresChanges,
              ChannelFilter(
                event: 'INSERT',
                schema: 'public',
                table: 'hinoo',
                filter: 'recipient_tag=eq.$userId',
              ),
              (dynamic payload, [dynamic _]) =>
                  _handlePayload(payload, ReplyNotificationKind.hinoo, userId),
            );
      _replyChannel = channel;
      channel.subscribe((status, [error]) {
        if (!mounted || generation != _channelGeneration) return;
        if (status == 'SUBSCRIBED') {
          _reconnectAttempt = 0;
          _reconnectTimer?.cancel();
          unawaited(_catchUpMissedReplies(userId, generation));
          return;
        }
        if (status == 'CHANNEL_ERROR' ||
            status == 'CLOSED' ||
            status == 'TIMED_OUT') {
          _scheduleReconnect(userId);
        }
      });
    } catch (_) {
      _replyChannel = null;
      _scheduleReconnect(userId);
    }
  }

  void _scheduleReconnect(String userId) {
    if (_activeUserId != userId || _reconnectTimer?.isActive == true) return;
    final cappedAttempt = _reconnectAttempt > 5 ? 5 : _reconnectAttempt;
    final seconds = 1 << cappedAttempt;
    _reconnectAttempt += 1;
    _reconnectTimer = Timer(Duration(seconds: seconds), () {
      if (!mounted || _activeUserId != userId) return;
      final staleChannel = _replyChannel;
      _replyChannel = null;
      staleChannel?.unsubscribe();
      _connectChannels(userId);
    });
  }

  void _handlePayload(
    dynamic payload,
    ReplyNotificationKind kind,
    String userId,
  ) {
    final event = ReplyNotificationEvent.fromRealtimePayload(
      payload,
      kind: kind,
      currentUserId: userId,
    );
    if (event == null) return;

    _handleEvent(event);
  }

  void _handleEvent(ReplyNotificationEvent event) {
    final eventKey =
        '${event.recipientId}:${event.kind.name}:${event.replyId ?? event.conversationId}';
    if (!_deliveredEventKeys.add(eventKey)) return;
    if (_deliveredEventKeys.length > 4096) {
      _deliveredEventKeys.remove(_deliveredEventKeys.first);
    }
    _pendingEvents[eventKey] = event;
    _notificationTimer ??= Timer(
      widget.notificationBatchWindow,
      _flushPendingEvents,
    );
  }

  Future<void> _flushPendingEvents() async {
    _notificationTimer = null;
    if (!mounted || _pendingEvents.isEmpty) return;
    final queuedEvents = _pendingEvents.values.toList(growable: false);
    _pendingEvents.clear();
    final events = await _onlyUnseenEvents(queuedEvents);
    if (!mounted || events.isEmpty) return;
    final event = events.last;
    final replyCount = events.length;
    final conversationIds = events.map((item) => item.conversationId).toSet();
    final hasMultipleConversations = conversationIds.length > 1;
    ReplyNotificationSignal.notifyChanged();

    void open() => hasMultipleConversations
        ? _openRepliesInbox()
        : _openConversation(event);
    _systemNotification.show(
      contentLabel: event.contentLabel,
      conversationId: hasMultipleConversations
          ? 'multiple-conversations'
          : event.conversationId,
      onTap: open,
      replyCount: replyCount,
    );
    _multipleNotificationShown =
        _multipleNotificationShown || hasMultipleConversations;
    for (final item in events) {
      _shownEventsByConversation[item.conversationId] = item;
    }

    final context = widget.navigatorKey.currentContext;
    if (context != null && context.mounted) {
      unawaited(
        _showReplyDialog(context, replyCount: replyCount, onOpen: open),
      );
    }
  }

  Future<List<ReplyNotificationEvent>> _onlyUnseenEvents(
    List<ReplyNotificationEvent> events,
  ) async {
    if (events.isEmpty) return const [];
    final result = <ReplyNotificationEvent>[];
    final states = <String, ReplySeenState>{};
    for (final event in events) {
      final createdAt = event.createdAt;
      final state = states[event.recipientId] ??= await RepliesSeenTracker.load(
        userId: event.recipientId,
      );
      if (!state.isSeen(
        conversationId: event.conversationId,
        createdAt: createdAt,
        replyId: event.replyId,
      )) {
        result.add(event);
      }
    }
    return result;
  }

  void _reconcileSeenNotifications() {
    unawaited(_closeNotificationsAlreadySeen());
  }

  Future<void> _closeNotificationsAlreadySeen() async {
    if (_shownEventsByConversation.isEmpty && _pendingEvents.isEmpty) return;
    final events = <ReplyNotificationEvent>{
      ..._shownEventsByConversation.values,
      ..._pendingEvents.values,
    }.toList(growable: false);
    final unseen = await _onlyUnseenEvents(events);
    if (!mounted) return;
    final unseenConversations = unseen.map((e) => e.conversationId).toSet();
    final shownConversations = _shownEventsByConversation.keys.toList();
    for (final conversationId in shownConversations) {
      if (unseenConversations.contains(conversationId)) continue;
      _systemNotification.closeConversation(conversationId);
      _shownEventsByConversation.remove(conversationId);
    }
    if (_multipleNotificationShown && _shownEventsByConversation.isEmpty) {
      _systemNotification.closeConversation('multiple-conversations');
      _multipleNotificationShown = false;
    }
    _pendingEvents.removeWhere(
      (_, event) => !unseenConversations.contains(event.conversationId),
    );
  }

  Future<void> _showReplyDialog(
    BuildContext context, {
    required int replyCount,
    required VoidCallback onOpen,
  }) async {
    final shouldOpen = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      builder: (_) => HonooConfirmDialog(
        title: replyCount == 1
            ? 'Hai ricevuto una nuova risposta'
            : 'Hai ricevuto $replyCount nuove risposte',
        confirmLabel: 'Apri',
        cancelLabel: 'Ignora',
      ),
    );
    if (!mounted || shouldOpen != true) return;
    onOpen();
  }

  Future<void> _catchUpMissedReplies(String userId, int generation) async {
    if (_catchUpInFlightGeneration == generation) return;
    _catchUpInFlightGeneration = generation;
    try {
      final catchUpStartedAt = DateTime.now().toUtc();
      final seenState = await RepliesSeenTracker.load(userId: userId);
      if (!mounted || generation != _channelGeneration) return;
      final baseline = seenState.baseline?.toUtc();
      final lastCatchUp = _lastCatchUpAt;
      final sinceDate =
          baseline == null ||
              (lastCatchUp != null && lastCatchUp.isAfter(baseline))
          ? lastCatchUp
          : baseline;
      final since = sinceDate?.toIso8601String();
      dynamic honooQuery = SupabaseProvider.client
          .from('honoo')
          .select(
            'id,destination,reply_to,recipient_tag,created_at,user_id,conversation_id',
          )
          .eq('destination', 'reply')
          .eq('recipient_tag', userId);
      dynamic hinooQuery = SupabaseProvider.client
          .from('hinoo')
          .select(
            'id,type,reply_to,recipient_tag,created_at,user_id,conversation_id',
          )
          .eq('type', 'answer')
          .eq('recipient_tag', userId);
      if (since != null) {
        honooQuery = honooQuery.gt('created_at', since);
        hinooQuery = hinooQuery.gt('created_at', since);
      }
      final results = await Future.wait<dynamic>([
        honooQuery.order('created_at', ascending: false).limit(100),
        hinooQuery.order('created_at', ascending: false).limit(100),
      ]);
      if (!mounted || generation != _channelGeneration) return;
      final pending = <ReplyNotificationEvent>[];
      for (var i = 0; i < results.length; i++) {
        final kind = i == 0
            ? ReplyNotificationKind.honoo
            : ReplyNotificationKind.hinoo;
        for (final row in (results[i] as List).whereType<Map>()) {
          final event = ReplyNotificationEvent.fromRealtimePayload(
            {'eventType': 'INSERT', 'new': row},
            kind: kind,
            currentUserId: userId,
          );
          final createdAt = event?.createdAt;
          if (event != null &&
              createdAt != null &&
              !seenState.isSeen(
                conversationId: event.conversationId,
                createdAt: createdAt,
                replyId: event.replyId,
              )) {
            pending.add(event);
          }
        }
      }
      pending.sort(
        (a, b) => (a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)),
      );
      for (final event in pending) {
        _handleEvent(event);
      }
      _lastCatchUpAt = catchUpStartedAt;
    } catch (_) {
      // Il canale realtime resta attivo; il controllo periodico ritenterà.
    } finally {
      if (_catchUpInFlightGeneration == generation) {
        _catchUpInFlightGeneration = null;
      }
    }
  }

  void _openConversation(ReplyNotificationEvent event) {
    _systemNotification.closeConversation(event.conversationId);
    widget.navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => ChestPage(
          focusReplies: true,
          focusConversationId: event.conversationId,
          focusReplyId: event.replyId,
          highlightLatest: true,
        ),
      ),
    );
  }

  void _openRepliesInbox() {
    _systemNotification.closeConversation('multiple-conversations');
    widget.navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) =>
            const ChestPage(focusReplies: true, highlightLatest: true),
      ),
    );
  }

  void _closeRealtime({bool clearUser = true}) {
    _catchUpTimer?.cancel();
    _catchUpTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _channelGeneration += 1;
    _replyChannel?.unsubscribe();
    _replyChannel = null;
    _reconnectAttempt = 0;
    if (clearUser) _activeUserId = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final userId = _activeUserId;
    if (userId == null) return;
    if (_replyChannel == null) {
      _connectChannels(userId);
    } else {
      unawaited(_catchUpMissedReplies(userId, _channelGeneration));
    }
    _startCatchUpTimer(userId);
  }

  void _stop() {
    _notificationTimer?.cancel();
    _notificationTimer = null;
    _pendingEvents.clear();
    _shownEventsByConversation.clear();
    _multipleNotificationShown = false;
    _replyEventSubscription?.cancel();
    _replyEventSubscription = null;
    _authSubscription?.cancel();
    _authSubscription = null;
    _closeRealtime();
    _lastCatchUpAt = null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ReplyNotificationSignal.revision.removeListener(
      _reconcileSeenNotifications,
    );
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

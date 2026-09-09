import 'dart:async';

import 'package:flutter/foundation.dart';

import '../Entities/chest_item.dart';
import '../Entities/hinoo.dart';
import '../Entities/hinoo_thread_entry.dart';
import '../Services/chest_repository.dart';
import '../Services/chest_realtime_service.dart';
import '../Services/hinoo_service.dart';
import '../Services/reliability_policy.dart';

class ChestState {
  ChestState({
    List<ChestHinooItem> hinoo = const [],
    Map<String, DateTime> honooLatestReplies = const {},
    Map<String, DateTime> hinooLatestReplies = const {},
    Map<String, DateTime> honooLatestReceivedReplies = const {},
    Map<String, DateTime> hinooLatestReceivedReplies = const {},
    Map<String, List<HinooThreadEntry>> hinooRepliesByRoot = const {},
    this.isHinooLoading = true,
    this.isReplyLoading = false,
    this.hinooError,
    this.replyError,
  }) : hinoo = List.unmodifiable(hinoo),
       honooLatestReplies = Map.unmodifiable(honooLatestReplies),
       hinooLatestReplies = Map.unmodifiable(hinooLatestReplies),
       honooLatestReceivedReplies = Map.unmodifiable(
         honooLatestReceivedReplies,
       ),
       hinooLatestReceivedReplies = Map.unmodifiable(
         hinooLatestReceivedReplies,
       ),
       hinooRepliesByRoot = Map<String, List<HinooThreadEntry>>.unmodifiable(
         hinooRepliesByRoot.map<String, List<HinooThreadEntry>>(
           (key, value) =>
               MapEntry(key, List<HinooThreadEntry>.unmodifiable(value)),
         ),
       );

  final List<ChestHinooItem> hinoo;
  final Map<String, DateTime> honooLatestReplies;
  final Map<String, DateTime> hinooLatestReplies;
  final Map<String, DateTime> honooLatestReceivedReplies;
  final Map<String, DateTime> hinooLatestReceivedReplies;
  final Map<String, List<HinooThreadEntry>> hinooRepliesByRoot;
  final bool isHinooLoading;
  final bool isReplyLoading;
  final Object? hinooError;
  final Object? replyError;
  Object? get error => hinooError ?? replyError;
}

class ChestController extends ValueNotifier<ChestState> {
  ChestController({
    required this._repository,
    ChestRealtimeGateway? realtimeGateway,
    ReliabilityPolicy reliabilityPolicy = const ReliabilityPolicy(),
    this._realtimeReconnectBaseDelay = const Duration(seconds: 1),
    this._realtimeReconnectMaxDelay = const Duration(seconds: 30),
  }) : _realtimeGateway = realtimeGateway ?? SupabaseChestRealtimeGateway(),
       _reliability = reliabilityPolicy,
       super(ChestState());

  final ChestRepository _repository;
  final ChestRealtimeGateway _realtimeGateway;
  final ReliabilityPolicy _reliability;
  final Duration _realtimeReconnectBaseDelay;
  final Duration _realtimeReconnectMaxDelay;
  ChestRealtimeSubscription? _realtimeSubscription;
  Timer? _periodicRefreshTimer;
  Timer? _realtimeDebounce;
  Timer? _realtimeReconnectTimer;
  String? _activeUserId;
  Future<void> Function()? _onPeriodicReconcile;
  int _realtimeReconnectAttempt = 0;
  int _realtimeGeneration = 0;
  bool _isRefreshingReplies = false;
  String? _pendingReplyUserId;
  bool _isDisposed = false;
  String? _stateUserId;
  int _hinooLoadGeneration = 0;
  int _replyLoadGeneration = 0;

  void startRealtime(
    String userId, {
    Duration refreshInterval = const Duration(seconds: 60),
    Future<void> Function()? onPeriodicReconcile,
  }) {
    stopRealtime();
    _activeUserId = userId;
    _onPeriodicReconcile = onPeriodicReconcile;
    _connectRealtime(userId);
    _periodicRefreshTimer = Timer.periodic(
      refreshInterval,
      (_) => _runPeriodicReconcile(userId),
    );
  }

  void _connectRealtime(String userId) {
    if (_activeUserId != userId) return;
    _realtimeReconnectTimer?.cancel();
    _realtimeReconnectTimer = null;
    final previous = _realtimeSubscription;
    _realtimeSubscription = null;
    if (previous != null) unawaited(previous.close());

    final generation = ++_realtimeGeneration;
    try {
      _realtimeSubscription = _realtimeGateway.subscribe(
        userId: userId,
        onChange: _scheduleRealtimeRefresh,
        onStatus: (status, error) =>
            _handleRealtimeStatus(userId, generation, status),
      );
    } catch (_) {
      _scheduleRealtimeReconnect(userId, generation);
    }
  }

  void _handleRealtimeStatus(
    String userId,
    int generation,
    ChestRealtimeConnectionStatus status,
  ) {
    if (_activeUserId != userId || generation != _realtimeGeneration) return;
    if (status == ChestRealtimeConnectionStatus.subscribed) {
      _realtimeReconnectAttempt = 0;
      _realtimeReconnectTimer?.cancel();
      _realtimeReconnectTimer = null;
      _scheduleRealtimeRefresh();
      return;
    }
    _scheduleRealtimeReconnect(userId, generation);
  }

  void _scheduleRealtimeReconnect(String userId, int generation) {
    if (_activeUserId != userId || generation != _realtimeGeneration) return;
    if (_realtimeReconnectTimer?.isActive ?? false) return;
    final multiplier = 1 << _realtimeReconnectAttempt.clamp(0, 10);
    final requestedMs = _realtimeReconnectBaseDelay.inMilliseconds * multiplier;
    final delay = Duration(
      milliseconds: requestedMs.clamp(
        _realtimeReconnectBaseDelay.inMilliseconds,
        _realtimeReconnectMaxDelay.inMilliseconds,
      ),
    );
    _realtimeReconnectAttempt++;
    _realtimeReconnectTimer = Timer(delay, () => _connectRealtime(userId));
  }

  Future<void> _runPeriodicReconcile(String userId) async {
    final reconcile = _onPeriodicReconcile;
    if (reconcile != null) {
      await reconcile();
      return;
    }
    await refreshReplies(userId);
  }

  void _scheduleRealtimeRefresh() {
    _realtimeDebounce?.cancel();
    _realtimeDebounce = Timer(const Duration(milliseconds: 250), () {
      final userId = _activeUserId;
      if (userId != null) refreshReplies(userId);
    });
  }

  Future<void> refreshReplies(String userId) async {
    if (_isRefreshingReplies) {
      _pendingReplyUserId = userId;
      return;
    }
    _isRefreshingReplies = true;
    try {
      var requestedUserId = userId;
      do {
        _pendingReplyUserId = null;
        await loadReplies(requestedUserId);
        final pendingUserId = _pendingReplyUserId;
        if (pendingUserId == null) break;
        requestedUserId = pendingUserId;
      } while (!_isDisposed);
    } finally {
      _isRefreshingReplies = false;
    }
  }

  void stopRealtime() {
    _activeUserId = null;
    _onPeriodicReconcile = null;
    _realtimeGeneration++;
    _realtimeReconnectAttempt = 0;
    _periodicRefreshTimer?.cancel();
    _periodicRefreshTimer = null;
    _realtimeDebounce?.cancel();
    _realtimeDebounce = null;
    _realtimeReconnectTimer?.cancel();
    _realtimeReconnectTimer = null;
    final subscription = _realtimeSubscription;
    _realtimeSubscription = null;
    if (subscription != null) unawaited(subscription.close());
  }

  @override
  void dispose() {
    _isDisposed = true;
    stopRealtime();
    super.dispose();
  }

  void completeWithoutUser() {
    if (_isDisposed) return;
    _stateUserId = null;
    _hinooLoadGeneration++;
    _replyLoadGeneration++;
    _pendingReplyUserId = null;
    value = ChestState(isHinooLoading: false, isReplyLoading: false);
  }

  void _prepareUser(String userId) {
    if (_stateUserId == userId) return;
    _stateUserId = userId;
    _hinooLoadGeneration++;
    _replyLoadGeneration++;
    value = ChestState();
  }

  void removeHinoo(String id) {
    if (_isDisposed) return;
    value = ChestState(
      hinoo: value.hinoo.where((item) => item.id != id).toList(),
      honooLatestReplies: value.honooLatestReplies,
      hinooLatestReplies: value.hinooLatestReplies,
      honooLatestReceivedReplies: value.honooLatestReceivedReplies,
      hinooLatestReceivedReplies: value.hinooLatestReceivedReplies,
      hinooRepliesByRoot: value.hinooRepliesByRoot,
      isHinooLoading: value.isHinooLoading,
      isReplyLoading: value.isReplyLoading,
      hinooError: value.hinooError,
      replyError: value.replyError,
    );
  }

  void markHinooOnMoon(String id) {
    if (_isDisposed) return;
    value = ChestState(
      hinoo: value.hinoo
          .map(
            (item) => item.id == id
                ? ChestHinooItem(
                    id: item.id,
                    draft: item.draft,
                    createdAt: item.createdAt,
                    isFromMoonSaved: item.isFromMoonSaved,
                    ownerId: item.ownerId,
                    isOnMoon: true,
                    conversationId: item.conversationId,
                  )
                : item,
          )
          .toList(),
      honooLatestReplies: value.honooLatestReplies,
      hinooLatestReplies: value.hinooLatestReplies,
      honooLatestReceivedReplies: value.honooLatestReceivedReplies,
      hinooLatestReceivedReplies: value.hinooLatestReceivedReplies,
      hinooRepliesByRoot: value.hinooRepliesByRoot,
      isHinooLoading: value.isHinooLoading,
      isReplyLoading: value.isReplyLoading,
      hinooError: value.hinooError,
      replyError: value.replyError,
    );
  }

  Future<void> loadHinoo(String userId) async {
    if (_isDisposed) return;
    _prepareUser(userId);
    final generation = ++_hinooLoadGeneration;
    value = ChestState(
      hinoo: value.hinoo,
      honooLatestReplies: value.honooLatestReplies,
      hinooLatestReplies: value.hinooLatestReplies,
      honooLatestReceivedReplies: value.honooLatestReceivedReplies,
      hinooLatestReceivedReplies: value.hinooLatestReceivedReplies,
      hinooRepliesByRoot: value.hinooRepliesByRoot,
      isHinooLoading: true,
      isReplyLoading: value.isReplyLoading,
      replyError: value.replyError,
    );

    try {
      final rows = await _reliability.read<List<dynamic>>(
        () => _repository.fetchHinooRows(userId),
      );
      if (_isDisposed ||
          generation != _hinooLoadGeneration ||
          _stateUserId != userId) {
        return;
      }
      Set<String> moonFingerprints = const {};
      try {
        moonFingerprints = await _reliability.read<Set<String>>(
          () => _repository.fetchHinooMoonFingerprints(userId),
        );
      } catch (_) {
        // Il contenuto dello Scrigno resta utilizzabile anche se il controllo
        // dello stato Luna non è temporaneamente disponibile.
      }
      if (_isDisposed ||
          generation != _hinooLoadGeneration ||
          _stateUserId != userId) {
        return;
      }
      final hinoo = rows
          .whereType<Map>()
          .map(ChestHinooItem.fromDatabaseRow)
          .whereType<ChestHinooItem>()
          .map((item) {
            if (!HinooService.moonFingerprints(
              item.draft,
            ).any(moonFingerprints.contains)) {
              return item;
            }
            return ChestHinooItem(
              id: item.id,
              draft: item.draft,
              createdAt: item.createdAt,
              isFromMoonSaved: item.isFromMoonSaved,
              ownerId: item.ownerId,
              isOnMoon: true,
              conversationId: item.conversationId,
            );
          })
          .toList(growable: false);
      value = ChestState(
        hinoo: List.unmodifiable(hinoo),
        honooLatestReplies: value.honooLatestReplies,
        hinooLatestReplies: value.hinooLatestReplies,
        honooLatestReceivedReplies: value.honooLatestReceivedReplies,
        hinooLatestReceivedReplies: value.hinooLatestReceivedReplies,
        hinooRepliesByRoot: value.hinooRepliesByRoot,
        isHinooLoading: false,
        isReplyLoading: value.isReplyLoading,
        replyError: value.replyError,
      );
    } catch (error) {
      if (_isDisposed ||
          generation != _hinooLoadGeneration ||
          _stateUserId != userId) {
        return;
      }
      value = ChestState(
        hinoo: value.hinoo,
        honooLatestReplies: value.honooLatestReplies,
        hinooLatestReplies: value.hinooLatestReplies,
        honooLatestReceivedReplies: value.honooLatestReceivedReplies,
        hinooLatestReceivedReplies: value.hinooLatestReceivedReplies,
        hinooRepliesByRoot: value.hinooRepliesByRoot,
        isHinooLoading: false,
        isReplyLoading: value.isReplyLoading,
        hinooError: error,
        replyError: value.replyError,
      );
    }
  }

  Future<void> loadReplies(String userId) async {
    if (_isDisposed) return;
    _prepareUser(userId);
    final generation = ++_replyLoadGeneration;
    value = ChestState(
      hinoo: value.hinoo,
      honooLatestReplies: value.honooLatestReplies,
      hinooLatestReplies: value.hinooLatestReplies,
      honooLatestReceivedReplies: value.honooLatestReceivedReplies,
      hinooLatestReceivedReplies: value.hinooLatestReceivedReplies,
      hinooRepliesByRoot: value.hinooRepliesByRoot,
      isHinooLoading: value.isHinooLoading,
      isReplyLoading: true,
      hinooError: value.hinooError,
    );

    try {
      final honooLatest = <String, DateTime>{};
      final honooLatestReceived = <String, DateTime>{};
      final honooRows = await _reliability.refresh<List<dynamic>>(
        () => _repository.fetchHonooReplyRows(userId),
      );
      if (_isDisposed ||
          generation != _replyLoadGeneration ||
          _stateUserId != userId) {
        return;
      }
      final seenHonooKeys = <String>{};
      for (final row in honooRows.whereType<Map>()) {
        final conversationId = row['conversation_id']?.toString() ?? '';
        final replyTo = row['reply_to']?.toString() ?? '';
        final activityKey = conversationId.isNotEmpty
            ? conversationId
            : replyTo;
        if (activityKey.isEmpty) continue;
        final createdRaw = (row['created_at'] ?? '').toString();
        final key = '$activityKey|$createdRaw';
        if (!seenHonooKeys.add(key)) continue;
        final created = DateTime.tryParse(createdRaw) ?? DateTime.now();
        final existing = honooLatest[activityKey];
        if (existing == null || created.isAfter(existing)) {
          honooLatest[activityKey] = created;
        }
        if (row['user_id']?.toString() != userId) {
          final existingReceived = honooLatestReceived[activityKey];
          if (existingReceived == null || created.isAfter(existingReceived)) {
            honooLatestReceived[activityKey] = created;
          }
        }
      }

      final hinooLatest = <String, DateTime>{};
      final hinooLatestReceived = <String, DateTime>{};
      final hinooReplies = <String, List<HinooThreadEntry>>{};
      final hinooRootByConversation = <String, String>{
        for (final item in value.hinoo)
          if ((item.conversationId ?? '').isNotEmpty)
            item.conversationId!: item.id,
      };
      final rootIds = value.hinoo.map((item) => item.id).toList();
      final rows = await _reliability.refresh<List<dynamic>>(
        () => _repository.fetchHinooReplyRows(userId, rootIds),
      );
      if (_isDisposed ||
          generation != _replyLoadGeneration ||
          _stateUserId != userId) {
        return;
      }
      final seenHinooIds = <String>{};
      for (final row in rows.whereType<Map>()) {
        final id = row['id']?.toString() ?? '';
        if (id.isNotEmpty && !seenHinooIds.add(id)) continue;
        final storedRootId = row['reply_to']?.toString() ?? '';
        final conversationId = row['conversation_id']?.toString() ?? '';
        final rootId = storedRootId.isNotEmpty
            ? storedRootId
            : hinooRootByConversation[conversationId] ?? '';
        final activityKey = conversationId.isNotEmpty ? conversationId : rootId;
        final pages = row['pages'];
        if (activityKey.isEmpty || pages is! List) continue;
        final created =
            DateTime.tryParse((row['created_at'] ?? '').toString()) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final draft = HinooDraft(
          pages: pages
              .whereType<Map<String, dynamic>>()
              .map(HinooSlide.fromJson)
              .toList(),
          type: HinooType.answer,
          recipientTag: row['recipient_tag'] as String?,
          replyTo: rootId.isEmpty ? null : rootId,
          conversationId: conversationId.isEmpty ? null : conversationId,
        );
        if (rootId.isNotEmpty) {
          hinooReplies
              .putIfAbsent(rootId, () => <HinooThreadEntry>[])
              .add(
                HinooThreadEntry(
                  draft: draft,
                  id: row['id']?.toString(),
                  authorId: row['user_id']?.toString(),
                  isReply: true,
                  createdAt: created,
                ),
              );
        }
        final existing = hinooLatest[activityKey];
        if (existing == null || created.isAfter(existing)) {
          hinooLatest[activityKey] = created;
        }
        if (row['user_id']?.toString() != userId) {
          final existingReceived = hinooLatestReceived[activityKey];
          if (existingReceived == null || created.isAfter(existingReceived)) {
            hinooLatestReceived[activityKey] = created;
          }
        }
      }

      value = ChestState(
        hinoo: value.hinoo,
        honooLatestReplies: honooLatest,
        hinooLatestReplies: hinooLatest,
        honooLatestReceivedReplies: honooLatestReceived,
        hinooLatestReceivedReplies: hinooLatestReceived,
        hinooRepliesByRoot: hinooReplies,
        isHinooLoading: value.isHinooLoading,
        isReplyLoading: false,
        hinooError: value.hinooError,
      );
    } catch (error) {
      if (_isDisposed ||
          generation != _replyLoadGeneration ||
          _stateUserId != userId) {
        return;
      }
      value = ChestState(
        hinoo: value.hinoo,
        honooLatestReplies: value.honooLatestReplies,
        hinooLatestReplies: value.hinooLatestReplies,
        honooLatestReceivedReplies: value.honooLatestReceivedReplies,
        hinooLatestReceivedReplies: value.hinooLatestReceivedReplies,
        hinooRepliesByRoot: value.hinooRepliesByRoot,
        isHinooLoading: value.isHinooLoading,
        isReplyLoading: false,
        hinooError: value.hinooError,
        replyError: error,
      );
    }
  }
}

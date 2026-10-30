import '../Widgets/saved_content_edit_frame.dart';
import '../Utility/knocks_seen_tracker.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:honoo/Entities/hinoo.dart';
import 'package:honoo/Entities/honoo.dart';
import 'package:honoo/Entities/conversation_entry.dart';
import 'package:honoo/Services/conversation_service.dart';
import 'package:honoo/Services/supabase_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:honoo/UI/hinoo_viewer.dart';
import 'package:honoo/UI/honoo_card.dart';
import 'package:honoo/Widgets/loading_spinner.dart';
import 'package:honoo/Utility/download_capture.dart';
import 'package:honoo/Utility/network_image_prefetch.dart';
import 'package:honoo/Utility/honoo_colors.dart';
import 'package:honoo/Utility/chest_content_style.dart';
import 'package:honoo/Utility/replies_seen_tracker.dart';
// rendering a lista con separatori; rimosso carousel verticale

class UnifiedThreadView extends StatefulWidget {
  const UnifiedThreadView({
    super.key,
    required this.conversationId,
    required this.maxWidth,
    required this.maxHeight,
    this.onSelect,
    this.onReveal,
    this.highlightLatest = false,
    this.isActive = false,
    this.onDownloadTap,
    this.refreshToken = 0,
    this.conversationLoader,
    this.currentUserId,
    this.revealEntryId,
    this.preferLatestReceived = false,
    this.reconcileInterval = const Duration(seconds: 30),
  });

  final String conversationId;
  final double maxWidth;
  final double maxHeight;
  final ValueChanged<ConversationEntry>? onSelect;
  final ValueChanged<ConversationEntry?>? onReveal;
  final bool highlightLatest;
  final bool isActive;
  final VoidCallback? onDownloadTap;
  final int refreshToken;
  final Future<List<ConversationEntry>> Function(String conversationId)?
  conversationLoader;
  final String? currentUserId;
  final String? revealEntryId;
  final bool preferLatestReceived;
  @visibleForTesting
  final Duration reconcileInterval;

  @override
  State<UnifiedThreadView> createState() => _UnifiedThreadViewState();
}

class _UnifiedThreadViewState extends State<UnifiedThreadView>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  bool _loading = true;
  Object? _loadError;
  List<ConversationEntry> _entries = const [];
  RealtimeChannel? _chan;
  Timer? _reconnectTimer;
  Timer? _reconcileTimer;
  int _reconnectAttempt = 0;
  int _channelGeneration = 0;
  String? _revealedEntryKey;
  String? _appliedFocusKey;
  int _currentPageIndex = 0;
  int _loadGeneration = 0;
  bool _wheelInProgress = false;
  String? _loadInProgressFor;
  bool _loadRequested = false;
  bool _selectionScheduled = false;
  bool _routeIsCurrent = false;
  final PageController _pageController = PageController();
  final FocusNode _historyFocusNode = FocusNode();
  late AnimationController _controller;
  late Animation<double> _liftAnimation;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Subscribe to route visibility, including dialogs covering this page.
    // A reply loaded behind a dialog must be marked when it becomes visible.
    final isCurrent = ModalRoute.isCurrentOf(context) ?? true;
    if (isCurrent && !_routeIsCurrent) _scheduleSelection();
    _routeIsCurrent = isCurrent;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _liftAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 0.0,
          end: -1.0,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: -1.0,
          end: -0.84,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 12,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: -0.84,
          end: -1.0,
        ).chain(CurveTween(curve: Curves.easeIn)),
        weight: 12,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: -1.0,
          end: 0.0,
        ).chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 36,
      ),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _controller.addStatusListener((status) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !widget.isActive || _entries.isEmpty) {
          return;
        }
        final entry = _entries.reversed.elementAt(
          _currentPageIndex.clamp(0, _entries.length - 1),
        );
        widget.onReveal?.call(
          _controller.isAnimating ? _answeredEntryFor(entry) : null,
        );
      });
    });
    _load();
    _syncSubscription();
  }

  void _syncSubscription() {
    if (!widget.isActive) {
      _closeSubscription();
      return;
    }
    _reconcileTimer ??= Timer.periodic(
      widget.reconcileInterval,
      (_) => _load(),
    );
    _connectSubscription();
  }

  void _connectSubscription() {
    if (!widget.isActive || _chan != null) return;
    final generation = ++_channelGeneration;
    try {
      _chan = ConversationService.subscribeConversation(
        widget.conversationId,
        _load,
        onStatus: (status, error) {
          if (!mounted || generation != _channelGeneration) return;
          if (status == ConversationRealtimeConnectionStatus.subscribed) {
            _reconnectAttempt = 0;
            _reconnectTimer?.cancel();
            _load();
          } else {
            _scheduleReconnect(generation);
          }
        },
      );
    } catch (_) {
      _chan = null;
      _scheduleReconnect(generation);
    }
  }

  void _scheduleReconnect(int generation) {
    if (!widget.isActive ||
        generation != _channelGeneration ||
        _reconnectTimer?.isActive == true) {
      return;
    }
    final attempt = _reconnectAttempt.clamp(0, 5);
    _reconnectAttempt += 1;
    _reconnectTimer = Timer(Duration(seconds: 1 << attempt), () {
      if (!mounted || !widget.isActive || generation != _channelGeneration) {
        return;
      }
      final staleChannel = _chan;
      _chan = null;
      unawaited(staleChannel?.unsubscribe());
      _connectSubscription();
    });
  }

  void _closeSubscription() {
    _channelGeneration += 1;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconcileTimer?.cancel();
    _reconcileTimer = null;
    final channel = _chan;
    _chan = null;
    unawaited(channel?.unsubscribe());
    _reconnectAttempt = 0;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !widget.isActive) return;
    _closeSubscription();
    _load();
    _syncSubscription();
  }

  Future<void> _load() async {
    final requestedConversationId = widget.conversationId;
    _loadRequested = true;
    if (_loadInProgressFor == requestedConversationId) return;
    _loadInProgressFor = requestedConversationId;
    try {
      while (_loadRequested &&
          mounted &&
          widget.conversationId == requestedConversationId) {
        _loadRequested = false;
        await _performLoad();
      }
    } finally {
      if (_loadInProgressFor == requestedConversationId) {
        _loadInProgressFor = null;
        if (_loadRequested && mounted) _load();
      }
    }
  }

  Future<void> _performLoad() async {
    if (!mounted) return;
    final generation = ++_loadGeneration;
    final conversationId = widget.conversationId;
    if (_entries.isEmpty) {
      setState(() => _loading = true);
    }
    try {
      _loadError = null;
      final loader =
          widget.conversationLoader ?? ConversationService.fetchConversation;
      final entries = await loader(conversationId);
      // Never replace the timeline underneath a drag or a settling page.
      while (mounted &&
          conversationId == widget.conversationId &&
          _pageController.hasClients &&
          _pageController.position.isScrollingNotifier.value) {
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }

      if (!mounted ||
          generation != _loadGeneration ||
          conversationId != widget.conversationId) {
        return;
      }
      // The reader can scroll while the request is in flight. Preserve the
      // position at completion, rather than restoring the page at request time.
      final pageBeforeLoad = _currentPageIndex;
      final selectedEntryBeforeLoad =
          pageBeforeLoad >= 0 && pageBeforeLoad < _entries.length
          ? _entries.reversed.elementAt(pageBeforeLoad)
          : null;
      final wasEmpty = _entries.isEmpty;
      final targetWasMissing = _missingNotificationTarget;
      setState(() {
        _entries = entries;
        _loading = false;
        _loadError = null;
      });
      final focusWasApplied = _appliedFocusKey;
      _prefetchEntriesFrom(_pageToShowFirst);
      if (wasEmpty || (targetWasMissing && !_missingNotificationTarget)) {
        _showLatestReceivedAndReveal(forceFocus: true);
      }
      if (widget.isActive && _entries.isNotEmpty) {
        final hasExplicitReveal =
            (widget.revealEntryId ?? '').isNotEmpty &&
            focusWasApplied != _appliedFocusKey;
        final reversed = _entries.reversed.toList(growable: false);
        var selectedPage = (wasEmpty || hasExplicitReveal)
            ? _pageToShowFirst
            : pageBeforeLoad.clamp(0, _entries.length - 1);
        final newestIsOwn =
            reversed.first.ownerId ==
            (widget.currentUserId ??
                SupabaseProvider.client.auth.currentUser?.id);
        if (!wasEmpty &&
            !hasExplicitReveal &&
            !(pageBeforeLoad == 0 && newestIsOwn) &&
            selectedEntryBeforeLoad != null) {
          final preservedPage = reversed.indexWhere(
            (entry) =>
                entry.kind == selectedEntryBeforeLoad.kind &&
                entry.id == selectedEntryBeforeLoad.id,
          );
          if (preservedPage >= 0) selectedPage = preservedPage;
        }
        if (selectedPage != pageBeforeLoad) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted ||
                generation != _loadGeneration ||
                conversationId != widget.conversationId ||
                !_pageController.hasClients) {
              return;
            }
            _pageController.jumpToPage(selectedPage);
            _currentPageIndex = selectedPage;
          });
        }
        _currentPageIndex = selectedPage;
        _scheduleSelection();
      }
    } catch (error) {
      if (!mounted ||
          generation != _loadGeneration ||
          conversationId != widget.conversationId) {
        return;
      }
      setState(() {
        _loading = false;
        _loadError = error;
      });
    }
  }

  void _prefetchEntriesFrom(int pageIndex) {
    if (_entries.isEmpty) return;
    final reversed = _entries.reversed.toList(growable: false);
    final end = (pageIndex + 2).clamp(0, reversed.length);
    final urls = <String?>[];
    for (final entry in reversed.sublist(pageIndex, end)) {
      if (entry.honoo != null) {
        urls.addAll(honooImageUrls(entry.honoo!));
      } else if (entry.hinoo != null) {
        urls.addAll(hinooImageUrls(entry.hinoo!));
      }
    }
    prefetchImageUrls(context, urls);
  }

  @override
  void didUpdateWidget(covariant UnifiedThreadView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reconcileInterval != widget.reconcileInterval) {
      _reconcileTimer?.cancel();
      _reconcileTimer = null;
    }
    if (oldWidget.conversationId != widget.conversationId) {
      _closeSubscription();
      _revealedEntryKey = null;
      _appliedFocusKey = null;
      _currentPageIndex = 0;
      _entries = const [];
      _loading = true;
      _loadError = null;
      _controller.reset();
      _load();
    }
    if (oldWidget.refreshToken != widget.refreshToken &&
        oldWidget.conversationId == widget.conversationId) {
      _load();
    }
    if (oldWidget.isActive != widget.isActive ||
        oldWidget.conversationId != widget.conversationId ||
        oldWidget.reconcileInterval != widget.reconcileInterval) {
      _syncSubscription();
      if (widget.isActive && !oldWidget.isActive) {
        if (_appliedFocusKey == null) {
          _showLatestReceivedAndReveal(forceFocus: true);
        }
        _historyFocusNode.requestFocus();
        _scheduleSelection();
        _load();
      } else if (!widget.isActive && oldWidget.isActive) {
        _revealedEntryKey = null;
        _controller.reset();
      }
    }
    if (oldWidget.revealEntryId != widget.revealEntryId) {
      _revealedEntryKey = null;
      _appliedFocusKey = null;
      _showLatestReceivedAndReveal(forceFocus: true);
    }
  }

  bool get _missingNotificationTarget =>
      (widget.revealEntryId?.isNotEmpty ?? false) &&
      !_entries.any((entry) => entry.id == widget.revealEntryId);

  void _scheduleSelection() {
    if (_selectionScheduled) return;
    _selectionScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _selectionScheduled = false;
      if (!mounted || !widget.isActive || _entries.isEmpty) {
        return;
      }
      final entry = _entries.reversed.elementAt(
        _currentPageIndex.clamp(0, _entries.length - 1),
      );
      widget.onSelect?.call(entry);
      final userId =
          widget.currentUserId ?? SupabaseProvider.client.auth.currentUser?.id;
      if (userId == null ||
          entry.ownerId == null ||
          entry.ownerId == userId ||
          !_routeIsCurrent ||
          !_isReceivedReply(entry)) {
        return;
      }
      unawaited(_markDisplayedReply(entry, userId));
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _markDisplayedReply(
    ConversationEntry entry,
    String userId,
  ) async {
    try {
      if (entry.id?.isNotEmpty == true) {
        await RepliesSeenTracker.markReply(userId: userId, replyId: entry.id!);
        final recipient =
            entry.honoo?.recipientTag ?? entry.hinoo?.recipientTag;
        if (recipient != null && recipient != userId) {
          final knocks = await SupabaseProvider.client
              .from('house_access')
              .select('id')
              .eq(entry.honoo != null ? 'honoo_id' : 'hinoo_id', entry.id!);
          for (final knock in knocks) {
            await KnocksSeenTracker.mark(userId, knock['id'].toString());
          }
        }
      }
    } catch (error) {
      debugPrint('Unable to persist displayed reply: $error');
    }
  }

  int get _pageToShowFirst {
    final reversed = _entries.reversed.toList(growable: false);
    final revealEntryId = widget.revealEntryId;
    if (revealEntryId != null && revealEntryId.isNotEmpty) {
      final exactIndex = reversed.indexWhere(
        (entry) => entry.id == revealEntryId,
      );
      if (exactIndex >= 0) return exactIndex;

      // Se la riga indicata dalla notifica non è ancora disponibile, non
      // ricadere sulla radice della conversazione (che può essere un contenuto
      // salvato dalla Luna): mostra comunque l'ultima risposta ricevuta.
      final latestReceivedIndex = reversed.indexWhere(_isReceivedReply);
      if (latestReceivedIndex >= 0) return latestReceivedIndex;
    }
    if (widget.preferLatestReceived) {
      final latestReceivedIndex = reversed.indexWhere(_isReceivedReply);
      if (latestReceivedIndex >= 0) return latestReceivedIndex;
    }
    // Nell'apertura normale la pagina 0 corrisponde sempre al contenuto più
    // recente, indipendentemente dal fatto che sia una risposta ricevuta, una
    // risposta inviata o un nuovo contenuto. Solo una notifica esplicita può
    // spostare il focus su un elemento precedente.
    return 0;
  }

  void _showLatestReceivedAndReveal({bool forceFocus = false}) {
    if (!widget.isActive || _entries.isEmpty || !mounted) {
      return;
    }
    final targetPage = _pageToShowFirst;
    final entry = _entries.reversed.elementAt(targetPage);
    final focusKey = '${widget.conversationId}:${entry.kind.name}:${entry.id}';
    if (_appliedFocusKey == focusKey) return;
    if (!forceFocus && widget.revealEntryId == null && _currentPageIndex != 0) {
      return;
    }
    _appliedFocusKey = focusKey;
    final conversationId = widget.conversationId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          conversationId != widget.conversationId ||
          _appliedFocusKey != focusKey ||
          !widget.isActive ||
          _entries.isEmpty) {
        return;
      }
      if (_pageController.hasClients) {
        _pageController.jumpToPage(targetPage);
        _currentPageIndex = targetPage;
      }
      final entryKey = '${entry.kind.name}:${entry.id}';
      if (_revealedEntryKey != entryKey && _shouldReveal(entry)) {
        _revealedEntryKey = entryKey;
        _controller.forward(from: 0);
      }
    });
  }

  bool _shouldReveal(ConversationEntry e) {
    if (e.kind == ConversationEntryKind.deleted) return false;

    // Moon-saved: non rivelare
    final bool isMoon =
        e.isFromMoonSaved == true ||
        (e.honoo != null && (e.honoo!.isFromMoonSaved == true));
    if (isMoon) return false;

    if (!_isReceivedReply(e)) return false;

    final revealEntryId = widget.revealEntryId;
    if (revealEntryId != null && revealEntryId.isNotEmpty) {
      return e.id == revealEntryId;
    }
    return true;
  }

  bool _isReceivedReply(ConversationEntry entry) {
    if (!_isDisplayableReply(entry)) return false;
    final currentUserId =
        widget.currentUserId ?? SupabaseProvider.client.auth.currentUser?.id;
    return currentUserId == null || entry.ownerId != currentUserId;
  }

  bool _isDisplayableReply(ConversationEntry entry) {
    if (entry.kind == ConversationEntryKind.deleted || entry.isFromMoonSaved) {
      return false;
    }
    if (entry.honoo?.isFromMoonSaved == true) return false;
    return entry.honoo?.type == HonooType.answer ||
        entry.hinoo?.type == HinooType.answer;
  }

  ConversationEntry? _answeredEntryFor(ConversationEntry reply) {
    final replyTo = reply.replyTo;
    if (replyTo != null && replyTo.isNotEmpty) {
      for (final entry in _entries.reversed) {
        if (entry.id == replyTo) return entry;
      }
      final replyIndex = _entries.indexOf(reply);
      if (replyIndex > 0) {
        final fallback = _entries[replyIndex - 1];
        if (fallback.isFromMoonSaved) return fallback;
      }
      return null;
    }
    final replyIndex = _entries.indexOf(reply);
    return replyIndex > 0 ? _entries[replyIndex - 1] : null;
  }

  bool _isOwnedByCurrentUser(ConversationEntry entry) {
    final currentUserId =
        widget.currentUserId ?? SupabaseProvider.client.auth.currentUser?.id;
    return currentUserId != null && entry.ownerId == currentUserId;
  }

  Widget _entryCard(
    ConversationEntry entry, {
    String? keyName,
    bool showAsOwnedContent = false,
  }) {
    final GlobalKey repaintKey = GlobalKey();
    final conversationStyle = ChestContentStyle.forConversationEntry(
      entry,
      viewerUserId:
          widget.currentUserId ?? SupabaseProvider.client.auth.currentUser?.id,
    );
    final style =
        showAsOwnedContent &&
            !identical(conversationStyle, ChestContentStyle.receivedReply) &&
            !identical(conversationStyle, ChestContentStyle.moon)
        ? ChestContentStyle.own
        : conversationStyle;
    final Widget card;
    switch (entry.kind) {
      case ConversationEntryKind.honoo:
        card = HonooCard(
          downloadBoundaryKey: repaintKey,
          honoo: entry.honoo!,
          viewerUserId: widget.currentUserId,
          contentStyleOverride: style,
          onDownloadTap: () =>
              _downloadFromBoundary(repaintKey: repaintKey, baseName: 'honoo'),
        );
        break;
      case ConversationEntryKind.hinoo:
        card = HinooViewer(
          draft: entry.hinoo!,
          enablePageNavigation: false,
          maxHeight: widget.maxHeight,
          maxWidth: widget.maxWidth,
          isReply: entry.hinoo!.type == HinooType.answer,
          authorId: entry.ownerId,
          viewerUserId: widget.currentUserId,
          gapColor: style.backgroundColor,
          onDownloadCanvasTap: (canvasKey) =>
              _downloadFromBoundary(repaintKey: canvasKey, baseName: 'hinoo'),
        );
        break;
      case ConversationEntryKind.deleted:
        card = const ColoredBox(
          color: HonooColor.background,
          child: Center(
            child: Text(
              'contenuto eliminato',
              textAlign: TextAlign.center,
              style: TextStyle(color: HonooColor.onBackground, fontSize: 18),
            ),
          ),
        );
        break;
    }
    return ColoredBox(
      key: Key(
        keyName ??
            'conversation-entry-background:${entry.kind.name}:${entry.id}',
      ),
      color: style.backgroundColor,
      child: SizedBox.expand(
        child: SavedContentEditFrame(
          width: entry.honoo != null
              ? math.min(widget.maxWidth, (widget.maxHeight - 9.5) / 1.5)
              : math.min(widget.maxWidth, widget.maxHeight * 9 / 16),
          height: widget.maxHeight,
          honoo: entry.honoo,
          hinoo: entry.hinoo,
          hinooId: entry.id,
          ownerId: entry.ownerId,
          onSaved: _load,
          child: card,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: LoadingSpinner(color: Colors.white));
    }
    if (_entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _missingNotificationTarget
                    ? 'La risposta notificata non è ancora disponibile.'
                    : _loadError == null
                    ? 'Conversazione vuota'
                    : 'Non riesco a caricare la conversazione.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: HonooColor.onBackground,
                  fontSize: 17,
                ),
              ),
              if (_loadError != null || _missingNotificationTarget) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  label: const Text(
                    'Riprova',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return Focus(
      focusNode: _historyFocusNode,
      autofocus: widget.isActive,
      canRequestFocus: widget.isActive,
      onKeyEvent: (_, event) {
        if (!widget.isActive || event is KeyUpEvent) {
          return KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          _navigateHistory(1);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          _navigateHistory(-1);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: SizedBox(
        width: widget.maxWidth,
        height: widget.maxHeight,
        child: Column(
          children: [
            if (_missingNotificationTarget)
              Material(
                color: HonooColor.background,
                child: ListTile(
                  title: const Text(
                    'La risposta notificata non è ancora disponibile.',
                    style: TextStyle(color: Colors.white),
                  ),
                  trailing: TextButton(
                    onPressed: _load,
                    child: const Text(
                      'Riprova',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ),
            Expanded(
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  dragDevices: {
                    PointerDeviceKind.touch,
                    PointerDeviceKind.mouse,
                    PointerDeviceKind.stylus,
                    PointerDeviceKind.trackpad,
                  },
                ),
                child: PageView.builder(
                  controller: _pageController,
                  scrollDirection: Axis.vertical,
                  pageSnapping: true,
                  physics: const PageScrollPhysics(
                    parent: ClampingScrollPhysics(),
                  ),
                  onPageChanged: (index) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) widget.onReveal?.call(null);
                    });
                    _currentPageIndex = index;
                    _prefetchEntriesFrom(index);
                    final reversed = _entries.reversed.toList(growable: false);
                    if (index >= 0 && index < reversed.length) {
                      _scheduleSelection();
                    }
                  },
                  itemCount: _entries.length,
                  itemBuilder: (context, index) => Listener(
                    onPointerSignal: _onPointerSignal,
                    child: Builder(
                      builder: (context) {
                        // Ordine inverso: ultimo (più recente) in cima
                        final revIndex = _entries.length - 1 - index;
                        final e = _entries[revIndex];
                        final Widget page = _entryCard(e);
                        if (index == _pageToShowFirst && _shouldReveal(e)) {
                          final answeredEntry = _answeredEntryFor(e);
                          if (answeredEntry == null) return page;
                          final answeredPage = Transform.translate(
                            offset: Offset(0, widget.maxHeight * 0.52),
                            child: _entryCard(
                              answeredEntry,
                              keyName: 'reply_reveal_parent',
                              showAsOwnedContent: _isOwnedByCurrentUser(
                                answeredEntry,
                              ),
                            ),
                          );
                          return AnimatedBuilder(
                            animation: _liftAnimation,
                            builder: (context, childWidget) {
                              final double revealHeight =
                                  widget.maxHeight * 0.48;
                              return ClipRect(
                                child: Stack(
                                  children: [
                                    answeredPage,
                                    Transform.translate(
                                      key: const Key('reply_reveal_foreground'),
                                      offset: Offset(
                                        0,
                                        _liftAnimation.value * revealHeight,
                                      ),
                                      child: childWidget,
                                    ),
                                  ],
                                ),
                              );
                            },
                            child: page,
                          );
                        }
                        return page;
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent ||
        event.scrollDelta.dy == 0 ||
        event.scrollDelta.dy.abs() < event.scrollDelta.dx.abs() ||
        !widget.isActive ||
        !_pageController.hasClients) {
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      _navigateHistory(event.scrollDelta.dy > 0 ? 1 : -1);
    });
  }

  void _navigateHistory(int delta) {
    if (!widget.isActive ||
        _entries.isEmpty ||
        _wheelInProgress ||
        !_pageController.hasClients) {
      return;
    }
    final target = (_currentPageIndex + delta).clamp(0, _entries.length - 1);
    if (target == _currentPageIndex) return;
    _wheelInProgress = true;
    unawaited(
      _pageController
          .animateToPage(
            target,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
          )
          .whenComplete(() => _wheelInProgress = false),
    );
  }

  // Tile helpers non più utilizzati con il rendering a lista separata

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _closeSubscription();
    _historyFocusNode.dispose();
    _pageController.dispose();
    _controller.dispose();
    super.dispose();
  }

  // mapping handled by service
}

extension on _UnifiedThreadViewState {
  Future<void> _downloadFromBoundary({
    required GlobalKey repaintKey,
    required String baseName,
  }) async {
    if (!mounted) return;
    await captureAndSave(context, repaintKey: repaintKey, baseName: baseName);
  }
}

// ConversationEntry now lives in lib/Entities/conversation_entry.dart

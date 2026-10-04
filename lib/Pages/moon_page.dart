import 'package:carousel_slider/carousel_slider.dart' as cs;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:honoo/Services/content_feed_service.dart';
import 'package:honoo/Services/admin_service.dart';
import 'package:honoo/Services/honoo_service.dart';
import 'package:honoo/Services/duplication_result.dart';
import 'package:honoo/Services/hinoo_service.dart';

import '../Entities/hinoo.dart';
import '../Entities/honoo.dart';
import '../Entities/conversation_link.dart';
import '../Entities/reply_navigation_result.dart';
import 'home_page.dart';
import '../UI/hinoo_viewer.dart';
import '../UI/hinoo_typography.dart';
import '../UI/honoo_card.dart';
import '../Utility/honoo_colors.dart';
import '../Utility/responsive_layout.dart';
import '../Widgets/loading_spinner.dart';
import '../Widgets/honoo_dialogs.dart';
import '../Widgets/honoo_app_title.dart';
import '../UI/thread_layout_scaffold.dart';
import '../Widgets/responsive_footer_bar.dart';
import '../Widgets/desktop_carousel_arrows.dart';
import 'placeholder_page.dart';
import 'chest_page.dart';
import 'reply_honoo_page.dart';
import 'new_hinoo_page.dart';
import 'new_honoo_page.dart';
import '../Controller/honoo_controller.dart';
import '../Utility/app_logger.dart';
import '../Utility/network_image_prefetch.dart';

class MoonPage extends StatefulWidget {
  const MoonPage({super.key, this.initialItemId});

  final String? initialItemId;

  @visibleForTesting
  static Honoo honooFromMoonRow(Map<String, dynamic> row) {
    return Honoo.fromMap(row)..type = HonooType.moon;
  }

  @override
  State<MoonPage> createState() => _MoonPageState();
}

class _MoonPageState extends State<MoonPage> {
  bool _isLoading = true;
  bool _isAdmin = false;
  List<_MoonItem> _items = [];
  int _currentIndex = 0;
  final cs.CarouselSliderController _carouselController =
      cs.CarouselSliderController();
  DateTime? _lastScroll;
  final AdminService _adminService = AdminService();
  final ContentFeedService _contentFeedService = const ContentFeedService();
  // Elementi per cui l'utente ha appena inviato una risposta in questa sessione
  final Set<String> _repliedItemIds = <String>{};

  @override
  void initState() {
    super.initState();
    _loadMoonContent();
    _loadAdminStatus();
  }

  Future<void> _loadAdminStatus() async {
    try {
      final isAdmin = await _adminService.isCurrentUserAdmin();
      if (!mounted) return;
      setState(() => _isAdmin = isAdmin);
    } catch (error, stackTrace) {
      AppLogger.warning(
        'Verifica ruolo admin non riuscita',
        scope: 'MoonPage',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() => _isAdmin = false);
    }
  }

  Future<void> _loadMoonContent() async {
    try {
      final rows = await _contentFeedService.fetchMoonRows();
      if (!mounted) return;

      final List<_MoonItem> items = [];

      for (final row in rows) {
        final String kind = row['kind']?.toString() ?? '';
        final created =
            DateTime.tryParse((row['created_at'] ?? '').toString()) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        if (kind == 'honoo') {
          final honoo = MoonPage.honooFromMoonRow(row.cast<String, dynamic>());
          final String? ownerId = row['user_id']?.toString();
          if ((honoo.recipientTag ?? '').isEmpty && ownerId != null) {
            honoo.recipientTag = ownerId;
          }
          // Non mostrare le risposte (reply) sulla Luna
          if (honoo.type != HonooType.answer) {
            items.add(_MoonItem.honoo(honoo, created));
          }
        } else if (kind == 'hinoo') {
          final pages = row['pages'];
          if (pages is List) {
            final draft = HinooDraft(
              pages: pages
                  .whereType<Map<String, dynamic>>()
                  .map(HinooSlide.fromJson)
                  .toList(),
              type: HinooType.moon,
              recipientTag: row['recipient_tag'] as String?,
              conversationId: row['conversation_id']?.toString(),
            );
            final String? hinooId = row['id']?.toString();
            final String? ownerId = row['user_id']?.toString();
            // Non mostrare risposte (type answer) sulla Luna
            if (HinooType.moon == draft.type) {
              items.add(
                _MoonItem.hinoo(
                  draft,
                  created,
                  hinooId: hinooId,
                  ownerId: ownerId,
                ),
              );
            }
          }
        }
      }

      items.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      int initialIndex = 0;
      if (widget.initialItemId != null && widget.initialItemId!.isNotEmpty) {
        final idx = items.indexWhere((it) {
          final String? id = it.honoo?.dbId ?? it.hinooId;
          return id == widget.initialItemId;
        });
        if (idx >= 0) initialIndex = idx;
      }
      setState(() {
        _items = items;
        _currentIndex = initialIndex.clamp(
          0,
          items.isEmpty ? 0 : items.length - 1,
        );
        _isLoading = false;
      });
      _prefetchFrom(_currentIndex);
    } catch (e, stackTrace) {
      if (!mounted) return;
      AppLogger.error(
        'Caricamento Luna non riuscito',
        scope: 'MoonPage',
        error: e,
        stackTrace: stackTrace,
      );
      if (mounted) {
        showHonooToast(
          context,
          message:
              'Non riesco a caricare la Luna. Controlla la connessione e riprova.',
        );
      }
      setState(() => _isLoading = false);
    }
  }

  void _prefetchFrom(int index) {
    if (_items.isEmpty) return;
    final end = (index + 2).clamp(0, _items.length);
    final urls = <String?>[];
    for (final item in _items.sublist(index, end)) {
      if (item.honoo != null) {
        urls.addAll(honooImageUrls(item.honoo!));
      } else if (item.hinoo != null) {
        urls.addAll(hinooImageUrls(item.hinoo!));
      }
    }
    prefetchImageUrls(context, urls);
  }

  @override
  Widget build(BuildContext context) {
    return ThreadLayoutScaffold(
      backgroundColor: Colors.white,
      header: HonooAppTitle(
        onTap: () {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const PlaceholderPage()),
            (route) => false,
          );
        },
      ),
      bodyBuilder: (context, viewW, availableH, layoutMode) {
        final _MoonItem? current = _items.isEmpty
            ? null
            : _items[_currentIndex];
        final HonooBuilderMetrics honooMetrics =
            ResponsiveLayout.honooBuilderMetrics(
              availableHeight: availableH,
              maxWidth: viewW,
              mode: layoutMode,
            );
        final bool isCompact =
            layoutMode == ResponsiveLayoutMode.mobile ||
            layoutMode == ResponsiveLayoutMode.tablet;
        final double displayHeight = (current?.honoo != null)
            ? honooMetrics.height
            : availableH;
        return SizedBox(
          width: viewW,
          height: displayHeight,
          child: _buildBody(
            displayHeight,
            availableH,
            viewW,
            honooMetrics,
            isCompact,
            0,
          ),
        );
      },
      footerBuilder:
          (
            context,
            mode,
            footerIconSize,
            footerGap,
            footerTopSpacing,
            footerBottomSpacing,
          ) {
            return ResponsiveFooterBar(
              useSafeArea: false,
              bottomPadding: footerBottomSpacing,
              desiredGap: footerGap,
              minGap: 16,
              height: footerIconSize,
              actions: [
                ResponsiveFooterAction(
                  asset: 'assets/icons/home_onTertiary.svg',
                  semanticsLabel: 'Home',
                  size: footerIconSize,
                  splashRadius: 25,
                  tooltip: 'Home',
                  onPressed: () {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const HomePage()),
                      (route) => false,
                    );
                  },
                ),
                ResponsiveFooterAction(
                  asset: 'assets/icons/heart.svg',
                  semanticsLabel: 'Heart',
                  size: footerIconSize,
                  splashRadius: 25,
                  tooltip: 'Salva nel tuo Cuore',
                  onPressed: _saveCurrentToChest,
                ),
                () {
                  final _MoonItem? curr = _items.isEmpty
                      ? null
                      : _items[_currentIndex];
                  String? keyId;
                  if (curr != null) {
                    keyId = curr.honoo?.dbId ?? curr.hinooId;
                  }
                  final bool showSeeConversation =
                      keyId != null && _repliedItemIds.contains(keyId);
                  if (showSeeConversation) {
                    return ResponsiveFooterAction(
                      asset: 'assets/icons/reply.svg',
                      semanticsLabel: 'Vedi conversazione',
                      size: footerIconSize,
                      splashRadius: 25,
                      tooltip: 'Vedi conversazione',
                      colorFilter: const ColorFilter.mode(
                        HonooColor.secondary,
                        BlendMode.srcIn,
                      ),
                      onPressed: () async {
                        if (!mounted) return;
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ChestPage(focusReplies: true),
                          ),
                        );
                      },
                    );
                  }
                  return ResponsiveFooterAction(
                    asset: 'assets/icons/reply.svg',
                    semanticsLabel: 'Reply',
                    size: footerIconSize,
                    splashRadius: 25,
                    tooltip: 'Rispondi',
                    onPressed: () => _showReplyChoice(),
                  );
                }(),
                if (_isAdmin)
                  ResponsiveFooterAction(
                    asset: 'assets/Cestino.svg',
                    semanticsLabel: 'Elimina',
                    size: footerIconSize,
                    colorFilter: const ColorFilter.mode(
                      Colors.black,
                      BlendMode.srcIn,
                    ),
                    splashRadius: 25,
                    tooltip: 'Elimina',
                    onPressed: _deleteCurrentFromMoon,
                  ),
              ],
            );
          },
    );
  }

  Widget _buildBody(
    double bodyHeight,
    double availableHeight,
    double maxWidth,
    HonooBuilderMetrics honooMetrics,
    bool isCompact,
    double horizontalPadding,
  ) {
    Widget child;
    if (_isLoading) {
      child = const Center(
        key: ValueKey('moon_loading'),
        child: LoadingSpinner(color: HonooColor.background),
      );
    } else if (_items.isEmpty) {
      child = Center(
        key: const ValueKey('moon_empty'),
        child: Text(
          'Nessun contenuto sulla Luna',
          style: GoogleFonts.libreFranklin(
            color: HonooColor.onTertiary,
            fontSize: 18,
            fontWeight: FontWeight.w400,
          ),
          textAlign: TextAlign.center,
        ),
      );
    } else {
      child = FocusableActionDetector(
        autofocus: true,
        shortcuts: {
          LogicalKeySet(LogicalKeyboardKey.arrowLeft): const _ArrowIntent(-1),
          LogicalKeySet(LogicalKeyboardKey.arrowRight): const _ArrowIntent(1),
        },
        actions: {
          _ArrowIntent: CallbackAction<_ArrowIntent>(
            onInvoke: (intent) {
              _animateToIndex(_currentIndex + intent.delta);
              return null;
            },
          ),
        },
        child: SizedBox(
          key: ValueKey('moon_content_${_items.length}'),
          height: bodyHeight,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            child: Listener(
              onPointerSignal: (event) {
                if (event is PointerScrollEvent) {
                  _handlePointerScroll(event);
                }
              },
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  dragDevices: {
                    PointerDeviceKind.touch,
                    PointerDeviceKind.mouse,
                    PointerDeviceKind.stylus,
                    PointerDeviceKind.trackpad,
                  },
                ),
                child: () {
                  final Widget slider = cs.CarouselSlider.builder(
                    carouselController: _carouselController,
                    itemCount: _items.length,
                    options: cs.CarouselOptions(
                      initialPage: _currentIndex,
                      height: bodyHeight,
                      viewportFraction: 1.0,
                      enableInfiniteScroll: false,
                      padEnds: true,
                      enlargeCenterPage: false,
                      disableCenter: true,
                      scrollPhysics: const PageScrollPhysics(),
                      onPageChanged: (index, _) {
                        setState(() => _currentIndex = index);
                        _prefetchFrom(index);
                      },
                    ),
                    itemBuilder: (context, index, realIndex) {
                      final item = _items[index];
                      return Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: horizontalPadding,
                        ),
                        child: _buildMoonItem(
                          item,
                          availableHeight,
                          maxWidth,
                          honooMetrics,
                        ),
                      );
                    },
                  );

                  // Desktop-only arrows: derive from isCompact flag
                  final bool isDesktop = !isCompact;
                  if (!isDesktop || _items.length <= 1) return slider;
                  return DesktopCarouselArrows(
                    canPrev: _currentIndex > 0,
                    canNext: _currentIndex < _items.length - 1,
                    onPrev: () => _carouselController.animateToPage(
                      (_currentIndex - 1).clamp(0, _items.length - 1),
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                    ),
                    onNext: () => _carouselController.animateToPage(
                      (_currentIndex + 1).clamp(0, _items.length - 1),
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                    ),
                    arrowColor: Colors.black,
                    child: slider,
                  );
                }(),
              ),
            ),
          ),
        ),
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: child,
    );
  }

  Widget _buildMoonItem(
    _MoonItem item,
    double maxHeight,
    double maxWidth,
    HonooBuilderMetrics honooMetrics,
  ) {
    final String identity;
    final Widget content;

    if (item.honoo != null) {
      final honoo = item.honoo!;
      final String? dbId = honoo.dbId;
      final int localId = honoo.id;
      final String fallback = localId != 0
          ? localId.toString()
          : item.createdAt.toIso8601String();
      identity = 'moon_honoo_${dbId ?? fallback}';
      content = Center(
        child: SizedBox(
          width: honooMetrics.width,
          height: honooMetrics.height,
          child: HonooCard(honoo: honoo),
        ),
      );
    } else {
      final draft = item.hinoo!;
      identity =
          'moon_hinoo_${draft.hashCode}_${item.createdAt.toIso8601String()}';
      final Size hinooSize = ResponsiveLayout.fitAspectRatio(
        maxWidth,
        maxHeight,
        HinooTypography.aspectRatio,
      );
      final double cardW = hinooSize.width;
      final double cardH = hinooSize.height;
      final Widget viewer = HinooViewer(
        draft: draft,
        maxHeight: cardH,
        maxWidth: cardW,
      );
      content = Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: cardH, maxWidth: cardW),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(width: cardW, height: cardH, child: viewer),
          ),
        ),
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: KeyedSubtree(key: ValueKey(identity), child: content),
    );
  }

  void _handlePointerScroll(PointerScrollEvent event) {
    if (_items.isEmpty) return;
    final now = DateTime.now();
    if (_lastScroll != null &&
        now.difference(_lastScroll!) < const Duration(milliseconds: 200)) {
      return;
    }
    _lastScroll = now;
    final delta = event.scrollDelta.dy;
    if (delta > 0) {
      _animateToIndex(_currentIndex + 1);
    } else if (delta < 0) {
      _animateToIndex(_currentIndex - 1);
    }
  }

  void _animateToIndex(int target) {
    if (_items.isEmpty) return;
    final int clamped = target.clamp(0, _items.length - 1);
    if (clamped == _currentIndex) return;
    _carouselController.animateToPage(
      clamped,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _saveCurrentToChest() async {
    if (_items.isEmpty) return;
    final _MoonItem current = _items[_currentIndex];
    try {
      if (current.honoo != null) {
        final honoo = current.honoo!.copyWith(isFromMoonSaved: true);
        final saved = await HonooController().saveToChest(honoo);
        if (!mounted) return;
        showHonooToast(
          context,
          message: saved == DuplicationResult.inserted
              ? 'honoo salvato nello Scrigno.'
              : 'Era già nel tuo Scrigno.',
        );
        _openSavedMoonItemInChest(honoo.conversationId ?? honoo.dbId);
        return;
      }
      if (current.hinoo != null) {
        final draft = current.hinoo!.copyWith(
          type: HinooType.personal,
          isFromMoonSaved: true,
          conversationId: current.hinoo!.conversationId ?? current.hinooId,
        );
        final saved = await HinooService.duplicateMoonToChest(draft);
        if (!mounted) return;
        showHonooToast(
          context,
          message: saved == DuplicationResult.inserted
              ? 'hinoo salvato nello Scrigno.'
              : 'Era già nel tuo Scrigno.',
        );
        _openSavedMoonItemInChest(draft.conversationId);
      }
    } catch (e) {
      if (!mounted) return;
      showHonooToast(context, message: 'Errore: $e');
    }
  }

  void _openSavedMoonItemInChest(String? conversationId) {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ChestPage(focusConversationId: conversationId),
      ),
    );
  }

  Future<void> _deleteCurrentFromMoon() async {
    if (_items.isEmpty) return;
    final _MoonItem current = _items[_currentIndex];
    final bool isHonoo = current.honoo != null;
    final String kind = isHonoo ? 'honoo' : 'hinoo';
    final String? id = isHonoo ? current.honoo!.dbId : current.hinooId;
    if (id == null || id.isEmpty) return;

    final bool hasConversation;
    try {
      hasConversation = await _contentFeedService.moonContentHasConversation(
        kind: kind,
        id: id,
      );
    } catch (error) {
      if (!mounted) return;
      showHonooToast(
        context,
        message: 'Non riesco a verificare le conversazioni collegate: $error',
      );
      return;
    }
    if (!mounted) return;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => HonooConfirmDialog(
        title: hasConversation
            ? 'Questo contenuto fa parte di una conversazione, vuoi eliminarlo?'
            : 'Vuoi davvero eliminarlo?',
        message: '',
        confirmLabel: 'Sì',
        cancelLabel: 'No',
      ),
    );
    if (confirmed != true) return;

    try {
      await _contentFeedService.deleteMoonContent(kind: kind, id: id);
      if (!mounted) return;
      // Calcola il target come l'ultimo elemento visto prima di quello cancellato
      final int desired = (_currentIndex > 0) ? _currentIndex - 1 : 0;
      setState(() {
        _items.removeAt(_currentIndex);
        if (_items.isEmpty) {
          _currentIndex = 0;
        } else {
          _currentIndex = desired.clamp(0, _items.length - 1);
        }
      });
      // Allinea il carosello alla nuova pagina target
      if (_items.isNotEmpty) {
        // usa jumpToPage per evitare oscillazioni
        _carouselController.jumpToPage(_currentIndex);
      }
      showHonooToast(context, message: 'Eliminato dalla Luna.');
    } catch (e) {
      if (!mounted) return;
      showHonooToast(context, message: 'Errore eliminazione: $e');
    }
  }

  Future<void> _showReplyChoice() async {
    if (_items.isEmpty) return;
    final _MoonItem current = _items[_currentIndex];
    final _ReplyChoice? choice = await showDialog<_ReplyChoice>(
      context: context,
      barrierDismissible: true,
      builder: (_) => HonooDialogShell(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Vuoi rispondere con\n un honoo o un hinoo?',
                style: HonooDialogStyles.title(),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () =>
                      Navigator.of(context).pop(_ReplyChoice.honoo),
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
                    'honoo',
                    style: HonooDialogStyles.primaryAction(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () =>
                      Navigator.of(context).pop(_ReplyChoice.hinoo),
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
                    'hinoo',
                    style: HonooDialogStyles.primaryAction(),
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(foregroundColor: Colors.white54),
                child: Text(
                  'Annulla',
                  style: HonooDialogStyles.tertiaryAction(),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (choice == null || !mounted) return;
    if (choice == _ReplyChoice.honoo && current.honoo != null) {
      if (!await _ensureMoonItemInChest(current) || !mounted) return;
      final result = await Navigator.push<Object?>(
        context,
        MaterialPageRoute(
          builder: (_) => ReplyHonooPage(
            originalHonoo: current.honoo!,
            initialHintText: 'Scrivi la tua risposta',
            initialImageHint: 'Aggiungi un’immagine (opzionale)',
            returnToPreviousOnAnswer: true,
          ),
        ),
      );
      if (!mounted) return;
      await _openConversationAfterReply(current, result);
    } else if (choice == _ReplyChoice.honoo && current.hinoo != null) {
      // Risposta ad un hinoo con un honoo
      final parentId = current.hinooId;
      if (parentId == null || parentId.isEmpty) return;
      final recipientId = current.ownerId;
      if (recipientId == null || recipientId.isEmpty) return;
      final link = ConversationLink.fromParent(
        parentId: parentId,
        parentConversationId: current.hinoo!.conversationId,
        recipientId: recipientId,
      );
      if (!await _ensureMoonItemInChest(current) || !mounted) return;
      final result = await Navigator.push<Object?>(
        context,
        MaterialPageRoute(
          builder: (_) => NewHonooPage(
            targetContentName: 'hinoo',
            forcedType: HonooType.answer,
            recipientTag: link.recipientId,
            replyTo: link.replyTo,
            conversationId: link.conversationId,
            returnToPreviousOnAnswer: true,
          ),
        ),
      );
      if (!mounted) return;
      await _openConversationAfterReply(current, result);
    } else if (choice == _ReplyChoice.hinoo && current.hinoo != null) {
      final String? replyTo = current.hinooId;
      if (replyTo == null || replyTo.isEmpty) return;
      final recipientId = current.ownerId;
      if (recipientId == null || recipientId.isEmpty) return;
      final link = ConversationLink.fromParent(
        parentId: replyTo,
        parentConversationId: current.hinoo!.conversationId,
        recipientId: recipientId,
      );
      if (!await _ensureMoonItemInChest(current) || !mounted) return;
      final result = await Navigator.push<Object?>(
        context,
        MaterialPageRoute(
          builder: (_) => NewHinooPage(
            targetContentName: 'hinoo',
            forcedType: HinooType.answer,
            recipientTag: link.recipientId,
            replyTo: link.replyTo,
            conversationId: link.conversationId,
            returnToPreviousOnAnswer: true,
          ),
        ),
      );
      if (!mounted) return;
      await _openConversationAfterReply(current, result);
    } else if (choice == _ReplyChoice.hinoo && current.honoo != null) {
      // Risposta ad un honoo con un hinoo
      final parentId = current.honoo!.dbId;
      if (parentId == null || parentId.isEmpty) return;
      final link = ConversationLink.fromParent(
        parentId: parentId,
        parentConversationId: current.honoo!.conversationId,
        recipientId: current.honoo!.userId,
      );
      if (!await _ensureMoonItemInChest(current) || !mounted) return;
      final result = await Navigator.push<Object?>(
        context,
        MaterialPageRoute(
          builder: (_) => NewHinooPage(
            targetContentName: 'honoo',
            forcedType: HinooType.answer,
            recipientTag: link.recipientId,
            replyTo: link.replyTo,
            conversationId: link.conversationId,
            returnToPreviousOnAnswer: true,
          ),
        ),
      );
      if (!mounted) return;
      await _openConversationAfterReply(current, result);
    }
  }

  Future<void> _openConversationAfterReply(
    _MoonItem current,
    Object? result,
  ) async {
    final navigation = result is ReplyNavigationResult ? result : null;
    final conversationId =
        navigation?.conversationId ?? (result is String ? result : null);
    if (conversationId == null || conversationId.isEmpty || !mounted) return;
    final id = current.honoo?.dbId ?? current.hinooId;
    if (id != null && id.isNotEmpty) {
      setState(() => _repliedItemIds.add(id));
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChestPage(
          focusReplies: true,
          focusConversationId: conversationId,
          focusReplyId: navigation?.replyId,
          highlightLatest: true,
        ),
      ),
    );
  }

  Future<bool> _ensureMoonItemInChest(_MoonItem current) async {
    try {
      if (current.honoo != null) {
        await HonooService.duplicateToChest(
          current.honoo!.copyWith(isFromMoonSaved: true),
        );
      } else if (current.hinoo != null) {
        await HinooService.duplicateMoonToChest(current.hinoo!);
      }
      return true;
    } catch (_) {
      if (!mounted) return false;
      showHonooToast(context, message: 'Errore salvataggio nello scrigno.');
      return false;
    }
  }
}

class _ArrowIntent extends Intent {
  const _ArrowIntent(this.delta);

  final int delta;
}

class _MoonItem {
  final Honoo? honoo;
  final HinooDraft? hinoo;
  final DateTime createdAt;
  final String? hinooId;
  final String? ownerId;

  const _MoonItem._(
    this.honoo,
    this.hinoo,
    this.createdAt, {
    this.hinooId,
    this.ownerId,
  });

  factory _MoonItem.honoo(Honoo h, DateTime createdAt) =>
      _MoonItem._(h, null, createdAt);

  factory _MoonItem.hinoo(
    HinooDraft h,
    DateTime createdAt, {
    String? hinooId,
    String? ownerId,
  }) => _MoonItem._(null, h, createdAt, hinooId: hinooId, ownerId: ownerId);
}

enum _ReplyChoice { honoo, hinoo }

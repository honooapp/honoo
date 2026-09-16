import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:honoo/Entities/hinoo.dart';
import 'package:honoo/Entities/casa_share_mode.dart';
import 'package:honoo/Entities/casa_request_result.dart';
import 'package:honoo/Entities/campanelli_realtime_event.dart';
import 'package:honoo/Entities/campanelli_view_data.dart';
import 'package:honoo/Entities/pending_knock.dart';
import 'package:honoo/Services/supabase_provider.dart';
import 'package:honoo/Services/app_failure.dart';
import 'package:honoo/Controller/hinoo_controller.dart';
import 'package:honoo/Controller/campanelli_controller.dart';
import 'package:honoo/UI/hinoo_typography.dart';
import 'package:honoo/Utility/honoo_colors.dart';
import 'package:honoo/Utility/responsive_layout.dart';
import 'package:honoo/Utility/utility.dart';
import 'package:honoo/Widgets/honoo_dialogs.dart';
import 'package:honoo/Widgets/campanelli_footer.dart';
import 'package:honoo/Widgets/campanello_card.dart';
import 'package:honoo/Widgets/casa_section.dart';
import 'package:honoo/Widgets/house_invite_dialogs.dart';
import 'package:honoo/Widgets/pending_knocks_dialog.dart';
import 'package:honoo/Entities/honoo.dart';
import 'package:honoo/Controller/honoo_controller.dart';
import 'package:honoo/Widgets/desktop_carousel_arrows.dart';
import 'package:honoo/Widgets/busy_overlay.dart';
import 'package:honoo/Services/campanelli_repository.dart';
import 'package:honoo/Services/house_invite_prompt_controller.dart';

import '../../Pages/home_page.dart';
import '../../Pages/email_login_page.dart';
import '../../Pages/casa_builder_page.dart';
import '../../Pages/casa_share_selection_page.dart';
import '../../Pages/chest_page.dart';
import '../../Pages/shared_house_chest_page.dart';
import '../../Pages/new_hinoo_page.dart';
import 'pending_hinoo_page.dart';
import 'pending_honoo_page.dart';

class CampanelliPage extends StatefulWidget {
  const CampanelliPage({super.key});

  @override
  State<CampanelliPage> createState() => _CampanelliPageState();
}

class _CampanelliPageState extends State<CampanelliPage>
    with WidgetsBindingObserver {
  final CampanelliDataRepository _campanelliRepository =
      CampanelliDataRepository();
  late final CampanelliController _campanelliController = CampanelliController(
    repository: _campanelliRepository,
  );
  // Animations: centralize durations/curves to avoid magic numbers
  static const Duration _kAnimFast = Duration(milliseconds: 220);
  static const Duration _kHouseSlideDuration = Duration(milliseconds: 800);
  static const Duration _kCarouselHintDuration = Duration(seconds: 4);
  static const Curve _kCurve = Curves.easeOutCubic;
  int _campanelloIndex = 0;
  int _verticalPageIndex = 0;
  int _lastHouseCampanelloIndex = 0;
  final PageController _pageController = PageController();
  final PageController _campanelloPageController = PageController();
  List<_CampanelloEntry> _userEntries = const [];
  bool _isLoadingUserEntries = false;
  bool _isPageNavigationLocked = false;
  DateTime _ignorePageNavigationUntil = DateTime.fromMillisecondsSinceEpoch(0);
  Offset? _desktopDragStart;
  int? _desktopDragPointer;
  bool _showCarouselArrows = true;
  Timer? _carouselHintTimer;
  bool _isKnocking = false;
  DialogRoute<void>? _busyRoute;
  Timer? _accessRefreshTimer;
  bool _refreshingAccess = false;
  bool _isShowingKnockRequest = false;
  final Set<String> _shownKnockRequestIds = <String>{};
  bool get _hasOwnHouse => _campanelliController.state.hasOwnHouse;
  bool get _hasPendingOrAcceptedInvite =>
      _campanelliController.state.hasPendingOrAcceptedInvite;
  late final StreamSubscription<CampanelliRealtimeEvent>
  _realtimeEventsSubscription;
  List<PendingKnock> get _pendingKnocks =>
      _campanelliController.state.pendingKnocks;
  Set<String> get _pendingKnockTags => _campanelliController.pendingKnockTags;
  List<String> _ownedHinooIds = const [];
  static const String defaultCasaBg = 'assets/background.png';
  static const String userCampanelloBg = 'assets/background.png';
  static const String scrignoOverlay = 'assets/icons/scrigno_di_carta.png';
  final Set<String> _unlockedCampanelli = <String>{};

  void _showBusyOverlay(String message) {
    if (!mounted) return;
    if (_busyRoute != null) return;
    final route = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BusyOverlay(message: message),
    );
    _busyRoute = route;
    unawaited(Navigator.of(context, rootNavigator: true).push(route));
  }

  void _hideBusyOverlay() {
    final route = _busyRoute;
    _busyRoute = null;
    if (route != null && route.isActive) route.navigator?.removeRoute(route);
  }

  Future<void> _refreshAccess() async {
    final user = SupabaseProvider.client.auth.currentUser;
    if (!mounted || user == null || _refreshingAccess) return;
    _refreshingAccess = true;
    try {
      final tags = await _campanelliController.loadGrantedHouseTags(user.id);
      if (!mounted) return;
      setState(() {
        _unlockedCampanelli
          ..clear()
          ..addAll(
            _userEntries
                .where(
                  (entry) =>
                      entry.campanello.ownerId == user.id ||
                      tags.contains(entry.campanello.campanelloHinooId),
                )
                .map((entry) => entry.campanello.id),
          );
      });
    } catch (error) {
      debugPrint('[Campanelli] access refresh failed: $error');
    } finally {
      _refreshingAccess = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshAccess());
      unawaited(
        _campanelliController.refreshPendingKnocks(
          _ownedHinooIds,
          onChanged: () {
            if (mounted) setState(() {});
          },
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _accessRefreshTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(_refreshAccess()),
    );
    _scheduleCarouselArrowsHide();
    _realtimeEventsSubscription = _campanelliController.realtimeEvents.listen(
      _handleRealtimeEvent,
    );
    _loadUserEntries();
    _subscribeVisitorAccessChannel();
  }

  void _scheduleCarouselArrowsHide() {
    _carouselHintTimer?.cancel();
    _carouselHintTimer = Timer(_kCarouselHintDuration, () {
      if (mounted) setState(() => _showCarouselArrows = false);
    });
  }

  void _revealCarouselArrows() {
    if (!_showCarouselArrows && mounted) {
      setState(() => _showCarouselArrows = true);
    }
    _scheduleCarouselArrowsHide();
  }

  bool _isCampanelloUnlocked(String id) => _unlockedCampanelli.contains(id);

  void _handlePointerScroll(
    PageController controller,
    PointerScrollEvent event,
    Axis axis,
    int maxIndex,
  ) {
    if (_isPageNavigationLocked ||
        DateTime.now().isBefore(_ignorePageNavigationUntil) ||
        !controller.hasClients ||
        !controller.position.haveDimensions) {
      return;
    }
    final position = controller.position;
    if ((position.maxScrollExtent - position.minScrollExtent).abs() < 0.5) {
      return;
    }
    final double delta = axis == Axis.vertical
        ? event.scrollDelta.dy
        : (event.scrollDelta.dy.abs() > 0
              ? event.scrollDelta.dy
              : event.scrollDelta.dx);
    if (delta.abs() < 0.5) {
      return;
    }
    unawaited(
      _animatePage(
        controller,
        delta: delta.isNegative ? -1 : 1,
        maxIndex: maxIndex,
        debounceWheelEvents: true,
      ),
    );
  }

  Future<void> _animatePage(
    PageController controller, {
    required int delta,
    required int maxIndex,
    bool debounceWheelEvents = false,
  }) async {
    if (_isPageNavigationLocked ||
        (debounceWheelEvents &&
            DateTime.now().isBefore(_ignorePageNavigationUntil)) ||
        !controller.hasClients) {
      return;
    }
    final double? page = controller.page;
    final int current = page?.round() ?? controller.initialPage;
    final int target = (current + delta).clamp(0, maxIndex);
    if (target == current) return;
    _isPageNavigationLocked = true;
    try {
      await controller.animateToPage(
        target,
        duration: _kAnimFast,
        curve: _kCurve,
      );
    } finally {
      _isPageNavigationLocked = false;
      if (debounceWheelEvents) {
        // Trackpad e rotelline inviano una coda di eventi per lo stesso gesto.
        // Il breve debounce evita che la stessa inerzia avanzi altre pagine.
        _ignorePageNavigationUntil = DateTime.now().add(
          const Duration(milliseconds: 120),
        );
      }
    }
  }

  void _startDesktopDrag(PointerDownEvent event) {
    _desktopDragPointer = event.pointer;
    _desktopDragStart = event.position;
  }

  void _endDesktopDrag(
    PointerUpEvent event, {
    required int maxCampanelloIndex,
    required int maxVerticalIndex,
  }) {
    if (_desktopDragPointer != event.pointer || _desktopDragStart == null) {
      return;
    }
    final offset = event.position - _desktopDragStart!;
    _desktopDragPointer = null;
    _desktopDragStart = null;
    if (math.max(offset.dx.abs(), offset.dy.abs()) < 48) return;
    if (offset.dy.abs() > offset.dx.abs()) {
      unawaited(
        _animatePage(
          _pageController,
          delta: offset.dy.isNegative ? 1 : -1,
          maxIndex: maxVerticalIndex,
        ),
      );
      return;
    }
    if (_verticalPageIndex == 0) {
      unawaited(
        _animatePage(
          _campanelloPageController,
          delta: offset.dx.isNegative ? 1 : -1,
          maxIndex: maxCampanelloIndex,
        ),
      );
    }
  }

  void _cancelDesktopDrag(PointerCancelEvent event) {
    if (_desktopDragPointer != event.pointer) return;
    _desktopDragPointer = null;
    _desktopDragStart = null;
  }

  Future<void> _handleKnock(CampanelloData campanello) async {
    if (_isKnocking) return;
    // Light haptic feedback on knock intent
    try {
      HapticFeedback.lightImpact();
    } catch (error, stackTrace) {
      debugPrint(
        '[Campanelli] haptic failed: ${AppFailure.from(error, stackTrace)}',
      );
    }
    if (_isCampanelloUnlocked(campanello.id)) {
      await _showEnterDialog(campanello.id);
      return;
    }

    setState(() => _isKnocking = true);
    try {
      _showBusyOverlay('Sto bussando');
      try {
        final user = SupabaseProvider.client.auth.currentUser;
        final targetTag = campanello.campanelloHinooId;
        if (user == null ||
            targetTag == null ||
            targetTag.isEmpty ||
            campanello.ownerId == user.id) {
          _hideBusyOverlay();
          return;
        }
        await _campanelliController.sendHouseKnock(
          targetHouseTag: targetTag,
          visitorId: user.id,
        );
        _hideBusyOverlay();
        if (mounted) {
          showHonooToast(
            context,
            message:
                'Bussata inviata. Il proprietario la troverà anche quando torna online.',
          );
        }
      } on TimeoutException {
        _hideBusyOverlay();
        if (mounted) {
          showHonooToast(
            context,
            message:
                'Il server non risponde. Non posso confermare l’invio della bussata.',
          );
        }
      } catch (e) {
        debugPrint('house_access insert error: $e');
        _hideBusyOverlay();
        if (mounted) {
          showHonooToast(
            context,
            message: 'Invio non riuscito. Ritenta tra poco.',
          );
        }
      } finally {
        _hideBusyOverlay();
      }
    } finally {
      if (mounted) setState(() => _isKnocking = false);
    }
  }

  Future<void> _showEnterDialog(String campanelloId) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const HonooConfirmDialog(
        title: 'Entra pure a casa mia',
        confirmLabel: 'Entra',
        cancelLabel: 'Non ora',
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _unlockedCampanelli.add(campanelloId));
    await _slideToHouse();
  }

  Future<void> _slideToHouse() async {
    if (!_pageController.hasClients) return;
    await _pageController.animateToPage(
      1,
      duration: _kHouseSlideDuration,
      curve: _kCurve,
    );
  }

  Future<void> _handleScrigno(CampanelloData campanello) async {
    if (!_isCampanelloUnlocked(campanello.id)) {
      showHonooToast(context, message: 'Casa chiusa.');
      return;
    }

    final user = SupabaseProvider.client.auth.currentUser;
    final bool isOwner = user != null && campanello.ownerId == user.id;
    if (isOwner) {
      final filter = await Navigator.of(context).push<CasaChestFilter>(
        MaterialPageRoute(builder: (_) => const CasaChestFilterPage()),
      );
      if (!mounted || filter == null) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => ChestPage(casaFilter: filter)),
      );
      return;
    }
    final ownerId = campanello.ownerId;
    if (ownerId == null || ownerId.isEmpty) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => SharedHouseChestPage(ownerId: ownerId)),
    );
  }

  Future<Set<CasaShareMode>?> _showOwnerMultiShareDialog() {
    return Navigator.of(context).push<Set<CasaShareMode>>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const CasaShareSelectionPage(),
      ),
    );
  }

  List<_CampanelloEntry> _buildCampanelli() {
    final userId = SupabaseProvider.client.auth.currentUser?.id;
    if (userId == null) {
      return _userEntries;
    }

    final ownEntries = _userEntries
        .where((entry) => entry.campanello.ownerId == userId)
        .toList(growable: false);
    final otherEntries = _userEntries
        .where((entry) => entry.campanello.ownerId != userId)
        .toList(growable: false);
    return [...ownEntries, ...otherEntries];
  }

  HinooDraft _campanelloDraftFor(_CampanelloEntry entry) {
    return HinooDraft(
      pages: [
        HinooSlide(
          backgroundImage: entry.campanelloBackgroundUrl,
          text: entry.campanello.text,
          isTextWhite: entry.campanelloIsTextWhite,
          bgScale: entry.campanelloBgScale,
          bgOffsetX: entry.campanelloBgOffsetX,
          bgOffsetY: entry.campanelloBgOffsetY,
          bgTransform: entry.campanelloBgTransform,
        ),
      ],
    );
  }

  Future<void> _editCampanello(
    _CampanelloEntry entry,
    CampanelloEditMode editMode,
  ) async {
    final String? campanelloId = entry.campanello.campanelloHinooId;
    if (campanelloId == null || campanelloId.isEmpty) return;
    final bool? updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => NewHinooPage(
          isCampanello: true,
          initialDraft: _campanelloDraftFor(entry),
          editingCampanelloId: campanelloId,
          campanelloEditMode: editMode,
        ),
      ),
    );
    if (updated == true && mounted) {
      await _loadUserEntries();
      if (mounted) await _showOwnCampanello();
    }
  }

  Future<void> _showOwnCampanello() async {
    final String? userId = SupabaseProvider.client.auth.currentUser?.id;
    if (userId == null) return;
    final int ownIndex = _buildCampanelli().indexWhere(
      (entry) => entry.campanello.ownerId == userId,
    );
    if (ownIndex < 0) return;
    final int pageIndex = ownIndex;
    setState(() {
      _campanelloIndex = pageIndex;
      _lastHouseCampanelloIndex = pageIndex;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (_campanelloPageController.hasClients) {
      _campanelloPageController.jumpToPage(pageIndex);
    }
  }

  Future<void> _editCasa(_CampanelloEntry entry) async {
    final String? campanelloId = entry.campanello.campanelloHinooId;
    if (campanelloId == null || campanelloId.isEmpty) return;
    final bool? updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CasaBuilderPage(
          campanello: _campanelloDraftFor(entry),
          editingCampanelloId: campanelloId,
          initialHouseImageUrl: entry.houseImageUrl,
          initialTransform: entry.casa.bgTransform,
        ),
      ),
    );
    if (updated == true && mounted) await _loadUserEntries();
  }

  Future<void> _handleInviteRequestTap() async {
    if (SupabaseProvider.client.auth.currentUser == null) {
      final loggedIn = await Navigator.of(
        context,
      ).push<bool>(MaterialPageRoute(builder: (_) => const EmailLoginPage()));
      if (!mounted || loggedIn != true) return;
      await _loadUserEntries();
      if (!mounted) return;
    }
    if (!_campanelliController.beginInviteRequest()) return;
    try {
      if (_hasOwnHouse) {
        if (mounted) {
          showHonooToast(context, message: 'Hai già una casa.');
        }
        return;
      }
      if (_hasPendingOrAcceptedInvite) {
        final hasAuthorizedInvite = await _campanelliController
            .hasAuthorizedHouseInvite();
        if (!mounted) return;
        if (hasAuthorizedInvite) {
          HouseInvitePromptController.requestOpen();
        } else {
          showHonooToast(context, message: 'Hai già una richiesta in corso.');
        }
        return;
      }

      final String email =
          SupabaseProvider.client.auth.currentUser?.email ?? '';
      final result = await _campanelliController.requestHouseInvite().timeout(
        const Duration(seconds: 15),
        onTimeout: () => CasaRequestResult.backendUnavailable,
      );
      if (!mounted) return;
      switch (result) {
        case CasaRequestResult.success:
          await showDialog<void>(
            context: context,
            barrierDismissible: true,
            builder: (_) => HouseRequestSentDialog(email: email),
          );
        case CasaRequestResult.administrator:
          final invite = await showDialog<bool>(
            context: context,
            barrierDismissible: true,
            builder: (_) => HouseRequestReceivedDialog(email: email),
          );
          if (invite == true && mounted) {
            final inviteResult = await _campanelliController
                .sendAdminInvite()
                .timeout(
                  const Duration(seconds: 15),
                  onTimeout: () => CasaAdminInviteResult.backendUnavailable,
                );
            if (mounted) {
              showHonooToast(
                context,
                message: _adminInviteMessage(inviteResult),
              );
            }
          }
        default:
          showHonooToast(context, message: _requestMessage(result));
      }
    } finally {
      _campanelliController.endInviteRequest();
    }
  }

  String _requestMessage(CasaRequestResult result) {
    switch (result) {
      case CasaRequestResult.alreadyPresent:
        return 'Hai già una casa o una richiesta in corso.';
      case CasaRequestResult.rlsError:
        return 'La richiesta non è autorizzata dal backend.';
      case CasaRequestResult.sessionAbsent:
        return 'Accedi prima per richiedere una casa.';
      case CasaRequestResult.backendUnavailable:
        return 'Backend non disponibile. Ritenta più tardi.';
      case CasaRequestResult.success:
      case CasaRequestResult.administrator:
        return 'Operazione non disponibile.';
    }
  }

  String _adminInviteMessage(CasaAdminInviteResult result) {
    switch (result) {
      case CasaAdminInviteResult.success:
        return 'Invito inviato.';
      case CasaAdminInviteResult.alreadyPresent:
        return 'Invito già presente.';
      case CasaAdminInviteResult.rlsError:
        return 'Invito non autorizzato dal backend.';
      case CasaAdminInviteResult.sessionAbsent:
        return 'Sessione assente.';
      case CasaAdminInviteResult.backendUnavailable:
        return 'Backend non disponibile. Ritenta più tardi.';
    }
  }

  List<CampanelloPageData> _buildCampanelloPages(
    List<_CampanelloEntry> campanelli,
  ) {
    final pages = <CampanelloPageData>[
      CampanelloPageData.intro(Utility().campanelliText),
      for (final campanello in campanelli)
        CampanelloPageData.campanello(campanello.campanello),
    ];

    if (pages.isEmpty) {
      pages.add(CampanelloPageData.intro('Nessun campanello disponibile'));
    }

    return pages;
  }

  ImageProvider _houseBackgroundProvider(
    String? houseUrl,
    String? fallbackUrl,
  ) {
    if (houseUrl != null && houseUrl.isNotEmpty) {
      return NetworkImage(houseUrl);
    }
    if (fallbackUrl != null && fallbackUrl.isNotEmpty) {
      return NetworkImage(fallbackUrl);
    }
    return const AssetImage(defaultCasaBg);
  }

  ImageProvider _campanelloBackgroundProvider(String? bgUrl) {
    if (bgUrl != null && bgUrl.isNotEmpty) {
      return NetworkImage(bgUrl);
    }
    return const AssetImage(userCampanelloBg);
  }

  Future<void> _loadUserEntries() async {
    if (_isLoadingUserEntries) return;
    final previousCampanelli = _buildCampanelli();
    final previousPage = _verticalPageIndex == 1
        ? _lastHouseCampanelloIndex
        : _campanelloIndex;
    final previousCampanelloId =
        previousPage > 0 && previousPage <= previousCampanelli.length
        ? previousCampanelli[previousPage - 1].campanello.id
        : null;
    final user = SupabaseProvider.client.auth.currentUser;
    if (user == null) {
      await _loadPublicAdminEntries();
      return;
    }

    setState(() => _isLoadingUserEntries = true);
    try {
      final loadState = await _campanelliController.load(user.id);
      if (loadState.error != null) throw loadState.error!;
      final List<String> ownedHinooIds = loadState.ownedHinooIds;
      if (loadState.entries.isEmpty) {
        if (mounted) {
          setState(() {
            _userEntries = const [];
            _ownedHinooIds = const [];
            _unlockedCampanelli.clear();
            _campanelloIndex = 0;
            _lastHouseCampanelloIndex = 0;
          });
        }
        return;
      }

      final entries = loadState.entries
          .map((entry) {
            final casaId = 'casa_${entry.hinooId}';
            return _CampanelloEntry(
              campanello: CampanelloData.fromBackend(
                row: {
                  'id': 'campanello_${entry.hinooId}',
                  'campanello_hinoo_id': entry.hinooId,
                  'owner_id': entry.ownerId,
                },
                backgroundImage: _campanelloBackgroundProvider(
                  entry.campanelloBackgroundUrl,
                ),
                text: entry.text,
                linkedHouseId: casaId,
                bgTransform: entry.campanelloBgTransform,
              ),
              casa: CasaData.fromBackend(
                row: {'id': casaId, 'bg_transform': entry.bgTransform},
                backgroundImage: _houseBackgroundProvider(
                  entry.houseImageUrl,
                  entry.campanelloBackgroundUrl,
                ),
                bgScale: entry.bgScale,
                bgOffsetX: entry.bgOffsetX,
                bgOffsetY: entry.bgOffsetY,
              ),
              campanelloBackgroundUrl: entry.campanelloBackgroundUrl,
              houseImageUrl: entry.houseImageUrl,
              campanelloIsTextWhite: entry.campanelloIsTextWhite,
              campanelloBgScale: entry.bgScale,
              campanelloBgOffsetX: entry.bgOffsetX,
              campanelloBgOffsetY: entry.bgOffsetY,
              campanelloBgTransform: entry.campanelloBgTransform,
            );
          })
          .toList(growable: false);
      final grantedHouseTags = await _campanelliController.loadGrantedHouseTags(
        user.id,
      );

      if (mounted) {
        final sortedEntries = <_CampanelloEntry>[
          ...entries.where((entry) => entry.campanello.ownerId == user.id),
          ...entries.where((entry) => entry.campanello.ownerId != user.id),
        ];
        final previousEntryIndex = sortedEntries.indexWhere(
          (entry) => entry.campanello.id == previousCampanelloId,
        );
        final targetPage = previousCampanelloId == null
            ? 0
            : previousEntryIndex >= 0
            ? previousEntryIndex + 1
            : previousPage.clamp(0, entries.length);
        setState(() {
          _userEntries = entries;
          _ownedHinooIds = List<String>.from(ownedHinooIds);
          _campanelloIndex = targetPage;
          _lastHouseCampanelloIndex = targetPage;
          _unlockedCampanelli
            ..clear()
            ..addAll(
              entries
                  .where(
                    (entry) =>
                        entry.campanello.ownerId == user.id ||
                        grantedHouseTags.contains(
                          entry.campanello.campanelloHinooId,
                        ),
                  )
                  .map((entry) => entry.campanello.id),
            );
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_campanelloPageController.hasClients) return;
          _campanelloPageController.jumpToPage(targetPage);
        });
      }
      // Verifica inviti pendenti/accettati per nascondere CTA se già invitato
      try {
        await _campanelliController.refreshHouseInviteState(user.id);
        if (mounted) setState(() {});
      } catch (error, stackTrace) {
        debugPrint(
          '[Campanelli] invite state failed: ${AppFailure.from(error, stackTrace)}',
        );
      }
      _subscribeOwnerAccessChannel();
      await _campanelliController.startPendingKnockRefresh(
        ownedHinooIds: ownedHinooIds,
        onChanged: () {
          if (!mounted) return;
          setState(() {});
          if (_pendingKnocks.isNotEmpty) {
            final sorted = List<PendingKnock>.from(_pendingKnocks)
              ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
            unawaited(_showKnockRequestOnce(sorted.first));
          }
        },
      );
    } catch (error, stackTrace) {
      debugPrint(
        '[Campanelli] user entries failed: ${AppFailure.from(error, stackTrace)}',
      );
      if (mounted) {
        setState(() {
          _userEntries = const [];
          _ownedHinooIds = const [];
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingUserEntries = false);
      }
    }
  }

  Future<void> _loadPublicAdminEntries() async {
    setState(() => _isLoadingUserEntries = true);
    try {
      final rows = await _campanelliRepository.fetchPublicAdminCampanelli();
      final entries = <_CampanelloEntry>[];
      for (final rawRow in rows) {
        if (rawRow is! Map) continue;
        final row = Map<String, dynamic>.from(rawRow);
        final hinooId = row['campanello_hinoo_id']?.toString() ?? '';
        final ownerId = row['owner_id']?.toString() ?? '';
        final pages = row['pages'];
        if (hinooId.isEmpty ||
            ownerId.isEmpty ||
            pages is! List ||
            pages.isEmpty) {
          continue;
        }
        final firstPage = pages.first;
        if (firstPage is! Map) continue;
        final slide = HinooSlide.fromJson(Map<String, dynamic>.from(firstPage));
        if (slide.text.trim().isEmpty) continue;
        final casaId = 'casa_$hinooId';
        final houseImageUrl = row['house_image_url']?.toString();
        entries.add(
          _CampanelloEntry(
            campanello: CampanelloData.fromBackend(
              row: {
                'id': 'campanello_$hinooId',
                'campanello_hinoo_id': hinooId,
                'owner_id': ownerId,
              },
              backgroundImage: _campanelloBackgroundProvider(
                slide.backgroundImage,
              ),
              text: slide.text.trim(),
              linkedHouseId: casaId,
              bgTransform: slide.bgTransform,
            ),
            casa: CasaData.fromBackend(
              row: {'id': casaId, 'bg_transform': row['house_bg_transform']},
              backgroundImage: _houseBackgroundProvider(
                houseImageUrl,
                slide.backgroundImage,
              ),
              bgScale: slide.bgScale,
              bgOffsetX: slide.bgOffsetX,
              bgOffsetY: slide.bgOffsetY,
            ),
            campanelloBackgroundUrl: slide.backgroundImage,
            houseImageUrl: houseImageUrl,
            campanelloIsTextWhite: slide.isTextWhite,
            campanelloBgScale: slide.bgScale,
            campanelloBgOffsetX: slide.bgOffsetX,
            campanelloBgOffsetY: slide.bgOffsetY,
            campanelloBgTransform: slide.bgTransform,
          ),
        );
      }
      if (mounted) {
        setState(() {
          _userEntries = List<_CampanelloEntry>.unmodifiable(entries);
          _unlockedCampanelli.addAll(
            entries.map((entry) => entry.campanello.id),
          );
        });
      }
    } catch (error, stackTrace) {
      debugPrint(
        '[Campanelli] public admins load failed: '
        '${AppFailure.from(error, stackTrace)}',
      );
    } finally {
      if (mounted) setState(() => _isLoadingUserEntries = false);
    }
  }

  void _subscribeOwnerAccessChannel() {
    try {
      final user = SupabaseProvider.client.auth.currentUser;
      if (user == null) return;
      _campanelliController.startOwnerRealtime(
        userId: user.id,
        ownedHinooIds: _ownedHinooIds,
      );
    } catch (error, stackTrace) {
      debugPrint(
        '[Campanelli] owner realtime failed: ${AppFailure.from(error, stackTrace)}',
      );
      // In test or when Realtime not available, safely ignore
    }
  }

  void _subscribeVisitorAccessChannel() {
    try {
      final user = SupabaseProvider.client.auth.currentUser;
      if (user == null) return;
      _campanelliController.startVisitorRealtime(userId: user.id);
    } catch (error, stackTrace) {
      debugPrint(
        '[Campanelli] visitor realtime failed: ${AppFailure.from(error, stackTrace)}',
      );
      // In test or when Realtime not available, safely ignore
    }
  }

  Future<void> _handleRealtimeEvent(CampanelliRealtimeEvent event) async {
    if (!mounted) return;
    switch (event) {
      case CampanelliPendingKnockReceived(:final knock):
        setState(() {});
        await _showKnockRequestOnce(knock);
      case CampanelliPendingKnockRemoved():
        setState(() {});
      case CampanelliAccessGranted(:final targetTag):
        showHonooToast(context, message: 'La casa è stata aperta');
        try {
          HapticFeedback.lightImpact();
        } catch (error, stackTrace) {
          debugPrint(
            '[Campanelli] haptic failed: ${AppFailure.from(error, stackTrace)}',
          );
        }
        final entry = _entryForTag(targetTag);
        if (entry != null) {
          setState(() => _unlockedCampanelli.add(entry.campanello.id));
        }
    }
  }

  Future<void> _showKnockRequestOnce(PendingKnock knock) async {
    if (!mounted ||
        _isShowingKnockRequest ||
        !_shownKnockRequestIds.add(knock.id)) {
      return;
    }
    _isShowingKnockRequest = true;
    try {
      await _openPendingKnock(knock);
    } finally {
      _isShowingKnockRequest = false;
    }
  }

  _CampanelloEntry? _entryForTag(String? tag) {
    if (tag == null || tag.isEmpty) return null;
    for (final entry in _userEntries) {
      if (entry.campanello.campanelloHinooId == tag) return entry;
    }
    return null;
  }

  String _pendingLabelForTag(String? tag) {
    final entry = _entryForTag(tag);
    if (entry == null) return 'Campanello';
    final String raw = entry.campanello.text.trim();
    if (raw.isEmpty) return 'Campanello';
    final String firstLine = raw.split('\n').first.trim();
    return firstLine.isEmpty ? 'Campanello' : firstLine;
  }

  String _formatPendingTimestamp(DateTime ts) {
    final DateTime local = ts.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  Future<void> _approvePendingKnock(
    PendingKnock knock,
    _CampanelloEntry entry, {
    HinooDraft? draft,
    Honoo? honoo,
  }) async {
    final Set<CasaShareMode>? modes = await _showOwnerMultiShareDialog();
    if (modes == null || modes.isEmpty || !mounted) return;
    _showBusyOverlay('Apro la casa...');
    try {
      final user = SupabaseProvider.client.auth.currentUser;
      final campanelloHinooId = entry.campanello.campanelloHinooId;
      if (user == null || campanelloHinooId == null) return;
      try {
        await _campanelliController.approvePendingKnock(
          knockId: knock.id,
          shareModes: modes.map((mode) => mode.dbValue).toList(growable: false),
        );
        if (mounted) {
          setState(() {});
        }
      } catch (e) {
        debugPrint('house_access grant error: $e');
        if (mounted) {
          showHonooToast(context, message: 'Operazione non riuscita. Ritenta.');
        }
        return;
      }
    } finally {
      _hideBusyOverlay();
    }

    if (draft != null) {
      try {
        final HinooDraft personalDraft = draft.copyWith(
          type: HinooType.personal,
          recipientTag: null,
        );
        await HinooController().saveToChest(personalDraft);
      } catch (error, stackTrace) {
        debugPrint(
          '[Campanelli] save hinoo failed: ${AppFailure.from(error, stackTrace)}',
        );
      }
    }

    if (honoo != null) {
      try {
        await HonooController().saveToChest(honoo);
      } catch (error, stackTrace) {
        debugPrint(
          '[Campanelli] save honoo failed: ${AppFailure.from(error, stackTrace)}',
        );
      }
    }

    if (!mounted) return;
    setState(() {});
    showHonooToast(context, message: 'Casa aperta.');
    // Light haptic on owner approval as further confirmation
    try {
      HapticFeedback.lightImpact();
    } catch (error, stackTrace) {
      debugPrint(
        '[Campanelli] haptic failed: ${AppFailure.from(error, stackTrace)}',
      );
    }
  }

  Future<void> _openPendingKnock(PendingKnock knock) async {
    final entry = _entryForTag(knock.targetTag);
    if (entry == null) return;
    if (knock.hinooId == null && knock.honooId == null) {
      final bool? openHouse = await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (_) => const HonooConfirmDialog(
          title: 'Qualcuno sta bussando alla tua casa, vuoi farlo entrare?',
          confirmLabel: 'Sì',
          cancelLabel: 'No',
        ),
      );

      if (openHouse == true && mounted) {
        await _approvePendingKnock(knock, entry);
      }
      return;
    }

    if (knock.hinooId != null && knock.hinooId!.isNotEmpty) {
      final draft = await _campanelliController.fetchPendingHinoo(
        knock.hinooId!,
      );
      if (draft == null || !mounted) return;
      final bool? approved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => PendingHinooPage(draft: draft)),
      );

      if (approved == true && mounted) {
        await _approvePendingKnock(knock, entry, draft: draft);
      }
      return;
    }

    if (knock.honooId != null && knock.honooId!.isNotEmpty) {
      final honoo = await _campanelliController.fetchPendingHonoo(
        knock.honooId!,
      );
      if (honoo == null || !mounted) return;
      final bool? approved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => PendingHonooPage(honoo: honoo)),
      );

      if (approved == true && mounted) {
        await _approvePendingKnock(knock, entry, honoo: honoo);
      }
    }
  }

  Future<void> _openPendingKnocksDialog() async {
    if (_pendingKnocks.isEmpty) return;
    final List<PendingKnock> sorted = List<PendingKnock>.from(_pendingKnocks)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => PendingKnocksDialog(
        knocks: sorted,
        labelForKnock: (knock) => _pendingLabelForTag(knock.targetTag),
        timestampForKnock: (knock) => _formatPendingTimestamp(knock.createdAt),
        onOpen: _openPendingKnock,
      ),
    );
  }

  @override
  void dispose() {
    _carouselHintTimer?.cancel();
    _realtimeEventsSubscription.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _accessRefreshTimer?.cancel();
    _hideBusyOverlay();
    _pageController.dispose();
    _campanelloPageController.dispose();
    _campanelliController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HonooColor.background,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final double maxWidth = constraints.maxWidth;
          final double maxHeight = constraints.maxHeight;
          final ResponsiveLayoutMode layoutMode = ResponsiveLayout.modeForWidth(
            maxWidth,
          );
          final double footerIconSize = ResponsiveLayout.footerIconSizeForMode(
            layoutMode,
          );
          final double footerGap = ResponsiveLayout.footerGapForMode(
            layoutMode,
          );
          final bool isMobile = layoutMode == ResponsiveLayoutMode.mobile;
          final bool usesDesktopPointerNavigation = switch (layoutMode) {
            ResponsiveLayoutMode.desktop ||
            ResponsiveLayoutMode.wideDesktop ||
            ResponsiveLayoutMode.largeDesktop => true,
            ResponsiveLayoutMode.mobile || ResponsiveLayoutMode.tablet => false,
          };
          final double footerBottomPadding =
              ResponsiveLayout.footerBottomPaddingForMode(layoutMode) +
              (isMobile ? 0 : 12);
          final double safeBottom = MediaQuery.of(context).viewPadding.bottom;
          final double footerSpacing = footerBottomPadding + safeBottom;
          final double footerBottomSpacing = footerSpacing / 2;
          final double carouselArrowSize = switch (layoutMode) {
            ResponsiveLayoutMode.mobile => 24,
            ResponsiveLayoutMode.tablet => 26,
            ResponsiveLayoutMode.desktop ||
            ResponsiveLayoutMode.wideDesktop ||
            ResponsiveLayoutMode.largeDesktop => 28,
          };
          final double scrignoSize = math.min(
            footerIconSize * 4,
            math.min(maxWidth, maxHeight),
          );
          final double canvasWidth = isMobile
              ? maxWidth
              : math.min(maxWidth, maxHeight * HinooTypography.aspectRatio);
          final Size canvasSize = Size(canvasWidth, maxHeight);
          final double canvasHorizontalInset = (maxWidth - canvasWidth) / 2;
          final double casaWidth = canvasWidth;
          final double casaHeight = maxHeight;
          final List<_CampanelloEntry> campanelli = _buildCampanelli();
          final List<CampanelloPageData> campanelloPages =
              _buildCampanelloPages(campanelli);
          final int safeCampanelloIndex = _campanelloIndex.clamp(
            0,
            campanelloPages.length - 1,
          );
          final activePage = campanelloPages[safeCampanelloIndex];
          final CampanelloData? activeCampanello = activePage.campanello;
          final _CampanelloEntry? activeEntry = activeCampanello == null
              ? null
              : campanelli.cast<_CampanelloEntry?>().firstWhere(
                  (entry) => entry?.campanello.id == activeCampanello.id,
                  orElse: () => null,
                );
          final _CampanelloEntry? houseEntry =
              activeEntry ?? (campanelli.isEmpty ? null : campanelli.first);
          final bool showCampanello = activeCampanello != null;
          final bool showFooter = _verticalPageIndex == 0;
          final user = SupabaseProvider.client.auth.currentUser;
          final String? activeCampanelloId =
              activeCampanello?.campanelloHinooId;
          final bool hasPendingKnock =
              activeCampanelloId != null &&
              _pendingKnockTags.contains(activeCampanelloId);
          final bool hasAnyPendingKnock = _pendingKnockTags.isNotEmpty;
          final int pendingKnockCount = _pendingKnocks.length;
          final bool casaUnlocked = activeCampanello == null
              ? false
              : _isCampanelloUnlocked(activeCampanello.id);
          final VoidCallback? scrignoTap = activeCampanello == null
              ? null
              : () => _handleScrigno(activeCampanello);
          final bool isOwnCampanello =
              activeCampanello != null &&
              user != null &&
              activeCampanello.ownerId == user.id;
          final ScrollPhysics pagePhysics = usesDesktopPointerNavigation
              ? const NeverScrollableScrollPhysics()
              : const PageScrollPhysics().applyTo(
                  const BouncingScrollPhysics(),
                );
          const int verticalPages = 2;
          final int maxCampanelloIndex = math.max(
            0,
            campanelloPages.length - 1,
          );
          final int firstCampanelloPageIndex = campanelloPages.indexWhere(
            (page) => page.campanello != null,
          );
          const int maxVerticalIndex = verticalPages - 1;

          return FocusableActionDetector(
            autofocus: true,
            shortcuts: {
              LogicalKeySet(LogicalKeyboardKey.arrowLeft): const _ArrowIntent(
                Axis.horizontal,
                -1,
              ),
              LogicalKeySet(LogicalKeyboardKey.arrowRight): const _ArrowIntent(
                Axis.horizontal,
                1,
              ),
              LogicalKeySet(LogicalKeyboardKey.arrowUp): const _ArrowIntent(
                Axis.vertical,
                -1,
              ),
              LogicalKeySet(LogicalKeyboardKey.arrowDown): const _ArrowIntent(
                Axis.vertical,
                1,
              ),
            },
            actions: {
              _ArrowIntent: CallbackAction<_ArrowIntent>(
                onInvoke: (intent) {
                  _revealCarouselArrows();
                  if (intent.axis == Axis.horizontal &&
                      _verticalPageIndex == 0) {
                    _animatePage(
                      _campanelloPageController,
                      delta: intent.delta,
                      maxIndex: maxCampanelloIndex,
                    );
                  } else if (intent.axis == Axis.vertical) {
                    _animatePage(
                      _pageController,
                      delta: intent.delta,
                      maxIndex: maxVerticalIndex,
                    );
                  }
                  return null;
                },
              ),
            },
            child: Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.none,
              children: [
                SizedBox(
                  height: maxHeight,
                  child: Listener(
                    onPointerDown: (event) {
                      _revealCarouselArrows();
                      if (usesDesktopPointerNavigation) {
                        _startDesktopDrag(event);
                      }
                    },
                    onPointerUp: usesDesktopPointerNavigation
                        ? (event) => _endDesktopDrag(
                            event,
                            maxCampanelloIndex: maxCampanelloIndex,
                            maxVerticalIndex: maxVerticalIndex,
                          )
                        : null,
                    onPointerCancel: usesDesktopPointerNavigation
                        ? _cancelDesktopDrag
                        : null,
                    onPointerSignal: (event) {
                      if (event is! PointerScrollEvent) return;
                      if (_verticalPageIndex == 0) {
                        _handlePointerScroll(
                          _campanelloPageController,
                          event,
                          Axis.horizontal,
                          maxCampanelloIndex,
                        );
                        return;
                      }
                      _handlePointerScroll(
                        _pageController,
                        event,
                        Axis.vertical,
                        maxVerticalIndex,
                      );
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
                      child: PageView(
                        controller: _pageController,
                        scrollDirection: Axis.vertical,
                        physics: pagePhysics,
                        onPageChanged: (index) {
                          _revealCarouselArrows();
                          if (index == 1) {
                            _lastHouseCampanelloIndex = activeCampanello == null
                                ? math.max(0, firstCampanelloPageIndex)
                                : _campanelloIndex;
                          }
                          if (index == 0) {
                            final int target = _lastHouseCampanelloIndex;
                            setState(() {
                              _verticalPageIndex = index;
                              _campanelloIndex = target;
                            });
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (!mounted ||
                                  _verticalPageIndex != 0 ||
                                  !_campanelloPageController.hasClients) {
                                return;
                              }
                              _campanelloPageController.jumpToPage(target);
                            });
                            return;
                          }
                          setState(() => _verticalPageIndex = index);
                        },
                        children: [
                          Center(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 90),
                              curve: Curves.easeOutCubic,
                              child: SizedBox(
                                width: canvasSize.width,
                                height: canvasSize.height,
                                child: MouseRegion(
                                  child: Listener(
                                    onPointerSignal: (event) {
                                      if (event is PointerScrollEvent) {
                                        _handlePointerScroll(
                                          _campanelloPageController,
                                          event,
                                          Axis.horizontal,
                                          maxCampanelloIndex,
                                        );
                                      }
                                    },
                                    child: ScrollConfiguration(
                                      behavior: ScrollConfiguration.of(context)
                                          .copyWith(
                                            dragDevices: {
                                              PointerDeviceKind.touch,
                                              PointerDeviceKind.mouse,
                                              PointerDeviceKind.stylus,
                                              PointerDeviceKind.trackpad,
                                            },
                                          ),
                                      child: () {
                                        final pvViewport = SizedBox(
                                          width: canvasSize.width,
                                          height: canvasSize.height,
                                          child: PageView.builder(
                                            controller:
                                                _campanelloPageController,
                                            scrollDirection: Axis.horizontal,
                                            physics: pagePhysics,
                                            itemCount: campanelloPages.length,
                                            onPageChanged: (index) {
                                              _revealCarouselArrows();
                                              setState(() {
                                                _campanelloIndex = index;
                                                if (campanelloPages[index]
                                                        .campanello !=
                                                    null) {
                                                  _lastHouseCampanelloIndex =
                                                      index;
                                                }
                                              });
                                            },
                                            itemBuilder: (context, pageIndex) {
                                              final page =
                                                  campanelloPages[pageIndex];
                                              final _CampanelloEntry? entry =
                                                  page.campanello == null
                                                  ? null
                                                  : campanelli
                                                        .cast<
                                                          _CampanelloEntry?
                                                        >()
                                                        .firstWhere(
                                                          (candidate) =>
                                                              candidate
                                                                  ?.campanello
                                                                  .id ==
                                                              page
                                                                  .campanello!
                                                                  .id,
                                                          orElse: () => null,
                                                        );
                                              final bool isOwnEntry =
                                                  entry != null &&
                                                  user != null &&
                                                  entry.campanello.ownerId ==
                                                      user.id;
                                              return CampanelloCard(
                                                data: page,
                                                width: canvasSize.width,
                                                height: canvasSize.height,
                                                onRequestTap:
                                                    _handleInviteRequestTap,
                                                onEditImageTap: isOwnEntry
                                                    ? () => _editCampanello(
                                                        entry,
                                                        CampanelloEditMode
                                                            .image,
                                                      )
                                                    : null,
                                                onEditTextTap: isOwnEntry
                                                    ? () => _editCampanello(
                                                        entry,
                                                        CampanelloEditMode.text,
                                                      )
                                                    : null,
                                              );
                                            },
                                          ),
                                        );
                                        return pvViewport;
                                      }(),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (houseEntry == null)
                            const SizedBox.expand()
                          else if (casaUnlocked)
                            Center(
                              child: CasaSection(
                                key: ValueKey('${houseEntry.casa.id}_open'),
                                casa: houseEntry.casa,
                                isUnlocked: casaUnlocked,
                                scrignoAsset: scrignoOverlay,
                                onScrignoTap: scrignoTap,
                                footerIconSize: footerIconSize,
                                scrignoSize: scrignoSize,
                                footerBottomSpacing: footerBottomSpacing,
                                width: casaWidth,
                                height: casaHeight,
                                onEditTap: isOwnCampanello
                                    ? () => _editCasa(houseEntry)
                                    : null,
                              ),
                            )
                          else
                            Center(
                              child: CasaSection(
                                key: ValueKey('${houseEntry.casa.id}_closed'),
                                casa: houseEntry.casa,
                                isUnlocked: casaUnlocked,
                                scrignoAsset: scrignoOverlay,
                                onScrignoTap: scrignoTap,
                                footerIconSize: footerIconSize,
                                scrignoSize: scrignoSize,
                                footerBottomSpacing: footerBottomSpacing,
                                width: casaWidth,
                                height: casaHeight,
                                onEditTap: isOwnCampanello
                                    ? () => _editCasa(houseEntry)
                                    : null,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_verticalPageIndex == 0 && campanelloPages.length > 1)
                  Positioned(
                    top: 0,
                    bottom: 0,
                    left: canvasHorizontalInset,
                    right: canvasHorizontalInset,
                    child: IgnorePointer(
                      ignoring: !_showCarouselArrows,
                      child: AnimatedOpacity(
                        key: const ValueKey<String>(
                          'campanelli_carousel_arrows',
                        ),
                        opacity: _showCarouselArrows ? 1 : 0,
                        duration: const Duration(milliseconds: 280),
                        child: DesktopCarouselArrows(
                          canPrev: safeCampanelloIndex > 0,
                          canNext:
                              safeCampanelloIndex < campanelloPages.length - 1,
                          onPrev: () {
                            _revealCarouselArrows();
                            _animatePage(
                              _campanelloPageController,
                              delta: -1,
                              maxIndex: maxCampanelloIndex,
                            );
                          },
                          onNext: () {
                            _revealCarouselArrows();
                            _animatePage(
                              _campanelloPageController,
                              delta: 1,
                              maxIndex: maxCampanelloIndex,
                            );
                          },
                          arrowColor: Colors.white,
                          arrowSize: carouselArrowSize,
                          horizontalInset: isMobile ? 4 : 10,
                          arrowAlignment: Alignment.center,
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                  ),
                if (showFooter)
                  Positioned(
                    bottom: 0,
                    left: canvasHorizontalInset,
                    right: canvasHorizontalInset,
                    child: CampanelliFooter(
                      iconSize: footerIconSize,
                      bottomPadding: footerBottomSpacing,
                      desiredGap: footerGap,
                      showCampanello: showCampanello,
                      isOwnCampanello: isOwnCampanello,
                      isKnocking: _isKnocking,
                      hasPendingKnock: hasPendingKnock,
                      hasAnyPendingKnock: hasAnyPendingKnock,
                      pendingKnockCount: pendingKnockCount,
                      onHome: () {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (_) => const HomePage()),
                          (route) => false,
                        );
                      },
                      onKnock: () => _handleKnock(activeCampanello!),
                      onOpenPendingKnocks: _openPendingKnocksDialog,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ArrowIntent extends Intent {
  const _ArrowIntent(this.axis, this.delta);

  final Axis axis;
  final int delta;
}

class _CampanelloEntry {
  final CampanelloData campanello;
  final CasaData casa;
  final String? campanelloBackgroundUrl;
  final String? houseImageUrl;
  final bool campanelloIsTextWhite;
  final double campanelloBgScale;
  final double campanelloBgOffsetX;
  final double campanelloBgOffsetY;
  final List<double>? campanelloBgTransform;

  const _CampanelloEntry({
    required this.campanello,
    required this.casa,
    this.campanelloBackgroundUrl,
    this.houseImageUrl,
    this.campanelloIsTextWhite = true,
    this.campanelloBgScale = 1,
    this.campanelloBgOffsetX = 0,
    this.campanelloBgOffsetY = 0,
    this.campanelloBgTransform,
  });
}

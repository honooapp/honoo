// rimosso carousel per rendering a lista separata
import 'package:flutter/material.dart';
import 'package:honoo/Entities/hinoo.dart';
import 'package:honoo/Entities/hinoo_thread_entry.dart';
import 'package:honoo/UI/hinoo_viewer.dart';
import 'package:honoo/Services/supabase_provider.dart';
import 'package:honoo/Utility/chest_content_style.dart';

class HinooThreadView extends StatefulWidget {
  const HinooThreadView({
    super.key,
    required this.root,
    required this.replies,
    required this.maxHeight,
    required this.maxWidth,
    this.rootAuthorId,
    this.rootId,
    this.onSelect,
    this.onDownloadTap,
  });

  final String? rootId;
  final ValueChanged<HinooThreadEntry>? onSelect;
  final HinooDraft root;
  final List<HinooThreadEntry> replies;
  final double maxHeight;
  final double maxWidth;
  final String? rootAuthorId;
  final ValueChanged<GlobalKey>? onDownloadTap;

  @override
  State<HinooThreadView> createState() => _HinooThreadViewState();
}

class _HinooThreadViewState extends State<HinooThreadView>
    with TickerProviderStateMixin {
  late final AnimationController _introController;
  late final Animation<double> _introCurve;
  late final AnimationController _bounceController;
  late final Animation<double> _bounceCurve;
  // Micro-hint per suggerire contenuto successivo (12px max)
  late final AnimationController _hintController;
  late final Animation<double> _hintCurve;
  bool _hinted = false;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _introCurve = CurvedAnimation(
      parent: _introController,
      curve: Curves.easeOutBack,
    );
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _bounceCurve = CurvedAnimation(
      parent: _bounceController,
      curve: Curves.easeOutBack,
    );
    _hintController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );
    _hintCurve = TweenSequence<double>([
      TweenSequenceItem(tween: CurveTween(curve: Curves.easeOut), weight: 50),
      TweenSequenceItem(tween: CurveTween(curve: Curves.easeIn), weight: 50),
    ]).animate(_hintController);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _introController.forward();
    });
  }

  @override
  void dispose() {
    _introController.dispose();
    _bounceController.dispose();
    _hintController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // animazioni già inizializzate in initState
    final List<HinooThreadEntry> sortedReplies = [...widget.replies];
    sortedReplies.sort((a, b) {
      if (a.createdAt == null && b.createdAt == null) return 0;
      if (a.createdAt == null) return 1;
      if (b.createdAt == null) return -1;
      return b.createdAt!.compareTo(a.createdAt!);
    });
    final List<HinooThreadEntry> items = [
      ...sortedReplies,
      HinooThreadEntry(
        draft: widget.root,
        id: widget.rootId,
        authorId: widget.rootAuthorId,
        isReply: false,
      ),
    ];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.onSelect?.call(items[_selectedIndex.clamp(0, items.length - 1)]);
      }
    });
    final slider = LayoutBuilder(
      builder: (ctx, c) {
        final double h = c.maxHeight.isFinite ? c.maxHeight : widget.maxHeight;
        final dy =
            (1.0 - _introCurve.value) * 12.0 - (_bounceCurve.value * 6.0);
        final scale =
            1.0 -
            (1.0 - _introCurve.value) * 0.01 -
            (_bounceCurve.value * 0.005);
        // Micro-rimbalzo: max ~12px per non spostare sensibilmente il primo messaggio
        if (items.length > 1 && !_hinted) {
          _hinted = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _hintController.forward(from: 0);
          });
        }
        // Rimbalzo: sali fino a metà schermo (negativo) e ritorna alla posizione iniziale
        final double hint = -_hintCurve.value * (h * 0.5);
        return Transform.translate(
          offset: Offset(0, -dy + hint),
          child: Transform.scale(
            scale: scale.clamp(0.97, 1.0),
            child: PageView.builder(
              scrollDirection: Axis.vertical,
              pageSnapping: true,
              physics: const PageScrollPhysics(parent: ClampingScrollPhysics()),
              itemCount: items.length,
              onPageChanged: (index) {
                _selectedIndex = index;
                widget.onSelect?.call(items[index]);
              },
              itemBuilder: (context, index) {
                final entry = items[index];
                final style = ChestContentStyle.forHinoo(
                  entry.draft,
                  authorId: entry.authorId,
                  viewerUserId: SupabaseProvider.client.auth.currentUser?.id,
                  isReply: entry.isReply,
                );
                return ColoredBox(
                  color: style.backgroundColor,
                  child: HinooViewer(
                    draft: entry.draft,
                    maxHeight: widget.maxHeight,
                    maxWidth: widget.maxWidth,
                    isReply: entry.isReply,
                    authorId: entry.authorId,
                    onDownloadCanvasTap: widget.onDownloadTap,
                  ),
                );
              },
            ),
          ),
        );
      },
    );

    final bool hasReplies = items.length > 1;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 420),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        if (!hasReplies) {
          final offset = Tween<Offset>(
            begin: const Offset(0, 0.12),
            end: Offset.zero,
          ).animate(animation);
          return SlideTransition(position: offset, child: child);
        }
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.elasticOut,
        );
        final offset = Tween<Offset>(
          begin: const Offset(0, 0.28),
          end: Offset.zero,
        ).animate(curved);
        final scale = Tween<double>(begin: 0.97, end: 1.0).animate(curved);
        return SlideTransition(
          position: offset,
          child: ScaleTransition(
            scale: scale,
            child: FadeTransition(opacity: animation, child: child),
          ),
        );
      },
      child: slider,
    );
  }
}

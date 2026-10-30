import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:honoo/Services/supabase_provider.dart';
import '../Entities/hinoo.dart';
import 'hinoo_typography.dart';
import '../Utility/honoo_colors.dart';
import '../Utility/inline_text_formatting.dart';
import '../Utility/network_image_prefetch.dart';
import '../Widgets/smooth_image.dart';
import '../Widgets/cover_transform_image.dart';
import '../Widgets/text_box_download_button.dart';

class HinooViewer extends StatefulWidget {
  final HinooDraft draft;
  final double maxHeight;
  final double maxWidth;
  final Color gapColor;
  final VoidCallback? onDownloadTap;
  final ValueChanged<GlobalKey>? onDownloadCanvasTap;
  const HinooViewer({
    super.key,
    required this.draft,
    required this.maxHeight,
    required this.maxWidth,
    this.gapColor = HonooColor.background,
    this.onDownloadTap,
    this.onDownloadCanvasTap,
    this.isReply = false,
    this.enablePageNavigation = true,
    this.authorId,
    this.viewerUserId,
  });
  final bool isReply;
  final bool enablePageNavigation;
  final String? authorId;
  final String? viewerUserId;

  @override
  State<HinooViewer> createState() => _HinooViewerState();
}

class _HinooViewerState extends State<HinooViewer> {
  late final PageController _vController;
  final GlobalKey _downloadBoundaryKey = GlobalKey();
  Timer? _snapTimer;

  @override
  void initState() {
    super.initState();
    _vController = PageController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _prefetchPagesFrom(0);
  }

  @override
  void didUpdateWidget(covariant HinooViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.draft != widget.draft) {
      _prefetchPagesFrom(0);
    }
  }

  void _prefetchPagesFrom(int index) {
    if (widget.draft.pages.isEmpty) return;
    final end = (index + 2).clamp(0, widget.draft.pages.length);
    prefetchImageUrls(
      context,
      widget.draft.pages
          .sublist(index.clamp(0, widget.draft.pages.length - 1), end)
          .map((page) => page.backgroundImage),
    );
  }

  @override
  void dispose() {
    _snapTimer?.cancel();
    _vController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const double baselineW = HinooTypography.baselineCanvasWidth;
    const double baselineH = HinooTypography.baselineCanvasHeight;

    double scale = 1.0;
    if (widget.maxWidth.isFinite &&
        widget.maxWidth > 0 &&
        widget.maxHeight.isFinite &&
        widget.maxHeight > 0) {
      scale = (widget.maxWidth / baselineW).clamp(0.0, double.infinity);
      final double scaleH = (widget.maxHeight / baselineH).clamp(
        0.0,
        double.infinity,
      );
      scale = scale < scaleH ? scale : scaleH;
    } else if (widget.maxWidth.isFinite && widget.maxWidth > 0) {
      scale = widget.maxWidth / baselineW;
    } else if (widget.maxHeight.isFinite && widget.maxHeight > 0) {
      scale = widget.maxHeight / baselineH;
    }
    if (!scale.isFinite || scale <= 0) {
      scale = 1.0;
    }
    final double displayW = baselineW * scale;
    final double displayH = baselineH * scale;
    final VoidCallback? onDownloadTap = widget.onDownloadCanvasTap != null
        ? () => widget.onDownloadCanvasTap!(_downloadBoundaryKey)
        : widget.onDownloadTap;

    final String? currentUserId =
        widget.viewerUserId ?? SupabaseProvider.client.auth.currentUser?.id;
    final bool isOwn = (widget.authorId != null && widget.authorId!.isNotEmpty)
        ? (widget.authorId == currentUserId)
        : false;

    final viewer = FocusableActionDetector(
      enabled: widget.enablePageNavigation,
      autofocus: widget.enablePageNavigation,
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.arrowUp): const _ArrowIntent(-1),
        LogicalKeySet(LogicalKeyboardKey.arrowDown): const _ArrowIntent(1),
      },
      actions: {
        _ArrowIntent: CallbackAction<_ArrowIntent>(
          onInvoke: (intent) {
            if (!_vController.hasClients) return null;
            final double? page = _vController.page;
            final int current = page?.round() ?? _vController.initialPage;
            final int maxIndex = widget.draft.pages.length - 1;
            final int target = (current + intent.delta).clamp(0, maxIndex);
            if (target == current) return null;
            _vController.animateToPage(
              target,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
            );
            return null;
          },
        ),
      },
      child: Center(
        child: SizedBox(
          width: displayW,
          height: displayH,
          child: FittedBox(
            fit: BoxFit.contain,
            child: RepaintBoundary(
              key: _downloadBoundaryKey,
              child: SizedBox(
                width: baselineW,
                height: baselineH,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: Listener(
                        onPointerSignal: (event) {
                          if (widget.enablePageNavigation &&
                              event is PointerScrollEvent &&
                              widget.draft.pages.length > 1 &&
                              _vController.hasClients &&
                              _vController.position.haveDimensions) {
                            final position = _vController.position;
                            if ((position.maxScrollExtent -
                                        position.minScrollExtent)
                                    .abs() <
                                0.5) {
                              return;
                            }
                            final double target =
                                (position.pixels + event.scrollDelta.dy).clamp(
                                  position.minScrollExtent,
                                  position.maxScrollExtent,
                                );
                            if ((target - position.pixels).abs() > 0.5) {
                              GestureBinding.instance.pointerSignalResolver
                                  .register(event, (_) {
                                    _vController.jumpTo(target);
                                    _scheduleSnap();
                                  });
                            }
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
                          child: PageView.builder(
                            scrollDirection: Axis.vertical,
                            controller: _vController,
                            // disabilita scroll interno in contesti di thread verticale a pagina intera
                            physics: const NeverScrollableScrollPhysics(),
                            allowImplicitScrolling: true,
                            onPageChanged: _prefetchPagesFrom,
                            itemCount: widget.draft.pages.length,
                            itemBuilder: (context, index) {
                              return HinooSlideView(
                                slide: widget.draft.pages[index],
                                width: baselineW,
                                height: baselineH,
                                gap: 0,
                                gapColor: widget.gapColor,
                                scaleLegacyTextToFit:
                                    widget.draft.baseCanvasHeight == null,
                                onDownloadTap: onDownloadTap,
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (!widget.isReply) return viewer;
    return Semantics(
      container: true,
      label: isOwn ? 'Risposta inviata' : 'Risposta ricevuta',
      child: viewer,
    );
  }

  void _scheduleSnap() {
    if (widget.draft.pages.length <= 1) return;
    _snapTimer?.cancel();
    _snapTimer = Timer(const Duration(milliseconds: 140), _snapToPage);
  }

  void _snapToPage() {
    _snapTimer?.cancel();
    if (widget.draft.pages.length <= 1) return;
    if (!_vController.hasClients || !_vController.position.haveDimensions) {
      return;
    }
    final double page =
        _vController.page ?? _vController.initialPage.toDouble();
    final int target = page.round().clamp(0, widget.draft.pages.length - 1);
    _vController.animateToPage(
      target,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }
}

class _ArrowIntent extends Intent {
  const _ArrowIntent(this.delta);

  final int delta;
}

class HinooSlideView extends StatelessWidget {
  final HinooSlide slide;
  final double width;
  final double height;
  final double gap;
  final Color gapColor;
  final bool scaleLegacyTextToFit;
  final VoidCallback? onDownloadTap;
  const HinooSlideView({
    super.key,
    required this.slide,
    required this.width,
    required this.height,
    required this.gap,
    required this.gapColor,
    this.scaleLegacyTextToFit = false,
    this.onDownloadTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color textColor = slide.isTextWhite ? Colors.white : Colors.black;
    final ImageProvider bg =
        (slide.backgroundImage != null && slide.backgroundImage!.isNotEmpty)
        ? NetworkImage(slide.backgroundImage!)
        : const AssetImage('assets/images/hinoo_default_1080x1920.png')
              as ImageProvider;

    const double designWidth = 1080;
    const double designHeight = 1920;
    final double scaleX = width / designWidth;
    final double scaleY = height / designHeight;

    Matrix4 buildTransform() {
      if (slide.bgTransform != null && slide.bgTransform!.length == 16) {
        final List<double> m = List<double>.from(slide.bgTransform!);
        m[12] *= scaleX;
        m[13] *= scaleY;
        return Matrix4.fromList(m);
      }

      final double tx = slide.bgOffsetX * scaleX;
      final double ty = slide.bgOffsetY * scaleY;
      return Matrix4.identity()
        ..translateByDouble(tx, ty, 0, 1)
        ..scaleByDouble(slide.bgScale, slide.bgScale, slide.bgScale, 1);
    }

    final Matrix4 transform = buildTransform();

    final TextStyle effectiveStyle = HinooTypography.displayTextStyle(
      color: textColor,
    );
    final double halfGap = gap / 2;
    const double actionInset = 6;
    final Widget? downloadOverlay = onDownloadTap == null
        ? null
        : TextBoxDownloadButton(onPressed: onDownloadTap!, tooltip: 'download');
    final Widget text = FormattedText(
      slide.text,
      textAlign: TextAlign.center,
      style: effectiveStyle,
      softWrap: false,
    );

    return SizedBox(
      key: const ValueKey('hinoo-slide-canvas'),
      width: width,
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRect(
            child: transform.isIdentity()
                ? SmoothImage(
                    image: bg,
                    fit: BoxFit.cover,
                    placeholderColor: HonooColor.background,
                  )
                : CoverTransformImage.transformed(
                    key: const ValueKey('hinoo-saved-background-transform'),
                    image: bg,
                    transform: transform,
                  ),
          ),
          Positioned.fill(
            top: gap / 2,
            bottom: gap / 2,
            child: Padding(
              padding: HinooTypography.textViewportPadding(width),
              child: Center(
                key: const ValueKey('hinoo-saved-text-position'),
                child: scaleLegacyTextToFit
                    ? FittedBox(
                        key: const ValueKey('hinoo-legacy-fitted-text'),
                        fit: BoxFit.scaleDown,
                        child: text,
                      )
                    : text,
              ),
            ),
          ),
          if (downloadOverlay != null)
            Positioned(
              top: halfGap + actionInset,
              right: actionInset,
              child: downloadOverlay,
            ),
          if (halfGap > 0.05)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: halfGap,
              child: IgnorePointer(
                child: DecoratedBox(decoration: BoxDecoration(color: gapColor)),
              ),
            ),
          if (halfGap > 0.05)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: halfGap,
              child: IgnorePointer(
                child: DecoratedBox(decoration: BoxDecoration(color: gapColor)),
              ),
            ),
        ],
      ),
    );
  }
}

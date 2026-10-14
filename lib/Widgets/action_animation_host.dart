import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../Services/action_animation.dart';
import '../Utility/honoo_colors.dart';

/// Lives above the entire app, including dialogs and safe-area padding.
class ActionAnimationHost extends StatefulWidget {
  const ActionAnimationHost({super.key, required this.child});
  final Widget child;

  @override
  State<ActionAnimationHost> createState() => _ActionAnimationHostState();
}

class _ActionAnimationHostState extends State<ActionAnimationHost> {
  VideoPlayerController? _controller;
  Completer<void>? _completion;
  VoidCallback? _retryWithAudio;
  Size _videoSize = Size.zero;
  Future<void> _queue = Future<void>.value();
  late final Future<void> Function(ActionAnimation) _presenter = _enqueue;

  @override
  void initState() {
    super.initState();
    ActionAnimations.presenter = _presenter;
  }

  Future<void> _enqueue(ActionAnimation animation) {
    _queue = _queue.then((_) => _play(animation));
    return _queue;
  }

  Future<void> _play(ActionAnimation animation) async {
    if (!mounted) return;
    final controller = VideoPlayerController.asset(animation.asset);
    final completion = Completer<void>();
    _completion = completion;
    VideoPlayerValue? initializedValue;
    var retried = false;
    Timer? watchdog;
    void finish() {
      if (!completion.isCompleted) completion.complete();
    }

    void handlePlaybackError() {
      final ready = initializedValue;
      if (ready == null || retried) {
        finish();
        return;
      }
      if (!mounted || completion.isCompleted) return;
      setState(() {
        _retryWithAudio = () {
          retried = true;
          watchdog?.cancel();
          watchdog = Timer(const Duration(seconds: 30), finish);
          setState(() => _retryWithAudio = null);
          // The web plugin replaces the value on an autoplay rejection, even
          // though the underlying video is still loaded. Restore it so play()
          // reaches that same video synchronously inside the user's gesture.
          controller.value = ready;
          unawaited(controller.play().catchError((Object _) => finish()));
        };
      });
    }

    void listen() {
      final value = controller.value;
      if (value.hasError) {
        handlePlaybackError();
      } else if (value.isCompleted) {
        finish();
      }
    }

    watchdog = Timer(const Duration(seconds: 30), finish);
    controller.addListener(listen);
    try {
      await controller.initialize().timeout(const Duration(seconds: 8));
      if (!mounted || completion.isCompleted) return;
      await controller.setVolume(1);
      if (!mounted || completion.isCompleted) return;
      initializedValue = controller.value;
      setState(() {
        _controller = controller;
        _videoSize = controller.value.size;
      });
      try {
        await controller.play().timeout(const Duration(seconds: 5));
      } catch (_) {
        handlePlaybackError();
      }
      await completion.future;
    } catch (_) {
      // Keep the successful operation and its navigation intact.
    } finally {
      watchdog?.cancel();
      controller.removeListener(listen);
      if (mounted) {
        setState(() {
          _controller = null;
          _retryWithAudio = null;
        });
      }
      _completion = null;
      // Native cleanup must not hold up navigation or the next animation.
      unawaited(controller.dispose().catchError((Object _) {}));
    }
  }

  @override
  void dispose() {
    if (identical(ActionAnimations.presenter, _presenter)) {
      ActionAnimations.presenter = null;
    }
    final completion = _completion;
    if (completion != null && !completion.isCompleted) completion.complete();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ExcludeFocus(
            excluding: controller != null,
            child: ExcludeSemantics(
              excluding: controller != null,
              child: widget.child,
            ),
          ),
          if (controller != null)
            Positioned.fill(
              child: AbsorbPointer(
                child: ColoredBox(
                  color: HonooColor.background,
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: SizedBox(
                        width: _videoSize.width,
                        height: _videoSize.height,
                        child: VideoPlayer(controller),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (_retryWithAudio != null)
            Positioned.fill(
              child: Material(
                color: HonooColor.background,
                child: SafeArea(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FilledButton.icon(
                          onPressed: _retryWithAudio,
                          icon: const Icon(Icons.volume_up),
                          label: const Text('Riproduci con audio'),
                        ),
                        TextButton(
                          onPressed: () {
                            final completion = _completion;
                            if (completion != null && !completion.isCompleted) {
                              completion.complete();
                            }
                          },
                          child: const Text('Continua'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

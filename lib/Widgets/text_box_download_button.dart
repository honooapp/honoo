import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class TextBoxDownloadButton extends StatelessWidget {
  const TextBoxDownloadButton({
    super.key,
    required this.onPressed,
    this.tooltip = 'download',
    this.size = 30,
    this.asset = 'assets/icons/download.svg',
  });

  final VoidCallback onPressed;
  final String tooltip;
  final double size;
  final String asset;

  static final ValueNotifier<bool> _hiddenForCapture = ValueNotifier<bool>(
    false,
  );
  static int _captureDepth = 0;

  static Future<T> hideWhileCapturing<T>(Future<T> Function() capture) async {
    _captureDepth += 1;
    if (_captureDepth == 1) {
      _hiddenForCapture.value = true;
    }
    try {
      // Every overlapping capture must wait for the hidden controls to paint.
      await WidgetsBinding.instance.endOfFrame;
      return await capture();
    } finally {
      _captureDepth -= 1;
      if (_captureDepth == 0) {
        _hiddenForCapture.value = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _hiddenForCapture,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(size / 2),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(size / 2),
              ),
              child: Center(
                child: SvgPicture.asset(
                  asset,
                  width: size * 0.6,
                  height: size * 0.6,
                  colorFilter: const ColorFilter.mode(
                    Colors.white,
                    BlendMode.srcIn,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      builder: (BuildContext context, bool hidden, Widget? child) {
        return Visibility(
          visible: !hidden,
          maintainState: true,
          maintainAnimation: true,
          maintainSize: true,
          child: child!,
        );
      },
    );
  }
}

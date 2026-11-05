import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'text_box_download_button.dart';

/// Keeps the original canvas size. Short viewports scroll instead of scaling
/// the content down to make room for editing actions.
class ContentEditFrame extends StatelessWidget {
  const ContentEditFrame({
    super.key,
    required this.child,
    required this.width,
    required this.height,
    required this.onImage,
    required this.onText,
    this.onSave,
    this.overlayControls = false,
  });
  final bool overlayControls;
  final Widget child;
  final double width;
  final double height;
  final VoidCallback onImage;
  final VoidCallback onText;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final controls = SizedBox(
        height: 40,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextBoxDownloadButton(
              key: const Key('content-edit-image'),
              onPressed: onImage,
              tooltip: 'Modifica immagine',
              asset: 'assets/icons/immagine.svg',
            ),
            if (onSave != null)
              TextBoxDownloadButton(
                onPressed: onSave!,
                tooltip: 'Conferma e salva',
                asset: 'assets/icons/ok.svg',
              ),
            TextBoxDownloadButton(
              key: const Key('content-edit-text'),
              onPressed: onText,
              tooltip: 'Modifica testo',
              asset: 'assets/icons/modifica testo.svg',
            ),
          ],
        ),
      );
      if (overlayControls) {
        return Stack(
          fit: StackFit.expand,
          children: [
            DownloadActionSpacing(child: child),
            Align(
              alignment: Alignment.topCenter,
              child: SizedBox(width: width, child: controls),
            ),
          ],
        );
      }
      final viewportHeight = constraints.maxHeight.isFinite
          ? constraints.maxHeight
          : height + 40;
      return SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: viewportHeight),
          child: Center(
            child: SizedBox(
              width: math.min(width, constraints.maxWidth),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  controls,
                  SizedBox(width: width, height: height, child: child),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

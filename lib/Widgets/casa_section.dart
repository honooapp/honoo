import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../Entities/campanelli_view_data.dart';
import '../Utility/honoo_colors.dart';
import 'text_box_download_button.dart';
import '../Utility/download_capture.dart';
import 'cover_transform_image.dart';

class CasaSection extends StatelessWidget {
  const CasaSection({
    super.key,
    required this.casa,
    required this.isUnlocked,
    required this.scrignoAsset,
    this.onScrignoTap,
    required this.footerIconSize,
    required this.scrignoSize,
    required this.footerBottomSpacing,
    required this.width,
    required this.height,
    this.onEditTap,
    this.onEditTextTap,
  });

  final CasaData casa;
  final bool isUnlocked;
  final String scrignoAsset;
  final VoidCallback? onScrignoTap;
  final double footerIconSize;
  final double scrignoSize;
  final double footerBottomSpacing;
  final double width;
  final double height;
  final VoidCallback? onEditTap;
  final VoidCallback? onEditTextTap;

  @override
  Widget build(BuildContext context) {
    const double designWidth = 1080;
    const double designHeight = 1920;
    final double scaleX = width / designWidth;
    final double scaleY = height / designHeight;

    Matrix4 buildTransform() {
      final List<double>? transform = casa.bgTransform;
      if (transform != null && transform.length == 16) {
        final List<double> m = List<double>.from(transform);
        m[12] *= scaleX;
        m[13] *= scaleY;
        return Matrix4.fromList(m);
      }

      final double tx = casa.bgOffsetX * scaleX;
      final double ty = casa.bgOffsetY * scaleY;
      return Matrix4.identity()
        ..translateByDouble(tx, ty, 0, 1)
        ..scaleByDouble(casa.bgScale, casa.bgScale, casa.bgScale, 1);
    }

    final Matrix4 transform = buildTransform();

    final repaintKey = GlobalKey();
    return RepaintBoundary(
      key: repaintKey,
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CoverTransformImage.transformed(
              image: casa.backgroundImage,
              transform: transform,
            ),
            if (isUnlocked && casa.text.isNotEmpty)
              Center(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    24,
                    48,
                    24,
                    scrignoSize + footerBottomSpacing,
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SizedBox(
                      width: (width - 48).clamp(1.0, double.infinity),
                      child: Text(
                        casa.text,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.lora(
                          fontSize: 18,
                          color: Colors.white,
                          shadows: const [
                            Shadow(blurRadius: 4, color: Colors.black),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (onEditTextTap != null)
              Positioned(
                top: 6,
                right: 6,
                child: TextBoxDownloadButton(
                  tooltip: 'Modifica testo',
                  asset: 'assets/icons/modifica testo.svg',
                  onPressed: onEditTextTap!,
                ),
              ),
            if (!isUnlocked)
              Center(
                child: Text(
                  'Casa chiusa',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.lora(
                    fontSize: 18,
                    color: HonooColor.onBackground,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            Positioned(
              bottom: 8,
              right: 8,
              child: TextBoxDownloadButton(
                tooltip: 'Scarica casa',
                onPressed: () => captureAndSave(
                  context,
                  repaintKey: repaintKey,
                  baseName: 'casa',
                ),
              ),
            ),
            if (onEditTap != null)
              Positioned(
                top: 6,
                left: 6,
                child: TextBoxDownloadButton(
                  key: const ValueKey('edit-own-casa'),
                  onPressed: onEditTap!,
                  tooltip: 'Modifica casa',
                  asset: 'assets/icons/immagine.svg',
                ),
              ),
            Positioned(
              bottom: footerBottomSpacing,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  key: const ValueKey('house-chest'),
                  behavior: HitTestBehavior.opaque,
                  onTap: onScrignoTap,
                  child: SizedBox(
                    width: scrignoSize,
                    height: scrignoSize,
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: Image.asset(scrignoAsset),
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
}

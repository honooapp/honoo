import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

import '../Entities/honoo.dart';
import 'package:honoo/Services/supabase_provider.dart';
import '../Utility/chest_content_style.dart';
import '../Utility/honoo_colors.dart';
import '../Utility/inline_text_formatting.dart';
import '../Widgets/smooth_image.dart';
import '../Widgets/text_box_download_button.dart';

class HonooCard extends StatelessWidget {
  final Honoo honoo;
  final GlobalKey? downloadBoundaryKey;
  final VoidCallback? onDownloadTap;
  final String? viewerUserId;
  final ChestContentStyle? contentStyleOverride;

  const HonooCard({
    super.key,
    required this.honoo,
    this.downloadBoundaryKey,
    this.onDownloadTap,
    this.viewerUserId,
    this.contentStyleOverride,
  });

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final String? currentUserId =
        viewerUserId ?? SupabaseProvider.client.auth.currentUser?.id;
    final contentStyle =
        contentStyleOverride ??
        ChestContentStyle.forHonoo(honoo, viewerUserId: currentUserId);
    // Sulla Luna il fondo esterno della card deve essere bianco: usando il
    // blu dello Scrigno questo affiorava agli angoli arrotondati come piccoli
    // rettangoli tra pannello testo e immagine.
    final Color cardBg =
        contentStyleOverride == null && honoo.type == HonooType.moon
        ? HonooColor.tertiary
        : contentStyle.backgroundColor;
    final bool isReceivedReply = identical(
      contentStyle,
      ChestContentStyle.receivedReply,
    );
    final Color textPanelColor = isReceivedReply
        ? Colors.white
        : HonooColor.tertiary;
    final Color textColor = isReceivedReply
        ? Colors.black
        : HonooColor.onTertiary;

    return LayoutBuilder(
      builder: (context, constraints) {
        final double availW = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : media.size.width;
        final double availH = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : (media.size.height - media.padding.vertical).clamp(
                0.0,
                double.infinity,
              );

        if (availW <= 0 || availH <= 0) {
          return const SizedBox.shrink();
        }

        // Parametri layout
        const double gap = 9.0; // spazio tra box testo e immagine
        const double eps = 0.5; // cuscinetto anti-rounding
        final double maxByH = (availH - gap - eps) / 1.5;
        final double imageSize = math.min(availW, maxByH);
        final double textHeight = imageSize / 2;
        final double totalHeight = textHeight + gap + imageSize;

        final String imageUrl = honoo.image.toString();
        final bool hasImage = imageUrl.isNotEmpty;

        const double cornerRadius = 5;

        final Color gapColor =
            contentStyleOverride == null && honoo.type == HonooType.moon
            ? HonooColor.tertiary
            : cardBg;

        final Widget content = Card(
          color: cardBg,
          elevation: 0,
          margin: EdgeInsets.zero,
          // Evita clipping dei bordi/ombre esterne applicate dal contenitore padre
          clipBehavior: Clip.none,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(cornerRadius),
          ),
          child: SizedBox(
            width: imageSize,
            height: totalHeight,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: imageSize,
                  height: textHeight,
                  child: Container(
                    key: const Key('honoo-card-text-panel'),
                    decoration: BoxDecoration(
                      color: textPanelColor,
                      border: isReceivedReply
                          ? null
                          : Border.all(color: Colors.black12),
                      borderRadius: BorderRadius.circular(cornerRadius),
                      boxShadow: isReceivedReply
                          ? null
                          : [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                    ),
                    child: Stack(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Center(
                            child: FormattedText(
                              honoo.text,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.arvo(
                                color: textColor,
                                fontSize: 18,
                                height: 1.4,
                                fontWeight: FontWeight.w400,
                              ),
                              maxLines: 5,
                              overflow: TextOverflow.visible,
                              softWrap: false,
                            ),
                          ),
                        ),
                        if (onDownloadTap != null)
                          Positioned(
                            top: 6,
                            right: 6 + DownloadActionSpacing.of(context),
                            child: TextBoxDownloadButton(
                              onPressed: onDownloadTap!,
                              tooltip: 'download',
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: imageSize,
                  height: gap,
                  child: ColoredBox(
                    key: const Key('honoo-card-gap'),
                    color: gapColor,
                  ),
                ),
                SizedBox(
                  width: imageSize,
                  height: imageSize,
                  child: Container(
                    decoration: BoxDecoration(
                      color: HonooColor.tertiary,
                      borderRadius: BorderRadius.circular(cornerRadius),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    foregroundDecoration: BoxDecoration(
                      border: Border.all(color: Colors.black12),
                      borderRadius: BorderRadius.circular(cornerRadius),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: hasImage
                        ? SmoothImage(
                            key: const ValueKey('honoo-saved-image'),
                            image: NetworkImage(imageUrl),
                            fit: BoxFit.cover,
                            alignment: Alignment.center,
                            placeholderColor: HonooColor.tertiary,
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Carica qui la tua immagine',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.libreFranklin(
                                  color: HonooColor.onSecondary,
                                  fontSize: 18,
                                ),
                              ),
                              const SizedBox(height: 22),
                              SvgPicture.asset(
                                'assets/icons/immagine.svg',
                                width: 48,
                                height: 48,
                                colorFilter: const ColorFilter.mode(
                                  HonooColor.primary,
                                  BlendMode.srcIn,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        );

        final exportContent = RepaintBoundary(
          key: downloadBoundaryKey,
          child: content,
        );
        final bool isReply = honoo.type == HonooType.answer;
        final bool isOwn =
            currentUserId != null && currentUserId == honoo.userId;
        return Center(
          child: isReply
              ? Semantics(
                  container: true,
                  label: isOwn ? 'Risposta inviata' : 'Risposta ricevuta',
                  child: exportContent,
                )
              : exportContent,
        );
      },
    );
  }
}

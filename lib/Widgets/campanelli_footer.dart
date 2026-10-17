import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

import '../Utility/honoo_colors.dart';
import 'responsive_footer_bar.dart';

class CampanelliFooter extends StatelessWidget {
  const CampanelliFooter({
    super.key,
    required this.iconSize,
    required this.bottomPadding,
    required this.desiredGap,
    required this.showCampanello,
    required this.isOwnCampanello,
    required this.isKnocking,
    required this.hasPendingKnock,
    required this.hasAnyPendingKnock,
    required this.pendingKnockCount,
    required this.onHome,
    required this.onKnock,
    required this.onOpenPendingKnocks,
  });

  final double iconSize;
  final double bottomPadding;
  final double desiredGap;
  final bool showCampanello;
  final bool isOwnCampanello;
  final bool isKnocking;
  final bool hasPendingKnock;
  final bool hasAnyPendingKnock;
  final int pendingKnockCount;
  final VoidCallback onHome;
  final VoidCallback onKnock;
  final VoidCallback onOpenPendingKnocks;

  @override
  Widget build(BuildContext context) {
    return ResponsiveFooterBar(
      useSafeArea: false,
      bottomPadding: bottomPadding,
      desiredGap: desiredGap,
      minGap: 16,
      height: iconSize,
      centerFirstAction: !showCampanello,
      actions: [
        ResponsiveFooterAction(
          asset: "assets/icons/home.svg",
          semanticsLabel: 'Home',
          colorFilter: const ColorFilter.mode(
            HonooColor.onBackground,
            BlendMode.srcIn,
          ),
          size: iconSize,
          splashRadius: 25,
          tooltip: 'Home',
          onPressed: onHome,
        ),
        if (showCampanello && !isOwnCampanello && !isKnocking)
          ResponsiveFooterAction(
            asset: "assets/icons/campana.svg",
            semanticsLabel: 'Campanello',
            size: iconSize,
            splashRadius: 25,
            tooltip: 'Campanello',
            onPressed: onKnock,
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                SvgPicture.asset(
                  "assets/icons/campana.svg",
                  width: iconSize,
                  height: iconSize,
                  fit: BoxFit.contain,
                ),
                if (hasPendingKnock && pendingKnockCount > 0)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: _PendingKnockBadge(count: pendingKnockCount),
                  ),
              ],
            ),
          ),
        if (showCampanello && !isOwnCampanello && isKnocking)
          ResponsiveFooterAction(
            asset: "assets/icons/campana.svg",
            semanticsLabel: 'Campanello',
            size: iconSize,
            splashRadius: 25,
            tooltip: 'Campanello',
            onPressed: null,
            icon: SizedBox(width: iconSize, height: iconSize),
          ),
        if (!showCampanello && hasAnyPendingKnock)
          ResponsiveFooterAction(
            asset: "assets/icons/campana.svg",
            semanticsLabel: 'Campanelli',
            size: iconSize,
            splashRadius: 25,
            tooltip: 'Bussate in attesa',
            onPressed: onOpenPendingKnocks,
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                SvgPicture.asset(
                  "assets/icons/campana.svg",
                  width: iconSize,
                  height: iconSize,
                  fit: BoxFit.contain,
                ),
                if (pendingKnockCount > 0)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: _PendingKnockBadge(count: pendingKnockCount),
                  ),
              ],
            ),
          ),
        if (!showCampanello && !hasAnyPendingKnock)
          ResponsiveFooterAction(
            asset: "assets/icons/campana.svg",
            semanticsLabel: 'Campanelli',
            size: iconSize,
            splashRadius: 25,
            tooltip: 'Bussate in attesa',
            onPressed: null,
            icon: SizedBox(width: iconSize, height: iconSize),
          ),
      ],
    );
  }
}

class _PendingKnockBadge extends StatelessWidget {
  const _PendingKnockBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final String label = count > 99 ? '99+' : count.toString();
    final double size = count > 9 ? 18 : 16;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      height: size,
      constraints: BoxConstraints(minWidth: size),
      decoration: BoxDecoration(
        color: Colors.redAccent,
        borderRadius: BorderRadius.circular(size / 2),
        border: Border.all(color: HonooColor.background, width: 1.5),
      ),
      child: Center(
        child: Text(
          label,
          style: GoogleFonts.libreFranklin(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

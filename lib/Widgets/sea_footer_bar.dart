import 'luna_fissa.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:honoo/Utility/honoo_colors.dart';
import 'package:honoo/Widgets/composer_onboarding.dart';
import 'package:honoo/Services/auth_navigation_service.dart';

// Pagine per la navigazione (come in HomePage)
import 'package:honoo/IsolaDelleStorie/Pages/island_page.dart';
import 'package:honoo/Pages/chest_page.dart';
import 'package:honoo/IsolaDelleStorie/Pages/campanelli_page.dart';

/// Barra “mare” riutilizzabile con onde + isola (sx) + scrigno (centro) + bottiglia (dx)
/// Posizioni, dimensioni e z-order identici alla HomePage.
class SeaFooterBar extends StatelessWidget {
  const SeaFooterBar({
    super.key,
    this.replyCount = 0,
    this.showHouseEntry = false,
  });

  final int replyCount;
  final bool showHouseEntry;

  /// Altezza fissa come in HomePage
  static const double height = 105;

  static void openComposer(BuildContext context) {
    ComposerLauncher.open(context);
  }

  static void openIsland(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const IslandPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      // Include the house button in the hit-test area above the existing sea.
      height: showHouseEntry
          ? height * 0.64 + 44 + MediaQuery.of(context).viewPadding.bottom
          : height,
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double safeBottom = MediaQuery.of(context).viewPadding.bottom;
          final w = constraints.maxWidth;

          // Dimensioni icone (coerenti con HomePage)
          const double chestSize = 70; // scrigno
          const double bottleSize = 70; // bottiglia
          const double islandSize = 180; // isola

          // Posizioni "storiche" rispetto al centro (coerenti con HomePage)
          final double chestCenterX = (w / 2) - chestSize / 2 + 36;
          final double islandTargetX = (w / 2) - 200;
          final double bottleTargetX = (w / 2) + 104;

          // Clamp per evitare tagli laterali
          final double islandX = islandTargetX
              .clamp(0.0, (w - islandSize))
              .toDouble();
          final double bottleX = bottleTargetX
              .clamp(0.0, (w - bottleSize))
              .toDouble();
          final double chestX = chestCenterX
              .clamp(0.0, (w - chestSize))
              .toDouble();

          return Stack(
            clipBehavior: Clip.none,
            children: [
              // Onde (non bloccano i tap)
              // 2) Onde in MEZZO (sopra la bottiglia) ma non bloccano i tap
              Positioned(
                bottom: safeBottom + height * 0.0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: SizedBox(
                    height: height * 0.285,
                    child: Container(color: HonooColor.wave3),
                  ),
                ),
              ),
              Positioned(
                bottom: safeBottom + height * 0.48,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: SizedBox(
                    height: height * 0.16,
                    child: Container(color: HonooColor.wave1),
                  ),
                ),
              ),

              // Bottiglia tra seconda e terza onda
              Positioned(
                bottom: safeBottom,
                left: bottleX,
                child: Transform.translate(
                  offset: const Offset(0, -height * 0.24),
                  child: IconButton(
                    constraints: const BoxConstraints.tightFor(
                      width: bottleSize,
                      height: bottleSize,
                    ),
                    padding: EdgeInsets.zero,
                    icon: SvgPicture.asset(
                      "assets/icons/bottle.svg",
                      width: bottleSize,
                      height: bottleSize,
                      semanticsLabel: 'Bottle',
                    ),
                    iconSize: bottleSize,
                    splashRadius: 40,
                    tooltip: 'Scrivi',
                    onPressed: () => SeaFooterBar.openComposer(context),
                  ),
                ),
              ),

              Positioned(
                bottom: safeBottom + height * 0.29,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: SizedBox(
                    height: height * 0.26,
                    child: Container(color: HonooColor.wave2),
                  ),
                ),
              ),

              // Isola (sx)
              Positioned(
                bottom: safeBottom,
                left: islandX,
                child: Transform.translate(
                  offset: const Offset(0, height * 0.15),
                  child: IconButton(
                    constraints: const BoxConstraints.tightFor(
                      width: islandSize,
                      height: islandSize,
                    ),
                    key: const Key('footer_island_entry'),
                    padding: EdgeInsets.zero,
                    icon: SvgPicture.asset(
                      "assets/icons/isoladellestorie/island.svg",
                      theme: const SvgTheme(
                        currentColor: HonooColor.onBackground,
                      ),
                      colorFilter: const ColorFilter.mode(
                        HonooColor.onBackground,
                        BlendMode.srcIn,
                      ),
                      width: islandSize,
                      height: islandSize,
                      semanticsLabel: 'Island',
                    ),
                    iconSize: islandSize,
                    splashRadius: 1,
                    tooltip: "Vai all'Isola delle Storie",
                    onPressed: () => SeaFooterBar.openIsland(context),
                  ),
                ),
              ),

              if (showHouseEntry)
                Positioned(
                  bottom: safeBottom + height * 0.64,
                  left:
                      (w >= 1200 ? 16 : 8) +
                      (LunaFissa.iconSizeForWidth(w) - 44) / 2,
                  child: IconButton(
                    key: const Key('home_house_entry'),
                    tooltip: 'La tua casa',
                    constraints: const BoxConstraints.tightFor(
                      width: 44,
                      height: 44,
                    ),
                    padding: EdgeInsets.zero,
                    iconSize: 27.5,
                    icon: SvgPicture.asset(
                      'assets/icons/ospiti.svg',
                      width: 27.5,
                      height: 27.5,
                      semanticsLabel: 'La tua casa',
                    ),
                    onPressed: () async {
                      final loggedIn =
                          await AuthNavigationService.ensureLoggedIn(context);
                      if (!context.mounted || !loggedIn) return;
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              const CampanelliPage(openOwnHouse: true),
                        ),
                      );
                    },
                  ),
                ),

              // Scrigno (centro)
              Positioned(
                bottom: safeBottom,
                left: chestX,
                child: Transform.translate(
                  offset: const Offset(0, height * 0.01),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      IconButton(
                        constraints: const BoxConstraints.tightFor(
                          width: chestSize,
                          height: chestSize,
                        ),
                        padding: EdgeInsets.zero,
                        icon: SvgPicture.asset(
                          "assets/icons/chest.svg",
                          width: chestSize,
                          height: chestSize,
                          semanticsLabel: 'Chest',
                        ),
                        iconSize: chestSize,
                        splashRadius: 40,
                        tooltip: 'Apri il tuo Cuore',
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ChestPage(
                                focusReplies: replyCount > 0,
                                highlightLatest: replyCount > 0,
                              ),
                            ),
                          );
                        },
                      ),
                      if (replyCount > 0)
                        Positioned(
                          top: -2,
                          right: -2,
                          child: _ReplyBadge(count: replyCount),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ReplyBadge extends StatelessWidget {
  const _ReplyBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final String label = count > 99 ? '99+' : count.toString();
    final double size = count > 9 ? 20 : 18;
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

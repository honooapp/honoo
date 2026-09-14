import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

import '../Entities/casa_share_mode.dart';
import '../Utility/honoo_colors.dart';

class CasaShareSelectionPage extends StatefulWidget {
  const CasaShareSelectionPage({
    super.key,
    this.initialSelection = const <CasaShareMode>{},
  });

  final Set<CasaShareMode> initialSelection;

  @override
  State<CasaShareSelectionPage> createState() => _CasaShareSelectionPageState();
}

/// Menu di ingresso allo Scrigno dalla propria casa. La scelta è immediata:
/// non rappresenta un'autorizzazione e quindi non ha stato selezionato né OK.
class CasaChestFilterPage extends StatelessWidget {
  const CasaChestFilterPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HonooColor.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 650;
            final iconSize = compact ? 72.0 : 96.0;
            final spacing = compact ? 28.0 : 46.0;
            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 32,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _ShareIcon(
                      key: const ValueKey('house-chest-home'),
                      label: CasaChestFilter.authored.label,
                      asset: 'assets/icons/honoo_chest_blue.svg',
                      selected: false,
                      size: iconSize,
                      addWhiteOutline: true,
                      onTap: () =>
                          Navigator.of(context).pop(CasaChestFilter.authored),
                    ),
                    SizedBox(height: spacing),
                    _ShareIcon(
                      key: const ValueKey('house-chest-moon'),
                      label: CasaChestFilter.moonSaved.label,
                      asset: 'assets/icons/honoo_chest_white.svg',
                      selected: false,
                      size: iconSize,
                      onTap: () =>
                          Navigator.of(context).pop(CasaChestFilter.moonSaved),
                    ),
                    SizedBox(height: spacing),
                    _ShareIcon(
                      key: const ValueKey('house-chest-all'),
                      label: CasaChestFilter.all.label,
                      asset: 'assets/icons/chest_home.svg',
                      selected: false,
                      size: iconSize,
                      addWhiteOutline: true,
                      onTap: () =>
                          Navigator.of(context).pop(CasaChestFilter.all),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CasaShareSelectionPageState extends State<CasaShareSelectionPage> {
  late final Set<CasaShareMode> _selected = Set<CasaShareMode>.of(
    widget.initialSelection,
  );

  void _toggle(CasaShareMode mode) {
    setState(() {
      if (!_selected.add(mode)) _selected.remove(mode);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HonooColor.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 650;
            final iconSize = compact ? 72.0 : 96.0;
            final spacing = compact ? 18.0 : 32.0;
            return Stack(
              fit: StackFit.expand,
              children: [
                SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 96),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - 124,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'cosa vuoi mostrare?',
                          key: const ValueKey('house-share-title'),
                          textAlign: TextAlign.center,
                          style: GoogleFonts.arvo(
                            color: Colors.white,
                            fontSize: compact ? 22 : 26,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        SizedBox(height: compact ? 24 : 40),
                        _ShareIcon(
                          key: const ValueKey('house-share-home'),
                          label: CasaShareMode.home.label,
                          asset: 'assets/icons/honoo_chest_blue.svg',
                          selected: _selected.contains(CasaShareMode.home),
                          size: iconSize,
                          addWhiteOutline: true,
                          onTap: () => _toggle(CasaShareMode.home),
                        ),
                        SizedBox(height: spacing),
                        _ShareIcon(
                          key: const ValueKey('house-share-moon'),
                          label: CasaShareMode.moon.label,
                          asset: 'assets/icons/honoo_chest_white.svg',
                          selected: _selected.contains(CasaShareMode.moon),
                          size: iconSize,
                          onTap: () => _toggle(CasaShareMode.moon),
                        ),
                        SizedBox(height: spacing),
                        _ShareIcon(
                          key: const ValueKey('house-share-all'),
                          label: CasaShareMode.all.label,
                          asset: 'assets/icons/chest_home.svg',
                          selected: _selected.contains(CasaShareMode.all),
                          size: iconSize,
                          addWhiteOutline: true,
                          onTap: () => _toggle(CasaShareMode.all),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  right: 20,
                  bottom: 14,
                  child: Tooltip(
                    message: 'Salva',
                    preferBelow: false,
                    child: IconButton(
                      key: const ValueKey('house-share-confirm'),
                      onPressed: _selected.isEmpty
                          ? null
                          : () => Navigator.of(
                              context,
                            ).pop(Set<CasaShareMode>.unmodifiable(_selected)),
                      iconSize: compact ? 48 : 58,
                      padding: const EdgeInsets.all(8),
                      icon: Opacity(
                        opacity: _selected.isEmpty ? 0.35 : 1,
                        child: SvgPicture.asset(
                          'assets/icons/ok.svg',
                          width: compact ? 48 : 58,
                          height: compact ? 48 : 58,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ShareIcon extends StatelessWidget {
  const _ShareIcon({
    super.key,
    required this.label,
    required this.asset,
    required this.selected,
    required this.size,
    required this.onTap,
    this.addWhiteOutline = false,
  });

  final String label;
  final String asset;
  final bool selected;
  final double size;
  final VoidCallback onTap;
  final bool addWhiteOutline;

  @override
  Widget build(BuildContext context) {
    final icon = Stack(
      alignment: Alignment.center,
      children: [
        if (addWhiteOutline)
          Transform.scale(
            scale: 1.045,
            child: SvgPicture.asset(
              asset,
              width: size,
              height: size,
              colorFilter: const ColorFilter.mode(
                Colors.white,
                BlendMode.srcIn,
              ),
            ),
          ),
        SvgPicture.asset(asset, width: size, height: size),
      ],
    );

    return Tooltip(
      message: label,
      preferBelow: false,
      verticalOffset: 18,
      waitDuration: const Duration(milliseconds: 250),
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              width: size + 34,
              height: size + 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected
                    ? Colors.white.withValues(alpha: 0.14)
                    : Colors.transparent,
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: Colors.white.withValues(alpha: 0.9),
                          blurRadius: 24,
                          spreadRadius: 3,
                        ),
                      ]
                    : const [],
              ),
              child: icon,
            ),
          ),
        ),
      ),
    );
  }
}

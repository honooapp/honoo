import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class ResponsiveFooterAction {
  final String asset;
  final double size;
  final String tooltip;
  final VoidCallback? onPressed;
  final String? semanticsLabel;
  final ColorFilter? colorFilter;
  final double? splashRadius;
  final Widget? icon;
  final bool visible;

  const ResponsiveFooterAction({
    required this.asset,
    required this.size,
    required this.tooltip,
    this.onPressed,
    this.semanticsLabel,
    this.colorFilter,
    this.splashRadius,
    this.icon,
    this.visible = true,
  });
}

class ResponsiveFooterBar extends StatelessWidget {
  const ResponsiveFooterBar({
    super.key,
    required this.actions,
    this.bottomPadding = 12,
    this.desiredGap = 24,
    this.minGap = 12,
    this.height = 60,
    this.lockGapWhenPossible = false,
    this.useSafeArea = true,
    this.mainAxisAlignment = MainAxisAlignment.center,
    this.alignment = Alignment.center,
    this.expandToAvailableWidth = false,
    this.centerFirstAction = false,
  });

  final List<ResponsiveFooterAction> actions;
  final double bottomPadding;
  final double desiredGap;
  final double minGap;
  final double height;
  final bool lockGapWhenPossible;
  final bool useSafeArea;
  final MainAxisAlignment mainAxisAlignment;
  final AlignmentGeometry alignment;
  final bool expandToAvailableWidth;
  final bool centerFirstAction;

  @override
  Widget build(BuildContext context) {
    final bool isPhone = MediaQuery.of(context).size.shortestSide < 600;
    final double effectiveDesiredGap = isPhone ? desiredGap + 4 : desiredGap;
    final double effectiveMinGap = isPhone ? minGap + 2 : minGap;
    final Widget bar = Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double availableWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : double.infinity;
          final bool balanceFirstAction =
              centerFirstAction && actions.length == 2;
          final double totalIconWidth =
              actions.fold(0.0, (sum, action) => sum + action.size) +
              (balanceFirstAction ? actions.last.size : 0);
          final double iconScale =
              availableWidth.isFinite &&
                  totalIconWidth > availableWidth &&
                  totalIconWidth > 0
              ? availableWidth / totalIconWidth
              : 1;
          final double fittedIconWidth = totalIconWidth * iconScale;
          final int gapCount = balanceFirstAction
              ? 2
              : math.max(0, actions.length - 1);
          double gap = effectiveDesiredGap;

          if (availableWidth.isFinite && gapCount > 0) {
            final double maxGap = (availableWidth - fittedIconWidth) / gapCount;
            if (lockGapWhenPossible && maxGap >= effectiveDesiredGap) {
              gap = effectiveDesiredGap;
            } else if (maxGap <= effectiveMinGap) {
              gap = math.max(0, maxGap);
            } else {
              gap = math.max(
                effectiveMinGap,
                math.min(effectiveDesiredGap, maxGap),
              );
            }
          }

          return SizedBox(
            height: height,
            child: Align(
              alignment: alignment,
              child: Row(
                mainAxisAlignment: mainAxisAlignment,
                mainAxisSize: expandToAvailableWidth
                    ? MainAxisSize.max
                    : MainAxisSize.min,
                children: [
                  if (balanceFirstAction) ...[
                    SizedBox(width: actions.last.size * iconScale),
                    SizedBox(width: gap),
                  ],
                  for (int index = 0; index < actions.length; index++) ...[
                    _FooterIconButton(
                      action: actions[index],
                      size: actions[index].size * iconScale,
                    ),
                    if (!expandToAvailableWidth && index < actions.length - 1)
                      SizedBox(width: gap),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );

    if (!useSafeArea) {
      return bar;
    }

    return SafeArea(top: false, child: bar);
  }
}

class _FooterIconButton extends StatelessWidget {
  const _FooterIconButton({required this.action, required this.size});

  final ResponsiveFooterAction action;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (!action.visible) return SizedBox.square(dimension: size);
    final Widget iconWidget = action.icon == null
        ? SvgPicture.asset(
            action.asset,
            semanticsLabel: action.semanticsLabel,
            colorFilter: action.colorFilter,
            width: size,
            height: size,
          )
        : SizedBox.square(
            dimension: size,
            child: FittedBox(child: action.icon),
          );

    return IconButton(
      visualDensity: VisualDensity.compact,
      constraints: BoxConstraints.tightFor(width: size, height: size),
      padding: EdgeInsets.zero,
      icon: iconWidget,
      iconSize: size,
      splashRadius: math.min(action.splashRadius ?? size * 0.5, size * 0.5),
      tooltip: action.tooltip,
      onPressed: action.onPressed,
    );
  }
}

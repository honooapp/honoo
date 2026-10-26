import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../Pages/home_page.dart';

/// Shared navigation arrow, placed at the start of the page header.
class HonooBackButton extends StatelessWidget {
  const HonooBackButton({
    super.key,
    this.color = Colors.white,
    this.enabled = true,
  });

  final Color color;
  final bool enabled;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Indietro',
    onPressed: !enabled
        ? null
        : () {
            final navigator = Navigator.of(context);
            if (navigator.canPop()) {
              navigator.pop();
            } else {
              navigator.pushReplacement(
                MaterialPageRoute(builder: (_) => const HomePage()),
              );
            }
          },
    icon: SvgPicture.asset(
      'assets/icons/arrow_left.svg',
      width: 32,
      height: 32,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    ),
  );
}

import 'honoo_back_button.dart';
import 'package:flutter/material.dart';
import 'package:honoo/Utility/honoo_colors.dart';

import 'honoo_app_title.dart';
import 'luna_fissa.dart';
import '../Pages/placeholder_page.dart';

class HonooScaffold extends StatelessWidget {
  const HonooScaffold({
    super.key,
    required this.body,
    this.showFooter = false,
    this.showBack = false,
    this.footer,
  });

  final Widget body;
  final bool showFooter;
  final bool showBack;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final content = Stack(
      fit: StackFit.expand,
      children: [
        Column(
          children: [
            SizedBox(
              height: 52,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Center(
                    child: HonooAppTitle(
                      onTap: () {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(
                            builder: (_) => const PlaceholderPage(),
                          ),
                          (route) => false,
                        );
                      },
                    ),
                  ),
                  if (showBack)
                    const Positioned(left: 8, child: HonooBackButton()),
                ],
              ),
            ),
            Expanded(child: body),
            if (showFooter && footer != null) footer!,
          ],
        ),
        const LunaFissa(),
      ],
    );

    return Scaffold(
      backgroundColor: HonooColor.background,
      body: SafeArea(child: content),
    );
  }
}

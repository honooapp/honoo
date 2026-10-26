import '../honoo_back_button.dart';
import 'package:flutter/material.dart';

import '../../Utility/honoo_colors.dart';
import '../honoo_app_title.dart';

class ChingScaffold extends StatelessWidget {
  const ChingScaffold({super.key, required this.body});

  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // HEADER: back a sinistra, logo al centro
            const SizedBox(
              height: 56,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned(
                    left: 6,
                    child: HonooBackButton(color: HonooColor.background),
                  ),
                  Center(child: HonooAppTitle()),
                ],
              ),
            ),

            // BODY (scrollabile, ma con larghezza limitata)
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: body,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

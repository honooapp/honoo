import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ColoreTestoOverlay extends StatelessWidget {
  const ColoreTestoOverlay({super.key, required this.onPick});

  final ValueChanged<Color> onPick;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Scegli il colore del testo',
              textAlign: TextAlign.center,
              style: GoogleFonts.lora(color: Colors.white, fontSize: 16),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ColorDot(color: Colors.white, onTap: () => onPick(Colors.white)),
              const SizedBox(width: 16),
              _ColorDot(color: Colors.black, onTap: () => onPick(Colors.black)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.color, required this.onTap});
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: color == Colors.white ? 'Testo bianco' : 'Testo nero',
      child: Semantics(
        button: true,
        label: color == Colors.white ? 'Testo bianco' : 'Testo nero',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: color == Colors.white ? Colors.black : Colors.white,
                  width: 3,
                ),
                boxShadow: const [
                  BoxShadow(color: Colors.grey, spreadRadius: 2),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

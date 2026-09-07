import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'honoo_dialogs.dart';

const String storieStorieContinuation = 'storiestorie-romanzo';

bool isStorieStorieContinuation(Uri uri) =>
    uri.queryParameters['continue'] == storieStorieContinuation;

class StorieStorieAccessDialog extends StatelessWidget {
  const StorieStorieAccessDialog({super.key});

  TextStyle _textStyle({
    required double fontSize,
    required Color color,
    FontWeight fontWeight = FontWeight.normal,
  }) => GoogleFonts.arvo(
    color: color,
    fontSize: fontSize,
    fontWeight: fontWeight,
  );

  @override
  Widget build(BuildContext context) {
    return HonooDialogShell(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Prima di entrare',
                style: _textStyle(
                  fontSize: 20,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Su Google Drive usa la stessa mail/n'
                    'con cui ti sei registrato su honoo/n'
                    'Poi clicca su Richiedi accesso/n'
                    'Venceslao ti autorizzerà/n come visualizzatore',
                style: _textStyle(fontSize: 14, color: Colors.white70),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'Continua su Google Drive',
                    style: _textStyle(
                      fontSize: 14,
                      color: Colors.black,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                style: TextButton.styleFrom(foregroundColor: Colors.white54),
                child: Text(
                  'Annulla',
                  style: _textStyle(fontSize: 13, color: Colors.white54),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

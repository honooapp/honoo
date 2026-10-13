import 'package:flutter/material.dart';
import 'honoo_dialogs.dart';

enum HouseKnockContent { honoo, hinoo }

class HouseKnockDialog extends StatelessWidget {
  const HouseKnockDialog({super.key});

  @override
  Widget build(BuildContext context) => HonooDialogShell(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Per entrare, invia un honoo o un hinoo',
            textAlign: TextAlign.center,
            style: HonooDialogStyles.title(),
          ),
          const SizedBox(height: 20),
          for (final kind in HouseKnockContent.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(kind),
                  child: Text('Invia un ${kind.name}'),
                ),
              ),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annulla'),
          ),
        ],
      ),
    ),
  );
}

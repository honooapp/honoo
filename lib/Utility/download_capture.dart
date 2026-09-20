import 'package:flutter/material.dart';
import 'package:honoo/Services/download_capture_service.dart';
import 'package:honoo/Widgets/gallery_save_dialog.dart';
import 'package:honoo/Widgets/honoo_dialogs.dart';

final DownloadCaptureService _downloadCaptureService = DownloadCaptureService();

Future<void> captureAndSave(
  BuildContext context, {
  required GlobalKey repaintKey,
  required String baseName,
  String toastOnStart = 'Download avviato.',
  String? message,
}) async {
  NavigatorState? rootNav;
  try {
    // Capture a navigator tied to a root overlay before any async gap
    rootNav = Navigator.of(context, rootNavigator: true);
    final result = await _downloadCaptureService.captureAndSave(
      repaintKey: repaintKey,
      baseName: baseName,
      message: message ?? toastOnStart,
    );

    if (!rootNav.mounted) return;
    await showDownloadSaveResult(
      context: rootNav.context,
      contentName: ['casa', 'campanello'].contains(baseName)
          ? baseName
          : baseName.toLowerCase().startsWith('hinoo')
          ? 'hinoo'
          : 'honoo',
      result: result,
    );
  } catch (e) {
    if (rootNav != null && rootNav.mounted) {
      showHonooToast(rootNav.context, message: 'Errore download: $e');
    }
  }
}

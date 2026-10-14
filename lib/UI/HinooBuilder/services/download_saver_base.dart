import 'dart:typed_data';

abstract class DownloadSaver {
  Future<DownloadSaveResult> save(
    List<DownloadImage> images, {
    String? message,
  });

  Future<bool> openSavedImage(DownloadSaveResult result);
}

class DownloadSaveResult {
  const DownloadSaveResult({
    required this.message,
    this.savedToGallery = false,
    this.cancelled = false,
    this.savedItemUri,
  });

  final String message;
  final bool savedToGallery;
  final bool cancelled;
  final String? savedItemUri;
}

class DownloadImage {
  DownloadImage({required this.filename, required this.bytes});

  final String filename;
  final Uint8List bytes;
}

String sanitizeDownloadFilename(String filename) {
  final String trimmed = filename.trim();
  final int dotIndex = trimmed.lastIndexOf('.');
  final bool hasExtension = dotIndex > 0 && dotIndex < trimmed.length - 1;
  String stem = hasExtension ? trimmed.substring(0, dotIndex) : trimmed;
  String extension = hasExtension ? trimmed.substring(dotIndex) : '';

  stem = stem
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
      .replaceAll(RegExp(r'[. ]+$'), '')
      .trim();
  extension = extension.replaceAll(RegExp(r'[^A-Za-z0-9.]'), '').toLowerCase();

  if (stem.isEmpty) stem = 'honoo';
  return '$stem$extension';
}

bool isMobileOrTabletBrowser(String userAgent, {int maxTouchPoints = 0}) {
  final String normalized = userAgent.toLowerCase();
  return normalized.contains('android') ||
      normalized.contains('iphone') ||
      normalized.contains('ipad') ||
      normalized.contains('ipod') ||
      (normalized.contains('macintosh') && maxTouchPoints > 1);
}

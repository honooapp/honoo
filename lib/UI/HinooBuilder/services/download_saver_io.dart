import 'dart:io';

import 'package:honoo/env/env.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import 'download_saver_base.dart';

class _DownloadSaverIo implements DownloadSaver {
  @override
  Future<DownloadSaveResult> save(
    List<DownloadImage> images, {
    String? message,
  }) async {
    if (images.isEmpty) {
      return const DownloadSaveResult(
        message: 'Nessuna immagine da scaricare.',
      );
    }

    if (Platform.isAndroid || Platform.isIOS) {
      // Prova a salvare direttamente in Galleria/Foto
      int ok = 0;
      final List<String> savedItemUris = <String>[];
      for (final img in images) {
        final String filename = sanitizeDownloadFilename(img.filename);
        String? savedItemUri = await _saveToGallery(img, filename);
        if (savedItemUri == null && Platform.isAndroid) {
          final PermissionStatus status = await Permission.storage.request();
          if (status.isGranted) {
            savedItemUri = await _saveToGallery(img, filename);
          }
        }
        if (savedItemUri != null) {
          ok++;
          savedItemUris.add(savedItemUri);
        }
      }

      if (ok == images.length && ok > 0) {
        return DownloadSaveResult(
          message: images.length == 1
              ? 'Immagine salvata nella galleria.'
              : 'Immagini salvate nella galleria.',
          savedToGallery: true,
          savedItemUri: images.length == 1 ? savedItemUris.single : null,
        );
      }

      // Fallback: apri il foglio di condivisione
      final List<XFile> files = images
          .map(
            (img) => XFile.fromData(
              img.bytes,
              name: sanitizeDownloadFilename(img.filename),
              mimeType: 'image/png',
            ),
          )
          .toList(growable: false);
      final shared = await Share.shareXFiles(files, text: message ?? '');
      if (shared.status == ShareResultStatus.dismissed) {
        return const DownloadSaveResult(
          message: 'Salvataggio annullato.',
          cancelled: true,
        );
      }
      return const DownloadSaveResult(
        message: 'Condividi o salva le immagini dalle opzioni di sistema.',
      );
    }

    final Directory targetDir = await _resolveDownloadDirectory();
    final List<String> savedPaths = <String>[];
    for (final DownloadImage img in images) {
      final String filename = sanitizeDownloadFilename(img.filename);
      final String filePath = _joinPaths(targetDir.path, filename);
      final File file = File(filePath);
      await file.writeAsBytes(img.bytes, flush: true);
      savedPaths.add(file.path);
    }
    return DownloadSaveResult(message: 'Immagini salvate in ${targetDir.path}');
  }

  @override
  Future<bool> openSavedImage(DownloadSaveResult result) async {
    final String? rawUri = result.savedItemUri;
    if (rawUri == null || rawUri.isEmpty) return false;
    final Uri? uri = Uri.tryParse(rawUri);
    if (uri == null) return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  Future<String?> _saveToGallery(DownloadImage image, String filename) async {
    try {
      final dynamic result = await ImageGallerySaver.saveImage(
        image.bytes,
        quality: 100,
        name: filename.replaceFirst(
          RegExp(r'\.png$', caseSensitive: false),
          '',
        ),
        isReturnImagePathOfIOS: true,
      );
      return _extractSavedItemUri(result);
    } catch (_) {
      return null;
    }
  }

  Future<Directory> _resolveDownloadDirectory() async {
    final String folderName = 'hinoo_${DateTime.now().millisecondsSinceEpoch}';
    Directory? base;
    if (Platform.isMacOS || Platform.isLinux) {
      final String home = readEnv('HOME');
      if (home.isNotEmpty) {
        final Directory downloads = Directory(_joinPaths(home, 'Downloads'));
        if (downloads.existsSync()) base = downloads;
      }
    } else if (Platform.isWindows) {
      final String userProfile = readEnv('USERPROFILE');
      if (userProfile.isNotEmpty) {
        final Directory downloads = Directory(
          _joinPaths(userProfile, 'Downloads'),
        );
        if (downloads.existsSync()) base = downloads;
      }
    }

    base ??= await Directory.systemTemp.createTemp('hinoo_download_base_');
    final Directory target = Directory(_joinPaths(base.path, folderName));
    if (!target.existsSync()) {
      await target.create(recursive: true);
    }
    return target;
  }

  String _joinPaths(String parent, String child) {
    if (parent.endsWith(Platform.pathSeparator)) {
      return '$parent$child';
    }
    return '$parent${Platform.pathSeparator}$child';
  }
}

DownloadSaver getDownloadSaverImpl() => _DownloadSaverIo();

String? _extractSavedItemUri(dynamic result) {
  try {
    if (result is Map) {
      final success = result['isSuccess'] == true || result['success'] == true;
      final dynamic rawPath = result['filePath'];
      if (success && rawPath is String && rawPath.isNotEmpty) return rawPath;
    }
  } catch (_) {}
  return null;
}

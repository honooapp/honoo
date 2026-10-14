import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'download_saver_base.dart';

class _DownloadSaverWeb implements DownloadSaver {
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

    final shared = _isMobileOrTabletBrowser()
        ? await _shareWithSystem(images, message)
        : false;
    if (shared == null) {
      return const DownloadSaveResult(
        message: 'Salvataggio annullato.',
        cancelled: true,
      );
    }
    if (shared) {
      return DownloadSaveResult(
        message: images.length == 1
            ? 'Scegli “Salva immagine” per aggiungerla alla galleria.'
            : 'Scegli “Salva immagini” per aggiungerle alla galleria.',
      );
    }

    final bool iosBrowser = _isIosBrowser();
    for (final DownloadImage img in images) {
      // Alcuni browser mobile (iOS Safari) ignorano download programmatici.
      // Usiamo un fallback aprendolo in una nuova scheda.
      final String mime = iosBrowser ? 'application/octet-stream' : 'image/png';
      final web.Blob blob = web.Blob(
        <JSAny>[img.bytes.toJS].toJS,
        web.BlobPropertyBag(type: mime),
      );
      final String url = web.URL.createObjectURL(blob);

      try {
        if (iosBrowser) {
          // Fallback: apri in una nuova scheda; l’utente può salvare dall’UI
          final web.Window? opened = web.window.open(url, '_blank');
          if (opened == null) {
            web.window.location.assign(url);
          } else {
            _revokeLater(url);
          }
        } else {
          final web.HTMLAnchorElement anchor = web.HTMLAnchorElement()
            ..href = url
            ..download = sanitizeDownloadFilename(img.filename)
            ..rel = 'noopener'
            ..target = '_self'
            ..style.display = 'none';
          web.document.body?.append(anchor);
          anchor.click();
          anchor.remove();
          web.URL.revokeObjectURL(url);
        }
      } catch (_) {
        // Ultimo fallback generico: prova ad aprire in nuova scheda
        final web.Window? opened = web.window.open(url, '_blank');
        if (opened == null) {
          web.window.location.assign(url);
        } else {
          _revokeLater(url);
        }
      }
    }

    return DownloadSaveResult(
      message: images.length == 1
          ? 'Download avviato.'
          : 'Download multipli avviati.',
    );
  }

  @override
  Future<bool> openSavedImage(DownloadSaveResult result) async => false;
}

DownloadSaver getDownloadSaverImpl() => _DownloadSaverWeb();

bool _isIosBrowser() {
  final ua = web.window.navigator.userAgent.toLowerCase();
  return ua.contains('iphone') || ua.contains('ipad') || ua.contains('ipod');
}

bool _isMobileOrTabletBrowser() {
  return isMobileOrTabletBrowser(
    web.window.navigator.userAgent,
    maxTouchPoints: web.window.navigator.maxTouchPoints,
  );
}

Future<bool?> _shareWithSystem(
  List<DownloadImage> images,
  String? message,
) async {
  final web.Navigator navigator = web.window.navigator;
  if (!navigator.hasProperty('share'.toJS).toDart) return false;

  final List<web.File> files = images
      .map(
        (DownloadImage image) => web.File(
          <JSAny>[image.bytes.toJS].toJS,
          sanitizeDownloadFilename(image.filename),
          web.FilePropertyBag(type: 'image/png'),
        ),
      )
      .toList(growable: false);
  final web.ShareData shareData = web.ShareData(
    files: files.toJS,
    title: 'Honoo',
    text: message?.trim() ?? '',
  );

  if (navigator.hasProperty('canShare'.toJS).toDart) {
    try {
      final bool canShare = navigator.canShare(shareData);
      if (!canShare) return false;
    } catch (_) {
      return false;
    }
  }

  try {
    await navigator.share(shareData).toDart;
    return true;
  } catch (error) {
    // Un annullamento volontario non deve avviare un download inatteso.
    try {
      final JSString? name = (error as JSObject).getProperty('name'.toJS);
      if (name?.toDart == 'AbortError') {
        return null;
      }
    } catch (_) {}
    return false;
  }
}

void _revokeLater(String url) {
  Timer(const Duration(seconds: 30), () => web.URL.revokeObjectURL(url));
}

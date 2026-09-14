// lib/Services/hinoo_storage_uploader.dart
import 'dart:typed_data';
import 'package:honoo/Services/supabase_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'reliability_policy.dart';

class HinooStorageUploader {
  static const String bucket = 'hinoo';
  static const Uuid _uuid = Uuid();
  static const ReliabilityPolicy _reliability = ReliabilityPolicy();

  // Getter iniettabile nei test
  static SupabaseClient get _client =>
      _overrideClient ?? SupabaseProvider.client;
  static SupabaseClient? _overrideClient;

  /// TEST-ONLY: abilita injection di un client mock
  static void $setTestClient(SupabaseClient? c) => _overrideClient = c;

  static String _normalizeExt(String ext) {
    final e = ext.trim().toLowerCase();
    if (e == 'jpeg') return 'jpg';
    const allowed = {'jpg', 'png', 'webp'};
    return allowed.contains(e) ? e : 'jpg';
  }

  static String _contentTypeForExt(String ext) {
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'jpg':
      case 'jpeg':
      default:
        return 'image/jpeg';
    }
  }

  static String _normalizeFolder(String? folder) {
    switch (folder) {
      case 'backgrounds':
      case 'exports':
        return folder!;
      default:
        return 'backgrounds';
    }
  }

  static void _assertUserId(String userId) {
    if (userId.isEmpty || userId.contains('/')) {
      throw 'userId non valido per il path Storage';
    }
  }

  /// Upload generico in:
  ///   hinoo/<userId>/<folder>/<uuid>.<ext>
  static Future<String> uploadBytes({
    required Uint8List bytes,
    required String filenameExt, // es: "jpg" | "png" | "webp" | "jpeg"
    required String userId,
    String folder = 'backgrounds', // default sicuro
    Duration? writeTimeout,
  }) async {
    _assertUserId(userId);
    final safeExt = _normalizeExt(filenameExt);
    final safeFolder = _normalizeFolder(folder);

    final id = _uuid.v4();
    final path = '$userId/$safeFolder/$id.$safeExt';

    final reliability = writeTimeout == null
        ? _reliability
        : ReliabilityPolicy(writeTimeout: writeTimeout);
    await reliability.write(
      () => _client.storage
          .from(bucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              upsert: false,
              // storage_client sends this as a multipart field and Supabase
              // expects seconds only (not a complete HTTP Cache-Control value).
              cacheControl: '31536000',
              contentType: _contentTypeForExt(safeExt),
            ),
          ),
    );

    return _client.storage.from(bucket).getPublicUrl(path);
  }

  /// Sfondi → hinoo/<userId>/backgrounds/<uuid>.<ext>
  static Future<String> uploadBackground({
    required Uint8List bytes,
    required String ext,
    required String userId,
    Duration? writeTimeout,
  }) {
    return uploadBytes(
      bytes: bytes,
      filenameExt: ext,
      userId: userId,
      folder: 'backgrounds',
      writeTimeout: writeTimeout,
    );
  }

  /// Removes a background returned by [uploadBackground].
  static Future<void> deleteBackgroundUrl({
    required String url,
    required String userId,
  }) async {
    _assertUserId(userId);
    final uri = Uri.tryParse(url);
    if (uri == null) throw const FormatException('URL Storage non valido');
    final segments = uri.pathSegments;
    final marker = segments.indexOf('public');
    if (marker < 0 ||
        marker + 2 >= segments.length ||
        segments[marker + 1] != bucket) {
      throw const FormatException('URL Storage non riconosciuto');
    }
    final path = segments.skip(marker + 2).join('/');
    if (!path.startsWith('$userId/backgrounds/')) {
      throw const FormatException('Percorso Storage non autorizzato');
    }
    await _reliability.write(
      () => _client.storage.from(bucket).remove([path]),
    );
  }

  /// Export PNG → hinoo/<userId>/exports/<uuid>.png
  static Future<String> uploadExportPng({
    required Uint8List pngBytes,
    required String userId,
  }) {
    return uploadBytes(
      bytes: pngBytes,
      filenameExt: 'png',
      userId: userId,
      folder: 'exports',
    );
  }
}

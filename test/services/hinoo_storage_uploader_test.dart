import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:honoo/Services/hinoo_storage_uploader.dart';

/// Mocks per supabase_flutter ^1.10.x
class _MockSupabaseClient extends Mock implements SupabaseClient {}

class _MockStorageClient extends Mock implements SupabaseStorageClient {}

class _MockFileApi extends Mock implements StorageFileApi {}

void main() {
  late _MockSupabaseClient client;
  late _MockStorageClient storage;
  late _MockFileApi fileApi;

  setUpAll(() {
    // Fallback per matcher su tipi posizionali/named
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(const FileOptions());
  });

  setUp(() {
    client = _MockSupabaseClient();
    storage = _MockStorageClient();
    fileApi = _MockFileApi();

    // Inietta il client mock nell'uploader
    HinooStorageUploader.$setTestClient(client);

    // catena: client.storage -> storage ; storage.from('hinoo') -> fileApi
    when(() => client.storage).thenReturn(storage);
    when(() => storage.from('hinoo')).thenReturn(fileApi);

    // Stub base (asincrono → thenAnswer)
    when(() => fileApi.uploadBinary(
          any(), // path
          any<Uint8List>(), // file
          fileOptions: any(named: 'fileOptions'),
        )).thenAnswer((_) async => 'ignored-path-returned-by-upload');
    when(() => fileApi.getPublicUrl(any()))
        .thenReturn('https://cdn.example.com/hinoo/mock-url.png');
    when(() => fileApi.remove(any())).thenAnswer((_) async => []);
  });

  tearDown(() {
    HinooStorageUploader.$setTestClient(null);
  });

  test('uploadExportPng: usa folder exports e ritorna un URL pubblico',
      () async {
    final bytes = Uint8List.fromList([137, 80, 78, 71]); // header PNG

    final url = await HinooStorageUploader.uploadExportPng(
      pngBytes: bytes,
      userId: 'u1',
    );

    expect(url, contains('https://cdn.example.com/hinoo/'));

    final captured = verify(() => fileApi.uploadBinary(
          captureAny(), // path
          any<Uint8List>(),
          fileOptions: captureAny(named: 'fileOptions'),
        )).captured;

    final String path = captured.first as String;
    final options = captured.last as FileOptions;
    // path = u1/exports/<uuid>.png
    expect(path, allOf([contains('u1/exports/'), endsWith('.png')]));
    verify(() => fileApi.getPublicUrl(path)).called(1);

    expect(options.cacheControl, '31536000');
  });

  test(
      'uploadBackground: usa folder backgrounds e rispetta estensione (jpeg → jpg)',
      () async {
    when(() => fileApi.getPublicUrl(any()))
        .thenReturn('https://cdn.example.com/hinoo/bg.jpg');

    final url = await HinooStorageUploader.uploadBackground(
      bytes: Uint8List.fromList([1, 2, 3]),
      ext: 'jpeg', // deve essere normalizzato in 'jpg'
      userId: 'u2',
    );

    expect(url, endsWith('.jpg'));

    final captured = verify(() => fileApi.uploadBinary(
          captureAny(),
          any<Uint8List>(),
          fileOptions: any(named: 'fileOptions', that: isA<FileOptions>()),
        )).captured;

    final String path = captured.first as String;
    expect(path, allOf([contains('u2/backgrounds/'), endsWith('.jpg')]));
    verify(() => fileApi.getPublicUrl(path)).called(1);
  });

  test('uploadBackground accetta un timeout esteso per la casa', () async {
    when(() => fileApi.uploadBinary(
          any(),
          any<Uint8List>(),
          fileOptions: any(named: 'fileOptions'),
        )).thenAnswer((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      return 'slow-house-upload';
    });

    final url = await HinooStorageUploader.uploadBackground(
      bytes: Uint8List.fromList([1, 2, 3]),
      ext: 'png',
      userId: 'u-house',
      writeTimeout: const Duration(milliseconds: 100),
    );

    expect(url, 'https://cdn.example.com/hinoo/mock-url.png');
  });

  test(
      'uploadBytes: folder custom e normalizzazione estensioni non permesse → jpg',
      () async {
    when(() => fileApi.getPublicUrl(any()))
        .thenReturn('https://cdn.example.com/hinoo/custom.jpg');

    final url = await HinooStorageUploader.uploadBytes(
      bytes: Uint8List.fromList([9, 9]),
      filenameExt: 'tiff', // non ammesso → forzato a 'jpg'
      userId: 'u3',
      folder: 'backgrounds',
    );

    expect(url, endsWith('.jpg'));

    final captured = verify(() => fileApi.uploadBinary(
          captureAny(),
          any<Uint8List>(),
          fileOptions: any(named: 'fileOptions', that: isA<FileOptions>()),
        )).captured;

    final String path = captured.first as String;
    expect(path, allOf([contains('u3/backgrounds/'), endsWith('.jpg')]));
    verify(() => fileApi.getPublicUrl(path)).called(1);
  });

  test('uploadBytes: userId non valido → lancia', () async {
    expect(
      () => HinooStorageUploader.uploadBytes(
        bytes: Uint8List.fromList([0]),
        filenameExt: 'png',
        userId: 'invalid/user', // contiene '/'
      ),
      throwsA(isA<String>()),
    );
    verifyNever(() => fileApi.uploadBinary(any(), any(),
        fileOptions: any(named: 'fileOptions')));
  });

  test('deleteBackgroundUrl rimuove soltanto il file dello stesso utente',
      () async {
    const url = 'https://project.supabase.co/storage/v1/object/public/'
        'hinoo/u1/backgrounds/image.png';

    await HinooStorageUploader.deleteBackgroundUrl(url: url, userId: 'u1');

    verify(() => fileApi.remove(['u1/backgrounds/image.png'])).called(1);
  });

  test('deleteBackgroundUrl rifiuta il percorso di un altro utente',
      () async {
    const url = 'https://project.supabase.co/storage/v1/object/public/'
        'hinoo/u2/backgrounds/image.png';

    await expectLater(
      HinooStorageUploader.deleteBackgroundUrl(url: url, userId: 'u1'),
      throwsFormatException,
    );
    verifyNever(() => fileApi.remove(any()));
  });
}

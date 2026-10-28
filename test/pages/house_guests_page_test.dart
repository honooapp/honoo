import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:honoo/Widgets/smooth_image.dart';
import 'package:honoo/Entities/casa_share_mode.dart';
import 'package:honoo/Entities/hinoo.dart';
import 'package:honoo/Entities/honoo.dart';
import 'package:honoo/Pages/house_guests_page.dart';
import 'package:honoo/Services/house_guests_service.dart';
import 'package:mocktail/mocktail.dart';
import '../test_supabase_helper.dart';

class _Guests extends Mock implements HouseGuestsService {}

class _ImageClient extends Mock implements HttpClient {}

class _ImageRequest extends Mock implements HttpClientRequest {}

class _ImageHeaders extends Mock implements HttpHeaders {}

class _ImageResponse extends Mock implements HttpClientResponse {
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEUlEQVR4nGNQaPj/H4QZYAwAWBIKeSZb5REAAAAASUVORK5CYII=',
    ),
  ).listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);
}

class _ImageOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = _ImageClient();
    final request = _ImageRequest();
    final response = _ImageResponse();
    when(() => client.getUrl(any())).thenAnswer((_) async => request);
    when(() => request.headers).thenReturn(_ImageHeaders());
    when(() => request.close()).thenAnswer((_) async => response);
    when(() => response.statusCode).thenReturn(HttpStatus.ok);
    when(() => response.contentLength).thenReturn(-1);
    when(
      () => response.compressionState,
    ).thenReturn(HttpClientResponseCompressionState.notCompressed);
    return client;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ByteData fontManifest;
  late ByteData testFont;
  setUpAll(() async {
    // Use a bundled font for offline rendering; typography is asserted separately.
    testFont = await rootBundle.load('assets/google_fonts/Arvo-Regular.ttf');
    const codec = StandardMessageCodec();
    final manifest = Map<Object?, Object?>.from(
      codec.decodeMessage(await rootBundle.load('AssetManifest.bin')) as Map,
    );
    for (final family in ['LibreFranklin-SemiBold', 'Lora-Regular']) {
      final path = 'test_fonts/$family.ttf';
      manifest[path] = [
        <String, Object>{'asset': path},
      ];
    }
    fontManifest = codec.encodeMessage(manifest)!;
    GoogleFonts.config.allowRuntimeFetching = false;
    registerSupabaseFallbacks();
    registerFallbackValue(Uri.parse('https://example.test'));
    registerFallbackValue(<CasaShareMode>{});
  });
  setUp(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMessageHandler('flutter/assets', (message) {
      final asset = utf8.decode(
        message!.buffer.asUint8List(
          message.offsetInBytes,
          message.lengthInBytes,
        ),
      );
      if (asset == 'AssetManifest.bin') return Future.value(fontManifest);
      if (asset.startsWith('test_fonts/')) return Future.value(testFont);
      return messenger.delegate.send('flutter/assets', message);
    });
  });
  for (final size in [const Size(320, 640), const Size(1440, 900)]) {
    testWidgets('ospiti: layout e revoca/riattivazione a $size', (
      tester,
    ) async {
      final previousOverrides = HttpOverrides.current;
      HttpOverrides.global = _ImageOverrides();
      addTearDown(() => HttpOverrides.global = previousOverrides);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final harness = SupabaseTestHarness(withAuthenticatedUser: true)
        ..enableOverrides();
      addTearDown(harness.disableOverrides);
      final service = _Guests();
      when(() => service.fetch('house')).thenAnswer(
        (_) async => [
          HouseGuest(
            id: '1',
            modes: {CasaShareMode.home},
            honoo: Honoo.fromMap({
              'id': 'honoo',
              'text': 'La mia bussata',
              'image_url': 'https://example.test/honoo.png',
              'user_id': 'guest',
            }),
          ),
          const HouseGuest(
            id: '2',
            modes: {},
            hinoo: HinooDraft(
              pages: [
                HinooSlide(
                  text: 'Un hinoo per entrare',
                  backgroundImage: 'https://example.test/hinoo.png',
                  isTextWhite: true,
                ),
              ],
            ),
          ),
        ],
      );
      when(() => service.update('1', any())).thenAnswer((_) async {});
      await tester.pumpWidget(
        MaterialApp(
          home: HouseGuestsPage(houseTag: 'house', service: service),
        ),
      );
      await tester.pumpAndSettle();
      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.centerTitle, isTrue);
      final title = tester.widget<Text>(find.text('ospiti'));
      expect(title.style?.fontFamily, startsWith('LibreFranklin'));
      expect(
        tester.getCenter(find.text('ospiti')).dx,
        closeTo(size.width / 2, 1),
      );
      final back = tester.widget<IconButton>(
        find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == 'Indietro',
        ),
      );
      expect(
        (back.icon as SvgPicture).bytesLoader,
        isA<SvgAssetLoader>().having(
          (l) => l.assetName,
          'asset',
          'assets/icons/arrow_left.svg',
        ),
      );
      expect(find.text('La mia bussata', findRichText: true), findsOneWidget);
      expect(
        find.text('Un hinoo per entrare', findRichText: true),
        findsOneWidget,
      );
      final previews = tester.widgetList<SmoothImage>(find.byType(SmoothImage));
      expect(
        previews.map((p) => (p.image as NetworkImage).url),
        containsAll([
          'https://example.test/honoo.png',
          'https://example.test/hinoo.png',
        ]),
      );
      await tester.runAsync(() async {
        for (final image in tester.widgetList<Image>(find.byType(Image))) {
          await precacheImage(
            image.image,
            tester.element(find.byType(HouseGuestsPage)),
          );
        }
      });
      await tester.pumpAndSettle();
      expect(find.byType(RawImage), findsWidgets);
      expect(
        tester
            .widgetList<RawImage>(find.byType(RawImage))
            .where((image) => image.image != null)
            .length,
        greaterThanOrEqualTo(2),
      );
      expect(find.byTooltip('Riprova a caricare l’immagine'), findsNothing);
      final home = find.byKey(const ValueKey('guest-1-home'));
      final moon = find.byKey(const ValueKey('guest-1-moon'));
      final all = find.byKey(const ValueKey('guest-1-all'));
      expect(tester.getCenter(home).dy, tester.getCenter(moon).dy);
      expect(tester.getCenter(home).dy, tester.getCenter(all).dy);
      expect(find.byTooltip('Revoca: honoo e hinoo di casa'), findsOneWidget);
      await tester.tap(home);
      await tester.pumpAndSettle();
      verify(() => service.update('1', <CasaShareMode>{})).called(1);
      expect(home, findsOneWidget); // Remains manageable after full revocation.
      expect(find.byTooltip('Revoca: honoo e hinoo di casa'), findsNothing);
      await tester.tap(home);
      await tester.pumpAndSettle();
      verify(() => service.update('1', {CasaShareMode.home})).called(1);
      expect(find.byTooltip('Revoca: honoo e hinoo di casa'), findsOneWidget);
      expect(tester.takeException(), isNull);
      when(() => service.update('1', any())).thenThrow(StateError('offline'));
      await tester.tap(home);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Revoca: honoo e hinoo di casa'), findsOneWidget);
    });
  }
}

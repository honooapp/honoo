import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honoo/Pages/home_page.dart';
import 'package:honoo/IsolaDelleStorie/Pages/campanelli_page.dart';
import 'package:honoo/Pages/placeholder_page.dart';
import 'package:honoo/Services/home_service.dart';
import 'package:honoo/Utility/reply_notification_signal.dart';
import 'package:honoo/Widgets/sea_footer_bar.dart';
import 'package:mocktail/mocktail.dart';

import '../test_supabase_helper.dart';

class _ControlledHomeService extends HomeService {
  final List<Completer<int>> requests = [];

  @override
  Future<int> fetchUnreadReplyCount(String userId) {
    final request = Completer<int>();
    requests.add(request);
    return request.future;
  }

  @override
  Future<void> recordVisit() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SupabaseTestHarness harness;

  setUpAll(() async {
    registerSupabaseFallbacks();
    for (final entry in [
      (FontWeight.w400, 'Regular'),
      (FontWeight.w700, 'Bold'),
    ]) {
      final family = GoogleFonts.arvo(fontWeight: entry.$1).fontFamily!;
      await (FontLoader(family)..addFont(
            rootBundle.load('assets/google_fonts/Arvo-${entry.$2}.ttf'),
          ))
          .load();
    }
  });

  setUp(() {
    harness = SupabaseTestHarness();
    harness.enableOverrides();
    final visit = MockQueryChain();
    when(
      () => harness.client.rpc('increment_site_visit'),
    ).thenAnswer((_) => visit);
  });

  tearDown(() {
    harness.disableOverrides();
  });

  Future<void> pumpHomeAtSize(WidgetTester tester, Size size) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pump();
  }

  testWidgets('mantiene testo e azioni inline senza ridurre il carattere', (
    tester,
  ) async {
    await pumpHomeAtSize(tester, const Size(320, 500));

    final intro = find.byKey(const Key('home_intro_text'));
    expect(intro, findsOneWidget);
    expect(find.textContaining('Ti regaliamo la Luna'), findsOneWidget);
    expect(
      find.textContaining('È vero. Ma non per i poeti\nVuoi essere'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('home_island_followup_text')), findsOneWidget);
    final islandFollowupTransform = tester.widget<Transform>(
      find.byKey(const Key('home_island_followup_text_offset')),
    );
    expect(islandFollowupTransform.transform.getTranslation().y, -2);
    expect(find.textContaining('e vedi tutto'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsNothing);
    final introRect = tester.getRect(intro);
    expect(introRect.top, greaterThanOrEqualTo(52));
    expect(
      introRect.bottom,
      lessThanOrEqualTo(tester.view.physicalSize.height - 100),
    );
    expect(tester.widget<Text>(intro).textSpan!.style!.fontSize, 18);
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: intro, matching: find.byType(RichText)).first,
    );
    final length = paragraph.text.toPlainText().length;
    final boxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: length - 11, extentOffset: length),
    );
    expect(boxes, isNotEmpty);
    expect(
      paragraph.localToGlobal(Offset(0, boxes.last.bottom)).dy,
      lessThanOrEqualTo(tester.getRect(find.byType(SeaFooterBar)).top),
    );
    expect(
      find.ancestor(of: intro, matching: find.byType(FittedBox)),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('home_inline_bottle')), findsOneWidget);
    expect(find.byKey(const Key('home_inline_moon')), findsOneWidget);
    expect(find.byKey(const Key('home_inline_island')), findsOneWidget);
    expect(find.byKey(const Key('home_inline_honoo')), findsOneWidget);
    expect(find.byKey(const Key('home_bottle_leading_gap')), findsOneWidget);
    expect(find.byKey(const Key('home_moon_leading_gap')), findsOneWidget);
    expect(find.byKey(const Key('home_island_leading_gap')), findsOneWidget);
    expect(find.byKey(const Key('home_honoo_leading_gap')), findsOneWidget);

    for (final key in const [
      Key('home_bottle_leading_gap'),
      Key('home_moon_leading_gap'),
      Key('home_island_leading_gap'),
      Key('home_honoo_leading_gap'),
    ]) {
      expect(tester.getSize(find.byKey(key)).width, 8);
    }

    for (final entry in const [
      (Key('home_inline_bottle'), 42.0),
      (Key('home_inline_moon'), 28.0),
      (Key('home_inline_island'), 55.0),
    ]) {
      final key = entry.$1;
      final button = tester.widget<IconButton>(find.byKey(key));
      expect(button.onPressed, isNotNull);
      expect(button.constraints!.maxWidth, entry.$2);
      expect(button.constraints!.maxHeight, entry.$2);
    }

    final inlineHonooStyle = tester.widget<AnimatedDefaultTextStyle>(
      find.descendant(
        of: find.byKey(const Key('home_inline_honoo')),
        matching: find.byType(AnimatedDefaultTextStyle),
      ),
    );
    expect(inlineHonooStyle.style.fontSize, 23);

    await pumpHomeAtSize(tester, const Size(1440, 1000));

    expect(find.byKey(const Key('home_intro_text')), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsNothing);
    final desktopIntroRect = tester.getRect(intro);
    expect(desktopIntroRect.top, greaterThanOrEqualTo(52));
    expect(
      desktopIntroRect.bottom,
      lessThanOrEqualTo(tester.view.physicalSize.height - 100),
    );
    expect(tester.widget<Text>(intro).textSpan!.style!.fontSize, 18);
    expect(
      find.ancestor(of: intro, matching: find.byType(FittedBox)),
      findsNothing,
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final size in const [Size(320, 500), Size(1440, 1000)]) {
    testWidgets('casa sotto la Luna sopra le onde e accessi distinti a $size', (
      tester,
    ) async {
      await pumpHomeAtSize(tester, size);
      final house = find.byKey(const Key('home_house_entry'));
      final island = find.byKey(const Key('footer_island_entry'));
      expect(house.hitTestable(), findsOneWidget);
      expect(island.hitTestable(), findsOneWidget);
      final houseRect = tester.getRect(house);
      final islandRect = tester.getRect(island);
      expect(houseRect.center.dx, lessThan(islandRect.center.dx));
      expect(
        houseRect.bottom,
        closeTo(size.height - SeaFooterBar.height * 0.64, 0.01),
      );
      expect(houseRect.center.dx, closeTo(size.width >= 1200 ? 52 : 32, 0.01));
      expect(houseRect.left, greaterThanOrEqualTo(0));
      expect(houseRect.right, lessThanOrEqualTo(size.width));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('l icona casa apre l invito per chi non ha casa', (tester) async {
    final rpc = MockQueryChain()..queueResponse(const []);
    when(
      () => harness.client.rpc('get_public_admin_campanelli'),
    ).thenAnswer((_) => rpc);
    await pumpHomeAtSize(tester, const Size(320, 600));
    await tester.tap(find.byKey(const Key('home_house_entry')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<CampanelliPage>(find.byType(CampanelliPage)).openOwnHouse,
      isTrue,
    );
    expect(
      find.textContaining('Vuoi anche tu', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Clicca qui'), findsOneWidget);
  });

  testWidgets("la scritta honoo apre la placeholder page", (tester) async {
    await pumpHomeAtSize(tester, const Size(320, 600));

    await tester.ensureVisible(find.byKey(const Key('home_inline_honoo')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('home_inline_honoo')));
    await tester.pumpAndSettle();

    expect(find.byType(PlaceholderPage), findsOneWidget);
  });

  testWidgets('una risposta vecchia non ripristina il badge già azzerato', (
    tester,
  ) async {
    harness.disableOverrides();
    harness = SupabaseTestHarness(withAuthenticatedUser: true)
      ..enableOverrides();
    final service = _ControlledHomeService();

    await tester.pumpWidget(MaterialApp(home: HomePage(homeService: service)));
    await tester.pump();
    expect(service.requests, hasLength(1));

    ReplyNotificationSignal.notifyChanged();
    await tester.pump();
    expect(service.requests, hasLength(2));

    service.requests[1].complete(0);
    await tester.pump();
    service.requests[0].complete(3);
    await tester.pump();

    final footer = tester.widget<SeaFooterBar>(find.byType(SeaFooterBar));
    expect(footer.replyCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

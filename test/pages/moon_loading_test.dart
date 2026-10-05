import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:honoo/Pages/moon_page.dart';
import 'package:honoo/UI/honoo_card.dart';
import 'package:mocktail/mocktail.dart';
import '../test_supabase_helper.dart';
import '../pending_query.dart';

void main() {
  setUpAll(() {
    registerSupabaseFallbacks();
    GoogleFonts.config.allowRuntimeFetching = false;
  });
  late SupabaseTestHarness harness;
  setUp(() {
    harness = SupabaseTestHarness(withAuthenticatedUser: true)
      ..enableOverrides();
    when(
      () => harness.client.rpc('admin_is_admin'),
    ).thenAnswer((_) => MockQueryChain()..queueResponse(false));
  });
  tearDown(() => harness.disableOverrides());

  testWidgets('search opens the selected moon card, not the first', (
    tester,
  ) async {
    harness.stubTable('moon_public').queueResponse([
      for (var i = 0; i < 3; i++)
        {
          'id': 'item-$i',
          'kind': 'honoo',
          'text': 'Card $i',
          'image_url': '',
          'user_id': 'author',
          'created_at': '2026-09-${20 - i}T10:00:00Z',
        },
    ]);
    await tester.pumpWidget(
      const MaterialApp(home: MoonPage(initialItemId: 'item-2')),
    );
    await tester.pumpAndSettle();
    final carousel = tester.widget<CarouselSlider>(find.byType(CarouselSlider));
    expect(carousel.options.initialPage, 2);
    final pages = tester.widget<PageView>(
      find
          .descendant(
            of: find.byType(CarouselSlider),
            matching: find.byType(PageView),
          )
          .first,
    );
    expect(pages.controller!.page, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('delete keeps the card selected while the request is pending', (
    tester,
  ) async {
    when(
      () => harness.client.rpc('admin_is_admin'),
    ).thenAnswer((_) => MockQueryChain()..queueResponse(true));
    when(
      () => harness.client.rpc(
        'admin_moon_content_has_replies',
        params: any(named: 'params'),
      ),
    ).thenAnswer((_) => MockQueryChain()..queueResponse(false));
    final deletion = PendingQuery();
    when(
      () => harness.client.rpc(
        'admin_soft_delete_moon_content',
        params: any(named: 'params'),
      ),
    ).thenAnswer((_) => deletion);
    harness.stubTable('moon_public').queueResponse([
      for (var i = 0; i < 3; i++)
        {
          'id': 'item-$i',
          'kind': 'honoo',
          'text': 'Card $i',
          'image_url': '',
          'user_id': 'author',
          'created_at': '2026-09-${20 - i}T10:00:00Z',
        },
    ]);
    await tester.pumpWidget(const MaterialApp(home: MoonPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Elimina'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sì'));
    await tester.pumpAndSettle();
    tester
        .widget<PageView>(find.byType(PageView).first)
        .controller!
        .jumpToPage(1);
    await tester.pumpAndSettle();
    deletion.response.complete(null);
    await tester.pumpAndSettle();
    expect(
      tester.widget<CarouselSlider>(find.byType(CarouselSlider)).itemCount,
      2,
    );
    expect(
      find.byWidgetPredicate((w) => w is HonooCard && w.honoo.dbId == 'item-0'),
      findsNothing,
    );
    expect(
      find.byWidgetPredicate((w) => w is HonooCard && w.honoo.dbId == 'item-1'),
      findsOneWidget,
    );
    expect(
      tester.widget<PageView>(find.byType(PageView).first).controller!.page,
      0,
    );
    expect(tester.takeException(), isNull);
  });

  for (final fail in [false, true]) {
    testWidgets('leaving Moon before response is safe (failure: $fail)', (
      tester,
    ) async {
      final query = PendingQuery();
      when(() => harness.client.from('moon_public')).thenAnswer((_) => query);
      when(() => query.select(any())).thenAnswer((_) => query);
      when(
        () => query.order(any(), ascending: any(named: 'ascending')),
      ).thenAnswer((_) => query);
      await tester.pumpWidget(const MaterialApp(home: MoonPage()));
      await tester.pump();
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      if (fail) {
        query.response.completeError(StateError('network unavailable'));
      } else {
        query.response.complete([]);
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}

import 'dart:async';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:honoo/Pages/moon_page.dart';
import 'package:mocktail/mocktail.dart';
import '../test_supabase_helper.dart';

class PendingQuery extends MockQueryChain {
  final response = Completer<dynamic>();
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #then) {
      return response.future.then<dynamic>((value) {
        (invocation.positionalArguments.first as dynamic Function(dynamic))(
          value,
        );
        return null;
      }, onError: invocation.namedArguments[#onError]);
    }
    return super.noSuchMethod(invocation);
  }
}

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

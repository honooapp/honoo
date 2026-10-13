import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honoo/Entities/casa_share_mode.dart';
import 'package:honoo/Entities/hinoo.dart';
import 'package:honoo/Entities/honoo.dart';
import 'package:honoo/Pages/house_guests_page.dart';
import 'package:honoo/Services/house_guests_service.dart';
import 'package:mocktail/mocktail.dart';
import '../test_supabase_helper.dart';

class _Guests extends Mock implements HouseGuestsService {}

void main() {
  setUpAll(() {
    registerSupabaseFallbacks();
    registerFallbackValue(<CasaShareMode>{});
  });
  for (final size in [const Size(320, 640), const Size(1440, 900)]) {
    testWidgets('ospiti: layout e revoca/riattivazione a $size', (
      tester,
    ) async {
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
                  backgroundImage: '',
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

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honoo/IsolaDelleStorie/Pages/campanelli_page.dart';
import 'package:honoo/Pages/email_login_page.dart';
import 'package:honoo/Widgets/campanello_card.dart';
import 'package:honoo/Widgets/campanelli_footer.dart';
import 'package:honoo/Widgets/busy_overlay.dart';
import 'package:honoo/Widgets/casa_section.dart';
import 'package:mocktail/mocktail.dart';

import '../test_supabase_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(registerSupabaseFallbacks);

  late SupabaseTestHarness harness;

  setUp(() {
    harness = SupabaseTestHarness();
    harness.enableOverrides();
  });

  tearDown(() => harness.disableOverrides());

  testWidgets(
    'un ospite vede il link nella presentazione e i due admin in ordine',
    (tester) async {
      final rpc = MockQueryChain();
      rpc.queueResponse(const [
        {
          'admin_email': 'venceslao.cembalo@gmail.com',
          'campanello_hinoo_id': 'hinoo-venceslao',
          'owner_id': 'admin-venceslao',
          'house_image_url': null,
          'pages': [
            {
              'backgroundImage': null,
              'text': 'Campanello di Venceslao',
              'isTextWhite': true,
            },
          ],
        },
        {
          'admin_email': 'mariandreealavric@gmail.com',
          'campanello_hinoo_id': 'hinoo-mariandreea',
          'owner_id': 'admin-mariandreea',
          'house_image_url': null,
          'pages': [
            {
              'backgroundImage': null,
              'text': 'Campanello di Mari Andreea',
              'isTextWhite': false,
            },
          ],
        },
      ]);
      when(
        () => harness.client.rpc('get_public_admin_campanelli'),
      ).thenAnswer((_) => rpc);

      await tester.pumpWidget(const MaterialApp(home: CampanelliPage()));
      await tester.pumpAndSettle();

      CampanelloCard card = tester.widget(find.byType(CampanelloCard));
      expect(card.data.isIntro, isTrue);
      expect(
        card.data.text,
        contains('Vuoi anche tu\nla tua casa sull’Isola?\n\n\nClicca qui'),
      );

      await tester.tap(find.text('Clicca qui'));
      await tester.pumpAndSettle();
      expect(find.byType(EmailLoginPage), findsOneWidget);
      Navigator.of(tester.element(find.byType(EmailLoginPage))).pop();
      await tester.pumpAndSettle();

      await tester.drag(find.byType(CampanelloCard), const Offset(-500, 0));
      await tester.pumpAndSettle();
      card = tester.widget(find.byType(CampanelloCard));
      expect(card.data.campanello?.campanelloHinooId, 'hinoo-venceslao');
      expect(card.data.text, 'Campanello di Venceslao');
      expect(card.data.text, isNot(contains('Magari sono a casa')));

      await tester.drag(find.byType(CampanelloCard), const Offset(-500, 0));
      await tester.pumpAndSettle();
      card = tester.widget(find.byType(CampanelloCard));
      expect(card.data.campanello?.campanelloHinooId, 'hinoo-mariandreea');
      expect(card.data.text, 'Campanello di Mari Andreea');
      expect(card.data.text, isNot(contains('Magari sono sul terrazzo')));
    },
  );

  testWidgets(
    'un utente autenticato vede prima la presentazione e poi i campanelli',
    (tester) async {
      harness.disableOverrides();
      harness = SupabaseTestHarness(withAuthenticatedUser: true);
      harness.enableOverrides();

      final houses = harness.stubTable('case');
      final settings = harness.stubTable('house_share_settings');
      final hinoo = harness.stubTable('hinoo');
      final houseAccess = harness.stubTable('house_access');
      final houseInvites = harness.stubTable('house_invites');
      when(() => harness.user.email).thenReturn('utente@example.com');
      when(
        () => houseAccess.not('granted_at', 'is', null),
      ).thenAnswer((_) => houseAccess);

      houses.queueResponse(const [
        {
          'campanello_hinoo_id': 'newer',
          'owner_id': 'user-3',
          'created_at': '2026-08-03T10:00:00Z',
        },
        {
          'campanello_hinoo_id': 'owned',
          'owner_id': 'test_user',
          'created_at': '2026-08-04T10:00:00Z',
        },
        {
          'campanello_hinoo_id': 'older',
          'owner_id': 'user-2',
          'created_at': '2026-08-01T10:00:00Z',
        },
      ]);
      settings.queueResponse(const []);
      hinoo.queueResponse(const [
        {
          'id': 'newer',
          'pages': [
            {'text': 'Campanello più recente'},
          ],
        },
        {
          'id': 'owned',
          'pages': [
            {'text': 'Il mio campanello'},
          ],
        },
        {
          'id': 'older',
          'pages': [
            {'text': 'Campanello più vecchio'},
          ],
        },
      ]);
      houseAccess
        ..queueResponse(const [])
        ..queueResponse(const []);
      houseInvites.queueResponse(const []);

      await tester.pumpWidget(const MaterialApp(home: CampanelliPage()));
      await tester.pumpAndSettle();

      CampanelloCard card = tester.widget(find.byType(CampanelloCard));
      expect(card.data.isIntro, isTrue);

      await tester.drag(find.byType(CampanelloCard), const Offset(-500, 0));
      await tester.pumpAndSettle();
      card = tester.widget(find.byType(CampanelloCard));
      expect(card.data.text, 'Il mio campanello');

      await tester.drag(find.byType(CampanelloCard), const Offset(-500, 0));
      await tester.pumpAndSettle();
      card = tester.widget(find.byType(CampanelloCard));
      expect(card.data.text, 'Campanello più vecchio');

      // Nessun evento realtime: il proprietario può essere offline.
      tester.widget<CampanelliFooter>(find.byType(CampanelliFooter)).onKnock();
      await tester.pumpAndSettle();
      expect(find.byType(BusyOverlay), findsNothing);
      expect(find.textContaining('Bussata inviata.'), findsOneWidget);
      verify(() => houseAccess.insert(any())).called(1);

      // Recupera anche un permesso concesso mentre realtime era assente.
      houseAccess.queueResponse(const [
        {
          'target_house_tag': 'older',
          'share_modes': ['honoo'],
        },
      ]);
      await tester.pump(const Duration(seconds: 15));
      await tester.pumpAndSettle();
      tester.widget<CampanelliFooter>(find.byType(CampanelliFooter)).onKnock();
      await tester.pumpAndSettle();
      expect(find.text('Entra pure a casa mia'), findsOneWidget);
      await tester.tap(find.text('Non ora'));
      await tester.pumpAndSettle();

      // Una revoca successiva deve chiudere la casa anche senza riaprire la pagina.
      houseAccess.queueResponse(const []);
      await tester.pump(const Duration(seconds: 15));
      await tester.pumpAndSettle();
      tester.widget<CampanelliFooter>(find.byType(CampanelliFooter)).onKnock();
      await tester.pumpAndSettle();
      expect(find.text('Entra pure a casa mia'), findsNothing);
      verify(() => houseAccess.insert(any())).called(1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('dopo la modifica della casa resta sul campanello selezionato', (
    tester,
  ) async {
    harness.disableOverrides();
    harness = SupabaseTestHarness(withAuthenticatedUser: true);
    harness.enableOverrides();

    final houses = harness.stubTable('case');
    final settings = harness.stubTable('house_share_settings');
    final hinoo = harness.stubTable('hinoo');
    final houseAccess = harness.stubTable('house_access');
    final houseInvites = harness.stubTable('house_invites');
    when(() => harness.user.email).thenReturn('utente@example.com');
    when(
      () => houseAccess.not('granted_at', 'is', null),
    ).thenAnswer((_) => houseAccess);

    const houseRows = [
      {
        'campanello_hinoo_id': 'owned',
        'owner_id': 'test_user',
        'created_at': '2026-08-04T10:00:00Z',
      },
    ];
    const hinooRows = [
      {
        'id': 'owned',
        'pages': [
          {'text': 'Il mio campanello'},
        ],
      },
    ];
    houses
      ..queueResponse(houseRows)
      ..queueResponse(houseRows);
    settings
      ..queueResponse(const [])
      ..queueResponse(const []);
    hinoo
      ..queueResponse(hinooRows)
      ..queueResponse(hinooRows);
    houseAccess
      ..queueResponse(const [])
      ..queueResponse(const []);
    houseInvites
      ..queueResponse(const [])
      ..queueResponse(const []);

    await tester.pumpWidget(const MaterialApp(home: CampanelliPage()));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CampanelloCard), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(
      tester.widget<CampanelloCard>(find.byType(CampanelloCard)).data.text,
      'Il mio campanello',
    );

    await tester.drag(find.byType(CampanelloCard), const Offset(0, -900));
    await tester.pumpAndSettle();
    final houseContext = tester.element(find.byType(CasaSection));
    tester.widget<CasaSection>(find.byType(CasaSection)).onEditTap!();
    await tester.pump();
    Navigator.of(houseContext).pop(true);
    await tester.pumpAndSettle();

    await tester.drag(find.byType(CasaSection), const Offset(0, 900));
    await tester.pumpAndSettle();
    expect(
      tester.widget<CampanelloCard>(find.byType(CampanelloCard)).data.text,
      'Il mio campanello',
    );
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honoo/IsolaDelleStorie/Pages/campanelli_page.dart';
import 'package:honoo/Pages/email_login_page.dart';
import 'package:honoo/Widgets/campanello_card.dart';
import 'package:honoo/Widgets/campanelli_footer.dart';
import 'package:honoo/Widgets/busy_overlay.dart';
import 'package:honoo/Pages/new_honoo_page.dart';
import 'package:honoo/Pages/new_hinoo_page.dart';
import 'package:honoo/Entities/honoo.dart';
import 'package:honoo/Entities/hinoo.dart';
import 'package:honoo/Services/honoo_service.dart';
import 'package:honoo/Services/hinoo_service.dart';
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

      // Esegue i publisher reali con i parametri ricevuti dai due editor.
      final honoo = harness.stubTable('honoo');
      String? previousConversationId;
      for (final isHonoo in [true, false]) {
        tester
            .widget<CampanelliFooter>(find.byType(CampanelliFooter))
            .onKnock();
        await tester.pumpAndSettle();
        expect(find.byType(BusyOverlay), findsNothing);
        verifyNever(() => houseAccess.insert(any()));
        await tester.tap(
          find.text(isHonoo ? 'Invia un honoo' : 'Invia un hinoo'),
        );
        await tester.pumpAndSettle();

        final String? replyTo;
        final String? recipientTag;
        final String? conversationId;
        final String savedId;
        final MockQueryChain contentTable;
        final Finder editor;
        if (isHonoo) {
          editor = find.byType(NewHonooPage);
          final composer = tester.widget<NewHonooPage>(editor);
          expect(composer.returnSavedId, isTrue);
          replyTo = composer.replyTo;
          recipientTag = composer.recipientTag;
          conversationId = composer.conversationId;
          contentTable = honoo;
          honoo.queueResponse({'id': 'sent-honoo'});
          final content = Honoo(
            0,
            'Busso alla tua casa',
            'bg.png',
            '',
            '',
            'test_user',
            composer.forcedType!,
            replyTo,
            recipientTag,
          )..conversationId = conversationId;
          savedId = await HonooService.publishHonooAndReturnId(content);
        } else {
          editor = find.byType(NewHinooPage);
          final composer = tester.widget<NewHinooPage>(editor);
          expect(composer.returnSavedId, isTrue);
          replyTo = composer.replyTo;
          recipientTag = composer.recipientTag;
          conversationId = composer.conversationId;
          contentTable = hinoo;
          hinoo.queueResponse({'id': 'sent-hinoo'});
          savedId = await HinooService.publishHinooAndReturnId(
            HinooDraft(
              pages: const [
                HinooSlide(
                  text: 'Busso alla tua casa',
                  backgroundImage: 'bg.png',
                  isTextWhite: true,
                ),
              ],
              type: composer.forcedType!,
              replyTo: replyTo,
              recipientTag: recipientTag,
              conversationId: conversationId,
            ),
          );
        }
        expect(replyTo, 'older');
        expect(recipientTag, 'older');
        expect(conversationId, isNotNull);
        expect(conversationId, isNot(isEmpty));
        expect(conversationId, isNot(previousConversationId));
        previousConversationId = conversationId;
        final payload =
            verify(() => contentTable.insert(captureAny())).captured.single
                as Map<String, dynamic>;
        expect(payload['reply_to'], 'older');
        expect(payload['recipient_tag'], 'older');
        expect(payload['conversation_id'], conversationId);
        Navigator.of(tester.element(editor)).pop(savedId);
        await tester.pumpAndSettle();
        expect(find.textContaining('Bussata inviata.'), findsOneWidget);
        Navigator.of(
          tester.element(find.textContaining('Bussata inviata.')),
        ).pop();
        await tester.pumpAndSettle();
        final knock =
            verify(() => houseAccess.insert(captureAny())).captured.single
                as Map<String, dynamic>;
        expect(knock[isHonoo ? 'honoo_id' : 'hinoo_id'], savedId);
      }

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
      expect(find.text('Invia un honoo'), findsOneWidget);
      verifyNever(() => houseAccess.insert(any()));
      await tester.tap(find.text('Annulla'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('dalla home apre direttamente la propria casa con lo Scrigno', (
    tester,
  ) async {
    harness.disableOverrides();
    harness = SupabaseTestHarness(withAuthenticatedUser: true)
      ..enableOverrides();
    harness.stubTable('case').queueResponse(const [
      {
        'campanello_hinoo_id': 'owned',
        'owner_id': 'test_user',
        'house_text': 'La mia casa',
      },
    ]);
    harness.stubTable('house_share_settings').queueResponse(const []);
    harness.stubTable('hinoo').queueResponse(const [
      {
        'id': 'owned',
        'pages': [
          {'text': 'Il mio campanello'},
        ],
      },
    ]);
    final access = harness.stubTable('house_access');
    when(() => access.not('granted_at', 'is', null)).thenAnswer((_) => access);
    access
      ..queueResponse(const [])
      ..queueResponse(const []);
    harness.stubTable('house_invites').queueResponse(const []);
    await tester.pumpWidget(
      const MaterialApp(home: CampanelliPage(openOwnHouse: true)),
    );
    await tester.pumpAndSettle();
    final casa = tester.widget<CasaSection>(find.byType(CasaSection));
    expect(casa.isUnlocked, isTrue);
    expect(casa.onGuestsTap, isNotNull);
    expect(casa.onScrignoTap, isNotNull);
    expect(find.byKey(const ValueKey('house-chest')), findsOneWidget);
    expect(find.text('Clicca qui'), findsNothing);
  });

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

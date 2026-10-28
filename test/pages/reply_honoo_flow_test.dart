import 'package:shared_preferences/shared_preferences.dart';
import 'package:honoo/Services/reply_draft_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:honoo/Pages/chest_page.dart';
import 'package:honoo/Pages/reply_honoo_page.dart';
import 'package:honoo/Entities/honoo.dart';
import 'package:honoo/Entities/reply_navigation_result.dart';
import 'package:honoo/UI/honoo_builder.dart';
import 'package:honoo/Widgets/honoo_dialogs.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sizer/sizer.dart';

import '../test_supabase_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SupabaseTestHarness harness;

  setUpAll(registerSupabaseFallbacks);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    harness = SupabaseTestHarness(withAuthenticatedUser: true);
    harness.enableOverrides();
    final honoo = harness.stubTable('honoo');
    honoo.queueResponse(<String, dynamic>{'id': 'reply-1'});
    final hinoo = harness.stubTable('hinoo');
    when(() => honoo.neq(any(), any())).thenAnswer((_) => honoo);
    when(() => hinoo.neq(any(), any())).thenAnswer((_) => hinoo);
    final visit = MockQueryChain();
    when(
      () => harness.client.rpc('increment_site_visit'),
    ).thenAnswer((_) => visit);
  });

  tearDown(() {
    harness.disableOverrides();
  });

  testWidgets('recupera il testo della bozza dopo la riapertura', (
    tester,
  ) async {
    final original = Honoo(
      1,
      'origine',
      '',
      '',
      '',
      'other',
      HonooType.personal,
    );
    Widget page() => Sizer(
      builder: (_, _, _) =>
          MaterialApp(home: ReplyHonooPage(originalHonoo: original)),
    );
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    tester.widget<HonooBuilder>(find.byType(HonooBuilder)).onHonooChanged!(
      'bozza recuperabile',
      '',
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    final builder = tester.widget<HonooBuilder>(find.byType(HonooBuilder));
    expect(builder.initialText, 'bozza recuperabile');
    expect(builder.initialImageUrl, '');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('riapertura invio incerto riutilizza id e conversazione', (
    tester,
  ) async {
    await ReplyDraftStore('test_user', '1').save({
      'text': 'risposta',
      'image': '',
      'requestId': '11111111-1111-4111-8111-111111111111',
      'conversationId': 'existing-conversation',
      'recipientId': 'other',
    });
    final original = Honoo(
      1,
      'origine',
      '',
      '',
      '',
      'other',
      HonooType.personal,
    );
    await tester.pumpWidget(
      Sizer(
        builder: (_, _, _) =>
            MaterialApp(home: ReplyHonooPage(originalHonoo: original)),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Invio da confermare. Riprova per verificarlo.'),
      findsOneWidget,
    );
    await tester.tap(find.bySemanticsLabel('Invia risposta'));
    await tester.pumpAndSettle();
    final chain = harness.client.from('honoo');
    final payload =
        verify(() => chain.insert(captureAny())).captured.single as Map;
    expect(payload['id'], '11111111-1111-4111-8111-111111111111');
    expect(payload['conversation_id'], 'existing-conversation');
    expect(await ReplyDraftStore('test_user', '1').load(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'ReplyHonooPage mantiene le dimensioni quando si apre la tastiera',
    (tester) async {
      final original = Honoo(
        1,
        '“Testo origine”',
        '',
        '2024-01-01T00:00:00Z',
        '2024-01-01T00:00:00Z',
        'user_1',
        HonooType.moon,
      );

      await tester.pumpWidget(
        Sizer(
          builder: (context, orientation, deviceType) {
            return MaterialApp(home: ReplyHonooPage(originalHonoo: original));
          },
        ),
      );
      await tester.pumpAndSettle();

      final builder = find.byType(HonooBuilder);
      expect(find.bySemanticsLabel('Indietro'), findsNothing);
      final sizeBeforeKeyboard = tester.getSize(builder);

      await tester.tap(find.byType(TextField).first);
      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      await tester.pump();

      expect(tester.getSize(builder), sizeBeforeKeyboard);
    },
  );

  testWidgets(
    'ReplyHonooPage: dopo la conferma apre la conversazione nello Scrigno',
    (tester) async {
      final original = Honoo(
        1,
        '“Testo origine”',
        '',
        '2024-01-01T00:00:00Z',
        '2024-01-01T00:00:00Z',
        'user_1',
        HonooType.personal,
      );

      await tester.pumpWidget(
        Sizer(
          builder: (context, orientation, deviceType) {
            return MaterialApp(home: ReplyHonooPage(originalHonoo: original));
          },
        ),
      );
      await tester.pumpAndSettle();

      final tf = find.byType(TextField).first;
      expect(tf, findsOneWidget);

      await tester.enterText(tf, '-- risposta ... << prova >>\n');
      await tester.pump();

      expect(
        tester.widget<TextField>(tf).controller?.text,
        '— risposta … « prova »\n',
      );

      final sendButton = find.bySemanticsLabel('Invia risposta');
      expect(sendButton, findsNothing);
      expect(find.byKey(const Key('honoo-save')), findsOneWidget);
      await tester.tap(find.byKey(const Key('honoo-save')));
      await tester.pump();
      expect(sendButton, findsOneWidget);

      await tester.enterText(tf, 'risposta modificata');
      await tester.pump();
      expect(sendButton, findsNothing);
      expect(find.byKey(const Key('honoo-save')), findsOneWidget);
      await tester.tap(find.byKey(const Key('honoo-save')));
      await tester.pump();
      expect(sendButton, findsOneWidget);

      await tester.tap(sendButton);
      await tester.pump();
      await tester.pump();

      expect(find.byType(HonooMessageDialog), findsOneWidget);
      expect(
        find.text(
          'Il tuo honoo è nel tuo Scrigno,\n'
          'ma soprattutto,\n'
          'in quello di qualcun altro',
        ),
        findsOneWidget,
      );
      Navigator.of(
        tester.element(find.byType(HonooMessageDialog)),
        rootNavigator: true,
      ).pop();
      await tester.pumpAndSettle();

      expect(find.byType(ChestPage), findsOneWidget);
      expect(find.byType(ReplyHonooPage), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 25));
    },
  );

  testWidgets(
    'ReplyHonooPage: nello Scrigno restituisce la conversazione aggiornata',
    (tester) async {
      final result = ValueNotifier<ReplyNavigationResult?>(null);
      final original = Honoo(
        1,
        '“Testo origine”',
        '',
        '2024-01-01T00:00:00Z',
        '2024-01-01T00:00:00Z',
        'user_1',
        HonooType.personal,
      );

      await tester.pumpWidget(
        Sizer(
          builder: (context, orientation, deviceType) {
            return MaterialApp(
              home: Builder(
                builder: (context) => Scaffold(
                  body: ElevatedButton(
                    onPressed: () async {
                      result.value = await Navigator.of(context)
                          .push<ReplyNavigationResult>(
                            MaterialPageRoute(
                              builder: (_) => ReplyHonooPage(
                                originalHonoo: original,
                                returnToPreviousOnAnswer: true,
                              ),
                            ),
                          );
                    },
                    child: const Text('Rispondi'),
                  ),
                ),
              ),
            );
          },
        ),
      );

      await tester.tap(find.text('Rispondi'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'risposta');
      expect(find.bySemanticsLabel('Invia risposta'), findsNothing);
      await tester.tap(find.byKey(const Key('honoo-save')));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Invia risposta'));
      await tester.pump();
      await tester.pump();

      Navigator.of(
        tester.element(find.byType(HonooMessageDialog)),
        rootNavigator: true,
      ).pop();
      await tester.pumpAndSettle();

      expect(result.value?.conversationId, '1');
      expect(result.value?.replyId, matches(RegExp(r'^[0-9a-f-]{36}$')));
      expect(find.byType(ReplyHonooPage), findsNothing);
      expect(find.text('Rispondi'), findsOneWidget);
    },
  );
}

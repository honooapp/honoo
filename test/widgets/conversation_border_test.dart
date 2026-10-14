import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honoo/Entities/hinoo.dart';
import 'package:honoo/Entities/honoo.dart';
import 'package:honoo/Entities/conversation_entry.dart';
import 'package:honoo/UI/hinoo_viewer.dart';
import 'package:honoo/UI/honoo_card.dart';
import 'package:honoo/Utility/honoo_colors.dart';
import 'package:honoo/Utility/chest_content_style.dart';

import '../test_supabase_helper.dart';

void main() {
  setUpAll(registerSupabaseFallbacks);

  late SupabaseTestHarness harness;

  setUp(() {
    harness = SupabaseTestHarness(withAuthenticatedUser: true)
      ..enableOverrides();
  });

  tearDown(() {
    harness.disableOverrides();
  });

  Finder borderWithColor(Color color) => find.byWidgetPredicate((widget) {
    final Decoration? decoration = switch (widget) {
      Container(:final decoration) => decoration,
      DecoratedBox(:final decoration) => decoration,
      _ => null,
    };
    if (decoration is! BoxDecoration) return false;
    final border = decoration.border;
    return border is Border &&
        border.top.color == color &&
        border.right.color == color &&
        border.bottom.color == color &&
        border.left.color == color &&
        border.top.width == 6;
  });

  Honoo honoo({
    required HonooType type,
    String owner = 'other_user',
    bool fromMoon = false,
  }) {
    return Honoo(
      0,
      'Test conversazione',
      '',
      '2026-07-18T10:00:00Z',
      '2026-07-18T10:00:00Z',
      owner,
      type,
    )..isFromMoonSaved = fromMoon;
  }

  HinooDraft hinoo({bool fromMoon = false}) => HinooDraft(
    pages: const [
      HinooSlide(
        backgroundImage: null,
        text: 'Test conversazione',
        isTextWhite: true,
      ),
    ],
    type: HinooType.personal,
    isFromMoonSaved: fromMoon,
  );

  Future<void> pumpHonoo(
    WidgetTester tester,
    Honoo value, {
    ChestContentStyle? contentStyleOverride,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 500,
            height: 750,
            child: HonooCard(
              honoo: value,
              contentStyleOverride: contentStyleOverride,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> pumpHinoo(
    WidgetTester tester, {
    required HinooDraft draft,
    required bool isReply,
    required String authorId,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HinooViewer(
            draft: draft,
            maxWidth: 500,
            maxHeight: 750,
            isReply: isReply,
            authorId: authorId,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('Honoo di risposta proprio resta blu e non ha cornice', (
    tester,
  ) async {
    final value = honoo(
      type: HonooType.answer,
      owner: 'test_user',
      fromMoon: true,
    );
    await pumpHonoo(tester, value);

    expect(
      ChestContentStyle.forHonoo(value, viewerUserId: 'test_user'),
      same(ChestContentStyle.own),
    );
    final ownGap = tester.widget<ColoredBox>(
      find.byKey(const Key('honoo-card-gap')),
    );
    expect(ownGap.color, HonooColor.background);
    expect(borderWithColor(HonooColor.secondary), findsNothing);
    expect(borderWithColor(Colors.white), findsNothing);
  });

  testWidgets('Honoo ricevuto usa sfondo esterno rosso e box testo bianco', (
    tester,
  ) async {
    final value = honoo(type: HonooType.answer);
    await pumpHonoo(tester, value);

    expect(
      ChestContentStyle.forHonoo(value, viewerUserId: 'test_user'),
      same(ChestContentStyle.receivedReply),
    );
    final textPanel = tester.widget<Container>(
      find.byKey(const Key('honoo-card-text-panel')),
    );
    expect((textPanel.decoration! as BoxDecoration).color, Colors.white);
    final replyText = tester.widget<Text>(find.text('Test conversazione'));
    expect(replyText.style?.color, Colors.black);
    expect(borderWithColor(HonooColor.secondary), findsNothing);
    expect(borderWithColor(Colors.white), findsNothing);
  });

  testWidgets('Honoo salvato dalla Luna usa sfondo bianco e non ha cornice', (
    tester,
  ) async {
    final value = honoo(
      type: HonooType.personal,
      owner: 'test_user',
      fromMoon: true,
    );
    await pumpHonoo(tester, value);

    expect(
      ChestContentStyle.forHonoo(value, viewerUserId: 'test_user'),
      same(ChestContentStyle.moon),
    );
    expect(borderWithColor(Colors.white), findsNothing);
    expect(borderWithColor(HonooColor.secondary), findsNothing);
  });

  test('Honoo salvato dalla Luna resta bianco nella conversazione', () {
    final value = honoo(
      type: HonooType.personal,
      owner: 'test_user',
      fromMoon: true,
    );

    expect(
      ChestContentStyle.forConversationEntry(
        ConversationEntry.honoo(value),
        viewerUserId: 'test_user',
      ),
      same(ChestContentStyle.moon),
    );
  });

  test(
    'Hinoo salvato dalla Luna resta bianco anche se attribuito ad altri',
    () {
      final draft = hinoo().copyWith(isFromMoonSaved: true);
      expect(
        ChestContentStyle.forConversationEntry(
          ConversationEntry.hinoo(
            draft,
            createdAt: DateTime.utc(2026, 10, 14),
            ownerId: 'other_user',
            isFromMoonSaved: true,
          ),
          viewerUserId: 'test_user',
        ),
        same(ChestContentStyle.moon),
      );
    },
  );

  test('Honoo Luna storico diventa rosso nella conversazione', () {
    final value = honoo(type: HonooType.moon, owner: 'other_user');

    expect(
      ChestContentStyle.forConversationEntry(
        ConversationEntry.honoo(value),
        viewerUserId: 'test_user',
      ),
      same(ChestContentStyle.receivedReply),
    );
  });

  test('Honoo Luna proprio resta blu nella conversazione', () {
    final value = honoo(type: HonooType.moon, owner: 'test_user');

    expect(
      ChestContentStyle.forConversationEntry(
        ConversationEntry.honoo(value),
        viewerUserId: 'test_user',
      ),
      same(ChestContentStyle.own),
    );
  });

  testWidgets('Honoo Luna in conversazione usa il rosso anche nella fascia', (
    tester,
  ) async {
    final value = honoo(type: HonooType.moon, owner: 'other_user');
    await pumpHonoo(
      tester,
      value,
      contentStyleOverride: ChestContentStyle.receivedReply,
    );

    final gap = tester.widget<ColoredBox>(
      find.byKey(const Key('honoo-card-gap')),
    );
    expect(gap.color, HonooColor.secondary);
  });

  test('Honoo personale altrui diventa rosso nella conversazione', () {
    final value = honoo(type: HonooType.personal, owner: 'other_user');

    expect(
      ChestContentStyle.forConversationEntry(
        ConversationEntry.honoo(value),
        viewerUserId: 'test_user',
      ),
      same(ChestContentStyle.receivedReply),
    );
  });

  test('Honoo personale proprio resta blu nella conversazione', () {
    final value = honoo(type: HonooType.personal, owner: 'test_user');

    expect(
      ChestContentStyle.forConversationEntry(
        ConversationEntry.honoo(value),
        viewerUserId: 'test_user',
      ),
      same(ChestContentStyle.own),
    );
  });

  test('Hinoo Luna proprio resta blu nella conversazione', () {
    final draft = hinoo().copyWith(type: HinooType.moon);

    expect(
      ChestContentStyle.forConversationEntry(
        ConversationEntry.hinoo(
          draft,
          createdAt: DateTime.parse('2026-07-18T10:00:00Z'),
          ownerId: 'test_user',
        ),
        viewerUserId: 'test_user',
      ),
      same(ChestContentStyle.own),
    );
  });

  test('Hinoo Luna altrui resta rosso nella conversazione', () {
    final draft = hinoo().copyWith(type: HinooType.moon);

    expect(
      ChestContentStyle.forConversationEntry(
        ConversationEntry.hinoo(
          draft,
          createdAt: DateTime.parse('2026-07-18T10:00:00Z'),
          ownerId: 'other_user',
        ),
        viewerUserId: 'test_user',
      ),
      same(ChestContentStyle.receivedReply),
    );
  });

  testWidgets('Hinoo di risposta proprio non ha cornice', (tester) async {
    final draft = hinoo(fromMoon: true);
    await pumpHinoo(tester, draft: draft, isReply: true, authorId: 'test_user');

    expect(
      ChestContentStyle.forHinoo(
        draft,
        authorId: 'test_user',
        viewerUserId: 'test_user',
        isReply: true,
      ),
      same(ChestContentStyle.own),
    );
    expect(borderWithColor(HonooColor.secondary), findsNothing);
    expect(borderWithColor(Colors.white), findsNothing);
  });

  testWidgets('Hinoo ricevuto in risposta usa sfondo rosso e non ha cornice', (
    tester,
  ) async {
    final draft = hinoo();
    await pumpHinoo(
      tester,
      draft: draft,
      isReply: true,
      authorId: 'other_user',
    );

    expect(
      ChestContentStyle.forHinoo(
        draft,
        authorId: 'other_user',
        viewerUserId: 'test_user',
        isReply: true,
      ),
      same(ChestContentStyle.receivedReply),
    );
    expect(borderWithColor(HonooColor.secondary), findsNothing);
    expect(borderWithColor(Colors.white), findsNothing);
  });

  testWidgets('Hinoo salvato dalla Luna usa sfondo bianco e non ha cornice', (
    tester,
  ) async {
    final draft = hinoo(fromMoon: true);
    await pumpHinoo(
      tester,
      draft: draft,
      isReply: false,
      authorId: 'test_user',
    );

    expect(
      ChestContentStyle.forHinoo(
        draft,
        authorId: 'test_user',
        viewerUserId: 'test_user',
      ),
      same(ChestContentStyle.moon),
    );
    expect(borderWithColor(Colors.white), findsNothing);
    expect(borderWithColor(HonooColor.secondary), findsNothing);
  });
}

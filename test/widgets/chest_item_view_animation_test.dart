import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honoo/Entities/chest_item.dart';
import 'package:honoo/Entities/conversation_entry.dart';
import 'package:honoo/Entities/honoo.dart';
import 'package:honoo/UI/honoo_card.dart';
import 'package:honoo/UI/honoo_thread_view.dart';
import 'package:honoo/UI/unified_thread_view.dart';
import 'package:honoo/Utility/responsive_layout.dart';
import 'package:honoo/Utility/honoo_colors.dart';
import 'package:honoo/Widgets/chest_item_view.dart';

import '../test_supabase_helper.dart';

void main() {
  setUpAll(registerSupabaseFallbacks);

  late SupabaseTestHarness harness;

  setUp(() {
    harness = SupabaseTestHarness(withAuthenticatedUser: true)
      ..enableOverrides();
  });

  tearDown(() => harness.disableOverrides());

  testWidgets(
    'il contenitore non mantiene il rosso della radice su una risposta propria',
    (tester) async {
      final root =
          Honoo(
              0,
              'Ricevuto',
              '',
              '2026-07-25T10:00:00Z',
              '',
              'other_user',
              HonooType.answer,
            )
            ..dbId = 'root'
            ..conversationId = 'thread';
      final own =
          Honoo(
              0,
              'Mio',
              '',
              '2026-07-25T11:00:00Z',
              '',
              'test_user',
              HonooType.answer,
            )
            ..dbId = 'own'
            ..conversationId = 'thread';
      harness.stubTable('honoo').queueResponse([
        root.toMap()..['id'] = 'root',
        own.toMap()..['id'] = 'own',
      ]);
      harness.stubTable('hinoo');
      harness.stubTable('conversation_tombstones');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChestItemView(
              item: ChestItem.honoo(root, DateTime.utc(2026, 7, 25)),
              availableHeight: 600,
              maxWidth: 800,
              honooMetrics: ResponsiveLayout.honooBuilderMetrics(
                availableHeight: 600,
                maxWidth: 800,
                mode: ResponsiveLayoutMode.desktop,
              ),
              repaintKey: GlobalKey(),
              hinooRepliesByRoot: const {},
              isNormalMode: true,
              isActive: false,
              highlightLatest: false,
              focusConversationId: null,
              revealEntryId: null,
              onSelectConversationEntry: (_) {},
              onDownload: (_) {},
              conversationRefreshToken: 0,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final backgrounds = tester.widgetList<ColoredBox>(
        find.ancestor(
          of: find.byType(UnifiedThreadView),
          matching: find.byType(ColoredBox),
        ),
      );
      expect(backgrounds, isNotEmpty);
      expect(
        backgrounds.every((box) => box.color == Colors.transparent),
        isTrue,
      );
      expect(
        find.descendant(
          of: find.byType(ChestItemView),
          matching: find.byType(AnimatedSwitcher),
        ),
        findsNothing,
      );
    },
  );

  testWidgets('un Honoo singolo non usa viste o transizioni di conversazione', (
    tester,
  ) async {
    final honoo = Honoo(
      0,
      'Honoo singolo',
      '',
      '2026-07-25T10:00:00Z',
      '2026-07-25T10:00:00Z',
      'test_user',
      HonooType.personal,
    )..dbId = 'honoo-single';
    final item = ChestItem.honoo(honoo, DateTime.parse('2026-07-25T10:00:00Z'));

    final repaintKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChestItemView(
            item: item,
            availableHeight: 700,
            maxWidth: 390,
            honooMetrics: ResponsiveLayout.honooBuilderMetrics(
              availableHeight: 700,
              maxWidth: 390,
              mode: ResponsiveLayoutMode.mobile,
            ),
            repaintKey: repaintKey,
            hinooRepliesByRoot: const {},
            isNormalMode: true,
            isActive: true,
            highlightLatest: false,
            focusConversationId: null,
            revealEntryId: null,
            onSelectConversationEntry: (ConversationEntry _) {},
            onDownload: (_) {},
            conversationRefreshToken: 0,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(HonooCard), findsOneWidget);
    expect(find.byType(HonooThreadView), findsNothing);
    expect(find.byType(UnifiedThreadView), findsNothing);
    final captureBoundary = tester.widget<RepaintBoundary>(
      find.byKey(repaintKey),
    );
    final captureBackground = captureBoundary.child! as Card;
    expect(captureBackground.color, HonooColor.background);
    final chestItem = find.byType(ChestItemView);
    expect(
      find.descendant(of: chestItem, matching: find.byType(AnimatedSwitcher)),
      findsNothing,
    );
    expect(
      find.descendant(of: chestItem, matching: find.byType(SlideTransition)),
      findsNothing,
    );
    expect(
      find.descendant(of: chestItem, matching: find.byType(ScaleTransition)),
      findsNothing,
    );
    expect(
      find.descendant(of: chestItem, matching: find.byType(FadeTransition)),
      findsNothing,
    );
  });
}

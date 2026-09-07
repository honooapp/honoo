import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honoo/Entities/conversation_entry.dart';
import 'package:honoo/Entities/hinoo.dart';
import 'package:honoo/Entities/honoo.dart';
import 'package:honoo/UI/unified_thread_view.dart';
import 'package:honoo/Utility/honoo_colors.dart';
import 'package:honoo/Utility/replies_seen_tracker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_supabase_helper.dart';

void main() {
  setUpAll(registerSupabaseFallbacks);
  late SupabaseTestHarness harness;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    harness = SupabaseTestHarness(withAuthenticatedUser: true)
      ..enableOverrides();
  });
  tearDown(() => harness.disableOverrides());

  for (final kind in ['honoo', 'hinoo']) {
    ConversationEntry entry(String id, String owner, int hour) {
      final createdAt = DateTime.utc(2026, 9, 7, hour);
      if (kind == 'honoo') {
        return ConversationEntry.honoo(
          Honoo(
              0,
              id,
              '',
              createdAt.toIso8601String(),
              '',
              owner,
              HonooType.answer,
            )
            ..dbId = id
            ..conversationId = 'conversation',
        );
      }
      return ConversationEntry.hinoo(
        const HinooDraft(
          type: HinooType.answer,
          conversationId: 'conversation',
          pages: [
            HinooSlide(backgroundImage: null, text: 'Test', isTextWhite: true),
          ],
        ),
        id: id,
        ownerId: owner,
        createdAt: createdAt,
      );
    }

    testWidgets(
      '$kind: lettura persistente solo dopo attivazione, anche senza onSelect',
      (tester) async {
        final received = entry('received', 'other', 11);
        Widget view(bool active) => MaterialApp(
          home: Scaffold(
            body: UnifiedThreadView(
              conversationId: 'conversation',
              maxWidth: 800,
              maxHeight: 600,
              isActive: active,
              conversationLoader: (_) async => [received],
            ),
          ),
        );
        await tester.pumpWidget(view(false));
        await tester.pumpAndSettle();
        expect(
          (await RepliesSeenTracker.load(userId: 'test_user')).replyIds,
          isEmpty,
        );
        await tester.pumpWidget(view(true));
        await tester.pumpAndSettle();
        await tester.pump();
        final reloaded = await RepliesSeenTracker.load(userId: 'test_user');
        expect(reloaded.replyIds, contains('received'));
        expect(
          reloaded.isSeen(
            conversationId: 'conversation',
            createdAt: received.createdAt,
            replyId: 'received',
          ),
          isTrue,
        );
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      '$kind: tutto il fondo passa dal rosso al blu sul messaggio proprio',
      (tester) async {
        tester.view.physicalSize = const Size(1000, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final own = entry('own', 'test_user', 10);
        final received = entry('received', 'other', 11);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 800,
                  height: 700,
                  child: UnifiedThreadView(
                    conversationId: 'conversation',
                    maxWidth: 800,
                    maxHeight: 700,
                    isActive: true,
                    conversationLoader: (_) async => [own, received],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final red = find.byKey(
          Key('conversation-entry-background:$kind:received'),
        );
        expect(tester.widget<ColoredBox>(red).color, HonooColor.secondary);
        expect(tester.getSize(red), const Size(800, 700));
        await tester.drag(find.byType(PageView).first, const Offset(0, -600));
        await tester.pumpAndSettle();
        final blue = find.byKey(Key('conversation-entry-background:$kind:own'));
        expect(tester.widget<ColoredBox>(blue).color, HonooColor.background);
        expect(tester.getSize(blue), const Size(800, 700));
        expect(
          (await RepliesSeenTracker.load(userId: 'test_user')).replyIds,
          isNot(contains('own')),
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}

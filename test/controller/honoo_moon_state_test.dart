import 'package:mocktail/mocktail.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honoo/Controller/honoo_controller.dart';

import '../test_supabase_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(registerSupabaseFallbacks);

  late SupabaseTestHarness harness;

  setUp(() {
    harness = SupabaseTestHarness(withAuthenticatedUser: true);
    harness.enableOverrides();
  });

  tearDown(() => harness.disableOverrides());

  test('loadChest marca un honoo con la stessa copia già sulla Luna', () async {
    final hiddenConversations = harness.stubTable('chest_hidden_conversations');
    hiddenConversations.queueResponse(const []);
    final honoo = harness.stubTable('honoo');
    honoo.queueResponse([
      {
        'id': 'chest-1',
        'text': 'Testo',
        'image_url': 'image.png',
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': '2026-01-01T00:00:00Z',
        'user_id': 'test_user',
        'destination': 'chest',
      },
    ]);
    honoo.queueResponse([
      {
        'id': 'moon-1',
        'text': 'Testo',
        'image_url': 'image.png',
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': '2026-01-01T00:00:00Z',
        'user_id': 'test_user',
        'destination': 'moon',
      },
    ]);
    honoo.queueResponse(const []);

    final controller = HonooController();
    await controller.loadChest();

    expect(controller.personal.single.isOnMoon, isTrue);
  });
  test(
    'cache is hidden on account switch and cleared before a failed load',
    () async {
      harness.stubTable('chest_hidden_conversations');
      final honoo = harness.stubTable('honoo');
      honoo.queueResponse([
        {
          'id': 'private-a',
          'text': 'Privato A',
          'image_url': 'image.png',
          'user_id': 'test_user',
          'destination': 'chest',
        },
      ]);
      honoo.queueResponse(const []);
      honoo.queueResponse(const []);
      final controller = HonooController();
      await controller.loadChest();
      expect(controller.personal.single.dbId, 'private-a');
      when(() => harness.user.id).thenReturn('user-b');
      expect(controller.personal, isEmpty);
      when(
        () => harness.client.from('chest_hidden_conversations'),
      ).thenThrow(StateError('read failed'));
      await expectLater(controller.loadChest(), throwsA(anything));
      expect(controller.personal, isEmpty);
      when(() => harness.user.id).thenReturn('test_user');
      expect(controller.personal, isEmpty);
      controller.clearCache();
    },
  );

  test('logout invalidates an in-flight chest load', () async {
    harness.stubTable('chest_hidden_conversations');
    final honoo = harness.stubTable('honoo');
    honoo.queueResponse([
      {
        'id': 'stale',
        'text': 'Privato',
        'image_url': 'image.png',
        'user_id': 'test_user',
        'destination': 'chest',
      },
    ]);
    honoo.queueResponse(const []);
    honoo.queueResponse(const []);
    final controller = HonooController();
    final pending = controller.loadChest();
    controller.clearCache();
    when(() => harness.auth.currentUser).thenReturn(null);
    await pending;
    expect(controller.personal, isEmpty);
    expect(controller.isLoading.value, isFalse);
    when(() => harness.auth.currentUser).thenReturn(harness.user);
    expect(controller.personal, isEmpty);
  });
}

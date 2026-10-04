import 'package:mocktail/mocktail.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honoo/Controller/honoo_controller.dart';
import 'package:honoo/Entities/honoo.dart';
import 'package:honoo/Services/duplication_result.dart';

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

  test('successful save remains successful when cache refresh fails', () async {
    final chain = harness.stubTable('honoo');
    chain.queueResponse([]);
    when(
      () => harness.client.from('chest_hidden_conversations'),
    ).thenThrow(StateError('refresh unavailable'));
    final controller = HonooController();
    addTearDown(controller.clearCache);
    final honoo = Honoo.fromMap({
      'id': 'moon-id',
      'text': 'Salvato',
      'image_url': '',
      'user_id': 'author',
      'destination': 'moon',
    });
    expect(await controller.saveToChest(honoo), DuplicationResult.inserted);
    verify(() => chain.insert(any())).called(1);
    expect(controller.isLoading.value, isFalse);
  });

  test('failed insert still reports failure', () async {
    final chain = harness.stubTable('honoo');
    when(() => chain.insert(any())).thenThrow(StateError('insert failed'));
    final honoo = Honoo.fromMap({
      'id': 'moon-id',
      'text': 'Test',
      'image_url': '',
    });
    await expectLater(HonooController().saveToChest(honoo), throwsA(anything));
  });

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

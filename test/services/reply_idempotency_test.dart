import 'package:flutter_test/flutter_test.dart';
import 'package:honoo/Entities/honoo.dart';
import 'package:honoo/Services/honoo_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../test_supabase_helper.dart';

void main() {
  setUpAll(registerSupabaseFallbacks);
  late SupabaseTestHarness harness;
  late MockQueryChain chain;
  late Honoo reply;
  setUp(() {
    harness = SupabaseTestHarness(withAuthenticatedUser: true)
      ..enableOverrides();
    chain = harness.stubTable('honoo');
    reply = Honoo(
      0,
      'text',
      '',
      '',
      '',
      'test_user',
      HonooType.answer,
      'parent',
      'other',
    )..conversationId = 'conversation';
  });
  tearDown(() => harness.disableOverrides());
  test('il retry conferma la risposta esistente senza aggiornarla', () async {
    when(
      () => chain.insert(any()),
    ).thenThrow(const PostgrestException(message: 'duplicate', code: '23505'));
    chain.queueResponse({
      ...reply.toInsertMap(),
      'id': 'stable-id',
      'user_id': 'test_user',
    });
    expect(
      await HonooService.publishReplyOnce(reply, 'stable-id'),
      'stable-id',
    );
    final inserted =
        verify(() => chain.insert(captureAny())).captured.single as Map;
    expect(inserted['id'], 'stable-id');
    verifyNever(() => chain.upsert(any()));
    verifyNever(() => chain.update(any()));
  });
  test('non conferma un contenuto differente con lo stesso id', () async {
    when(
      () => chain.insert(any()),
    ).thenThrow(const PostgrestException(message: 'duplicate', code: '23505'));
    chain.queueResponse({...reply.toInsertMap(), 'text': 'different'});
    await expectLater(
      HonooService.publishReplyOnce(reply, 'stable-id'),
      throwsA(anything),
    );
  });
}

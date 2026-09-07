import 'package:flutter_test/flutter_test.dart';
import 'package:honoo/Services/house_shared_content_service.dart';
import 'package:mocktail/mocktail.dart';

import '../test_supabase_helper.dart';

void main() {
  setUpAll(registerSupabaseFallbacks);

  test('mappa e ordina lo scrigno autorizzato restituito dalla RPC', () async {
    final harness = SupabaseTestHarness(withAuthenticatedUser: true);
    final rpc = MockQueryChain()
      ..queueResponse([
        {
          'kind': 'honoo',
          'data': {
            'id': 'honoo-1',
            'conversation_id': 'honoo-thread',
            'text': 'Honoo condiviso',
            'image_url': '',
            'destination': 'chest',
            'created_at': '2026-08-10T10:00:00Z',
            'updated_at': '2026-08-10T10:00:00Z',
            'user_id': 'owner-1',
            'is_from_moon_saved': false,
          },
        },
        {
          'kind': 'hinoo',
          'data': {
            'id': 'hinoo-1',
            'conversation_id': 'hinoo-thread',
            'pages': [
              {'text': 'Hinoo condiviso', 'backgroundImage': ''},
            ],
            'type': 'personal',
            'created_at': '2026-08-11T10:00:00Z',
            'user_id': 'owner-1',
            'is_from_moon_saved': true,
          },
        },
      ]);
    when(
      () => harness.client.rpc(
        'get_shared_house_chest',
        params: any(named: 'params'),
      ),
    ).thenAnswer((_) => rpc);

    final items = await HouseSharedContentService(
      client: harness.client,
    ).fetch('owner-1');

    expect(items, hasLength(2));
    expect(items.first.hinoo?.id, 'hinoo-1');
    expect(items.last.honoo?.dbId, 'honoo-1');
    expect(items.last.honoo?.conversationId, 'honoo-thread');
    expect(items.first.hinoo?.conversationId, 'hinoo-thread');
    verify(
      () => harness.client.rpc(
        'get_shared_house_chest',
        params: {'p_owner_id': 'owner-1'},
      ),
    ).called(1);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:honoo/Entities/casa_share_mode.dart';
import 'package:honoo/Services/house_guests_service.dart';
import 'package:mocktail/mocktail.dart';
import '../test_supabase_helper.dart';

void main() {
  setUpAll(registerSupabaseFallbacks);
  test('pending requests retain their exact conversation and message', () {
    for (final kind in ['honoo', 'hinoo']) {
      final request = HouseGuest.fromJson({
        'id': 7,
        'granted_at': null,
        'target_house_tag': 'house',
        'share_modes': [],
        kind: {
          'id': 'message',
          'conversation_id': 'conversation',
          'pages': [
            {'text': 'Ciao'},
          ],
        },
      });
      expect(request.pending, isTrue);
      expect(request.modes, isEmpty);
      expect(request.conversationId, 'conversation');
      expect(request.contentId, 'message');
    }
  });
  test('mantiene ospiti revocati e contenuti non più disponibili', () async {
    final harness = SupabaseTestHarness(withAuthenticatedUser: true);
    final rpc = MockQueryChain();
    when(() => rpc.timeout(const Duration(seconds: 12))).thenAnswer(
      (_) async => [
        {'id': 1, 'share_modes': [], 'honoo': null, 'hinoo': null},
        {
          'id': 2,
          'share_modes': ['moon'],
          'honoo': {'text': 'Bussata'},
        },
      ],
    );
    when(
      () => harness.client.rpc(
        'get_house_inbox',
        params: {'p_house_tag': 'house'},
      ),
    ).thenAnswer((_) => rpc);
    final guests = await HouseGuestsService(
      client: harness.client,
    ).fetch('house');
    expect(guests.length, 2);
    expect(guests.first.modes, isEmpty);
    expect(guests.last.modes, {CasaShareMode.moon});
    expect(guests.last.honoo?.text, 'Bussata');
  });
  test(
    'revoca completa invia un insieme vuoto alla RPC proprietario',
    () async {
      final harness = SupabaseTestHarness(withAuthenticatedUser: true);
      final rpc = MockQueryChain();
      when(
        () => rpc.timeout(const Duration(seconds: 12)),
      ).thenAnswer((_) async => null);
      when(
        () => harness.client.rpc(
          'update_house_guest_access',
          params: any(named: 'params'),
        ),
      ).thenAnswer((_) => rpc);
      await HouseGuestsService(client: harness.client).update('42', {});
      verify(
        () => harness.client.rpc(
          'update_house_guest_access',
          params: {'p_knock_id': 42, 'p_share_modes': <String>[]},
        ),
      ).called(1);
    },
  );
}

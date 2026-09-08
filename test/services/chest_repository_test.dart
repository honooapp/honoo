import 'package:flutter_test/flutter_test.dart';
import 'package:honoo/Services/chest_repository.dart';
import 'package:mocktail/mocktail.dart';

import '../test_supabase_helper.dart';

void main() {
  setUpAll(registerSupabaseFallbacks);

  late SupabaseTestHarness harness;
  late MockQueryChain hinoo;
  late MockQueryChain hiddenConversations;
  late ChestRepository repository;

  setUp(() {
    harness = SupabaseTestHarness(withAuthenticatedUser: true);
    hinoo = harness.stubTable('hinoo');
    hiddenConversations = harness.stubTable('chest_hidden_conversations');
    repository = ChestRepository(client: harness.client);
  });

  tearDown(resetMocktailState);

  test('fetchHinooRows mantiene filtri e ordinamento dello Scrigno', () async {
    final rows = <Map<String, dynamic>>[
      {'id': 'h-1', 'pages': <dynamic>[]},
    ];
    hiddenConversations.queueResponse(<Map<String, dynamic>>[]);
    hinoo.queueResponse(rows);

    final result = await repository.fetchHinooRows('user-1');

    expect(result, rows);
    verify(() => hinoo.in_('type', ['personal', 'answer'])).called(1);
    verify(
      () => hinoo.or(
        'user_id.eq.user-1,and(recipient_tag.eq.user-1,or(type.eq.answer,reply_to.not.is.null,conversation_id.not.is.null))',
      ),
    ).called(1);
    verify(() => hinoo.order('created_at', ascending: false)).called(1);
  });

  test('fetchHinooRows non ripristina conversazioni eliminate', () async {
    hiddenConversations.queueResponse([
      {'conversation_id': 'conversation-hidden'},
    ]);
    hinoo.queueResponse([
      {'id': 'h-1', 'conversation_id': 'conversation-hidden'},
      {'id': 'h-2', 'conversation_id': 'conversation-visible'},
    ]);

    final result = await repository.fetchHinooRows('user-1');

    expect(result, [
      {'id': 'h-2', 'conversation_id': 'conversation-visible'},
    ]);
  });

  test(
    'fetchHinooRows nasconde anche la radice senza conversation id',
    () async {
      hiddenConversations.queueResponse([
        {'conversation_id': 'root-hidden'},
      ]);
      hinoo.queueResponse([
        {'id': 'root-hidden'},
        {'id': 'root-visible'},
      ]);

      final result = await repository.fetchHinooRows('user-1');

      expect(result, [
        {'id': 'root-visible'},
      ]);
    },
  );

  test('hideConversation salva una rimozione persistente per utente', () async {
    hiddenConversations.queueResponse(<String, dynamic>{});

    await repository.hideConversation(
      userId: 'user-1',
      conversationId: 'conversation-1',
    );

    verify(
      () => hiddenConversations.upsert({
        'user_id': 'user-1',
        'conversation_id': 'conversation-1',
      }),
    ).called(1);
  });

  test(
    'fetchHinooMoonFingerprints restituisce i fingerprint pubblicati',
    () async {
      hinoo.queueResponse([
        {'fingerprint': 'fp-1'},
        {'fingerprint': null},
        {'fingerprint': 'fp-2'},
      ]);

      final result = await repository.fetchHinooMoonFingerprints('user-1');

      expect(result, {'fp-1', 'fp-2'});
      verify(() => hinoo.select('fingerprint')).called(1);
      verify(() => hinoo.eq('user_id', 'user-1')).called(1);
      verify(() => hinoo.eq('type', 'moon')).called(1);
    },
  );

  test('fetchHinooReplyRows include le risposte legacy senza reply_to', () async {
    hiddenConversations.queueResponse(<Map<String, dynamic>>[]);
    hinoo.queueResponse([
      {'id': 'legacy-received'},
    ]);
    hinoo.queueResponse([
      {'id': 'legacy-sent'},
    ]);

    final result = await repository.fetchHinooReplyRows('user-1', const []);

    expect(result, [
      {'id': 'legacy-received'},
      {'id': 'legacy-sent'},
    ]);
    verify(
      () => hinoo.or(
        'type.eq.answer,and(conversation_id.not.is.null,recipient_tag.not.is.null)',
      ),
    ).called(2);
  });

  test('deleteHinoo elimina esclusivamente la riga indicata', () async {
    hinoo.queueResponse(<String, dynamic>{});

    await repository.deleteHinoo('h-1');

    verify(() => hinoo.delete()).called(1);
    verify(() => hinoo.eq('id', 'h-1')).called(1);
  });
}

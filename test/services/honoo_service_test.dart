import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:honoo/Services/honoo_service.dart';
import 'package:honoo/Services/duplication_result.dart';
import 'package:honoo/Entities/honoo.dart';

class _MockQueryChain extends Mock
    implements
        SupabaseQueryBuilder,
        PostgrestFilterBuilder<dynamic>,
        PostgrestTransformBuilder<dynamic> {
  final Queue<dynamic> _responses = Queue<dynamic>();

  void queueResponse(dynamic value) => _responses.add(value);

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #then &&
        invocation.positionalArguments.isNotEmpty) {
      final onValue =
          invocation.positionalArguments[0] as dynamic Function(dynamic);
      final result = _responses.isEmpty ? null : _responses.removeFirst();
      return Future.value(onValue(result));
    }
    return super.noSuchMethod(invocation);
  }
}

class _MockSupabaseClient extends Mock implements SupabaseClient {}

class _MockAuth extends Mock implements GoTrueClient {}

class _MockSession extends Mock implements Session {}

class _MockUser extends Mock implements User {}

void main() {
  late _MockSupabaseClient client;
  late _MockQueryChain chain;
  late _MockQueryChain hiddenConversations;
  late _MockAuth auth;
  late _MockSession session;
  late _MockUser user;

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    client = _MockSupabaseClient();
    chain = _MockQueryChain();
    hiddenConversations = _MockQueryChain();
    auth = _MockAuth();
    session = _MockSession();
    user = _MockUser();

    HonooService.$setTestClient(client);
    when(() => client.auth).thenReturn(auth);
    when(() => auth.currentSession).thenReturn(session);
    when(() => session.user).thenReturn(user);
    when(() => user.id).thenReturn('user-1');
    when(() => client.from('honoo')).thenAnswer((_) => chain);
    when(
      () => client.from('chest_hidden_conversations'),
    ).thenAnswer((_) => hiddenConversations);

    when(() => chain.select(any())).thenAnswer((_) => chain);
    when(() => chain.insert(any())).thenAnswer((_) => chain);
    when(() => chain.delete()).thenAnswer((_) => chain);
    when(() => chain.eq(any(), any())).thenAnswer((_) => chain);
    when(() => chain.in_(any(), any())).thenAnswer((_) => chain);
    when(() => chain.limit(any())).thenAnswer((_) => chain);
    when(() => chain.maybeSingle()).thenAnswer((_) => chain);
    when(() => chain.or(any())).thenAnswer((_) => chain);
    when(
      () => chain.order(any(), ascending: any(named: 'ascending')),
    ).thenAnswer((_) => chain);
    when(
      () => hiddenConversations.select(any()),
    ).thenAnswer((_) => hiddenConversations);
    when(
      () => hiddenConversations.eq(any(), any()),
    ).thenAnswer((_) => hiddenConversations);
  });

  tearDown(() {
    HonooService.$setTestClient(null);
    resetMocktailState();
  });

  test(
    'fetchPublicHonoo: filtra destination=moon e ordina per created_at desc',
    () async {
      final rows = [
        {
          'id': 2,
          'text': '“b”',
          'image_url': '',
          'created_at': '2024-01-02T00:00:00Z',
          'updated_at': '2024-01-02T00:00:00Z',
          'user_id': 'u2',
          'type': 'personal',
        },
        {
          'id': 1,
          'text': '“a”',
          'image_url': '',
          'created_at': '2024-01-01T00:00:00Z',
          'updated_at': '2024-01-01T00:00:00Z',
          'user_id': 'u1',
          'type': 'personal',
        },
      ];
      chain.queueResponse(rows);

      final list = await HonooService.fetchPublicHonoo();

      expect(list, isA<List<Honoo>>());
      expect(list.length, 2);
      expect(list.first.dbId, '2');

      verify(() => client.from('honoo')).called(1);
      verify(() => chain.select('*')).called(1);
      verify(() => chain.eq('destination', 'moon')).called(1);
      verify(() => chain.order('created_at', ascending: false)).called(1);
    },
  );

  test('deleteHonooById: chiama delete().eq("id", id) e completa', () async {
    chain.queueResponse([
      {'id': '123'},
    ]);

    await HonooService.deleteHonooById('123');

    verify(() => client.from('honoo')).called(1);
    verify(() => chain.delete()).called(1);
    verify(() => chain.eq('id', '123')).called(1);
  });

  test(
    'fetchUserChestHonoo include risposte ricevute oltre ai contenuti propri',
    () async {
      hiddenConversations.queueResponse(<Map<String, dynamic>>[]);
      chain.queueResponse(<Map<String, dynamic>>[]);

      await HonooService.fetchUserChestHonoo('user-1');

      verify(() => chain.in_('destination', ['chest', 'reply'])).called(1);
      verify(
        () => chain.or(
          'user_id.eq.user-1,and(destination.eq.reply,recipient_tag.eq.user-1)',
        ),
      ).called(1);
      verify(() => chain.order('created_at', ascending: false)).called(1);
    },
  );

  test('fetchUserChestHonoo esclude conversazioni eliminate', () async {
    hiddenConversations.queueResponse([
      {'conversation_id': 'conversation-hidden'},
    ]);
    chain.queueResponse([
      {
        'id': 'hidden',
        'text': 'nascosto',
        'image_url': '',
        'created_at': '2026-08-06T10:00:00Z',
        'updated_at': '2026-08-06T10:00:00Z',
        'user_id': 'user-1',
        'destination': 'reply',
        'conversation_id': 'conversation-hidden',
      },
      {
        'id': 'visible',
        'text': 'visibile',
        'image_url': '',
        'created_at': '2026-08-06T11:00:00Z',
        'updated_at': '2026-08-06T11:00:00Z',
        'user_id': 'user-1',
        'destination': 'chest',
        'conversation_id': 'conversation-visible',
      },
    ]);

    final result = await HonooService.fetchUserChestHonoo('user-1');

    expect(result.map((honoo) => honoo.dbId), ['visible']);
  });

  test(
    'fetchUserChestHonoo nasconde anche la radice senza conversation id',
    () async {
      hiddenConversations.queueResponse([
        {'conversation_id': 'root-hidden'},
      ]);
      chain.queueResponse([
        {
          'id': 'root-hidden',
          'text': 'nascosto',
          'image_url': '',
          'created_at': '2026-08-06T10:00:00Z',
          'updated_at': '2026-08-06T10:00:00Z',
          'user_id': 'user-1',
          'destination': 'chest',
        },
        {
          'id': 'root-visible',
          'text': 'visibile',
          'image_url': '',
          'created_at': '2026-08-06T11:00:00Z',
          'updated_at': '2026-08-06T11:00:00Z',
          'user_id': 'user-1',
          'destination': 'chest',
        },
      ]);

      final result = await HonooService.fetchUserChestHonoo('user-1');

      expect(result.map((honoo) => honoo.dbId), ['root-visible']);
    },
  );

  test('publishHonoo: reply inserisce reply_to e recipient_tag', () async {
    chain.queueResponse(<String, dynamic>{});

    final honoo = Honoo(
      1,
      'testo',
      '',
      '2024-01-01T00:00:00Z',
      '2024-01-01T00:00:00Z',
      'user-1',
      HonooType.answer,
      'root-1',
      'recipient-1',
    )..conversationId = 'conversation-1';

    await HonooService.publishHonoo(honoo);

    final captured =
        verify(() => chain.insert(captureAny())).captured.single
            as Map<String, dynamic>;
    expect(captured['destination'], 'reply');
    expect(captured['reply_to'], 'root-1');
    expect(captured['recipient_tag'], 'recipient-1');
    expect(captured['image_url'], isNull);
  });

  test('duplicateToMoon rifiuta un honoo salvato dalla Luna', () async {
    final honoo = Honoo(
      1,
      'testo',
      '',
      '2024-01-01T00:00:00Z',
      '2024-01-01T00:00:00Z',
      'user-1',
      HonooType.personal,
    )..isFromMoonSaved = true;

    await expectLater(HonooService.duplicateToMoon(honoo), throwsArgumentError);
    verifyNever(() => client.from('honoo'));
  });

  test('duplicateToMoon inserisce una nuova riga a ogni invio', () async {
    final honoo = Honoo(
      1,
      'testo',
      '',
      '2024-01-01T00:00:00Z',
      '2024-01-01T00:00:00Z',
      'user-1',
      HonooType.personal,
    );
    chain.queueResponse(<String, dynamic>{});
    chain.queueResponse(<String, dynamic>{});

    final first = await HonooService.duplicateToMoon(honoo);
    final second = await HonooService.duplicateToMoon(honoo);

    expect(first, DuplicationResult.inserted);
    expect(second, DuplicationResult.inserted);
    verify(() => chain.insert(any())).called(2);
  });

  test('hasMoonCopy riconosce una pubblicazione Honoo precedente', () async {
    final honoo = Honoo(
      1,
      'testo',
      '',
      '2024-01-01T00:00:00Z',
      '2024-01-01T00:00:00Z',
      'user-1',
      HonooType.answer,
    );
    chain.queueResponse(<String, dynamic>{'id': 'moon-1'});

    expect(await HonooService.hasMoonCopy(honoo), isTrue);

    verify(() => chain.eq('user_id', 'user-1')).called(1);
    verify(() => chain.eq('destination', 'moon')).called(1);
    verify(
      () => chain.eq('fingerprint', HonooService.fingerprint(honoo)),
    ).called(1);
  });
}

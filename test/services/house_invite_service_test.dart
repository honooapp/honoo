import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:honoo/Entities/hinoo.dart';
import 'package:honoo/Services/house_invite_service.dart';

class _MockClient extends Mock implements SupabaseClient {}

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

void main() {
  late _MockClient client;
  late _MockQueryChain chain;
  late HouseInviteService service;

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    client = _MockClient();
    chain = _MockQueryChain();
    service = HouseInviteService(client: client);

    when(() => client.from('house_invites')).thenAnswer((_) => chain);
    when(() => chain.select(any())).thenAnswer((_) => chain);
    when(() => chain.eq(any(), any())).thenAnswer((_) => chain);
    when(() => chain.in_(any(), any())).thenAnswer((_) => chain);
    when(() => chain.limit(any())).thenAnswer((_) => chain);
  });

  test('verifica se la casa usa l\'immagine appena caricata', () async {
    when(() => client.from('case')).thenAnswer((_) => chain);
    chain.queueResponse([
      {'id': 'house-1'},
    ]);

    final result = await service.isHouseUsingImage(
      userId: 'user-1',
      imageUrl: 'https://example.com/house.png',
    );

    expect(result, isTrue);
    verify(() => chain.eq('owner_id', 'user-1')).called(1);
    verify(
      () => chain.eq('house_image_url', 'https://example.com/house.png'),
    ).called(1);
  });

  test(
    'hasPendingOrAcceptedInvite include richieste e inviti aperti',
    () async {
      chain.queueResponse([
        {'status': 'pending'},
      ]);

      final result = await service.hasPendingOrAcceptedInvite('user-1');

      expect(result, isTrue);
      verify(() => client.from('house_invites')).called(1);
      verify(() => chain.select('status')).called(1);
      verify(() => chain.eq('user_id', 'user-1')).called(1);
      verify(
        () => chain.in_('status', ['requested', 'pending', 'accepted']),
      ).called(1);
      verify(() => chain.limit(1)).called(1);
    },
  );

  test('createPendingRequest usa la RPC protetta', () async {
    final createdAt = DateTime.utc(2026, 7, 18, 12);
    when(
      () => client.rpc('request_house_invite', params: any(named: 'params')),
    ).thenAnswer((_) => chain);
    chain.queueResponse(true);

    final created = await service.createPendingRequest(
      userId: 'user-1',
      email: 'user@example.com',
      createdAt: createdAt,
    );

    expect(created, isTrue);
    verify(
      () => client.rpc(
        'request_house_invite',
        params: {'p_email': 'user@example.com'},
      ),
    ).called(1);
  });

  test('createHouseWithCampanello salva campanello e casa atomici', () async {
    when(
      () => client.rpc(
        'create_house_with_campanello',
        params: any(named: 'params'),
      ),
    ).thenAnswer((_) => chain);
    chain.queueResponse('campanello-1');
    const draft = HinooDraft(
      pages: [
        HinooSlide(
          backgroundImage: 'https://example.com/background.png',
          text: 'Suona qui',
          isTextWhite: true,
        ),
      ],
    );

    final id = await service.createHouseWithCampanello(
      campanello: draft,
      houseImageUrl: 'https://example.com/house.png',
      bgTransform: const [1, 0, 0, 1, 2, 3],
    );

    expect(id, 'campanello-1');
    verify(
      () => client.rpc(
        'create_house_with_campanello',
        params: {
          'p_pages': draft.pages.map((page) => page.toJson()).toList(),
          'p_house_image_url': 'https://example.com/house.png',
          'p_bg_transform': [1, 0, 0, 1, 2, 3],
        },
      ),
    ).called(1);
  });

  test('createHouseWithCampanello rifiuta bozze risposta', () async {
    const draft = HinooDraft(
      type: HinooType.answer,
      pages: [
        HinooSlide(backgroundImage: null, text: 'Risposta', isTextWhite: false),
      ],
    );

    expect(
      () => service.createHouseWithCampanello(
        campanello: draft,
        houseImageUrl: 'https://example.com/house.png',
        bgTransform: const [1, 0, 0, 1, 0, 0],
      ),
      throwsArgumentError,
    );
  });

  test(
    'updateCampanello aggiorna le pagine del campanello esistente',
    () async {
      when(() => client.from('hinoo')).thenAnswer((_) => chain);
      when(() => chain.update(any())).thenAnswer((_) => chain);
      chain.queueResponse([
        {'id': 'updated-1'},
      ]);
      const draft = HinooDraft(
        pages: [
          HinooSlide(
            backgroundImage: 'https://example.com/bell.png',
            text: 'Campanello modificato',
            isTextWhite: false,
          ),
        ],
      );

      await service.updateCampanello(
        campanelloHinooId: 'hinoo-1',
        campanello: draft,
      );

      verify(() => client.from('hinoo')).called(1);
      verify(
        () => chain.update(
          any(
            that: containsPair(
              'pages',
              draft.pages.map((page) => page.toJson()).toList(),
            ),
          ),
        ),
      ).called(1);
      verify(() => chain.eq('id', 'hinoo-1')).called(1);
    },
  );

  test(
    'updateHouse aggiorna immagine e trasformazione della propria casa',
    () async {
      when(() => client.from('case')).thenAnswer((_) => chain);
      when(() => chain.update(any())).thenAnswer((_) => chain);
      chain.queueResponse([
        {'id': 'updated-1'},
      ]);

      await service.updateHouse(
        campanelloHinooId: 'hinoo-1',
        houseImageUrl: 'https://example.com/house.png',
        bgTransform: const [1, 0, 0, 1],
      );

      verify(() => client.from('case')).called(1);
      verify(
        () => chain.update({
          'house_image_url': 'https://example.com/house.png',
          'bg_transform': [1, 0, 0, 1],
        }),
      ).called(1);
      verify(() => chain.eq('campanello_hinoo_id', 'hinoo-1')).called(1);
    },
  );
  for (final operation in ['campanello', 'immagine casa', 'testo casa']) {
    test('$operation segnala quando nessuna riga viene aggiornata', () async {
      when(() => client.from(any())).thenAnswer((_) => chain);
      when(() => chain.update(any())).thenAnswer((_) => chain);
      chain.queueResponse(<Map<String, dynamic>>[]);
      final Future<void> result;
      switch (operation) {
        case 'campanello':
          result = service.updateCampanello(
            campanelloHinooId: 'missing',
            campanello: const HinooDraft(pages: []),
          );
        case 'immagine casa':
          result = service.updateHouse(
            campanelloHinooId: 'missing',
            houseImageUrl: 'https://example.com/house.png',
            bgTransform: const [],
          );
        default:
          result = service.updateHouseText(
            campanelloHinooId: 'missing',
            text: 'Testo',
          );
      }
      await expectLater(result, throwsStateError);
    });
  }

  test('updateHouseText salva il testo nella casa selezionata', () async {
    when(() => client.from('case')).thenAnswer((_) => chain);
    when(() => chain.update(any())).thenAnswer((_) => chain);
    chain.queueResponse([
      {'id': 'house-1'},
    ]);
    await service.updateHouseText(
      campanelloHinooId: 'hinoo-1',
      text: 'Benvenuti',
    );
    verify(() => chain.update({'house_text': 'Benvenuti'})).called(1);
    verify(() => chain.eq('campanello_hinoo_id', 'hinoo-1')).called(1);
  });
}

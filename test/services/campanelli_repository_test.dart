import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:honoo/Services/campanelli_repository.dart';
import 'package:mocktail/mocktail.dart';

import '../test_supabase_helper.dart';

class _HangingQuery extends MockQueryChain {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    // ignore: prefer_void_to_null, matches Future.then<R=Null> in await.
    if (invocation.memberName == #then) return Completer<Null>().future;
    return super.noSuchMethod(invocation);
  }
}

void main() {
  setUpAll(registerSupabaseFallbacks);

  late SupabaseTestHarness harness;
  late MockQueryChain houses;
  late MockQueryChain settings;
  late MockQueryChain hinoo;
  late MockQueryChain honoo;
  late MockQueryChain houseAccess;
  late CampanelliDataRepository repository;

  setUp(() {
    harness = SupabaseTestHarness(withAuthenticatedUser: true);
    houses = harness.stubTable('case');
    settings = harness.stubTable('house_share_settings');
    hinoo = harness.stubTable('hinoo');
    honoo = harness.stubTable('honoo');
    houseAccess = harness.stubTable('house_access');
    repository = CampanelliDataRepository(client: harness.client);
  });

  tearDown(resetMocktailState);

  testWidgets(
    'una bussata senza risposta del server termina entro il timeout',
    (tester) async {
      when(() => houseAccess.insert(any())).thenAnswer((_) => _HangingQuery());
      final result = expectLater(
        repository.sendHouseKnock(
          targetHouseTag: 'house',
          visitorId: 'visitor',
        ),
        throwsA(isA<TimeoutException>()),
      );
      await tester.pump(CampanelliDataRepository.requestTimeout);
      await result;
    },
  );

  test('fetchPublicAdminCampanelli usa la RPC pubblica dedicata', () async {
    final rpc = MockQueryChain();
    final rows = <Map<String, dynamic>>[
      {'admin_email': 'venceslao.cembalo@gmail.com'},
    ];
    rpc.queueResponse(rows);
    when(
      () => harness.client.rpc('get_public_admin_campanelli'),
    ).thenAnswer((_) => rpc);

    expect(await repository.fetchPublicAdminCampanelli(), rows);
    verify(() => harness.client.rpc('get_public_admin_campanelli')).called(1);
  });

  test('fetchHouseRows mantiene colonne e tabella originali', () async {
    final rows = <Map<String, dynamic>>[
      {'campanello_hinoo_id': 'h-1', 'owner_id': 'user-1'},
    ];
    houses.queueResponse(rows);

    expect(await repository.fetchHouseRows(), rows);
    verify(() => harness.client.from('case')).called(1);
    verify(
      () => houses.select(
        'campanello_hinoo_id,owner_id,house_image_url,house_text,bg_transform,created_at',
      ),
    ).called(1);
  });

  test('fetchShareSettingsRows mantiene filtro sugli Hinoo', () async {
    final rows = <Map<String, dynamic>>[
      {'campanello_hinoo_id': 'h-1', 'share_mode': 'honoo'},
    ];
    settings.queueResponse(rows);

    expect(await repository.fetchShareSettingsRows(['h-1', 'h-2']), rows);
    verify(() => harness.client.from('house_share_settings')).called(1);
    verify(() => settings.in_('campanello_hinoo_id', ['h-1', 'h-2'])).called(1);
  });

  test('fetchHinooRows mantiene filtro sugli identificativi', () async {
    final rows = <Map<String, dynamic>>[
      {'id': 'h-1', 'pages': <dynamic>[]},
    ];
    hinoo.queueResponse(rows);

    expect(await repository.fetchHinooRows(['h-1']), rows);
    verify(() => harness.client.from('hinoo')).called(1);
    verify(() => hinoo.select('id,pages')).called(1);
    verify(() => hinoo.in_('id', ['h-1'])).called(1);
  });

  test('liste vuote evitano query settings e Hinoo', () async {
    expect(await repository.fetchShareSettingsRows(const []), isEmpty);
    expect(await repository.fetchHinooRows(const []), isEmpty);
    verifyNever(() => harness.client.from('house_share_settings'));
    verifyNever(() => harness.client.from('hinoo'));
  });

  test(
    'fetchPendingKnockRows filtra case possedute e accessi non concessi',
    () async {
      final rows = <Map<String, dynamic>>[
        {'id': 'knock-1', 'target_house_tag': 'h-1'},
      ];
      houseAccess.queueResponse(rows);

      expect(await repository.fetchPendingKnockRows(['h-1']), rows);
      verify(() => houseAccess.in_('target_house_tag', ['h-1'])).called(1);
      verify(() => houseAccess.is_('granted_at', null)).called(1);
    },
  );

  test('fetchHinooForKnock mantiene selezione e identificativo', () async {
    final row = <String, dynamic>{'pages': <dynamic>[], 'type': 'answer'};
    hinoo.queueResponse(row);

    expect(await repository.fetchHinooForKnock('h-1'), row);
    verify(() => hinoo.select('pages,type,recipient_tag,created_at')).called(1);
    verify(() => hinoo.eq('id', 'h-1')).called(1);
    verify(() => hinoo.maybeSingle()).called(1);
  });

  test('fetchHonooForKnock mantiene selezione e identificativo', () async {
    final row = <String, dynamic>{'id': 'honoo-1', 'text': 'Test'};
    honoo.queueResponse(row);

    expect(await repository.fetchHonooForKnock('honoo-1'), row);
    verify(() => honoo.eq('id', 'honoo-1')).called(1);
    verify(() => honoo.maybeSingle()).called(1);
  });

  test('grantHouseAccess aggiorna solo la bussata indicata', () async {
    final grantedAt = DateTime.utc(2026, 7, 17, 10, 30);
    houseAccess.queueResponse(<String, dynamic>{});

    await repository.grantHouseAccess(knockId: 'knock-1', grantedAt: grantedAt);

    verify(
      () => houseAccess.update({'granted_at': '2026-07-17T10:30:00.000Z'}),
    ).called(1);
    verify(() => houseAccess.eq('id', 'knock-1')).called(1);
  });

  test('approveHouseKnock salva i filtri sulla singola bussata', () async {
    final rpc = MockQueryChain()..queueResponse(null);
    when(
      () => harness.client.rpc(
        'approve_house_knock',
        params: any(named: 'params'),
      ),
    ).thenAnswer((_) => rpc);

    await repository.approveHouseKnock(
      knockId: '42',
      shareModes: const ['home', 'moon'],
    );

    verify(
      () => harness.client.rpc(
        'approve_house_knock',
        params: {
          'p_knock_id': 42,
          'p_share_modes': ['home', 'moon'],
        },
      ),
    ).called(1);
  });

  test('fetchGrantedHouseTags restituisce solo tag validi', () async {
    when(
      () => houseAccess.not('granted_at', 'is', null),
    ).thenAnswer((_) => houseAccess);
    houseAccess.queueResponse(const [
      {
        'target_house_tag': 'house-1',
        'share_modes': ['home'],
      },
      {
        'target_house_tag': '',
        'share_modes': ['all'],
      },
      {'target_house_tag': 'legacy-house', 'share_modes': []},
      {
        'target_house_tag': 'house-2',
        'share_modes': ['moon'],
      },
    ]);

    expect(await repository.fetchGrantedHouseTags('visitor-1'), [
      'house-1',
      'house-2',
    ]);
    verify(() => houseAccess.eq('visitor_id', 'visitor-1')).called(1);
    verify(() => houseAccess.not('granted_at', 'is', null)).called(1);
  });

  test('saveShareModes mantiene payload e chiave di conflitto', () async {
    final updatedAt = DateTime.utc(2026, 7, 18, 10, 30);
    when(
      () => settings.upsert(any(), onConflict: any(named: 'onConflict')),
    ).thenAnswer((_) => settings);
    settings.queueResponse(<String, dynamic>{});

    await repository.saveShareModes(
      ownerId: 'owner-1',
      campanelloHinooId: 'hinoo-1',
      modes: const ['honoo', 'hinoo'],
      updatedAt: updatedAt,
    );

    verify(
      () => settings.upsert({
        'owner_id': 'owner-1',
        'campanello_hinoo_id': 'hinoo-1',
        'share_mode': 'honoo',
        'share_modes': ['honoo', 'hinoo'],
        'updated_at': '2026-07-18T10:30:00.000Z',
      }, onConflict: 'campanello_hinoo_id'),
    ).called(1);
  });
}

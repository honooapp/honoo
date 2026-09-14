import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:honoo/Controller/campanelli_controller.dart';
import 'package:honoo/Entities/hinoo.dart';
import 'package:honoo/Entities/casa_request_result.dart';
import 'package:honoo/Entities/campanelli_realtime_event.dart';
import 'package:honoo/Services/admin_service.dart';
import 'package:honoo/Services/campanelli_repository.dart';
import 'package:honoo/Services/campanelli_realtime_service.dart';
import 'package:honoo/Services/house_invite_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MockCampanelliRepository extends Mock
    implements CampanelliDataRepository {}

class _MockHouseInviteService extends Mock implements HouseInviteService {}

class _MockAdminService extends Mock implements AdminService {}

class _MockSupabaseClient extends Mock implements SupabaseClient {}

class _MockGoTrueClient extends Mock implements GoTrueClient {}

class _FakeSubscription implements CampanelliRealtimeSubscription {
  bool closed = false;

  @override
  void close() => closed = true;
}

class _FakeRealtimeGateway implements CampanelliRealtimeGateway {
  final ownerSubscription = _FakeSubscription();
  final visitorSubscription = _FakeSubscription();
  void Function(Map<String, dynamic>)? onPendingInsert;
  void Function(String)? onDelete;
  void Function(String)? onAccessGranted;

  @override
  CampanelliRealtimeSubscription subscribeOwner({
    required String userId,
    required List<String> ownedHinooIds,
    required void Function(Map<String, dynamic> row) onPendingInsert,
    required void Function(String id) onDelete,
  }) {
    this.onPendingInsert = onPendingInsert;
    this.onDelete = onDelete;
    return ownerSubscription;
  }

  @override
  CampanelliRealtimeSubscription subscribeVisitor({
    required String userId,
    required void Function(String targetTag) onAccessGranted,
  }) {
    this.onAccessGranted = onAccessGranted;
    return visitorSubscription;
  }
}

void main() {
  late _MockCampanelliRepository repository;
  late _MockHouseInviteService houseInviteService;
  late _MockAdminService adminService;
  late _MockSupabaseClient client;
  late _MockGoTrueClient auth;
  late CampanelliController controller;

  setUp(() {
    repository = _MockCampanelliRepository();
    houseInviteService = _MockHouseInviteService();
    adminService = _MockAdminService();
    client = _MockSupabaseClient();
    auth = _MockGoTrueClient();
    when(() => client.auth).thenReturn(auth);
    controller = CampanelliController(
      repository: repository,
      houseInviteService: houseInviteService,
      adminService: adminService,
      client: client,
    );
  });

  tearDown(() => controller.dispose());

  test('carica righe e identifica gli Hinoo posseduti', () async {
    when(repository.fetchHouseRows).thenAnswer((_) async => [
          {
            'campanello_hinoo_id': 'hinoo-owned',
            'owner_id': 'user-1',
            'house_image_url': 'house.png',
            'bg_transform': [1, 0, 0, 1],
          },
          {
            'campanello_hinoo_id': 'hinoo-other',
            'owner_id': 'user-2',
          },
        ]);
    when(() => repository.fetchShareSettingsRows(any()))
        .thenAnswer((_) async => const [
              {'campanello_hinoo_id': 'hinoo-owned'}
            ]);
    when(() => repository.fetchHinooRows(any())).thenAnswer((_) async => const [
          {
            'id': 'hinoo-owned',
            'pages': [
              {
                'text': ' Il mio campanello ',
                'backgroundImage': 'bell.png',
                'isTextWhite': true,
                'bgScale': 1.2,
                'bgOffsetX': 0.1,
                'bgOffsetY': -0.2,
              }
            ],
          }
        ]);

    final loadingStates = <bool>[];
    controller.addListener(
      () => loadingStates.add(controller.state.isLoading),
    );
    final state = await controller.load('user-1');

    expect(loadingStates, [true, false]);
    expect(state.error, isNull);
    expect(state.ownedHinooIds, ['hinoo-owned']);
    expect(state.hasOwnHouse, isTrue);
    expect(state.entries, hasLength(1));
    expect(state.entries.single.text, 'Il mio campanello');
    expect(state.entries.single.ownerId, 'user-1');
    expect(state.entries.single.houseImageUrl, 'house.png');
    expect(state.entries.single.bgTransform, [1.0, 0.0, 0.0, 1.0]);
    verify(() => repository.fetchShareSettingsRows(
          ['hinoo-owned', 'hinoo-other'],
        )).called(1);
  });

  test('compone campanello e casa appartenenti a un altro utente', () async {
    when(repository.fetchHouseRows).thenAnswer((_) async => const [
          {
            'campanello_hinoo_id': 'hinoo-other',
            'owner_id': 'user-2',
            'house_image_url': 'other-house.png',
          },
        ]);
    when(() => repository.fetchShareSettingsRows(any()))
        .thenAnswer((_) async => const []);
    when(() => repository.fetchHinooRows(any())).thenAnswer((_) async => const [
          {
            'id': 'hinoo-other',
            'pages': [
              {
                'text': 'Campanello pubblico',
                'backgroundImage': 'other-bell.png',
                'isTextWhite': false,
              }
            ],
          },
        ]);

    final state = await controller.load('user-1');

    expect(state.hasOwnHouse, isFalse);
    expect(state.entries, hasLength(1));
    expect(state.entries.single.ownerId, 'user-2');
    expect(state.entries.single.campanelloBackgroundUrl, 'other-bell.png');
    expect(state.entries.single.houseImageUrl, 'other-house.png');
  });

  test('mette il proprio campanello in testa e gli altri per creazione',
      () async {
    when(repository.fetchHouseRows).thenAnswer((_) async => const [
          {
            'campanello_hinoo_id': 'hinoo-newer',
            'owner_id': 'user-3',
            'created_at': '2026-08-03T10:00:00Z',
          },
          {
            'campanello_hinoo_id': 'hinoo-owned',
            'owner_id': 'user-1',
            'created_at': '2026-08-04T10:00:00Z',
          },
          {
            'campanello_hinoo_id': 'hinoo-older',
            'owner_id': 'user-2',
            'created_at': '2026-08-01T10:00:00Z',
          },
        ]);
    when(() => repository.fetchShareSettingsRows(any()))
        .thenAnswer((_) async => const []);
    when(() => repository.fetchHinooRows(any())).thenAnswer((_) async => const [
          {
            'id': 'hinoo-newer',
            'pages': [
              {'text': 'Più recente'}
            ],
          },
          {
            'id': 'hinoo-owned',
            'pages': [
              {'text': 'Mio'}
            ],
          },
          {
            'id': 'hinoo-older',
            'pages': [
              {'text': 'Più vecchio'}
            ],
          },
        ]);

    final state = await controller.load('user-1');

    expect(state.entries.map((entry) => entry.hinooId), [
      'hinoo-owned',
      'hinoo-older',
      'hinoo-newer',
    ]);
  });

  test('pubblica uno stato di errore senza conservare dati parziali', () async {
    when(repository.fetchHouseRows).thenThrow(StateError('offline'));

    final state = await controller.load('user-1');

    expect(state.isLoading, isFalse);
    expect(state.error, isA<StateError>());
    expect(state.entries, isEmpty);
  });

  test('con nessuna casa evita le query successive', () async {
    when(repository.fetchHouseRows).thenAnswer((_) async => const []);
    when(() => repository.fetchShareSettingsRows(any()))
        .thenAnswer((_) async => const []);
    when(() => repository.fetchHinooRows(any()))
        .thenAnswer((_) async => const []);

    await controller.load('user-1');

    verify(() => repository.fetchShareSettingsRows(const [])).called(1);
    verify(() => repository.fetchHinooRows(const [])).called(1);
  });

  test('carica e mappa le bussate pendenti', () async {
    when(() => repository.fetchPendingKnockRows(['hinoo-1']))
        .thenAnswer((_) async => const [
              {
                'id': 'knock-1',
                'target_house_tag': 'hinoo-1',
                'created_at': '2026-07-17T10:00:00Z',
                'honoo_id': 'honoo-1',
              },
              {'id': '', 'target_house_tag': 'invalid'},
            ]);

    final knocks = await controller.loadPendingKnocks(['hinoo-1']);

    expect(knocks, hasLength(1));
    expect(knocks.single.id, 'knock-1');
    expect(knocks.single.createdAt, DateTime.parse('2026-07-17T10:00:00Z'));
    expect(controller.pendingKnockTags, {'hinoo-1'});
  });

  test('mappa il contenuto Hinoo associato alla bussata', () async {
    when(() => repository.fetchHinooForKnock('hinoo-1'))
        .thenAnswer((_) async => const {
              'pages': [
                {
                  'text': 'Messaggio lungo',
                  'backgroundImage': 'background.png',
                  'isTextWhite': true,
                }
              ],
              'recipient_tag': 'owner-1',
            });

    final draft = await controller.fetchPendingHinoo('hinoo-1');

    expect(draft, isNotNull);
    expect(draft!.type, HinooType.answer);
    expect(draft.recipientTag, 'owner-1');
    expect(draft.pages.single.text, 'Messaggio lungo');
  });

  test('mappa il contenuto Honoo associato alla bussata', () async {
    when(() => repository.fetchHonooForKnock('honoo-1'))
        .thenAnswer((_) async => const {
              'id': 'honoo-1',
              'text': 'Messaggio breve',
              'image_url': 'image.png',
              'destination': 'reply',
              'created_at': '2026-07-17T10:00:00Z',
              'updated_at': '2026-07-17T10:00:00Z',
              'user_id': 'visitor-1',
              'recipient_tag': 'owner-1',
            });

    final honoo = await controller.fetchPendingHonoo('honoo-1');

    expect(honoo, isNotNull);
    expect(honoo!.dbId, 'honoo-1');
    expect(honoo.text, 'Messaggio breve');
    expect(honoo.recipientTag, 'owner-1');
  });

  test('approva la bussata e la rimuove dallo stato', () async {
    controller.addPendingKnockRow(const {
      'id': 'knock-1',
      'target_house_tag': 'hinoo-1',
      'created_at': '2026-07-18T10:00:00Z',
    });
    when(() => repository.approveHouseKnock(
          knockId: 'knock-1',
          shareModes: ['home', 'moon'],
        )).thenAnswer((_) async {});

    await controller.approvePendingKnock(
      knockId: 'knock-1',
      shareModes: const ['home', 'moon'],
    );

    verify(() => repository.approveHouseKnock(
          knockId: 'knock-1',
          shareModes: ['home', 'moon'],
        )).called(1);
    expect(controller.state.pendingKnocks, isEmpty);
  });

  test('invia una bussata attraverso il repository', () async {
    when(() => repository.sendHouseKnock(
          targetHouseTag: 'hinoo-1',
          visitorId: 'visitor-1',
          hinooId: 'message-1',
          honooId: null,
        )).thenAnswer((_) async {});

    await controller.sendHouseKnock(
      targetHouseTag: 'hinoo-1',
      visitorId: 'visitor-1',
      hinooId: 'message-1',
    );

    verify(() => repository.sendHouseKnock(
          targetHouseTag: 'hinoo-1',
          visitorId: 'visitor-1',
          hinooId: 'message-1',
          honooId: null,
        )).called(1);
  });

  test('salva le modalità di condivisione attraverso il repository', () async {
    final updatedAt = DateTime.utc(2026, 7, 18, 12);
    when(() => repository.saveShareModes(
          ownerId: 'owner-1',
          campanelloHinooId: 'hinoo-1',
          modes: ['home', 'all'],
          updatedAt: updatedAt,
        )).thenAnswer((_) async {});

    await controller.saveShareModes(
      ownerId: 'owner-1',
      campanelloHinooId: 'hinoo-1',
      modes: const ['home', 'all'],
      updatedAt: updatedAt,
    );

    verify(() => repository.saveShareModes(
          ownerId: 'owner-1',
          campanelloHinooId: 'hinoo-1',
          modes: ['home', 'all'],
          updatedAt: updatedAt,
        )).called(1);
  });

  test('mantiene la bussata pendente se la concessione fallisce', () async {
    controller.addPendingKnockRow(const {
      'id': 'knock-1',
      'target_house_tag': 'hinoo-1',
      'created_at': '2026-07-18T10:00:00Z',
    });
    when(() => repository.approveHouseKnock(
          knockId: any(named: 'knockId'),
          shareModes: any(named: 'shareModes'),
        )).thenThrow(StateError('offline'));

    await expectLater(
      controller.approvePendingKnock(
        knockId: 'knock-1',
        shareModes: const ['home'],
      ),
      throwsStateError,
    );

    expect(controller.state.pendingKnocks.single.id, 'knock-1');
  });

  test('carica lo stato invito e impedisce richieste concorrenti', () async {
    when(() => houseInviteService.hasPendingOrAcceptedInvite('user-1'))
        .thenAnswer((_) async => true);

    expect(await controller.refreshHouseInviteState('user-1'), isTrue);
    expect(controller.state.hasPendingOrAcceptedInvite, isTrue);
    expect(controller.beginInviteRequest(), isTrue);
    expect(controller.beginInviteRequest(), isFalse);
    expect(controller.state.isInviteRequestBusy, isTrue);

    controller.endInviteRequest();
    expect(controller.state.isInviteRequestBusy, isFalse);
  });

  test('riconosce e sincronizza un invito autorizzato da riprendere', () async {
    const user = User(
      id: 'user-1',
      appMetadata: {},
      userMetadata: {},
      aud: 'authenticated',
      createdAt: '2026-07-18T12:00:00Z',
      email: 'user@example.com',
    );
    when(() => auth.currentUser).thenReturn(user);
    when(() => houseInviteService.syncInvitesForEmail('user@example.com'))
        .thenAnswer((_) async {});
    when(() => houseInviteService.hasAuthorizedInvite('user-1'))
        .thenAnswer((_) async => true);

    expect(await controller.hasAuthorizedHouseInvite(), isTrue);
    verify(
      () => houseInviteService.syncInvitesForEmail('user@example.com'),
    ).called(1);
    verify(() => houseInviteService.hasAuthorizedInvite('user-1')).called(1);
  });

  test('registra la richiesta e aggiorna lo stato solo dopo il successo',
      () async {
    final createdAt = DateTime.utc(2026, 7, 18, 12);
    when(() => houseInviteService.createPendingRequest(
          userId: 'user-1',
          email: 'user@example.com',
          createdAt: createdAt,
        )).thenAnswer((_) async => true);

    await controller.createPendingHouseRequest(
      userId: 'user-1',
      email: 'user@example.com',
      createdAt: createdAt,
    );

    expect(controller.state.hasPendingOrAcceptedInvite, isTrue);
  });

  group('richiesta Casa tipizzata', () {
    const user = User(
      id: 'user-1',
      appMetadata: {},
      userMetadata: {},
      aud: 'authenticated',
      createdAt: '2026-07-18T12:00:00Z',
      email: 'user@example.com',
    );

    setUp(() {
      when(() => auth.currentUser).thenReturn(user);
      when(() => houseInviteService.hasCasa('user-1'))
          .thenAnswer((_) async => false);
      when(() => houseInviteService.hasPendingOrAcceptedInvite('user-1'))
          .thenAnswer((_) async => false);
      when(() => adminService.isCurrentUserAdmin())
          .thenAnswer((_) async => false);
    });

    test('senza sessione restituisce sessionAbsent', () async {
      when(() => auth.currentUser).thenReturn(null);

      expect(
        await controller.requestHouseInvite(),
        CasaRequestResult.sessionAbsent,
      );
    });

    test('richiesta normale restituisce success', () async {
      when(() => houseInviteService.createPendingRequest(
            userId: 'user-1',
            email: 'user@example.com',
            createdAt: any(named: 'createdAt'),
          )).thenAnswer((_) async => true);

      expect(
        await controller.requestHouseInvite(),
        CasaRequestResult.success,
      );
      expect(controller.state.hasPendingOrAcceptedInvite, isTrue);
    });

    test('richiesta duplicata restituisce alreadyPresent', () async {
      when(() => houseInviteService.hasPendingOrAcceptedInvite('user-1'))
          .thenAnswer((_) async => true);

      expect(
        await controller.requestHouseInvite(),
        CasaRequestResult.alreadyPresent,
      );
      verifyNever(() => houseInviteService.createPendingRequest(
            userId: any(named: 'userId'),
            email: any(named: 'email'),
            createdAt: any(named: 'createdAt'),
          ));
    });

    test('amministratore restituisce administrator senza creare richiesta',
        () async {
      when(() => adminService.isCurrentUserAdmin())
          .thenAnswer((_) async => true);

      expect(
        await controller.requestHouseInvite(),
        CasaRequestResult.administrator,
      );
      verifyNever(() => houseInviteService.createPendingRequest(
            userId: any(named: 'userId'),
            email: any(named: 'email'),
            createdAt: any(named: 'createdAt'),
          ));
    });

    test('classifica RLS e backend non disponibili', () async {
      when(() => houseInviteService.createPendingRequest(
            userId: any(named: 'userId'),
            email: any(named: 'email'),
            createdAt: any(named: 'createdAt'),
          )).thenThrow(
        const PostgrestException(message: 'not allowed', code: '42501'),
      );
      expect(
        await controller.requestHouseInvite(),
        CasaRequestResult.rlsError,
      );

      when(() => houseInviteService.createPendingRequest(
            userId: any(named: 'userId'),
            email: any(named: 'email'),
            createdAt: any(named: 'createdAt'),
          )).thenThrow(StateError('offline'));
      expect(
        await controller.requestHouseInvite(),
        CasaRequestResult.backendUnavailable,
      );
    });
  });

  test('Realtime sostituisce duplicati e rimuove per id', () {
    expect(
      controller.addPendingKnockRow(const {
        'id': 'knock-1',
        'target_house_tag': 'hinoo-1',
        'created_at': '2026-07-17T10:00:00Z',
      }),
      isTrue,
    );
    controller.addPendingKnockRow(const {
      'id': 'knock-1',
      'target_house_tag': 'hinoo-2',
      'created_at': '2026-07-17T11:00:00Z',
    });

    expect(controller.state.pendingKnocks, hasLength(1));
    expect(controller.state.pendingKnocks.single.targetTag, 'hinoo-2');

    controller.removePendingKnock('knock-1');
    expect(controller.state.pendingKnocks, isEmpty);
    expect(controller.pendingKnockTags, isEmpty);
  });

  test('pubblica eventi Realtime tipizzati e chiude le sottoscrizioni',
      () async {
    final realtime = _FakeRealtimeGateway();
    final realtimeController = CampanelliController(
      repository: repository,
      realtimeGateway: realtime,
    );
    final events = <CampanelliRealtimeEvent>[];
    final eventsSubscription = realtimeController.realtimeEvents.listen(
      events.add,
    );

    realtimeController.startOwnerRealtime(
      userId: 'user-1',
      ownedHinooIds: const ['hinoo-1'],
    );
    realtimeController.startVisitorRealtime(
      userId: 'user-1',
    );
    realtime.onPendingInsert!(const {
      'id': 'knock-1',
      'target_house_tag': 'hinoo-1',
      'created_at': '2026-07-17T12:00:00Z',
    });
    realtime.onDelete!('knock-1');
    realtime.onAccessGranted!('hinoo-1');
    await Future<void>.delayed(Duration.zero);

    expect(events, hasLength(3));
    expect(events[0], isA<CampanelliPendingKnockReceived>());
    expect(
      (events[0] as CampanelliPendingKnockReceived).knock.id,
      'knock-1',
    );
    expect(
      (events[1] as CampanelliPendingKnockRemoved).knockId,
      'knock-1',
    );
    expect(
      (events[2] as CampanelliAccessGranted).targetTag,
      'hinoo-1',
    );
    expect(realtimeController.state.pendingKnocks, isEmpty);

    await eventsSubscription.cancel();
    realtimeController.dispose();
    expect(realtime.ownerSubscription.closed, isTrue);
    expect(realtime.visitorSubscription.closed, isTrue);
  });

  test('impedisce refresh periodici concorrenti', () async {
    final response = Completer<List<dynamic>>();
    when(() => repository.fetchPendingKnockRows(['hinoo-1']))
        .thenAnswer((_) => response.future);
    var changes = 0;

    final first = controller.refreshPendingKnocks(
      ['hinoo-1'],
      onChanged: () => changes++,
    );
    final second = await controller.refreshPendingKnocks(
      ['hinoo-1'],
      onChanged: () => changes++,
    );
    response.complete(const []);

    expect(second, isFalse);
    expect(await first, isTrue);
    expect(changes, 1);
    verify(() => repository.fetchPendingKnockRows(['hinoo-1'])).called(1);
  });

  test('timer periodico viene fermato dal controller', () async {
    when(() => repository.fetchPendingKnockRows(['hinoo-1']))
        .thenAnswer((_) async => const []);
    var changes = 0;

    await controller.startPendingKnockRefresh(
      ownedHinooIds: ['hinoo-1'],
      onChanged: () => changes++,
      interval: const Duration(milliseconds: 20),
    );
    await Future<void>.delayed(const Duration(milliseconds: 55));
    controller.stopPendingKnockRefresh();
    final stoppedAt = changes;
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(stoppedAt, greaterThanOrEqualTo(2));
    expect(changes, stoppedAt);
  });
}

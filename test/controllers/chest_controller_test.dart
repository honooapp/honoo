import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:honoo/Controller/chest_controller.dart';
import 'package:honoo/Entities/chest_item.dart';
import 'package:honoo/Entities/hinoo.dart';
import 'package:honoo/Services/chest_realtime_service.dart';
import 'package:honoo/Services/chest_repository.dart';
import 'package:honoo/Services/hinoo_service.dart';
import 'package:mocktail/mocktail.dart';

class _MockChestRepository extends Mock implements ChestRepository {}

class _FakeRealtimeSubscription implements ChestRealtimeSubscription {
  bool closed = false;

  @override
  Future<void> close() async => closed = true;
}

class _FakeRealtimeGateway implements ChestRealtimeGateway {
  String? userId;
  void Function()? onChange;
  void Function(ChestRealtimeConnectionStatus, Object?)? onStatus;
  final subscriptions = <_FakeRealtimeSubscription>[];
  _FakeRealtimeSubscription get subscription => subscriptions.last;

  @override
  ChestRealtimeSubscription subscribe({
    required String userId,
    required void Function() onChange,
    required void Function(ChestRealtimeConnectionStatus, Object?) onStatus,
  }) {
    this.userId = userId;
    this.onChange = onChange;
    this.onStatus = onStatus;
    final subscription = _FakeRealtimeSubscription();
    subscriptions.add(subscription);
    return subscription;
  }
}

class _FailingRealtimeGateway implements ChestRealtimeGateway {
  @override
  ChestRealtimeSubscription subscribe({
    required String userId,
    required void Function() onChange,
    required void Function(ChestRealtimeConnectionStatus, Object?) onStatus,
  }) {
    throw StateError('Realtime non disponibile');
  }
}

void main() {
  late _MockChestRepository repository;
  late _FakeRealtimeGateway realtimeGateway;
  late ChestController controller;

  setUp(() {
    repository = _MockChestRepository();
    realtimeGateway = _FakeRealtimeGateway();
    controller = ChestController(
      repository: repository,
      realtimeGateway: realtimeGateway,
    );
  });

  tearDown(() => controller.dispose());

  test('loadHinoo mappa le righe e pubblica uno stato immutabile', () async {
    when(() => repository.fetchHinooRows('user-1')).thenAnswer(
      (_) async => [
        {
          'id': 'h-1',
          'pages': [
            {
              'backgroundImage': 'background.png',
              'text': 'Testo',
              'isTextWhite': true,
            },
          ],
          'type': 'personal',
          'created_at': '2024-01-01T00:00:00Z',
          'user_id': 'user-1',
        },
      ],
    );
    when(
      () => repository.fetchHinooMoonFingerprints('user-1'),
    ).thenAnswer((_) async => const {});

    await controller.loadHinoo('user-1');

    expect(controller.value.isHinooLoading, isFalse);
    expect(controller.value.hinoo.single.id, 'h-1');
    expect(controller.value.hinoo.single.draft.pages.single.text, 'Testo');
    expect(
      () => controller.value.hinoo.add(controller.value.hinoo.single),
      throwsUnsupportedError,
    );
  });

  test('loadHinoo marca il contenuto già pubblicato sulla Luna', () async {
    const row = {
      'id': 'h-1',
      'pages': [
        {
          'backgroundImage': 'background.png',
          'text': 'Testo',
          'isTextWhite': true,
        },
      ],
      'type': 'personal',
      'created_at': '2024-01-01T00:00:00Z',
      'user_id': 'user-1',
    };
    final draft = ChestHinooItem.fromDatabaseRow(row)!.draft;
    final fingerprint = HinooService.fingerprint(
      draft.copyWith(type: HinooType.moon),
    );
    when(
      () => repository.fetchHinooRows('user-1'),
    ).thenAnswer((_) async => [row]);
    when(
      () => repository.fetchHinooMoonFingerprints('user-1'),
    ).thenAnswer((_) async => {fingerprint});

    await controller.loadHinoo('user-1');

    expect(controller.value.hinoo.single.isOnMoon, isTrue);
  });

  for (final legacy in [false, true]) {
    test('loadHinoo recognizes reply moon copy, legacy=$legacy', () async {
      final row = {
        'id': 'reply-1',
        'pages': [
          {
            'backgroundImage': 'bg.png',
            'text': 'Risposta',
            'isTextWhite': true,
          },
        ],
        'type': 'answer',
        'recipient_tag': 'user-2',
        'reply_to': 'root-1',
        'conversation_id': 'conversation-1',
        'user_id': 'user-1',
      };
      final draft = ChestHinooItem.fromDatabaseRow(row)!.draft;
      final moon = legacy
          ? draft.copyWith(type: HinooType.moon)
          : HinooDraft(pages: draft.pages, type: HinooType.moon);
      when(
        () => repository.fetchHinooRows('user-1'),
      ).thenAnswer((_) async => [row]);
      when(
        () => repository.fetchHinooMoonFingerprints('user-1'),
      ).thenAnswer((_) async => {HinooService.fingerprint(moon)});
      await controller.loadHinoo('user-1');
      expect(controller.value.hinoo.single.isOnMoon, isTrue);
    });
  }

  test('loadReplies deduplica e conserva la risposta più recente', () async {
    when(() => repository.fetchHonooReplyRows('user-1')).thenAnswer(
      (_) async => [
        {
          'conversation_id': 'conversation-1',
          'reply_to': 'root-1',
          'created_at': '2024-01-01T10:00:00Z',
          'user_id': 'user-2',
        },
        {
          'conversation_id': 'conversation-1',
          'reply_to': 'reply-1',
          'created_at': '2024-01-01T12:00:00Z',
          'user_id': 'user-1',
        },
        {
          'conversation_id': 'conversation-1',
          'reply_to': 'reply-1',
          'created_at': '2024-01-01T12:00:00Z',
          'user_id': 'user-1',
        },
      ],
    );
    when(() => repository.fetchHinooReplyRows('user-1', const [])).thenAnswer(
      (_) async => [
        {
          'id': 'hinoo-reply-2',
          'conversation_id': 'hinoo-conversation-1',
          'reply_to': 'hinoo-reply-1',
          'created_at': '2024-01-01T13:00:00Z',
          'user_id': 'user-2',
          'pages': [
            <String, dynamic>{
              'backgroundImage': 'background.png',
              'text': 'Risposta concatenata',
              'isTextWhite': true,
            },
          ],
        },
      ],
    );

    await controller.loadReplies('user-1');

    expect(controller.value.replyError, isNull);
    expect(
      controller.value.honooLatestReplies['conversation-1'],
      DateTime.parse('2024-01-01T12:00:00Z'),
    );
    expect(
      controller.value.hinooLatestReplies['hinoo-conversation-1'],
      DateTime.parse('2024-01-01T13:00:00Z'),
    );
    expect(
      controller.value.honooLatestReceivedReplies['conversation-1'],
      DateTime.parse('2024-01-01T10:00:00Z'),
    );
    expect(
      controller.value.hinooLatestReceivedReplies['hinoo-conversation-1'],
      DateTime.parse('2024-01-01T13:00:00Z'),
    );
    expect(controller.value.isReplyLoading, isFalse);
    expect(
      () => controller.value.honooLatestReplies['other'] = DateTime.now(),
      throwsUnsupportedError,
    );
  });

  test(
    'loadReplies collega una risposta Hinoo legacy tramite conversation_id',
    () async {
      when(() => repository.fetchHinooRows('user-1')).thenAnswer(
        (_) async => [
          {
            'id': 'hinoo-root',
            'conversation_id': 'legacy-conversation',
            'pages': [
              <String, dynamic>{
                'backgroundImage': 'root.png',
                'text': 'Radice',
                'isTextWhite': true,
              },
            ],
            'type': 'personal',
            'created_at': '2024-01-01T10:00:00Z',
            'user_id': 'user-1',
          },
        ],
      );
      when(
        () => repository.fetchHinooMoonFingerprints('user-1'),
      ).thenAnswer((_) async => const {});
      when(
        () => repository.fetchHonooReplyRows('user-1'),
      ).thenAnswer((_) async => const []);
      when(
        () => repository.fetchHinooReplyRows('user-1', ['hinoo-root']),
      ).thenAnswer(
        (_) async => [
          {
            'id': 'legacy-reply',
            'conversation_id': 'legacy-conversation',
            'reply_to': null,
            'recipient_tag': 'user-1',
            'created_at': '2024-01-01T11:00:00Z',
            'user_id': 'user-2',
            'pages': [
              <String, dynamic>{
                'backgroundImage': 'reply.png',
                'text': 'Risposta legacy',
                'isTextWhite': true,
              },
            ],
          },
        ],
      );

      await controller.loadHinoo('user-1');
      await controller.loadReplies('user-1');

      expect(
        controller.value.hinooLatestReplies['legacy-conversation'],
        DateTime.parse('2024-01-01T11:00:00Z'),
      );
      expect(
        controller.value.hinooLatestReceivedReplies['legacy-conversation'],
        DateTime.parse('2024-01-01T11:00:00Z'),
      );
      expect(
        controller
            .value
            .hinooRepliesByRoot['hinoo-root']!
            .single
            .draft
            .pages
            .single
            .text,
        'Risposta legacy',
      );
      expect(
        controller.value.hinooRepliesByRoot['hinoo-root']!.single.draft.replyTo,
        'hinoo-root',
      );
    },
  );

  test(
    'un errore conserva i dati precedenti e termina il caricamento',
    () async {
      when(
        () => repository.fetchHinooRows('user-1'),
      ).thenThrow(Exception('offline'));

      await controller.loadHinoo('user-1');

      expect(controller.value.isHinooLoading, isFalse);
      expect(controller.value.hinoo, isEmpty);
      expect(controller.value.error, isA<Exception>());
    },
  );

  test('loadHinoo non aggiorna lo stato dopo dispose', () async {
    final pendingRows = Completer<List<dynamic>>();
    final disposableController = ChestController(
      repository: repository,
      realtimeGateway: realtimeGateway,
    );
    when(
      () => repository.fetchHinooRows('user-1'),
    ).thenAnswer((_) => pendingRows.future);

    final loading = disposableController.loadHinoo('user-1');
    await Future<void>.delayed(Duration.zero);
    disposableController.dispose();
    pendingRows.complete(const []);

    await expectLater(loading, completes);
  });

  test('il logout elimina immediatamente i dati dello Scrigno', () async {
    when(() => repository.fetchHinooRows('user-1')).thenAnswer(
      (_) async => [
        {
          'id': 'private-hinoo',
          'pages': [
            {
              'backgroundImage': 'background.png',
              'text': 'Privato',
              'isTextWhite': true,
            },
          ],
          'type': 'personal',
          'created_at': '2026-08-03T10:00:00Z',
          'user_id': 'user-1',
        },
      ],
    );
    when(
      () => repository.fetchHinooMoonFingerprints('user-1'),
    ).thenAnswer((_) async => const {});

    await controller.loadHinoo('user-1');
    expect(controller.value.hinoo, isNotEmpty);

    controller.completeWithoutUser();

    expect(controller.value.hinoo, isEmpty);
    expect(controller.value.honooLatestReplies, isEmpty);
    expect(controller.value.hinooRepliesByRoot, isEmpty);
  });

  test(
    'un caricamento del vecchio utente non contamina la nuova sessione',
    () async {
      final oldRows = Completer<List<dynamic>>();
      when(
        () => repository.fetchHinooRows('user-old'),
      ).thenAnswer((_) => oldRows.future);
      when(() => repository.fetchHinooRows('user-new')).thenAnswer(
        (_) async => [
          {
            'id': 'new-user-hinoo',
            'pages': [
              {
                'backgroundImage': 'background.png',
                'text': 'Nuovo utente',
                'isTextWhite': true,
              },
            ],
            'type': 'personal',
            'created_at': '2026-08-03T11:00:00Z',
            'user_id': 'user-new',
          },
        ],
      );
      when(
        () => repository.fetchHinooMoonFingerprints('user-new'),
      ).thenAnswer((_) async => const {});

      final oldLoad = controller.loadHinoo('user-old');
      await Future<void>.delayed(Duration.zero);
      await controller.loadHinoo('user-new');
      oldRows.complete(const []);
      await oldLoad;

      expect(controller.value.hinoo.single.id, 'new-user-hinoo');
    },
  );

  test('start e stop gestiscono il ciclo di vita Realtime', () {
    controller.startRealtime(
      'user-1',
      refreshInterval: const Duration(hours: 1),
    );

    expect(realtimeGateway.userId, 'user-1');
    expect(realtimeGateway.subscription.closed, isFalse);

    controller.stopRealtime();

    expect(realtimeGateway.subscription.closed, isTrue);
  });

  test('una disconnessione Realtime crea una nuova sottoscrizione', () async {
    final reconnectingController = ChestController(
      repository: repository,
      realtimeGateway: realtimeGateway,
      realtimeReconnectBaseDelay: const Duration(milliseconds: 5),
      realtimeReconnectMaxDelay: const Duration(milliseconds: 10),
    );
    addTearDown(reconnectingController.dispose);

    reconnectingController.startRealtime(
      'user-1',
      refreshInterval: const Duration(hours: 1),
    );
    final firstSubscription = realtimeGateway.subscription;
    realtimeGateway.onStatus!(
      ChestRealtimeConnectionStatus.disconnected,
      StateError('offline'),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(realtimeGateway.subscriptions, hasLength(2));
    expect(firstSubscription.closed, isTrue);
  });

  test(
    'la riconciliazione periodica può aggiornare tutto lo Scrigno',
    () async {
      var reconciliations = 0;
      controller.startRealtime(
        'user-1',
        refreshInterval: const Duration(milliseconds: 5),
        onPeriodicReconcile: () async => reconciliations++,
      );

      await Future<void>.delayed(const Duration(milliseconds: 18));

      expect(reconciliations, greaterThanOrEqualTo(1));
    },
  );

  test('un errore Realtime non impedisce l’avvio del controller', () {
    final resilientController = ChestController(
      repository: repository,
      realtimeGateway: _FailingRealtimeGateway(),
    );

    expect(
      () => resilientController.startRealtime(
        'user-1',
        refreshInterval: const Duration(hours: 1),
      ),
      returnsNormally,
    );
    resilientController.dispose();
  });

  test('gli eventi Realtime ravvicinati producono un solo refresh', () async {
    when(
      () => repository.fetchHonooReplyRows('user-1'),
    ).thenAnswer((_) async => const []);
    when(
      () => repository.fetchHinooReplyRows('user-1', const []),
    ).thenAnswer((_) async => const []);

    controller.startRealtime(
      'user-1',
      refreshInterval: const Duration(hours: 1),
    );
    realtimeGateway.onChange!();
    realtimeGateway.onChange!();

    await Future<void>.delayed(const Duration(milliseconds: 100));
    verifyNever(() => repository.fetchHonooReplyRows(any()));

    await Future<void>.delayed(const Duration(milliseconds: 200));
    verify(() => repository.fetchHonooReplyRows('user-1')).called(1);
  });

  test('un refresh arrivato durante il caricamento viene accodato', () async {
    final firstResponse = Completer<List<dynamic>>();
    var callCount = 0;
    when(() => repository.fetchHonooReplyRows('user-1')).thenAnswer((_) {
      callCount++;
      return callCount == 1 ? firstResponse.future : Future.value(const []);
    });
    when(
      () => repository.fetchHinooReplyRows('user-1', const []),
    ).thenAnswer((_) async => const []);

    final runningRefresh = controller.refreshReplies('user-1');
    await Future<void>.delayed(Duration.zero);
    await controller.refreshReplies('user-1');
    firstResponse.complete(const []);
    await runningRefresh;

    verify(() => repository.fetchHonooReplyRows('user-1')).called(2);
  });
}

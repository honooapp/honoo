import 'package:flutter_test/flutter_test.dart';
import 'package:honoo/Entities/conversation_entry.dart';
import 'package:honoo/Services/conversation_service.dart';
import 'package:mocktail/mocktail.dart';

import '../test_supabase_helper.dart';

void main() {
  setUpAll(registerSupabaseFallbacks);

  late SupabaseTestHarness harness;

  setUp(() {
    harness = SupabaseTestHarness(withAuthenticatedUser: true)
      ..enableOverrides();
    harness.stubTable('conversation_tombstones');
  });

  tearDown(() {
    harness.disableOverrides();
    resetMocktailState();
  });

  Map<String, dynamic> historyRow(
    String id, {
    String? parent,
    String? conversation,
    bool deleted = false,
  }) => {
    'id': id,
    'text': id,
    'pages': [
      {'text': id},
    ],
    'destination': parent == null ? 'chest' : 'reply',
    'type': parent == null ? 'personal' : 'answer',
    'reply_to': parent,
    'conversation_id': conversation,
    'created_at': '2026-01-01T10:00:00Z',
    'user_id': 'test_user',
    if (deleted) 'admin_deleted_at': '2026-01-02T10:00:00Z',
  };

  test(
    'recupera tutti gli antenati misti anche riaprendo lo scrigno',
    () async {
      final honoo = harness.stubTable('honoo');
      final hinoo = harness.stubTable('hinoo');
      // Repeat the same read: no local notification or new write is required.
      for (var opening = 0; opening < 2; opening++) {
        honoo.queueResponse([
          historyRow('last', parent: 'middle', conversation: 'current'),
        ]);
        hinoo.queueResponse([]);
        honoo.queueResponse([]);
        hinoo.queueResponse([
          historyRow('middle', parent: 'root', conversation: 'older'),
        ]);
        honoo.queueResponse([historyRow('root', conversation: 'original')]);
        hinoo.queueResponse([]);
        final entries = await ConversationService.fetchConversation('current');
        expect(entries.map((entry) => entry.id), ['root', 'middle', 'last']);
        expect(entries[1].kind, ConversationEntryKind.hinoo);
      }
      // Only descendants without a conversation id are eligible; never merge
      // the other dialogs attached to the shared root.
      verifyNever(() => honoo.in_('reply_to', ['root']));
      verifyNever(() => hinoo.in_('reply_to', ['middle']));
    },
  );

  test('recupera risposte legacy annidate Honoo e Hinoo', () async {
    final honoo = harness.stubTable('honoo');
    final hinoo = harness.stubTable('hinoo');
    honoo.queueResponse([historyRow('root')]);
    hinoo.queueResponse([]);
    honoo.queueResponse([]);
    hinoo.queueResponse([historyRow('middle', parent: 'root')]);
    honoo.queueResponse([historyRow('last', parent: 'middle')]);
    hinoo.queueResponse([]);

    final entries = await ConversationService.fetchConversation('root');
    expect(entries.map((entry) => entry.id), ['root', 'middle', 'last']);
    verify(() => honoo.in_('reply_to', ['middle'])).called(1);
    verify(() => hinoo.is_('conversation_id', null)).called(3);
  });

  test(
    'termina su cicli e genitori mancanti senza duplicare messaggi',
    () async {
      final honoo = harness.stubTable('honoo');
      final hinoo = harness.stubTable('hinoo');
      honoo.queueResponse([
        historyRow('last', parent: 'middle', conversation: 'current'),
        historyRow('orphan', parent: 'unavailable', conversation: 'current'),
      ]);
      hinoo.queueResponse([]);
      honoo.queueResponse([
        historyRow('middle', parent: 'last', conversation: 'older'),
        historyRow('last', parent: 'middle', conversation: 'current'),
      ]);
      hinoo.queueResponse([]);

      final entries = await ConversationService.fetchConversation('current');
      expect(entries.map((entry) => entry.id).toSet(), {
        'last',
        'middle',
        'orphan',
      });
      expect(entries, hasLength(3));
      verify(() => honoo.in_('id', ['middle', 'unavailable'])).called(1);
    },
  );

  test('mantiene il segnaposto per un antenato eliminato', () async {
    final honoo = harness.stubTable('honoo');
    final hinoo = harness.stubTable('hinoo');
    honoo.queueResponse([
      historyRow('last', parent: 'deleted', conversation: 'current'),
    ]);
    hinoo.queueResponse([]);
    honoo.queueResponse([
      historyRow('deleted', conversation: 'older', deleted: true),
    ]);
    hinoo.queueResponse([]);
    final entries = await ConversationService.fetchConversation('current');
    expect(entries.map((entry) => entry.id), ['deleted', 'last']);
    expect(entries.first.kind, ConversationEntryKind.deleted);
  });

  test('ordina honoo e hinoo usando il created_at reale', () async {
    final honoo = harness.stubTable('honoo');
    final hinoo = harness.stubTable('hinoo');
    honoo.queueResponse(<Map<String, dynamic>>[
      {
        'id': 'honoo-1',
        'text': 'prima',
        'image_url': '',
        'destination': 'chest',
        'created_at': '2026-01-01T10:00:00Z',
        'updated_at': '2026-01-01T10:00:00Z',
        'user_id': 'user-1',
        'conversation_id': 'conversation-1',
      },
    ]);
    hinoo.queueResponse(<Map<String, dynamic>>[
      {
        'id': 'hinoo-1',
        'pages': <Map<String, dynamic>>[
          {'text': 'seconda', 'backgroundImage': 'bg.png', 'isTextWhite': true},
        ],
        'type': 'answer',
        'created_at': '2026-01-01T11:00:00Z',
        'user_id': 'user-2',
        'conversation_id': 'conversation-1',
      },
    ]);

    final result = await ConversationService.fetchConversation(
      'conversation-1',
    );

    expect(result.map((entry) => entry.kind), [
      ConversationEntryKind.honoo,
      ConversationEntryKind.hinoo,
    ]);
    expect(result.last.createdAt, DateTime.parse('2026-01-01T11:00:00Z'));
    verify(
      () => honoo.or(
        'conversation_id.eq.conversation-1,and(conversation_id.is.null,or(id.eq.conversation-1,reply_to.eq.conversation-1))',
      ),
    ).called(1);
    verify(
      () => hinoo.or(
        'conversation_id.eq.conversation-1,and(conversation_id.is.null,or(id.eq.conversation-1,reply_to.eq.conversation-1))',
      ),
    ).called(1);
  });

  test('carica radice e risposte legacy senza conversation_id', () async {
    final honoo = harness.stubTable('honoo');
    final hinoo = harness.stubTable('hinoo');
    honoo.queueResponse([
      {
        'id': 'root',
        'text': 'radice',
        'destination': 'chest',
        'created_at': '2026-01-01T10:00:00Z',
        'user_id': 'test_user',
      },
      {
        'id': 'reply',
        'text': 'risposta',
        'destination': 'reply',
        'reply_to': 'root',
        'created_at': '2026-01-01T11:00:00Z',
        'user_id': 'other',
      },
    ]);
    hinoo.queueResponse([
      {
        'id': 'hinoo-reply',
        'pages': [
          {'text': 'risposta hinoo'},
        ],
        'type': 'answer',
        'reply_to': 'root',
        'created_at': '2026-01-01T12:00:00Z',
        'user_id': 'other',
      },
    ]);
    final entries = await ConversationService.fetchConversation('root');
    expect(entries.map((e) => e.id), ['root', 'reply', 'hinoo-reply']);
    const filter =
        'conversation_id.eq.root,and(conversation_id.is.null,or(id.eq.root,reply_to.eq.root))';
    verify(() => honoo.or(filter)).called(1);
    verify(() => hinoo.or(filter)).called(1);
  });

  test('riconosce una vecchia risposta Hinoo anche senza reply_to', () async {
    final honoo = harness.stubTable('honoo');
    final hinoo = harness.stubTable('hinoo');
    honoo.queueResponse(<Map<String, dynamic>>[]);
    hinoo.queueResponse(<Map<String, dynamic>>[
      {
        'id': 'hinoo-legacy-reply',
        'pages': <Map<String, dynamic>>[
          {
            'text': 'risposta',
            'backgroundImage': 'bg.png',
            'isTextWhite': true,
          },
        ],
        'type': 'personal',
        'reply_to': null,
        'recipient_tag': 'recipient-1',
        'conversation_id': 'conversation-1',
        'created_at': '2026-01-01T11:00:00Z',
        'user_id': 'user-2',
        'is_from_moon_saved': false,
      },
    ]);

    final result = await ConversationService.fetchConversation(
      'conversation-1',
    );

    expect(result.single.hinoo!.type.name, 'answer');
  });

  test(
    'preferisce una sola copia Honoo salvata dalla Luna alla radice',
    () async {
      final honoo = harness.stubTable('honoo');
      final hinoo = harness.stubTable('hinoo');
      honoo.queueResponse(<Map<String, dynamic>>[
        {
          'id': 'moon-root',
          'text': 'stesso contenuto',
          'image_url': 'image.png',
          'destination': 'moon',
          'created_at': '2026-01-01T09:00:00Z',
          'updated_at': '2026-01-01T09:00:00Z',
          'user_id': 'author',
          'conversation_id': 'conversation-1',
          'is_from_moon_saved': false,
        },
        {
          'id': 'saved-root',
          'text': 'stesso contenuto',
          'image_url': 'image.png',
          'destination': 'chest',
          'created_at': '2026-01-01T10:00:00Z',
          'updated_at': '2026-01-01T10:00:00Z',
          'user_id': 'test_user',
          'conversation_id': 'conversation-1',
          'is_from_moon_saved': true,
        },
        {
          'id': 'reply',
          'text': 'risposta',
          'image_url': '',
          'destination': 'reply',
          'reply_to': 'moon-root',
          'created_at': '2026-01-01T11:00:00Z',
          'updated_at': '2026-01-01T11:00:00Z',
          'user_id': 'test_user',
          'conversation_id': 'conversation-1',
          'is_from_moon_saved': false,
        },
      ]);
      hinoo.queueResponse(<Map<String, dynamic>>[]);

      final result = await ConversationService.fetchConversation(
        'conversation-1',
      );

      expect(result.map((entry) => entry.id), ['saved-root', 'reply']);
      expect(result.first.isFromMoonSaved, isTrue);
    },
  );

  test(
    'preferisce una sola copia Hinoo salvata dalla Luna alla radice',
    () async {
      final honoo = harness.stubTable('honoo');
      final hinoo = harness.stubTable('hinoo');
      honoo.queueResponse(<Map<String, dynamic>>[]);
      final pages = <Map<String, dynamic>>[
        {
          'text': 'stesso contenuto',
          'backgroundImage': 'bg.png',
          'isTextWhite': true,
        },
      ];
      hinoo.queueResponse(<Map<String, dynamic>>[
        {
          'id': 'moon-root',
          'pages': pages,
          'type': 'moon',
          'created_at': '2026-01-01T09:00:00Z',
          'user_id': 'author',
          'conversation_id': 'conversation-1',
          'is_from_moon_saved': false,
        },
        {
          'id': 'saved-root',
          'pages': pages,
          'type': 'personal',
          'created_at': '2026-01-01T10:00:00Z',
          'user_id': 'test_user',
          'conversation_id': 'conversation-1',
          'is_from_moon_saved': true,
        },
        {
          'id': 'reply',
          'pages': <Map<String, dynamic>>[
            {
              'text': 'risposta',
              'backgroundImage': 'reply.png',
              'isTextWhite': true,
            },
          ],
          'type': 'answer',
          'reply_to': 'moon-root',
          'created_at': '2026-01-01T11:00:00Z',
          'user_id': 'test_user',
          'conversation_id': 'conversation-1',
          'is_from_moon_saved': false,
        },
      ]);

      final result = await ConversationService.fetchConversation(
        'conversation-1',
      );

      expect(result.map((entry) => entry.id), ['saved-root', 'reply']);
      expect(result.first.isFromMoonSaved, isTrue);
    },
  );

  test('ricostruisce il segnaposto per una conversazione orfana', () async {
    final honoo = harness.stubTable('honoo');
    final hinoo = harness.stubTable('hinoo');
    final tombstones = harness.stubTable('conversation_tombstones');
    honoo.queueResponse(<Map<String, dynamic>>[
      {
        'id': 'reply-1',
        'text': 'risposta',
        'image_url': '',
        'destination': 'reply',
        'reply_to': 'deleted-root',
        'created_at': '2026-01-01T11:00:00Z',
        'updated_at': '2026-01-01T11:00:00Z',
        'user_id': 'test_user',
        'conversation_id': 'conversation-1',
      },
    ]);
    hinoo.queueResponse(<Map<String, dynamic>>[]);
    tombstones.queueResponse(<Map<String, dynamic>>[
      {
        'content_id': 'deleted-root',
        'conversation_id': 'conversation-1',
        'original_created_at': '2026-01-01T10:59:59Z',
      },
    ]);

    final result = await ConversationService.fetchConversation(
      'conversation-1',
    );

    expect(result.map((entry) => entry.id), ['deleted-root', 'reply-1']);
    expect(result.first.kind, ConversationEntryKind.deleted);
  });

  test('trasforma un contenuto soft-deleted in segnaposto', () async {
    final honoo = harness.stubTable('honoo');
    final hinoo = harness.stubTable('hinoo');
    honoo.queueResponse(<Map<String, dynamic>>[
      {
        'id': 'deleted-root',
        'created_at': '2026-01-01T10:00:00Z',
        'conversation_id': 'conversation-1',
        'admin_deleted_at': '2026-01-02T10:00:00Z',
      },
    ]);
    hinoo.queueResponse(<Map<String, dynamic>>[]);

    final result = await ConversationService.fetchConversation(
      'conversation-1',
    );

    expect(result.single.kind, ConversationEntryKind.deleted);
    expect(result.single.id, 'deleted-root');
  });

  test('include la radice quando una risposta avvia un nuovo filo', () async {
    final honoo = harness.stubTable('honoo');
    final hinoo = harness.stubTable('hinoo');
    honoo.queueResponse(<Map<String, dynamic>>[
      {
        'id': 'reply-1',
        'text': 'nuova conversazione',
        'image_url': '',
        'destination': 'reply',
        'reply_to': 'moon-root',
        'created_at': '2026-01-01T11:00:00Z',
        'updated_at': '2026-01-01T11:00:00Z',
        'user_id': 'test_user',
        'conversation_id': 'forked-conversation',
      },
    ]);
    hinoo.queueResponse(<Map<String, dynamic>>[]);
    honoo.queueResponse(<Map<String, dynamic>>[
      {
        'id': 'moon-root',
        'text': 'radice',
        'image_url': 'root.png',
        'destination': 'moon',
        'created_at': '2026-01-01T10:00:00Z',
        'updated_at': '2026-01-01T10:00:00Z',
        'user_id': 'author',
        'conversation_id': 'original-conversation',
      },
    ]);

    final result = await ConversationService.fetchConversation(
      'forked-conversation',
    );

    expect(result.map((entry) => entry.id), ['moon-root', 'reply-1']);
  });

  test(
    'ordina deterministicamente 400 conversazioni concorrenti in tutte le combinazioni',
    () async {
      final honoo = harness.stubTable('honoo');
      final hinoo = harness.stubTable('hinoo');
      final honooRows = <Map<String, dynamic>>[];
      final hinooRows = <Map<String, dynamic>>[];
      const combinations = [
        ('honoo', 'honoo'),
        ('honoo', 'hinoo'),
        ('hinoo', 'honoo'),
        ('hinoo', 'hinoo'),
      ];

      Map<String, dynamic> row({
        required String kind,
        required String id,
        required String owner,
        required bool reply,
        String? replyTo,
      }) {
        final common = <String, dynamic>{
          'id': id,
          'user_id': owner,
          'created_at': '2026-08-05T12:00:00Z',
          'conversation_id': 'crowded-conversation',
          'reply_to': replyTo,
          'recipient_tag': reply ? 'owner-${id.split('-').last}' : null,
          'is_from_moon_saved': false,
        };
        if (kind == 'honoo') {
          return {
            ...common,
            'text': id,
            'image_url': '',
            'destination': reply ? 'reply' : 'chest',
            'updated_at': '2026-08-05T12:00:00Z',
          };
        }
        return {
          ...common,
          'type': reply ? 'answer' : 'personal',
          'pages': <Map<String, dynamic>>[
            {'text': id, 'backgroundImage': null, 'isTextWhite': true},
          ],
        };
      }

      for (var index = 0; index < 400; index++) {
        final suffix = index.toString().padLeft(4, '0');
        final combination = combinations[index % combinations.length];
        final rootId = 'z-root-$suffix';
        final replyId = 'a-reply-$suffix';
        final root = row(
          kind: combination.$1,
          id: rootId,
          owner: 'owner-$suffix',
          reply: false,
        );
        final reply = row(
          kind: combination.$2,
          id: replyId,
          owner: 'sender-$suffix',
          reply: true,
          replyTo: rootId,
        );
        (combination.$1 == 'honoo' ? honooRows : hinooRows).add(root);
        (combination.$2 == 'honoo' ? honooRows : hinooRows).add(reply);
      }
      honoo.queueResponse(honooRows);
      hinoo.queueResponse(hinooRows);

      final result = await ConversationService.fetchConversation(
        'crowded-conversation',
      );
      final positions = <String, int>{
        for (var index = 0; index < result.length; index++)
          result[index].id!: index,
      };

      expect(result, hasLength(800));
      for (var index = 0; index < 400; index++) {
        final suffix = index.toString().padLeft(4, '0');
        expect(
          positions['z-root-$suffix'],
          lessThan(positions['a-reply-$suffix']!),
          reason: 'il padre deve precedere la risposta $suffix',
        );
      }
    },
  );
}

import 'package:flutter_test/flutter_test.dart';
import 'package:honoo/Entities/casa_share_mode.dart';
import 'package:honoo/Controller/chest_organizer.dart';

class _Item {
  const _Item({
    required this.id,
    required this.createdAt,
    this.latestReply,
    this.latestNotification,
    this.conversationId,
  });

  final String id;
  final DateTime createdAt;
  final DateTime? latestReply;
  final DateTime? latestNotification;
  final String? conversationId;
}

ChestOrganization<_Item> _organize(List<_Item> items) {
  return ChestOrganizer.organize<_Item>(
    items: items,
    createdAtOf: (item) => item.createdAt,
    stableIdOf: (item) => item.id,
    latestReplyOf: (item) => item.latestReply,
    latestNotificationOf: (item) => item.latestNotification,
    conversationIdOf: (item) => item.conversationId,
  );
}

void main() {
  test('i filtri dello Scrigno di casa includono tutto con l’ultima icona', () {
    expect(
      ChestOrganizer.matchesCasaFilter(
        filter: CasaChestFilter.authored,
        isFromMoonSaved: false,
        hasConversation: false,
      ),
      isTrue,
    );
    expect(
      ChestOrganizer.matchesCasaFilter(
        filter: CasaChestFilter.moonSaved,
        isFromMoonSaved: true,
        hasConversation: false,
      ),
      isTrue,
    );
    expect(
      ChestOrganizer.matchesCasaFilter(
        filter: CasaChestFilter.all,
        isFromMoonSaved: true,
        hasConversation: true,
      ),
      isTrue,
    );
    expect(
      ChestOrganizer.matchesCasaFilter(
        filter: CasaChestFilter.all,
        isFromMoonSaved: false,
        hasConversation: false,
      ),
      isTrue,
    );
    expect(
      ChestOrganizer.matchesCasaFilter(
        filter: CasaChestFilter.authored,
        isFromMoonSaved: false,
        hasConversation: true,
      ),
      isFalse,
    );
    expect(
      ChestOrganizer.matchesCasaFilter(
        filter: CasaChestFilter.moonSaved,
        isFromMoonSaved: true,
        hasConversation: true,
      ),
      isFalse,
    );
  });

  group('ChestOrganizer', () {
    test('ordina gli elementi normali per data DESC e id stabile', () {
      final now = DateTime(2024, 1, 1, 12);
      final result = _organize([
        _Item(createdAt: now, id: 'b'),
        _Item(createdAt: now, id: 'a'),
        _Item(createdAt: now.add(const Duration(seconds: 1)), id: 'z'),
        _Item(createdAt: now.subtract(const Duration(seconds: 1)), id: 'm'),
      ]);

      expect(result.items.map((item) => item.id), ['z', 'a', 'b', 'm']);
      expect(result.conversationItemCount, 0);
      expect(result.latestNotificationItemIndex, -1);
    });

    test('mette prima le conversazioni ordinate per ultima risposta', () {
      final t1 = DateTime(2024, 1, 1, 12);
      final t2 = t1.add(const Duration(seconds: 10));
      final result = _organize([
        _Item(createdAt: t1, id: 'c', latestReply: t2),
        _Item(createdAt: t2, id: 'b', latestReply: t2),
        _Item(createdAt: t2, id: 'a', latestReply: t2),
        _Item(createdAt: t2, id: 'normal'),
      ]);

      expect(result.items.map((item) => item.id), ['a', 'b', 'normal', 'c']);
      expect(result.conversationItemCount, 3);
    });

    test(
      'il contenuto salvato più di recente precede conversazioni più vecchie',
      () {
        final old = DateTime(2024, 1, 1, 12);
        final recent = old.add(const Duration(minutes: 5));
        final result = _organize([
          _Item(
            createdAt: old,
            id: 'conversation',
            latestReply: old.add(const Duration(minutes: 1)),
            latestNotification: old.add(const Duration(minutes: 1)),
            conversationId: 'conversation-1',
          ),
          _Item(createdAt: recent, id: 'just-saved'),
        ]);

        expect(result.items.map((item) => item.id), [
          'just-saved',
          'conversation',
        ]);
        expect(result.latestNotificationItemIndex, 1);
      },
    );

    test('seleziona la conversazione dell’ultima notifica ricevuta', () {
      final base = DateTime(2024, 1, 1, 12);
      final result = _organize([
        _Item(
          createdAt: base,
          id: 'own-activity',
          latestReply: base.add(const Duration(minutes: 10)),
          conversationId: 'conversation-own',
        ),
        _Item(
          createdAt: base,
          id: 'received-notification',
          latestReply: base.add(const Duration(minutes: 5)),
          latestNotification: base.add(const Duration(minutes: 5)),
          conversationId: 'conversation-received',
        ),
      ]);

      expect(result.items.map((item) => item.id), [
        'own-activity',
        'received-notification',
      ]);
      expect(result.latestNotificationItemIndex, 1);
    });

    test('mostra una sola slide per conversazione usando il più recente', () {
      final t1 = DateTime(2024, 1, 1, 12);
      final t2 = t1.add(const Duration(seconds: 10));
      final result = _organize([
        _Item(
          createdAt: t1,
          id: 'root',
          latestReply: t2,
          conversationId: 'conversation-1',
        ),
        _Item(createdAt: t2, id: 'outside'),
        _Item(createdAt: t2, id: 'reply', conversationId: 'conversation-1'),
      ]);

      expect(result.items.map((item) => item.id), ['outside', 'reply']);
    });

    test('non modifica la lista ricevuta', () {
      final input = [
        _Item(createdAt: DateTime(2024, 1, 2), id: 'new'),
        _Item(createdAt: DateTime(2024, 1, 1), id: 'old'),
      ];

      final result = _organize(input.reversed.toList());

      expect(result.items.map((item) => item.id), ['new', 'old']);
      expect(() => result.items.add(input.first), throwsUnsupportedError);
    });
  });

  group('latestNotificationTarget', () {
    test('mantiene la conversazione dedicata anche senza una slide radice', () {
      final items = [
        _Item(
          id: 'root',
          conversationId: 'original-conversation',
          createdAt: DateTime.parse('2026-08-05T10:00:00Z'),
        ),
      ];

      final target = ChestOrganizer.latestNotificationTarget(
        items: items,
        conversationIdOf: (item) => item.conversationId,
        notifications: [
          {
            'original-conversation': DateTime.parse('2026-08-05T11:00:00Z'),
            'dedicated-conversation': DateTime.parse('2026-08-05T12:00:00Z'),
          },
        ],
      );

      expect(target?.conversationId, 'dedicated-conversation');
      expect(target?.isDetached, isTrue);
    });

    test('seleziona la slide quando la conversazione è già nello Scrigno', () {
      final items = [
        _Item(
          id: 'root',
          conversationId: 'conversation-1',
          createdAt: DateTime.parse('2026-08-05T10:00:00Z'),
        ),
      ];

      final target = ChestOrganizer.latestNotificationTarget(
        items: items,
        conversationIdOf: (item) => item.conversationId,
        notifications: [
          {'conversation-1': DateTime.parse('2026-08-05T11:00:00Z')},
        ],
      );

      expect(target?.itemIndex, 0);
      expect(target?.isDetached, isFalse);
    });
  });
}

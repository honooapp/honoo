import 'package:flutter_test/flutter_test.dart';
import 'package:honoo/Entities/chest_item.dart';
import 'package:honoo/Entities/hinoo.dart';

void main() {
  test(
    'riconosce risposte legacy senza reply_to ma conserva le copie Luna',
    () {
      final row = <String, dynamic>{
        'id': 'legacy',
        'pages': <Map<String, dynamic>>[],
        'type': 'personal',
        'recipient_tag': 'recipient',
        'conversation_id': 'thread',
      };
      expect(ChestHinooItem.fromDatabaseRow(row)!.draft.type, HinooType.answer);
      row['is_from_moon_saved'] = true;
      expect(
        ChestHinooItem.fromDatabaseRow(row)!.draft.type,
        HinooType.personal,
      );
    },
  );
  test('reply_to classifica come answer anche un vecchio record personal', () {
    final item = ChestHinooItem.fromDatabaseRow({
      'id': 'reply-id',
      'pages': <Map<String, dynamic>>[
        {'backgroundImage': null, 'text': 'Risposta', 'isTextWhite': true},
      ],
      'type': 'personal',
      'reply_to': 'parent-id',
      'conversation_id': 'conversation-id',
      'created_at': '2026-07-18T10:00:00Z',
      'user_id': 'author-id',
      'is_from_moon_saved': false,
    });

    expect(item, isNotNull);
    expect(item!.draft.type, HinooType.answer);
    expect(item.draft.replyTo, 'parent-id');
  });
}

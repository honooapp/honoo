import 'package:flutter_test/flutter_test.dart';
import 'package:honoo/Entities/reply_notification_event.dart';

void main() {
  test('non notifica risposte già cancellate senza modificare i record', () {
    final row = {
      'id': 'old',
      'destination': 'reply',
      'reply_to': 'root',
      'conversation_id': 'conversation',
      'recipient_tag': 'me',
      'user_id': 'other',
      'admin_deleted_at': '2026-01-01T00:00:00Z',
    };
    expect(
      ReplyNotificationEvent.fromRealtimePayload(
        {'eventType': 'INSERT', 'new': row},
        kind: ReplyNotificationKind.honoo,
        currentUserId: 'me',
      ),
      isNull,
    );
    expect(row['id'], 'old');
  });

  test('riconosce una nuova risposta Honoo destinata all’utente', () {
    final event = ReplyNotificationEvent.fromRealtimePayload(
      {
        'eventType': 'INSERT',
        'new': {
          'id': 'reply-42',
          'destination': 'reply',
          'reply_to': 'root-1',
          'conversation_id': 'conversation-1',
          'recipient_tag': 'me',
          'user_id': 'other',
        },
      },
      kind: ReplyNotificationKind.honoo,
      currentUserId: 'me',
    );

    expect(event, isNotNull);
    expect(event!.conversationId, 'conversation-1');
    expect(event.contentLabel, 'honoo');
    expect(event.replyId, 'reply-42');
  });

  test('riconosce una nuova risposta Hinoo', () {
    final event = ReplyNotificationEvent.fromRealtimePayload(
      {
        'event_type': 'insert',
        'record': {
          'type': 'answer',
          'reply_to': 'root-1',
          'conversation_id': 'conversation-1',
          'recipient_tag': 'me',
          'user_id': 'other',
        },
      },
      kind: ReplyNotificationKind.hinoo,
      currentUserId: 'me',
    );

    expect(event, isNotNull);
    expect(event!.contentLabel, 'hinoo');
  });

  test('ignora record propri, altri destinatari e update', () {
    Map<String, dynamic> payload({
      String event = 'INSERT',
      String recipient = 'me',
      String sender = 'other',
    }) => {
      'eventType': event,
      'new': {
        'destination': 'reply',
        'reply_to': 'root-1',
        'conversation_id': 'conversation-1',
        'recipient_tag': recipient,
        'user_id': sender,
      },
    };

    ReplyNotificationEvent? parse(Map<String, dynamic> value) =>
        ReplyNotificationEvent.fromRealtimePayload(
          value,
          kind: ReplyNotificationKind.honoo,
          currentUserId: 'me',
        );

    expect(parse(payload(sender: 'me')), isNull);
    expect(parse(payload(recipient: 'someone-else')), isNull);
    expect(parse(payload(event: 'UPDATE')), isNull);
  });

  test('filtra correttamente un flusso misto fra 250 utenti', () {
    var accepted = 0;
    for (var i = 0; i < 5000; i++) {
      final isHonoo = i.isEven;
      final recipient = i % 250 == 0 ? 'me' : 'user-${i % 250}';
      final sender = i % 1000 == 0 ? 'me' : 'sender-${i % 400}';
      final event = ReplyNotificationEvent.fromRealtimePayload(
        {
          'eventType': 'INSERT',
          'new': {
            'id': 'reply-$i',
            'destination': isHonoo ? 'reply' : null,
            'type': isHonoo ? null : 'answer',
            'reply_to': 'root-$i',
            'conversation_id': 'conversation-$i',
            'recipient_tag': recipient,
            'user_id': sender,
          },
        },
        kind: isHonoo
            ? ReplyNotificationKind.honoo
            : ReplyNotificationKind.hinoo,
        currentUserId: 'me',
      );
      if (event != null) {
        accepted++;
        expect(event.recipientId, 'me');
        expect(event.senderId, isNot('me'));
      }
    }

    expect(accepted, 15);
  });
}

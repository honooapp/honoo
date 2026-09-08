import 'package:flutter_test/flutter_test.dart';
import 'package:honoo/Entities/conversation_link.dart';

void main() {
  group('ConversationLink', () {
    test('continuare un messaggio inviato mantiene il destinatario', () {
      expect(
        ConversationLink.recipientForParent(
          ownerId: 'me',
          parentRecipientId: 'other',
          currentUserId: 'me',
        ),
        'other',
      );
    });
    test('rispondere a un messaggio ricevuto indirizza al suo autore', () {
      expect(
        ConversationLink.recipientForParent(
          ownerId: 'other',
          parentRecipientId: 'me',
          currentUserId: 'me',
        ),
        'other',
      );
    });
    for (final crossing in const [
      'honoo → honoo',
      'honoo → hinoo',
      'hinoo → honoo',
      'hinoo → hinoo',
    ]) {
      test('$crossing conserva padre, thread e destinatario', () {
        final link = ConversationLink.fromParent(
          parentId: 'parent-2',
          parentConversationId: 'conversation-1',
          recipientId: 'author-3',
        );

        expect(link.replyTo, 'parent-2');
        expect(link.conversationId, 'conversation-1');
        expect(link.recipientId, 'author-3');
      });
    }

    test('una radice senza conversation_id usa il proprio id', () {
      final link = ConversationLink.fromParent(
        parentId: 'root-1',
        parentConversationId: null,
        recipientId: 'author-1',
      );

      expect(link.conversationId, 'root-1');
    });
  });
}

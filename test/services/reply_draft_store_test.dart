import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:honoo/Services/reply_draft_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('le bozze sono separate per account e contenuto', () async {
    await ReplyDraftStore('alice', 'parent').save({'text': 'private'});
    expect(await ReplyDraftStore('bob', 'parent').load(), isNull);
    expect(await ReplyDraftStore('alice', 'other').load(), isNull);
    expect(
      (await ReplyDraftStore('alice', 'parent').load())?['text'],
      'private',
    );
  });
  test(
    'salvataggi e cancellazione mantengono ordine anche tra istanze',
    () async {
      final first = ReplyDraftStore('alice', 'parent');
      final second = ReplyDraftStore('alice', 'parent');
      final writes = [
        first.save({'text': 'old'}),
        second.save({'text': 'new'}),
        first.save(null),
      ];
      await Future.wait(writes);
      expect(await second.load(), isNull);
    },
  );
}

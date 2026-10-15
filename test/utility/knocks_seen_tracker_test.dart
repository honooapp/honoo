import 'package:flutter_test/flutter_test.dart';
import 'package:honoo/Utility/knocks_seen_tracker.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('bussate viste persistono e restano separate per utente', () async {
    SharedPreferences.setMockInitialValues({});
    await KnocksSeenTracker.mark('alice', 'knock-1');
    await KnocksSeenTracker.mark('alice', 'knock-1');
    await KnocksSeenTracker.mark('alice', 'knock-2');
    expect(await KnocksSeenTracker.load('alice'), {'knock-1', 'knock-2'});
    expect(await KnocksSeenTracker.load('bob'), isEmpty);
  });
}

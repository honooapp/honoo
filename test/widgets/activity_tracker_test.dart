import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honoo/Widgets/activity_tracker.dart';
import 'package:mocktail/mocktail.dart';
import '../test_supabase_helper.dart';

void main() {
  setUpAll(registerSupabaseFallbacks);
  testWidgets('presence stops in background, after logout and after disposal', (
    tester,
  ) async {
    final harness = SupabaseTestHarness(withAuthenticatedUser: true)
      ..enableOverrides();
    addTearDown(harness.disableOverrides);
    when(
      () => harness.client.rpc('record_activity'),
    ).thenAnswer((_) => MockQueryChain()..queueResponse(null));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const ActivityTracker(child: SizedBox()));
    await tester.pump();
    verify(() => harness.client.rpc('record_activity')).called(1);
    await tester.pump(const Duration(seconds: 30));
    verify(() => harness.client.rpc('record_activity')).called(1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(minutes: 3));
    verifyNever(() => harness.client.rpc('record_activity'));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    verify(() => harness.client.rpc('record_activity')).called(1);
    when(() => harness.auth.currentUser).thenReturn(null);
    await tester.pump(const Duration(seconds: 30));
    verifyNever(() => harness.client.rpc('record_activity'));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 1));
    verifyNever(() => harness.client.rpc('record_activity'));
  });
}

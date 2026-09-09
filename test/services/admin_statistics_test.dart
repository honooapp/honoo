import 'package:flutter_test/flutter_test.dart';
import 'package:honoo/Services/admin_service.dart';
import 'package:mocktail/mocktail.dart';
import '../test_supabase_helper.dart';

void main() {
  setUpAll(registerSupabaseFallbacks);
  test(
    'statistics RPC failures propagate instead of displaying zero',
    () async {
      final harness = SupabaseTestHarness();
      when(
        () => harness.client.rpc('admin_statistics_snapshot'),
      ).thenThrow(Exception('offline'));
      await expectLater(
        AdminService(client: harness.client).fetchStatistics(),
        throwsException,
      );
    },
  );
  test('malformed statistics are rejected', () async {
    final harness = SupabaseTestHarness();
    final rpc = MockQueryChain()..queueResponse({'daily': {}});
    when(
      () => harness.client.rpc('admin_statistics_snapshot'),
    ).thenAnswer((_) => rpc);
    await expectLater(
      AdminService(client: harness.client).fetchStatistics(),
      throwsFormatException,
    );
  });
  test('all counters come from one server snapshot', () async {
    final harness = SupabaseTestHarness();
    final snapshot = {
      'daily': {'chest_honoo': 1501},
      'visits': {'2026-09-09': 30},
      'active_users': 8,
      'registered_users': 2500,
      'houses': 12,
      'generated_at': '2026-09-09T15:00:00Z',
      'tracking_started_at': '2026-09-09T12:00:00Z',
      'tracking_started_date': '2026-09-09',
      'today': '2026-09-09',
    };
    final rpc = MockQueryChain()..queueResponse(snapshot);
    when(
      () => harness.client.rpc('admin_statistics_snapshot'),
    ).thenAnswer((_) => rpc);
    expect(
      await AdminService(client: harness.client).fetchStatistics(),
      snapshot,
    );
    verify(() => harness.client.rpc('admin_statistics_snapshot')).called(1);
  });
}

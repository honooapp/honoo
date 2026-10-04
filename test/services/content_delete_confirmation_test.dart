import 'package:flutter_test/flutter_test.dart';
import 'package:honoo/Services/chest_repository.dart';
import 'package:honoo/Services/hinoo_service.dart';
import 'package:honoo/Services/honoo_service.dart';
import '../test_supabase_helper.dart';

void main() {
  setUpAll(registerSupabaseFallbacks);
  for (final kind in ['honoo', 'hinoo', 'chest-hinoo']) {
    for (final deleted in [false, true]) {
      test(
        '$kind confirms deletion only when a row was deleted: $deleted',
        () async {
          final harness = SupabaseTestHarness(withAuthenticatedUser: true)
            ..enableOverrides();
          HinooService.$setTestClient(harness.client);
          addTearDown(() {
            HinooService.$setTestClient(null);
            harness.disableOverrides();
          });
          harness
              .stubTable(kind == 'honoo' ? 'honoo' : 'hinoo')
              .queueResponse(
                deleted
                    ? [
                        {'id': 'target'},
                      ]
                    : [],
              );
          final operation = switch (kind) {
            'honoo' => HonooService.deleteHonooById('target'),
            'hinoo' => HinooService.deleteHinooById('target'),
            _ => ChestRepository(client: harness.client).deleteHinoo('target'),
          };
          await expectLater(operation, deleted ? completes : throwsStateError);
        },
      );
    }
  }
}

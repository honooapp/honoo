import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honoo/Pages/chest_page.dart';
import 'package:honoo/Entities/casa_share_mode.dart';
import 'package:honoo/Pages/email_login_page.dart';

import '../test_supabase_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(registerSupabaseFallbacks);

  late SupabaseTestHarness supabase;

  setUp(() {
    supabase = SupabaseTestHarness();
    supabase.enableOverrides();
  });

  tearDown(() => supabase.disableOverrides());

  testWidgets('lo scrigno di casa torna alla casa con Indietro', (
    tester,
  ) async {
    supabase.disableOverrides();
    supabase = SupabaseTestHarness(withAuthenticatedUser: true);
    supabase.enableOverrides();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) =>
                      const ChestPage(casaFilter: CasaChestFilter.moonSaved),
                ),
              ),
              child: const Text('Casa'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Casa'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Indietro'), findsOneWidget);
    await tester.tap(find.byTooltip('Indietro'));
    await tester.pumpAndSettle();
    expect(find.text('Casa'), findsOneWidget);
    expect(find.byType(ChestPage), findsNothing);
  });

  testWidgets('lo Scrigno apre direttamente il login per un anonimo', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => const ChestPage()),
              ),
              child: const Text('Apri Scrigno'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Apri Scrigno'));
    await tester.pumpAndSettle();

    expect(find.byType(EmailLoginPage), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });
}

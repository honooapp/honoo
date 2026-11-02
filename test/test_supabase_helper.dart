import 'dart:async';
import 'dart:collection';

import 'package:honoo/Services/honoo_service.dart';
import 'package:honoo/Services/supabase_provider.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockGoTrueClient extends Mock implements GoTrueClient {}

class MockUser extends Mock implements User {}

class MockSession extends Mock implements Session {}

class MockQueryChain extends Mock
    implements
        SupabaseQueryBuilder,
        PostgrestFilterBuilder<dynamic>,
        PostgrestTransformBuilder<dynamic> {
  final Queue<dynamic> _responses = Queue<dynamic>();

  void queueResponse(dynamic value) => _responses.add(value);

  dynamic _nextResponse() {
    if (_responses.isEmpty) {
      return <dynamic>[];
    }
    return _responses.removeFirst();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #then &&
        invocation.positionalArguments.isNotEmpty) {
      final onValue =
          invocation.positionalArguments[0] as dynamic Function(dynamic);
      // Replica la semantica asincrona di Postgrest: Future.wait non supporta
      // callback `then` invocate sincronicamente durante la registrazione.
      final response = _nextResponse();
      // ignore: prefer_void_to_null, il mock deve rispettare R=Null di Future.then.
      return Future<Null>.microtask(() async {
        onValue(await response);
        return null;
      });
    }
    return super.noSuchMethod(invocation);
  }
}

class FakeAuthState extends Fake implements AuthState {}

void registerSupabaseFallbacks() {
  registerFallbackValue(<String, dynamic>{});
  registerFallbackValue(FakeAuthState());
  registerFallbackValue(OtpType.email);
}

class SupabaseTestHarness {
  SupabaseTestHarness({bool withAuthenticatedUser = false}) {
    when(() => client.auth).thenReturn(auth);
    when(() => auth.currentSession)
        .thenReturn(withAuthenticatedUser ? session : null);
    when(() => auth.currentUser)
        .thenReturn(withAuthenticatedUser ? user : null);
    when(() => user.id).thenReturn('test_user');
    when(() => session.user).thenReturn(user);
    when(() => auth.onAuthStateChange)
        .thenAnswer((_) => const Stream<AuthState>.empty());
    when(() => auth.signInWithOtp(email: any(named: 'email'))).thenAnswer(
        (_) async => AuthResponse(
            session: session, user: withAuthenticatedUser ? user : null));
    when(() => auth.verifyOTP(
              type: any(named: 'type'),
              email: any(named: 'email'),
              token: any(named: 'token'),
            ))
        .thenAnswer((_) async => AuthResponse(
            session: session, user: withAuthenticatedUser ? user : null));
  }

  final MockSupabaseClient client = MockSupabaseClient();
  final MockGoTrueClient auth = MockGoTrueClient();
  final MockUser user = MockUser();
  final MockSession session = MockSession();

  void enableOverrides() {
    SupabaseProvider.overrideForTests(client);
    HonooService.$setTestClient(client);
  }

  void disableOverrides() {
    SupabaseProvider.overrideForTests(null);
    HonooService.$setTestClient(null);
  }

  MockQueryChain stubTable(String table) {
    final chain = MockQueryChain();
    when(() => client.from(table)).thenAnswer((_) => chain);
    when(() => chain.select(any())).thenAnswer((_) => chain);
    when(() => chain.insert(any())).thenAnswer((_) => chain);
    when(() => chain.upsert(any())).thenAnswer((_) => chain);
    when(() => chain.eq(any(), any())).thenAnswer((_) => chain);
    when(() => chain.neq(any(), any())).thenAnswer((_) => chain);
    when(() => chain.gt(any(), any())).thenAnswer((_) => chain);
    when(() => chain.order(any(), ascending: any(named: 'ascending')))
        .thenAnswer((_) => chain);
    when(() => chain.limit(any())).thenAnswer((_) => chain);
    when(() => chain.or(any())).thenAnswer((_) => chain);
    when(() => chain.in_(any(), any())).thenAnswer((_) => chain);
    when(() => chain.is_(any(), any())).thenAnswer((_) => chain);
    when(() => chain.delete()).thenAnswer((_) => chain);
    when(() => chain.update(any())).thenAnswer((_) => chain);
    when(() => chain.maybeSingle()).thenAnswer((_) => chain);
    return chain;
  }
}

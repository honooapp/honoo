import 'dart:async';
import 'test_supabase_helper.dart';

class PendingQuery extends MockQueryChain {
  final response = Completer<dynamic>();
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #then) {
      return response.future.then<dynamic>((value) {
        (invocation.positionalArguments.first as dynamic Function(dynamic))(
          value,
        );
        return null;
      }, onError: invocation.namedArguments[#onError]);
    }
    return super.noSuchMethod(invocation);
  }
}

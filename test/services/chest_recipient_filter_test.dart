import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:honoo/Services/chest_recipient_filter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  for (final hasAddress in [true, false]) {
    test(
      'recipient lookup uses current schema (address: $hasAddress)',
      () async {
        final client = SupabaseClient(
          'https://example.test',
          'test-key',
          httpClient: MockClient((request) async {
            if (request.url.path == '/rest/v1/case') {
              expect(request.url.queryParameters['owner_id'], 'eq.user-1');
              return http.Response(
                jsonEncode([
                  {'campanello_hinoo_id': 'house-tag'},
                ]),
                200,
                request: request,
                headers: {'content-type': 'application/json'},
              );
            }
            expect(request.url.path, '/rest/v1/users');
            expect(request.url.queryParameters['select'], 'address');
            // Model the deployed schema: auth_id is not a valid column.
            if (request.url.queryParameters.containsKey('auth_id')) {
              return http.Response(
                jsonEncode({
                  'code': '42703',
                  'message': 'column users.auth_id does not exist',
                }),
                400,
                request: request,
              );
            }
            expect(request.url.queryParameters['auth_user_id'], 'eq.user-1');
            return http.Response(
              jsonEncode(
                hasAddress
                    ? [
                        {'address': 'casa-storica'},
                      ]
                    : [],
              ),
              200,
              request: request,
              headers: {'content-type': 'application/json'},
            );
          }),
        );
        addTearDown(client.dispose);
        expect(
          await chestRecipientFilter(client, 'user-1'),
          hasAddress
              ? 'recipient_tag.in.("user-1","casa-storica","house-tag")'
              : 'recipient_tag.in.("user-1","house-tag")',
        );
      },
    );
  }
}

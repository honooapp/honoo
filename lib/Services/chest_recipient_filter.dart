import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Mirrors the recipient identities accepted by the conversation RLS policies.
Future<String> chestRecipientFilter(
  SupabaseClient client,
  String userId,
) async {
  final rows = await client
      .from('users')
      .select('address')
      .eq('auth_id', userId);
  final identities = <String>{userId};
  for (final row in rows) {
    final address = row['address']?.toString();
    if (address != null && address.isNotEmpty) identities.add(address);
  }
  if (identities.length == 1) return 'recipient_tag.eq.$userId';
  return 'recipient_tag.in.(${identities.map(jsonEncode).join(',')})';
}

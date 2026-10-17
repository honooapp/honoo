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
      .eq('auth_user_id', userId);
  final identities = <String>{userId};
  for (final row in rows) {
    final address = row['address']?.toString();
    if (address != null && address.isNotEmpty) identities.add(address);
  }
  final houses = await client
      .from('case')
      .select('campanello_hinoo_id')
      .eq('owner_id', userId);
  for (final house in houses) {
    final tag = house['campanello_hinoo_id']?.toString();
    if (tag != null && tag.isNotEmpty) identities.add(tag);
  }
  if (identities.length == 1) return 'recipient_tag.eq.$userId';
  return 'recipient_tag.in.(${identities.map(jsonEncode).join(',')})';
}

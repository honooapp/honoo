import 'package:flutter/foundation.dart';
import 'package:honoo/Services/supabase_provider.dart';
import 'package:honoo/Services/app_failure.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminUserRecord {
  final String authUserId;
  final String? email;

  const AdminUserRecord({required this.authUserId, this.email});
}

class AdminService {
  AdminService({SupabaseClient? client})
      : _client = client ?? SupabaseProvider.client;

  final SupabaseClient _client;

  /// Failures propagate: an unavailable statistic must never become a zero.
  Future<Map<String, dynamic>> fetchStatistics() async {
    final result = await _client.rpc('admin_statistics_snapshot');
    if (result is! Map ||
        result['daily'] is! Map ||
        result['visits'] is! Map ||
        result['active_users'] is! num ||
        result['registered_users'] is! num ||
        result['houses'] is! num ||
        result['generated_at'] is! String ||
        result['tracking_started_at'] is! String ||
        result['tracking_started_date'] is! String ||
        result['today'] is! String) {
      throw const FormatException('Invalid admin statistics snapshot');
    }
    return Map<String, dynamic>.from(result);
  }

  Future<bool> isCurrentUserAdmin() async {
    try {
      final res = await _client.rpc('admin_is_admin');
      if (res is bool) return res;
      if (res is Map && res['admin_is_admin'] is bool) {
        return res['admin_is_admin'] as bool;
      }
      return res == true;
    } catch (error, stackTrace) {
      final failure = AppFailure.from(error, stackTrace);
      debugPrint('[AdminService] admin check failed: $failure');
      return false;
    }
  }

  Future<List<AdminUserRecord>> fetchAllUsers() async {
    final rows = await _safeRpc('admin_list_users');

    final users = <AdminUserRecord>[];
    if (rows is List) {
      for (final row in rows) {
        if (row is! Map) continue;
        final String id = row['auth_user_id']?.toString() ?? '';
        if (id.isEmpty) continue;
        users.add(AdminUserRecord(authUserId: id));
      }
    } else if (rows is Map) {
      final String id = rows['auth_user_id']?.toString() ?? '';
      if (id.isNotEmpty) {
        users.add(AdminUserRecord(authUserId: id));
      }
    }
    return users;
  }

  Future<List<AdminUserRecord>> fetchAllUsersWithEmails() async {
    final rows = await _safeRpc('admin_list_user_emails');
    final users = <AdminUserRecord>[];
    if (rows is List) {
      for (final row in rows) {
        if (row is! Map) continue;
        final String id = row['auth_user_id']?.toString() ?? '';
        if (id.isEmpty) continue;
        users.add(
          AdminUserRecord(
            authUserId: id,
            email: row['email']?.toString(),
          ),
        );
      }
    } else if (rows is Map) {
      final String id = rows['auth_user_id']?.toString() ?? '';
      if (id.isNotEmpty) {
        users.add(
          AdminUserRecord(
            authUserId: id,
            email: rows['email']?.toString(),
          ),
        );
      }
    }
    return users;
  }

  Future<Map<DateTime, int>> fetchRecentVisits({int days = 3}) async {
    final res = await _safeRpc(
      'admin_list_site_visits',
      params: {'p_days': days},
    );
    final Map<DateTime, int> visits = {};
    if (res is List) {
      for (final row in res) {
        if (row is! Map) continue;
        final dateValue = row['visit_date']?.toString() ?? '';
        final countValue = row['count'];
        if (dateValue.isEmpty) continue;
        final date = DateTime.tryParse(dateValue);
        if (date == null) continue;
        visits[DateTime(date.year, date.month, date.day)] =
            (countValue as num?)?.toInt() ?? 0;
      }
    }
    return visits;
  }

  Future<Map<String, int>> fetchTodayMoonCounts() async {
    final res = await _safeRpc('admin_moon_counts_today');
    int honooCount = 0;
    int hinooCount = 0;
    Map? row;
    if (res is List && res.isNotEmpty && res.first is Map) {
      row = res.first as Map;
    } else if (res is Map) {
      row = res;
    }
    if (row != null) {
      honooCount =
          ((row['honoo_count'] ?? row['honoo'] ?? row['count_honoo']) as num?)
                  ?.toInt() ??
              0;
      hinooCount =
          ((row['hinoo_count'] ?? row['hinoo'] ?? row['count_hinoo']) as num?)
                  ?.toInt() ??
              0;
    }
    return {
      'honoo': honooCount,
      'hinoo': hinooCount,
    };
  }

  Future<Map<String, int>> fetchDailyContentCounts() async {
    final res = await _safeRpc('admin_daily_content_counts');
    final Map<String, int> counts = {
      'chest_honoo': 0,
      'chest_hinoo': 0,
      'moon_honoo': 0,
      'moon_hinoo': 0,
      'reply_honoo': 0,
      'reply_hinoo': 0,
    };
    Map? row;
    if (res is List && res.isNotEmpty && res.first is Map) {
      row = res.first as Map;
    } else if (res is Map) {
      row = res;
    }
    int asInt(Map r, List<String> keys) {
      for (final k in keys) {
        final v = r[k];
        if (v is num) return v.toInt();
      }
      return 0;
    }

    if (row != null) {
      final Map r = row;
      counts['chest_honoo'] =
          asInt(r, ['chest_honoo', 'honoo_chest', 'count_chest_honoo']);
      counts['chest_hinoo'] =
          asInt(r, ['chest_hinoo', 'hinoo_chest', 'count_chest_hinoo']);
      counts['moon_honoo'] =
          asInt(r, ['moon_honoo', 'honoo_moon', 'count_moon_honoo']);
      counts['moon_hinoo'] =
          asInt(r, ['moon_hinoo', 'hinoo_moon', 'count_moon_hinoo']);
      counts['reply_honoo'] =
          asInt(r, ['reply_honoo', 'honoo_reply', 'count_reply_honoo']);
      counts['reply_hinoo'] =
          asInt(r, ['reply_hinoo', 'hinoo_reply', 'count_reply_hinoo']);
    }
    return counts;
  }

  Future<List<String>> fetchUserEmails() async {
    final rows = await _safeRpc('admin_list_user_emails');
    final emails = <String>[];
    if (rows is List) {
      for (final row in rows) {
        if (row is! Map) continue;
        final String email = row['email']?.toString() ?? '';
        if (email.isNotEmpty) emails.add(email);
      }
    } else if (rows is Map) {
      final String email = rows['email']?.toString() ?? '';
      if (email.isNotEmpty) emails.add(email);
    }
    return emails;
  }

  Future<AdminUserRecord?> findUserByEmail(String email) async {
    final res = await _safeRpc(
      'admin_find_user_by_email',
      params: {'p_email': email},
    );
    if (res == null) return null;
    if (res is List && res.isNotEmpty) {
      final row = res.first;
      if (row is! Map) return null;
      final String id = row['auth_user_id']?.toString() ?? '';
      if (id.isEmpty) return null;
      return AdminUserRecord(authUserId: id, email: row['email']?.toString());
    }
    if (res is Map) {
      final String id = res['auth_user_id']?.toString() ?? '';
      if (id.isEmpty) return null;
      return AdminUserRecord(authUserId: id, email: res['email']?.toString());
    }
    return null;
  }

  Future<Set<String>> fetchExistingInvites(List<String> userIds) async {
    if (userIds.isEmpty) return {};
    final rows = await _client
        .from('house_invites')
        .select('user_id,status')
        .in_('user_id', userIds);

    final existing = <String>{};
    for (final row in (rows as List)) {
      if (row is! Map) continue;
      final String id = row['user_id']?.toString() ?? '';
      final String status = row['status']?.toString() ?? '';
      if (status == 'declined') continue;
      if (id.isNotEmpty) existing.add(id);
    }
    return existing;
  }

  Future<bool> hasPendingInviteForEmail(String email) async {
    if (email.trim().isEmpty) return false;
    final rows = await _client
        .from('house_invites')
        .select('id,status')
        .ilike('email', email)
        .in_('status', ['requested', 'pending', 'accepted']).limit(1);
    if (rows is! List || rows.isEmpty) return false;
    return true;
  }

  Future<List<Map<String, dynamic>>> fetchPendingInvites(
      {bool newestFirst = true}) async {
    final rows = await _client
        .from('house_invites')
        .select('id,email,user_id,created_at,status')
        .eq('status', 'requested')
        .order('created_at', ascending: !newestFirst);
    if (rows is! List) return const [];
    return rows.whereType<Map<String, dynamic>>().toList();
  }

  Future<int> fetchPendingInviteCount() async {
    final count = await _client.rpc('admin_pending_invite_count');
    if (count is! num) throw const FormatException('Invalid invite count');
    return count.toInt();
  }

  Future<bool> hasCasaForUser(String userId) async {
    if (userId.trim().isEmpty) return false;
    final rows =
        await _client.from('case').select('id').eq('owner_id', userId).limit(1);
    return rows is List && rows.isNotEmpty;
  }

  Future<Set<String>> fetchExistingCaseOwners(List<String> userIds) async {
    if (userIds.isEmpty) return {};
    final rows =
        await _client.from('case').select('owner_id').in_('owner_id', userIds);

    final existing = <String>{};
    for (final row in (rows as List)) {
      if (row is! Map) continue;
      final String id = row['owner_id']?.toString() ?? '';
      if (id.isNotEmpty) existing.add(id);
    }
    return existing;
  }

  Future<int> inviteUsers({
    required String adminUid,
    required List<String> userIds,
    Map<String, String>? userEmails,
  }) async {
    final filtered = userIds.where((id) => id.trim().isNotEmpty).toList();
    if (filtered.isEmpty) return 0;

    final existing = await fetchExistingInvites(filtered);
    final existingCases = await fetchExistingCaseOwners(filtered);
    final toInsert = filtered
        .where((id) =>
            !existing.contains(id) &&
            !existingCases.contains(id))
        .toList();
    if (toInsert.isEmpty) return 0;

    final payload = toInsert
        .map(
          (id) => {
            'user_id': id,
            'invited_by': adminUid,
            'status': 'pending',
            'created_at': DateTime.now().toIso8601String(),
            if (userEmails != null && userEmails[id] != null)
              'email': userEmails[id],
          },
        )
        .toList();

    await _client.from('house_invites').insert(payload);
    if (userEmails != null) {
      for (final id in toInsert) {
        final email = userEmails[id];
        if (email == null || email.isEmpty) continue;
        await _sendInviteEmail(email);
      }
    }
    return toInsert.length;
  }

  Future<bool> inviteByEmailOnly({
    required String adminUid,
    required String email,
  }) async {
    if (email.trim().isEmpty) return false;
    final exists = await hasPendingInviteForEmail(email);
    if (exists) return false;
    await _client.from('house_invites').insert({
      'user_id': null,
      'email': email,
      'invited_by': adminUid,
      'status': 'pending',
      'created_at': DateTime.now().toIso8601String(),
    });
    return true;
  }

  Future<bool> reviewHouseRequest({
    required String inviteId,
    required bool approved,
  }) async {
    final result = await _client.rpc(
      'admin_review_house_request',
      params: {
        'p_invite_id': inviteId,
        'p_approved': approved,
      },
    );
    return result == true;
  }

  Future<dynamic> _safeRpc(String fn, {Map<String, dynamic>? params}) async {
    try {
      if (params == null) {
        return await _client.rpc(fn);
      }
      return await _client.rpc(fn, params: params);
    } catch (error, stackTrace) {
      final failure = AppFailure.from(error, stackTrace);
      debugPrint('[AdminService] RPC $fn failed: $failure');
      return null;
    }
  }

  Future<void> _sendInviteEmail(String email) async {
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        await _client.auth.signInWithOtp(
          email: email,
          shouldCreateUser: false,
        );
        return;
      } catch (e) {
        if (attempt == 1) rethrow;
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }
  }
}

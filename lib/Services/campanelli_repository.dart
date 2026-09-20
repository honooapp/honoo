import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_provider.dart';

/// Accesso ai dati necessari per costruire l’elenco dei Campanelli.
/// Mapping, ordinamento e stato UI restano fuori dal repository.
class CampanelliDataRepository {
  CampanelliDataRepository({SupabaseClient? client})
    : _client = client ?? SupabaseProvider.client;

  final SupabaseClient _client;

  static const requestTimeout = Duration(seconds: 12);

  Future<T> _request<T>(Future<T> Function() operation) =>
      (() async => await operation())().timeout(requestTimeout);

  Future<List<dynamic>> fetchPublicAdminCampanelli() async {
    final rows = await _request(
      () => _client.rpc('get_public_admin_campanelli'),
    );
    return _asList(rows);
  }

  Future<List<dynamic>> fetchHouseRows() async {
    final rows = await _request(
      () => _client
          .from('case')
          .select(
            'campanello_hinoo_id,owner_id,house_image_url,house_text,bg_transform,created_at',
          ),
    );
    return _asList(rows);
  }

  Future<List<dynamic>> fetchShareSettingsRows(List<String> hinooIds) async {
    if (hinooIds.isEmpty) return const [];
    final rows = await _request(
      () => _client
          .from('house_share_settings')
          .select('campanello_hinoo_id,share_mode,share_modes')
          .in_('campanello_hinoo_id', hinooIds),
    );
    return _asList(rows);
  }

  Future<List<dynamic>> fetchHinooRows(List<String> hinooIds) async {
    if (hinooIds.isEmpty) return const [];
    final rows = await _request(
      () => _client.from('hinoo').select('id,pages').in_('id', hinooIds),
    );
    return _asList(rows);
  }

  Future<List<dynamic>> fetchPendingKnockRows(
    List<String> targetHouseTags,
  ) async {
    if (targetHouseTags.isEmpty) return const [];
    final rows = await _request(
      () => _client
          .from('house_access')
          .select('id,target_house_tag,created_at,hinoo_id,honoo_id')
          .in_('target_house_tag', targetHouseTags)
          .is_('granted_at', null),
    );
    return _asList(rows);
  }

  Future<Map<String, dynamic>?> fetchHinooForKnock(String hinooId) async {
    final row = await _request(
      () => _client
          .from('hinoo')
          .select('pages,type,recipient_tag,created_at')
          .eq('id', hinooId)
          .maybeSingle(),
    );
    return _asMap(row);
  }

  Future<Map<String, dynamic>?> fetchHonooForKnock(String honooId) async {
    final row = await _request(
      () => _client
          .from('honoo')
          .select(
            'id,text,image_url,destination,reply_to,recipient_tag,created_at,updated_at,user_id',
          )
          .eq('id', honooId)
          .maybeSingle(),
    );
    return _asMap(row);
  }

  Future<void> grantHouseAccess({
    required String knockId,
    required DateTime grantedAt,
  }) async {
    await _request(
      () => _client
          .from('house_access')
          .update({'granted_at': grantedAt.toIso8601String()})
          .eq('id', knockId),
    );
  }

  Future<void> approveHouseKnock({
    required String knockId,
    required List<String> shareModes,
  }) async {
    final parsedKnockId = int.parse(knockId);
    await _request(
      () => _client.rpc(
        'approve_house_knock',
        params: {'p_knock_id': parsedKnockId, 'p_share_modes': shareModes},
      ),
    );
  }

  Future<List<String>> fetchGrantedHouseTags(String visitorId) async {
    final rows = await _request(
      () => _client
          .from('house_access')
          .select('target_house_tag,share_modes')
          .eq('visitor_id', visitorId)
          .not('granted_at', 'is', null),
    );
    return _asList(rows)
        .whereType<Map>()
        .where(
          (row) =>
              row['share_modes'] is List &&
              (row['share_modes'] as List).isNotEmpty,
        )
        .map((row) => row['target_house_tag']?.toString() ?? '')
        .where((tag) => tag.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> sendHouseKnock({
    required String targetHouseTag,
    required String visitorId,
    String? hinooId,
    String? honooId,
  }) async {
    await _request(
      () => _client.from('house_access').insert({
        'target_house_tag': targetHouseTag,
        'visitor_id': visitorId,
        if (hinooId != null && hinooId.isNotEmpty) 'hinoo_id': hinooId,
        if (honooId != null && honooId.isNotEmpty) 'honoo_id': honooId,
      }),
    );
  }

  Future<void> saveShareModes({
    required String ownerId,
    required String campanelloHinooId,
    required List<String> modes,
    required DateTime updatedAt,
  }) async {
    await _request(
      () => _client.from('house_share_settings').upsert({
        'owner_id': ownerId,
        'campanello_hinoo_id': campanelloHinooId,
        'share_mode': modes.isEmpty ? null : modes.first,
        'share_modes': modes,
        'updated_at': updatedAt.toIso8601String(),
      }, onConflict: 'campanello_hinoo_id'),
    );
  }

  static List<dynamic> _asList(dynamic rows) {
    if (rows is List) return rows;
    if (rows is Map) return [rows];
    return const [];
  }

  static Map<String, dynamic>? _asMap(dynamic row) {
    if (row is Map<String, dynamic>) return row;
    if (row is Map) return Map<String, dynamic>.from(row);
    return null;
  }
}

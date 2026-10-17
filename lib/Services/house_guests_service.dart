import 'package:supabase_flutter/supabase_flutter.dart';
import '../Entities/casa_share_mode.dart';
import '../Entities/hinoo.dart';
import '../Entities/honoo.dart';
import 'supabase_provider.dart';

class HouseGuest {
  const HouseGuest({
    required this.id,
    required this.modes,
    this.honoo,
    this.hinoo,
    this.pending = false,
    this.conversationId,
    this.contentId,
    this.houseTag,
  });
  final String id;
  final bool pending;
  final String? conversationId;
  final String? contentId;
  final String? houseTag;
  final Set<CasaShareMode> modes;
  final Honoo? honoo;
  final HinooDraft? hinoo;

  HouseGuest withModes(Set<CasaShareMode> modes) => HouseGuest(
    id: id,
    modes: Set.unmodifiable(modes),
    honoo: honoo,
    hinoo: hinoo,
    pending: pending,
    conversationId: conversationId,
    contentId: contentId,
    houseTag: houseTag,
  );

  factory HouseGuest.fromJson(Map row) {
    final hinoo = row['hinoo'];
    final pages = hinoo is Map ? hinoo['pages'] : null;
    return HouseGuest(
      id: row['id'].toString(),
      pending: row.containsKey('granted_at') && row['granted_at'] == null,
      houseTag: row['target_house_tag']?.toString(),
      conversationId:
          ((row['honoo'] ?? row['hinoo']) as Map?)?['conversation_id']
              ?.toString(),
      contentId: ((row['honoo'] ?? row['hinoo']) as Map?)?['id']?.toString(),
      modes: (row['share_modes'] as List? ?? [])
          .map((m) => CasaShareMode.fromDb(m.toString()))
          .whereType<CasaShareMode>()
          .toSet(),
      honoo: row['honoo'] is Map
          ? Honoo.fromMap(Map<String, dynamic>.from(row['honoo'] as Map))
          : null,
      hinoo: pages is List && pages.isNotEmpty
          ? HinooDraft(
              pages: pages
                  .whereType<Map>()
                  .map((p) => HinooSlide.fromJson(Map<String, dynamic>.from(p)))
                  .toList(),
              type: HinooType.answer,
            )
          : null,
    );
  }
}

class HouseGuestsService {
  HouseGuestsService({SupabaseClient? client})
    : _client = client ?? SupabaseProvider.client;
  final SupabaseClient _client;

  Future<List<HouseGuest>> fetch([String? houseTag]) async {
    final rows = await _client
        .rpc('get_house_inbox', params: {'p_house_tag': houseTag})
        .timeout(const Duration(seconds: 12));
    return (rows as List).whereType<Map>().map(HouseGuest.fromJson).toList();
  }

  Future<void> update(String id, Set<CasaShareMode> modes) async {
    await _client
        .rpc(
          'update_house_guest_access',
          params: {
            'p_knock_id': int.parse(id),
            'p_share_modes': modes.map((m) => m.dbValue).toList(),
          },
        )
        .timeout(const Duration(seconds: 12));
  }
}

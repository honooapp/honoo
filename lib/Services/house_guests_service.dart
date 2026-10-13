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
  });
  final String id;
  final Set<CasaShareMode> modes;
  final Honoo? honoo;
  final HinooDraft? hinoo;

  HouseGuest withModes(Set<CasaShareMode> modes) => HouseGuest(
    id: id,
    modes: Set.unmodifiable(modes),
    honoo: honoo,
    hinoo: hinoo,
  );

  factory HouseGuest.fromJson(Map row) {
    final hinoo = row['hinoo'];
    final pages = hinoo is Map ? hinoo['pages'] : null;
    return HouseGuest(
      id: row['id'].toString(),
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

  Future<List<HouseGuest>> fetch(String houseTag) async {
    final rows = await _client
        .rpc('get_house_guests', params: {'p_house_tag': houseTag})
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

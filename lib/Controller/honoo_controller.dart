import 'package:flutter/foundation.dart';
import 'package:honoo/Services/supabase_provider.dart';
import '../Entities/honoo.dart';
import '../Services/honoo_service.dart';
import '../Services/duplication_result.dart';

/// Repository + cache in memoria (niente mock)
class HonooController {
  static final HonooController _instance = HonooController._internal();
  factory HonooController() => _instance;
  HonooController._internal();

  // Cache
  final List<Honoo> _personal = [];
  String? _cacheUserId;
  int _loadGeneration = 0;
  final ValueNotifier<bool> isLoading = ValueNotifier<bool>(false);
  final ValueNotifier<int> version = ValueNotifier<int>(0);

  List<Honoo> get personal =>
      _cacheUserId == null ||
          _cacheUserId != SupabaseProvider.client.auth.currentUser?.id
      ? const []
      : List.unmodifiable(_personal);

  void clearCache() {
    _loadGeneration++;
    _cacheUserId = null;
    _personal.clear();
    isLoading.value = false;
    version.value++;
  }

  /// Carica dallo scrigno (destination='chest') – niente mock
  Future<void> loadChest() async {
    final userId = SupabaseProvider.client.auth.currentUser?.id;
    if (_cacheUserId != userId) clearCache();
    if (userId == null) return;
    _cacheUserId = userId;
    final generation = ++_loadGeneration;
    isLoading.value = true;
    try {
      final chest = await HonooService.fetchUserChestHonoo(userId);
      List<Honoo> moon = const [];
      try {
        moon = await HonooService.fetchUserHonoo(userId, 'moon');
      } catch (error) {
        debugPrint('loadChest moon lookup error: $error');
      }
      final moonContent = moon.map((h) => (h.text, h.image)).toSet();

      // Popola cache iniziale
      final personal = chest
          .map(
            (h) =>
                h.copyWith(isOnMoon: moonContent.contains((h.text, h.image))),
          )
          .toList();

      // === Calcolo hasReplies con una query IN (...) su reply_to ===
      // prendo tutti gli uuid (dbId) disponibili
      final ids = personal.map((h) => h.dbId).whereType<String>().toList();
      if (ids.isNotEmpty) {
        final client = SupabaseProvider.client;
        final rows = await client
            .from('honoo')
            .select('reply_to')
            .in_('reply_to', ids);

        // reply_to presenti → esistono risposte
        final repliedParents = <String>{};
        for (final row in (rows as List)) {
          final p = row['reply_to']?.toString();
          if (p != null) repliedParents.add(p);
        }

        // marca i tuoi honoo personali che hanno risposte
        for (var i = 0; i < personal.length; i++) {
          final h = personal[i];
          final has = h.dbId != null && repliedParents.contains(h.dbId);
          if (has != h.hasReplies) {
            personal[i] = h.copyWith(hasReplies: has);
          }
        }
      }

      if (generation != _loadGeneration ||
          SupabaseProvider.client.auth.currentUser?.id != userId) {
        return;
      }
      _personal
        ..clear()
        ..addAll(personal);
      version.value++;
    } finally {
      if (generation == _loadGeneration) isLoading.value = false;
    }
  }

  /// History (thread) per un honoo: include il padre e le sue reply
  Future<List<Honoo>> getHonooHistory(Honoo honoo) async {
    final id = honoo.dbId;
    if (id == null) {
      // se non hai l'uuid (dbId), ritorna almeno la card corrente
      return [honoo];
    }

    final client = SupabaseProvider.client;

    // Prendiamo l'honoo originale + tutte le reply collegate
    // or('id.eq.<id>,reply_to.eq.<id>')
    final rows = await client
        .from('honoo')
        .select(
          'id,text,image_url,destination,reply_to,recipient_tag,created_at,updated_at,user_id',
        )
        .or('id.eq.$id,reply_to.eq.$id')
        .order('created_at', ascending: true);

    final List<Honoo> thread = (rows as List)
        .map((m) => Honoo.fromMap(m as Map<String, dynamic>))
        .toList();

    // opzionale: marca il primo come personal/moon e le altre come answer se necessario
    return thread;
  }

  /// Pubblica una copia dell'honoo sulla Luna senza toccare l'originale nello scrigno.
  /// Ritorna:
  ///  - true  => inserito ora ("Spedito sulla Luna")
  ///  - false => già presente ("Già presente sulla Luna")
  Future<DuplicationResult> sendToMoon(Honoo h) async {
    try {
      final result = await HonooService.duplicateToMoon(h);
      final index = _personal.indexWhere(
        (item) => item.dbId != null && item.dbId == h.dbId,
      );
      if (index >= 0) {
        _personal[index] = _personal[index].copyWith(isOnMoon: true);
        version.value++;
      }
      h.isOnMoon = true;
      return result;
    } catch (e) {
      debugPrint('duplicateToMoon error: $e');
      rethrow;
    }
  }

  Future<DuplicationResult> saveToChest(Honoo h) async {
    try {
      final result = await HonooService.duplicateToChest(h);
      if (result == DuplicationResult.inserted) {
        await loadChest();
      }
      return result;
    } catch (e) {
      debugPrint('duplicateToChest error: $e');
      rethrow;
    }
  }

  Future<void> deleteHonoo(Honoo h) async {
    final String? id = h.dbId;
    if (id == null || id.isEmpty) {
      debugPrint('deleteHonoo: id mancante');
      return;
    }

    await HonooService.deleteHonooById(id);

    _personal.removeWhere((x) => x.dbId == id);
    version.value++;
  }

  Future<void> deleteHonooById(String? id) async {
    if (id == null || id.isEmpty) {
      debugPrint('deleteHonooById: id vuoto');
      return;
    }

    await HonooService.deleteHonooById(id);

    _personal.removeWhere((x) => x.dbId == id);
    version.value++;
  }
}

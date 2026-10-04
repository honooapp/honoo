import 'package:honoo/Services/supabase_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../Entities/honoo.dart';
import 'duplication_result.dart';
import 'reliability_policy.dart';

class HonooService {
  static const ReliabilityPolicy _reliability = ReliabilityPolicy();
  //sostituisci fuori dal test con il tuo client
  //static final _client = Supabase.instance.client;

  // ✅ Usa un getter, così nei test possiamo sovrascrivere il client
  static SupabaseClient get _client =>
      _overrideClient ?? SupabaseProvider.client;

  // ✅ Campo usato solo nei test (rimane null in produzione)
  static SupabaseClient? _overrideClient;

  /// TEST-ONLY: abilita injection del client mock
  static void $setTestClient(SupabaseClient? c) => _overrideClient = c;

  static Future<void> updateContent({
    required String id,
    required String text,
    required String imageUrl,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('Utente non autenticato');
    await _client
        .from('honoo')
        .update({
          'text': text,
          'image_url': imageUrl,
          'fingerprint': '$text\u001f$imageUrl',
        })
        .eq('id', id)
        .eq('user_id', userId)
        .select('id')
        .single();
  }

  /// Honoo pubblici (Luna)
  static Future<List<Honoo>> fetchPublicHonoo() async {
    final response = await _reliability.read(
      () async => await _client
          .from('honoo')
          .select('*')
          .eq('destination', 'moon')
          .order('created_at', ascending: false),
    );
    return (response as List).map((e) => Honoo.fromMap(e)).toList();
  }

  /// Honoo dell’utente per una certa destination (es. 'chest')
  static Future<List<Honoo>> fetchUserHonoo(
    String userId,
    String destination,
  ) async {
    final response = await _reliability.read(
      () async => await _client
          .from('honoo')
          .select('*')
          .eq('destination', destination)
          .eq('user_id', userId)
          .order('created_at', ascending: false),
    );
    return (response as List).map((e) => Honoo.fromMap(e)).toList();
  }

  /// Radici personali e risposte inviate o ricevute che devono comparire
  /// come un solo accesso persistente alla conversazione nello Scrigno.
  static Future<List<Honoo>> fetchUserChestHonoo(String userId) async {
    final hiddenResponse = await _reliability.read(
      () async => await _client
          .from('chest_hidden_conversations')
          .select('conversation_id')
          .eq('user_id', userId),
    );
    final hiddenConversationIds = (hiddenResponse as List)
        .map((row) => row['conversation_id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();
    final response = await _reliability.read(
      () async => await _client
          .from('honoo')
          .select('*')
          .in_('destination', ['chest', 'reply'])
          .or(
            'user_id.eq.$userId,and(destination.eq.reply,recipient_tag.eq.$userId)',
          )
          .order('created_at', ascending: false),
    );
    return (response as List)
        .map((e) => Honoo.fromMap(e))
        .where(
          (honoo) =>
              !hiddenConversationIds.contains(honoo.dbId) &&
              !hiddenConversationIds.contains(honoo.conversationId) &&
              !hiddenConversationIds.contains(honoo.replyTo),
        )
        .toList();
  }

  /// Tutte le reply indirizzate a recipientTag (se usi i tag poetici)
  static Future<List<Honoo>> fetchRepliesForUser(String recipientTag) async {
    final response = await _reliability.read(
      () async => await _client
          .from('honoo')
          .select('*')
          .eq('destination', 'reply')
          .eq('recipient_tag', recipientTag)
          .order('created_at', ascending: false),
    );
    return (response as List).map((e) => Honoo.fromMap(e)).toList();
  }

  /// Pubblica un nuovo honoo
  static Future<void> publishHonoo(Honoo honoo) async {
    _validateConversationLink(honoo);
    await _reliability.write(
      () async => await _client.from('honoo').insert(honoo.toInsertMap()),
    );
  }

  static Future<String> publishHonooAndReturnId(Honoo honoo) async {
    _validateConversationLink(honoo);
    Map<String, dynamic>? row;
    row = await _reliability.write(
      () async => await _client
          .from('honoo')
          .insert(honoo.toInsertMap())
          .select('id')
          .maybeSingle(),
    );
    final id = row?['id']?.toString() ?? '';
    if (id.isEmpty) {
      throw Exception('publishHonoo: id mancante');
    }
    return id;
  }

  static void _validateConversationLink(Honoo honoo) {
    if (honoo.type != HonooType.answer) return;
    if ((honoo.replyTo ?? '').trim().isEmpty ||
        (honoo.conversationId ?? '').trim().isEmpty ||
        (honoo.recipientTag ?? '').trim().isEmpty) {
      throw ArgumentError(
        'Una risposta Honoo richiede reply_to, conversation_id e destinatario.',
      );
    }
  }

  /// Aggiorna la destination (chest|moon|reply) per id (UUID DB)
  static Future<void> updateDestination({
    required String id,
    required String destination,
  }) async {
    await _reliability.write(
      () async => await _client
          .from('honoo')
          .update({'destination': destination})
          .eq('id', id),
    );
  }

  /// Duplica un honoo salvandolo nello scrigno dell'utente corrente.
  /// L'indice univoco sul fingerprint rende inserimento e deduplica atomici.
  static Future<DuplicationResult> duplicateToChest(Honoo h) async {
    final session = _client.auth.currentSession;
    if (session == null) {
      throw Exception('Nessuna sessione attiva');
    }
    final uid = session.user.id;

    final payload = <String, dynamic>{
      'text': h.text,
      'image_url': h.image.isEmpty ? null : h.image,
      'destination': 'chest',
      'reply_to': h.replyTo,
      'recipient_tag': h.recipientTag,
      'user_id': uid,
      'conversation_id': h.conversationId ?? h.dbId,
      'fingerprint': fingerprint(h),
      if (h.isFromMoonSaved) 'is_from_moon_saved': true,
    };
    return _insertDuplicate(payload);
  }

  /// Pubblica una nuova copia dell'honoo sulla Luna a ogni invio.
  /// Non tocca l'originale in 'chest'; il fingerprint resta disponibile per
  /// mostrare nello Scrigno che almeno una copia è già stata pubblicata.
  static Future<DuplicationResult> duplicateToMoon(Honoo h) async {
    if (h.isFromMoonSaved) {
      throw ArgumentError(
        'Un honoo salvato dalla Luna non può essere ripubblicato.',
      );
    }
    final session = _client.auth.currentSession;
    if (session == null) {
      throw Exception('Nessuna sessione attiva');
    }
    final uid = session.user.id;

    final payload = <String, dynamic>{
      'text': h.text,
      'image_url': (h.image.isEmpty) ? null : h.image,
      'destination': 'moon',
      'reply_to': null,
      'recipient_tag': null,
      'user_id': uid,
      'fingerprint': fingerprint(h),
    };
    return _insertDuplicate(payload);
  }

  static String fingerprint(Honoo h) => '${h.text}\u001f${h.image}';

  static Future<bool> hasMoonCopy(Honoo h) async {
    final session = _client.auth.currentSession;
    if (session == null) throw Exception('Nessuna sessione attiva');
    final row = await _reliability.read(
      () async => await _client
          .from('honoo')
          .select('id')
          .eq('user_id', session.user.id)
          .eq('destination', 'moon')
          .eq('fingerprint', fingerprint(h))
          .limit(1)
          .maybeSingle(),
    );
    return row != null;
  }

  static Future<DuplicationResult> _insertDuplicate(
    Map<String, dynamic> payload,
  ) {
    return _reliability.write(() async {
      try {
        await _client.from('honoo').insert(payload);
        return DuplicationResult.inserted;
      } on PostgrestException catch (error) {
        if (error.code == '23505') return DuplicationResult.alreadyPresent;
        rethrow;
      }
    });
  }

  /// Hard delete dal DB (tabella 'honoo')
  static Future<void> deleteHonooById(String id) async {
    final rows = await _reliability.write<List<dynamic>>(
      () async =>
          await _client.from('honoo').delete().eq('id', id).select('id'),
    );
    if (rows.length != 1) {
      throw StateError(
        'Eliminazione non confermata: contenuto non disponibile.',
      );
    }
  }
}

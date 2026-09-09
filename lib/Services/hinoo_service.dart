import 'package:honoo/Services/supabase_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../Entities/hinoo.dart';
import 'duplication_result.dart';
import 'reliability_policy.dart';

class HinooService {
  static const String _table = 'hinoo';
  static const ReliabilityPolicy _reliability = ReliabilityPolicy();

  // Iniezione client per i test
  static SupabaseClient? _testClient;
  static void $setTestClient(SupabaseClient? c) => _testClient = c;
  static SupabaseClient get _client => _testClient ?? SupabaseProvider.client;

  static String _toDbType(HinooType type) {
    switch (type) {
      case HinooType.moon:
        return 'moon';
      default:
        return type.name;
    }
  }

  static HinooType _fromDbType(String? value) {
    if (value == 'public' || value == 'moon') return HinooType.moon;
    if (value == 'answer') return HinooType.answer;
    return HinooType.personal;
  }

  static void _validateConversationLink(HinooDraft draft) {
    if (draft.type != HinooType.answer) return;
    if ((draft.replyTo ?? '').trim().isEmpty ||
        (draft.conversationId ?? '').trim().isEmpty ||
        (draft.recipientTag ?? '').trim().isEmpty) {
      throw ArgumentError(
        'Una risposta Hinoo richiede reply_to, conversation_id e destinatario.',
      );
    }
  }

  static Future<void> updateContent({
    required String id,
    required HinooDraft draft,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('Utente non autenticato');
    await _client
        .from(_table)
        .update({
          'pages': draft.toJson()['pages'],
          'fingerprint': draft.type == HinooType.moon
              ? fingerprint(draft)
              : null,
        })
        .eq('id', id)
        .eq('user_id', userId)
        .select('id')
        .single();
  }

  static Future<void> publishHinoo(HinooDraft draft) async {
    _validateConversationLink(draft);
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw 'Utente non autenticato';

    final data = {
      'user_id': userId,
      'type': _toDbType(draft.type),
      'pages': draft.toJson()['pages'],
      'recipient_tag': draft.recipientTag,
      'reply_to': draft.replyTo,
      'conversation_id': draft.conversationId,
      'is_from_moon_saved': draft.isFromMoonSaved,
      'fingerprint': (draft.type == HinooType.moon) ? fingerprint(draft) : null,
    };

    final res = await _insertPublished(data);
    if (res == null) throw 'publishHinoo: insert fallita';
  }

  static Future<String> publishHinooAndReturnId(HinooDraft draft) async {
    _validateConversationLink(draft);
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw 'Utente non autenticato';

    final data = {
      'user_id': userId,
      'type': _toDbType(draft.type),
      'pages': draft.toJson()['pages'],
      'recipient_tag': draft.recipientTag,
      'reply_to': draft.replyTo,
      'conversation_id': draft.conversationId,
      'is_from_moon_saved': draft.isFromMoonSaved,
      'fingerprint': (draft.type == HinooType.moon) ? fingerprint(draft) : null,
    };

    final res = await _insertPublished(data);
    if (res == null) throw 'publishHinoo: insert fallita';
    final id = res['id']?.toString() ?? '';
    if (id.isEmpty) throw 'publishHinoo: id mancante';
    return id;
  }

  static Future<Map<String, dynamic>?> _insertPublished(
    Map<String, dynamic> data,
  ) {
    return _reliability.write(() async {
      try {
        return await _client.from(_table).insert(data).select().maybeSingle();
      } on PostgrestException catch (error) {
        if (!_isMissingMoonSavedColumn(error)) rethrow;
        final fallback = Map<String, dynamic>.from(data)
          ..remove('is_from_moon_saved');
        return _client.from(_table).insert(fallback).select().maybeSingle();
      }
    });
  }

  /// Inserisce una nuova copia type='moon' a ogni invio. Il fingerprint resta
  /// disponibile per mostrare nello Scrigno lo stato di pubblicazione.
  static Future<DuplicationResult> duplicateToMoon(HinooDraft draft) async {
    if (draft.isFromMoonSaved) {
      throw ArgumentError(
        'Un hinoo salvato dalla Luna non può essere ripubblicato.',
      );
    }
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw 'Utente non autenticato';

    final sanitized = HinooDraft(
      pages: draft.pages,
      type: HinooType.moon,
      baseCanvasHeight: draft.baseCanvasHeight,
    );
    final fp = fingerprint(sanitized);

    final data = {
      'user_id': userId,
      'type': _toDbType(HinooType.moon),
      'pages': sanitized.toJson()['pages'],
      'fingerprint': fp,
      'recipient_tag': null,
      'reply_to': null,
      'is_from_moon_saved': false,
    };

    return _insertDuplicate(data);
  }

  static Future<DuplicationResult> duplicateMoonToChest(
    HinooDraft draft,
  ) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw 'Utente non autenticato';

    final sanitized = draft.copyWith(
      type: HinooType.personal,
      isFromMoonSaved: true,
    );
    final fp = fingerprint(sanitized);

    final data = {
      'user_id': userId,
      'type': _toDbType(HinooType.personal),
      'pages': sanitized.toJson()['pages'],
      'recipient_tag': sanitized.recipientTag,
      'reply_to': sanitized.replyTo,
      'conversation_id': sanitized.conversationId,
      'is_from_moon_saved': true,
      'fingerprint': fp,
    };

    return _insertDuplicate(data);
  }

  static Future<DuplicationResult> _insertDuplicate(Map<String, dynamic> data) {
    return _reliability.write(() async {
      try {
        await _client.from(_table).insert(data);
        return DuplicationResult.inserted;
      } on PostgrestException catch (error) {
        if (error.code == '23505') return DuplicationResult.alreadyPresent;
        if (!_isMissingMoonSavedColumn(error)) rethrow;
        final fallback = Map<String, dynamic>.from(data)
          ..remove('is_from_moon_saved');
        try {
          await _client.from(_table).insert(fallback);
          return DuplicationResult.inserted;
        } on PostgrestException catch (fallbackError) {
          if (fallbackError.code == '23505') {
            return DuplicationResult.alreadyPresent;
          }
          rethrow;
        }
      }
    });
  }

  static Future<void> deleteHinooById(String id) async {
    if (id.trim().isEmpty) return;
    await _reliability.write(() => _client.from(_table).delete().eq('id', id));
  }

  static String fingerprint(HinooDraft d) {
    final parts = <String>[
      'type=${d.type.name}',
      'pages=${d.pages.length}',
      for (final p in d.pages)
        'bg:${p.backgroundImage ?? ''}|'
            'txt:${p.text}|'
            'col:${p.isTextWhite ? 'w' : 'b'}|'
            'tr:${p.bgScale.toStringAsFixed(4)},${p.bgOffsetX.toStringAsFixed(2)},${p.bgOffsetY.toStringAsFixed(2)}',
      if (d.recipientTag != null) 'recipient=${d.recipientTag}',
    ];
    return parts.join('||');
  }

  static Set<String> moonFingerprints(HinooDraft draft) {
    final sanitized = HinooDraft(
      pages: draft.pages,
      type: HinooType.moon,
      baseCanvasHeight: draft.baseCanvasHeight,
    );
    return <String>{
      fingerprint(sanitized),
      // Compatibilità con le copie create prima che i riferimenti privati
      // della conversazione venissero rimossi dalla pubblicazione Luna.
      fingerprint(draft.copyWith(type: HinooType.moon)),
    };
  }

  static Future<bool> hasMoonCopy(HinooDraft draft) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw 'Utente non autenticato';
    final fingerprints = moonFingerprints(draft).toList(growable: false);
    final row = await _reliability.read(
      () async => await _client
          .from(_table)
          .select('id')
          .eq('user_id', userId)
          .eq('type', 'moon')
          .in_('fingerprint', fingerprints)
          .limit(1)
          .maybeSingle(),
    );
    return row != null;
  }

  static bool _isMissingMoonSavedColumn(PostgrestException e) {
    final message = e.message;
    final details = e.details ?? '';
    final hint = e.hint ?? '';
    final combined = '$message $details $hint';
    return combined.contains('is_from_moon_saved');
  }

  static Future<void> saveDraft(HinooDraft draft) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw 'Utente non autenticato';

    await _client.from('hinoo_drafts').upsert({
      'user_id': userId,
      'payload': draft.toJson(),
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'user_id');
  }

  static Future<HinooDraft?> getDraft() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;

    final res = await _client
        .from('hinoo_drafts')
        .select('payload')
        .eq('user_id', userId)
        .order('updated_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (res == null) return null;
    final payload = res['payload'];
    if (payload is Map<String, dynamic>) {
      return HinooDraft.fromJson(payload);
    }
    return null;
  }

  /// Carica gli Hinoo personali dell'utente (dallo scrigno)
  static Future<List<HinooDraft>> fetchUserHinoo(
    String userId, {
    HinooType type = HinooType.personal,
  }) async {
    final typeStr = _toDbType(type);
    final baseQuery = _client
        .from(_table)
        .select('pages,type,recipient_tag,created_at')
        .eq('user_id', userId);

    final filteredQuery = type == HinooType.moon
        ? baseQuery.eq('type', 'moon')
        : baseQuery.eq('type', typeStr);

    final rows = await filteredQuery.order('created_at', ascending: false);

    final List<HinooDraft> list = [];
    for (final r in (rows as List)) {
      final pages = r['pages'];
      final String? recipient = r['recipient_tag'] as String?;
      if (pages is List) {
        list.add(
          HinooDraft(
            pages: pages
                .whereType<Map<String, dynamic>>()
                .map((e) => HinooSlide.fromJson(e))
                .toList(),
            type: _fromDbType(r['type'] as String?),
            recipientTag: recipient,
          ),
        );
      }
    }
    return list;
  }
}

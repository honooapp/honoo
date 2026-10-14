import 'dart:convert';

import 'package:honoo/Entities/hinoo.dart';
import 'package:honoo/Entities/honoo.dart';
import 'package:honoo/Entities/conversation_entry.dart';
import 'package:honoo/Services/supabase_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'reliability_policy.dart';

class ConversationService {
  static SupabaseClient get _client => SupabaseProvider.client;

  static Future<List<ConversationEntry>> fetchConversation(
    String conversationId,
  ) => const ReliabilityPolicy().read(() => _fetchConversation(conversationId));

  static Future<List<ConversationEntry>> _fetchConversation(
    String conversationId,
  ) async {
    final rows = await Future.wait<dynamic>([
      _client
          .from('honoo')
          .select(
            'id,text,image_url,destination,reply_to,recipient_tag,created_at,updated_at,user_id,conversation_id,is_from_moon_saved,admin_deleted_at',
          )
          .or(
            'conversation_id.eq.$conversationId,and(conversation_id.is.null,or(id.eq.$conversationId,reply_to.eq.$conversationId))',
          )
          .order('created_at', ascending: true),
      _client
          .from('hinoo')
          .select(
            'id,pages,type,recipient_tag,reply_to,created_at,user_id,conversation_id,is_from_moon_saved,admin_deleted_at',
          )
          .or(
            'conversation_id.eq.$conversationId,and(conversation_id.is.null,or(id.eq.$conversationId,reply_to.eq.$conversationId))',
          )
          .order('created_at', ascending: true),
      _client
          .from('conversation_tombstones')
          .select('content_id,conversation_id,original_created_at')
          .eq('conversation_id', conversationId)
          .order('original_created_at', ascending: true),
    ]);
    final honooRows = rows[0] as List;
    final hinooRows = rows[1] as List;
    final tombstoneRows = rows[2] as List;

    final entries = <_Entry>[];
    for (final r in honooRows) {
      if (r['admin_deleted_at'] != null) {
        entries.add(
          _Entry.deleted(
            id: r['id']?.toString(),
            createdAt: _parseCreatedAt(r['created_at']),
          ),
        );
        continue;
      }
      final h = Honoo.fromMap(Map<String, dynamic>.from(r));
      entries.add(_Entry.honoo(h));
    }
    for (final r in hinooRows) {
      if (r['admin_deleted_at'] != null) {
        entries.add(
          _Entry.deleted(
            id: r['id']?.toString(),
            createdAt: _parseCreatedAt(r['created_at']),
          ),
        );
        continue;
      }
      final pages = r['pages'];
      if (pages is! List) continue;
      final replyTo = r['reply_to']?.toString();
      final recipientTag = r['recipient_tag']?.toString();
      final conversationId = r['conversation_id']?.toString();
      final bool isFromMoonSaved = (r['is_from_moon_saved'] as bool?) ?? false;
      // Compatibilita con risposte create quando reply_to non veniva
      // persistito: destinatario + conversation_id identificano comunque
      // inequivocabilmente un messaggio della conversazione.
      final bool isReply =
          replyTo?.isNotEmpty == true ||
          (!isFromMoonSaved &&
              recipientTag?.isNotEmpty == true &&
              conversationId?.isNotEmpty == true);
      final draft = HinooDraft(
        pages: pages
            .whereType<Map<String, dynamic>>()
            .map(HinooSlide.fromJson)
            .toList(),
        type: isReply ? HinooType.answer : _fromDbType(r['type'] as String?),
        recipientTag: recipientTag,
        replyTo: replyTo,
        conversationId: conversationId,
        isFromMoonSaved: isFromMoonSaved,
      );
      final ownerId = r['user_id']?.toString();
      entries.add(
        _Entry.hinoo(
          draft,
          createdAt:
              DateTime.tryParse(r['created_at']?.toString() ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0),
          ownerId: ownerId,
          id: r['id']?.toString(),
          isFromMoonSaved: isFromMoonSaved,
        ),
      );
    }
    final existingIds = entries
        .map((entry) => entry.id)
        .whereType<String>()
        .toSet();
    final missingParentIds = entries
        .map((entry) => entry.honoo?.replyTo ?? entry.hinoo?.replyTo)
        .whereType<String>()
        .where((id) => id.isNotEmpty && !existingIds.contains(id))
        .toSet();
    if (missingParentIds.isNotEmpty) {
      final parentRows = await Future.wait<dynamic>([
        _client
            .from('honoo')
            .select(
              'id,text,image_url,destination,reply_to,recipient_tag,created_at,updated_at,user_id,conversation_id,is_from_moon_saved,admin_deleted_at',
            )
            .in_('id', missingParentIds.toList()),
        _client
            .from('hinoo')
            .select(
              'id,pages,type,recipient_tag,reply_to,created_at,user_id,conversation_id,is_from_moon_saved,admin_deleted_at',
            )
            .in_('id', missingParentIds.toList()),
      ]);
      final parentHonooRows = parentRows[0] as List;
      final parentHinooRows = parentRows[1] as List;
      for (final row in parentHonooRows) {
        if (row['admin_deleted_at'] != null) continue;
        entries.add(
          _Entry.honoo(Honoo.fromMap(Map<String, dynamic>.from(row))),
        );
      }
      for (final row in parentHinooRows) {
        if (row['admin_deleted_at'] != null || row['pages'] is! List) continue;
        final pages = (row['pages'] as List)
            .whereType<Map<String, dynamic>>()
            .map(HinooSlide.fromJson)
            .toList();
        entries.add(
          _Entry.hinoo(
            HinooDraft(
              pages: pages,
              type: _fromDbType(row['type'] as String?),
              recipientTag: row['recipient_tag']?.toString(),
              replyTo: row['reply_to']?.toString(),
              conversationId: row['conversation_id']?.toString(),
              isFromMoonSaved: (row['is_from_moon_saved'] as bool?) ?? false,
            ),
            createdAt: _parseCreatedAt(row['created_at']),
            ownerId: row['user_id']?.toString(),
            id: row['id']?.toString(),
            isFromMoonSaved: (row['is_from_moon_saved'] as bool?) ?? false,
          ),
        );
      }
    }
    for (final row in tombstoneRows) {
      final id = row['content_id']?.toString();
      if (id == null || id.isEmpty || !existingIds.add(id)) continue;
      entries.add(
        _Entry.deleted(
          id: id,
          createdAt: _parseCreatedAt(row['original_created_at']),
        ),
      );
    }
    final deduplicatedEntries = _orderEntries(_deduplicateMoonRoots(entries));
    return deduplicatedEntries
        .map(
          (e) => e.when(
            honoo: (h) => ConversationEntry.honoo(h),
            hinoo: (d) => ConversationEntry.hinoo(
              d,
              createdAt: e.createdAt,
              ownerId: e.ownerId,
              id: e.id,
              isFromMoonSaved: e.isFromMoonSaved,
            ),
            deleted: () => ConversationEntry.deleted(
              id: e.id ?? '',
              createdAt: e.createdAt,
            ),
          ),
        )
        .toList();
  }

  static DateTime _parseCreatedAt(dynamic value) =>
      DateTime.tryParse(value?.toString() ?? '') ??
      DateTime.fromMillisecondsSinceEpoch(0);

  /// Produce una timeline stabile anche quando molti utenti scrivono nello
  /// stesso istante. Il confronto per id rende deterministici i pareggi, poi
  /// la visita del padre garantisce che una risposta non preceda mai il
  /// contenuto a cui risponde.
  static List<_Entry> _orderEntries(List<_Entry> entries) {
    final sorted = List<_Entry>.of(entries)
      ..sort((a, b) {
        final byTime = a.createdAt.compareTo(b.createdAt);
        if (byTime != 0) return byTime;
        return (a.id ?? '').compareTo(b.id ?? '');
      });
    final byId = <String, _Entry>{
      for (final entry in sorted)
        if (entry.id?.isNotEmpty == true) entry.id!: entry,
    };
    final ordered = <_Entry>[];
    final visiting = <_Entry>{};
    final visited = <_Entry>{};

    void visit(_Entry entry) {
      if (visited.contains(entry)) return;
      if (!visiting.add(entry)) return;
      final parentId = entry.replyTo;
      final parent = parentId == null ? null : byId[parentId];
      if (parent != null) visit(parent);
      visiting.remove(entry);
      if (visited.add(entry)) ordered.add(entry);
    }

    for (final entry in sorted) {
      visit(entry);
    }
    return ordered;
  }

  static List<_Entry> _deduplicateMoonRoots(List<_Entry> entries) {
    final moonSavedRootKeys = entries
        .where((entry) => entry.isFromMoonSaved && !entry.isReply)
        .map((entry) => entry.contentKey)
        .toSet();
    if (moonSavedRootKeys.isEmpty) return List<_Entry>.of(entries);

    final retainedMoonSavedRoots = <String>{};
    return entries.where((entry) {
      if (entry.isReply || !moonSavedRootKeys.contains(entry.contentKey)) {
        return true;
      }
      if (!entry.isFromMoonSaved) return false;
      return retainedMoonSavedRoots.add(entry.contentKey);
    }).toList();
  }

  static RealtimeChannel subscribeConversation(
    String conversationId,
    void Function() onChange, {
    void Function(ConversationRealtimeConnectionStatus status, Object? error)?
    onStatus,
  }) {
    void refresh(dynamic _, [dynamic __]) => onChange();
    final accessToken = _client.auth.currentSession?.accessToken;
    if (accessToken != null) _client.realtime.setAuth(accessToken);
    final chan = _client.channel('conv-$conversationId');
    chan
        .on(
          RealtimeListenTypes.postgresChanges,
          ChannelFilter(
            event: '*',
            schema: 'public',
            table: 'honoo',
            filter: 'conversation_id=eq.$conversationId',
          ),
          refresh,
        )
        .on(
          RealtimeListenTypes.postgresChanges,
          ChannelFilter(
            event: '*',
            schema: 'public',
            table: 'hinoo',
            filter: 'conversation_id=eq.$conversationId',
          ),
          refresh,
        )
        .on(
          RealtimeListenTypes.postgresChanges,
          ChannelFilter(
            event: '*',
            schema: 'public',
            table: 'conversation_tombstones',
            filter: 'conversation_id=eq.$conversationId',
          ),
          refresh,
        )
        .subscribe((status, [error]) {
          if (status == 'SUBSCRIBED') {
            onStatus?.call(
              ConversationRealtimeConnectionStatus.subscribed,
              null,
            );
          } else if (status == 'CHANNEL_ERROR' ||
              status == 'CLOSED' ||
              status == 'TIMED_OUT') {
            onStatus?.call(
              ConversationRealtimeConnectionStatus.disconnected,
              error ?? status,
            );
          }
        });
    return chan;
  }

  static HinooType _fromDbType(String? value) {
    if (value == 'moon' || value == 'public') return HinooType.moon;
    if (value == 'answer') return HinooType.answer;
    return HinooType.personal;
  }
}

enum ConversationRealtimeConnectionStatus { subscribed, disconnected }

class _Entry {
  final Honoo? honoo;
  final HinooDraft? hinoo;
  final DateTime createdAt;
  final String? ownerId;
  final String? id;
  final bool isFromMoonSaved;
  final bool isDeleted;

  _Entry._(
    this.honoo,
    this.hinoo,
    this.createdAt, {
    this.ownerId,
    this.id,
    this.isFromMoonSaved = false,
    this.isDeleted = false,
  });
  factory _Entry.honoo(Honoo h) => _Entry._(
    h,
    null,
    DateTime.tryParse(h.createdAt) ?? DateTime.now(),
    ownerId: h.userId,
    id: h.dbId,
    isFromMoonSaved: h.isFromMoonSaved,
  );
  factory _Entry.hinoo(
    HinooDraft d, {
    required DateTime createdAt,
    String? ownerId,
    String? id,
    bool isFromMoonSaved = false,
  }) => _Entry._(
    null,
    d,
    createdAt,
    ownerId: ownerId,
    id: id,
    isFromMoonSaved: isFromMoonSaved,
  );

  factory _Entry.deleted({required String? id, required DateTime createdAt}) =>
      _Entry._(null, null, createdAt, id: id, isDeleted: true);

  bool get isReply => isDeleted
      ? false
      : honoo != null
      ? honoo!.type == HonooType.answer
      : hinoo!.type == HinooType.answer;

  String? get replyTo => honoo?.replyTo ?? hinoo?.replyTo;

  String get contentKey {
    if (isDeleted) return 'deleted\u001f${id ?? ''}';
    if (honoo != null) {
      return 'honoo\u001f${honoo!.text}\u001f${honoo!.image}';
    }
    final pages = hinoo!.pages.map((page) => page.toJson()).toList();
    return 'hinoo\u001f${jsonEncode(pages)}';
  }

  T when<T>({
    required T Function(Honoo) honoo,
    required T Function(HinooDraft) hinoo,
    required T Function() deleted,
  }) {
    if (isDeleted) return deleted();
    if (this.honoo != null) return honoo(this.honoo!);
    return hinoo(this.hinoo!);
  }
}

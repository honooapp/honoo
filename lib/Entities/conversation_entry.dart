import 'package:honoo/Entities/hinoo.dart';
import 'package:honoo/Entities/honoo.dart';

enum ConversationEntryKind { honoo, hinoo, deleted }

class ConversationEntry {
  final ConversationEntryKind kind;
  final Honoo? honoo;
  final HinooDraft? hinoo;
  final String? ownerId;
  final String? id;
  final String? replyTo;
  final bool isFromMoonSaved;
  final bool deletedByOwner;
  final DateTime createdAt;

  ConversationEntry._(
    this.kind, {
    required this.createdAt,
    this.honoo,
    this.hinoo,
    this.ownerId,
    this.id,
    this.replyTo,
    this.isFromMoonSaved = false,
    this.deletedByOwner = false,
  });

  factory ConversationEntry.honoo(Honoo h) => ConversationEntry._(
    ConversationEntryKind.honoo,
    honoo: h,
    createdAt:
        DateTime.tryParse(h.createdAt) ??
        DateTime.fromMillisecondsSinceEpoch(0),
    ownerId: h.userId,
    id: h.dbId,
    replyTo: h.replyTo,
    isFromMoonSaved: h.isFromMoonSaved,
  );

  factory ConversationEntry.hinoo(
    HinooDraft d, {
    required DateTime createdAt,
    String? ownerId,
    String? id,
    bool isFromMoonSaved = false,
  }) => ConversationEntry._(
    ConversationEntryKind.hinoo,
    hinoo: d,
    createdAt: createdAt,
    ownerId: ownerId,
    id: id,
    replyTo: d.replyTo,
    isFromMoonSaved: isFromMoonSaved,
  );

  factory ConversationEntry.deleted({
    required String id,
    required DateTime createdAt,
    bool deletedByOwner = false,
  }) => ConversationEntry._(
    ConversationEntryKind.deleted,
    deletedByOwner: deletedByOwner,
    id: id,
    createdAt: createdAt,
  );
}

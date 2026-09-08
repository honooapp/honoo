import 'hinoo.dart';
import 'honoo.dart';

class ChestItem {
  const ChestItem._({this.honoo, this.hinoo, required this.createdAt});

  factory ChestItem.honoo(Honoo honoo, DateTime createdAt) =>
      ChestItem._(honoo: honoo, createdAt: createdAt);

  factory ChestItem.hinoo(ChestHinooItem hinoo) =>
      ChestItem._(hinoo: hinoo, createdAt: hinoo.createdAt);

  final Honoo? honoo;
  final ChestHinooItem? hinoo;
  final DateTime createdAt;

  T when<T>({
    required T Function(Honoo honoo) honoo,
    required T Function(ChestHinooItem hinoo) hinoo,
  }) {
    if (this.honoo != null) return honoo(this.honoo!);
    return hinoo(this.hinoo!);
  }
}

class ChestHinooItem {
  const ChestHinooItem({
    required this.id,
    required this.draft,
    required this.createdAt,
    required this.isFromMoonSaved,
    required this.ownerId,
    this.isOnMoon = false,
    this.conversationId,
  });

  final String id;
  final HinooDraft draft;
  final DateTime createdAt;
  final bool isFromMoonSaved;
  final String? ownerId;
  final bool isOnMoon;
  final String? conversationId;

  static ChestHinooItem? fromDatabaseRow(Map<dynamic, dynamic> row) {
    final pages = row['pages'];
    final id = row['id']?.toString();
    if (pages is! List || id == null || id.isEmpty) return null;

    final typeValue = row['type']?.toString();
    final replyTo = row['reply_to']?.toString();
    final hasReplyTarget = replyTo != null && replyTo.isNotEmpty;
    final isFromMoonSaved = (row['is_from_moon_saved'] as bool?) ?? false;
    final legacyReply =
        !isFromMoonSaved &&
        row['recipient_tag']?.toString().isNotEmpty == true &&
        row['conversation_id']?.toString().isNotEmpty == true;
    final type = hasReplyTarget || legacyReply
        ? HinooType.answer
        : typeValue == 'moon' || typeValue == 'public'
        ? HinooType.moon
        : typeValue == 'answer'
        ? HinooType.answer
        : HinooType.personal;

    return ChestHinooItem(
      id: id,
      draft: HinooDraft(
        pages: pages
            .whereType<Map<String, dynamic>>()
            .map(HinooSlide.fromJson)
            .toList(),
        type: type,
        recipientTag: row['recipient_tag'] as String?,
        replyTo: replyTo,
        conversationId: row['conversation_id']?.toString(),
        isFromMoonSaved: isFromMoonSaved,
      ),
      createdAt:
          DateTime.tryParse((row['created_at'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      isFromMoonSaved: isFromMoonSaved,
      isOnMoon: (row['is_on_moon'] as bool?) ?? false,
      ownerId: row['user_id']?.toString(),
      conversationId: row['conversation_id']?.toString(),
    );
  }
}

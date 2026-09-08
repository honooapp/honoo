import 'hinoo.dart';

class HinooThreadEntry {
  const HinooThreadEntry({
    required this.draft,
    required this.authorId,
    required this.isReply,
    this.createdAt,
    this.id,
  });

  final String? id;
  final HinooDraft draft;
  final String? authorId;
  final bool isReply;
  final DateTime? createdAt;
}

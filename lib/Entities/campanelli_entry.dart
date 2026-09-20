import 'package:flutter/foundation.dart';

@immutable
class CampanelliEntry {
  const CampanelliEntry({
    required this.hinooId,
    this.houseText = '',
    required this.ownerId,
    required this.createdAt,
    required this.text,
    required this.campanelloBackgroundUrl,
    required this.houseImageUrl,
    required this.bgTransform,
    required this.bgScale,
    required this.bgOffsetX,
    required this.bgOffsetY,
    required this.campanelloIsTextWhite,
    required this.campanelloBgTransform,
  });

  final String hinooId;
  final String houseText;
  final String ownerId;
  final DateTime createdAt;
  final String text;
  final String? campanelloBackgroundUrl;
  final String? houseImageUrl;
  final List<double>? bgTransform;
  final double bgScale;
  final double bgOffsetX;
  final double bgOffsetY;
  final bool campanelloIsTextWhite;
  final List<double>? campanelloBgTransform;
}

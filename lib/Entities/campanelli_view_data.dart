import 'package:flutter/widgets.dart';

class CampanelloData {
  const CampanelloData({
    required this.id,
    required this.campanelloHinooId,
    required this.ownerId,
    required this.backgroundImage,
    required this.text,
    required this.linkedHouseId,
    this.bgTransform,
  });

  final String id;
  final String? campanelloHinooId;
  final String? ownerId;
  final ImageProvider backgroundImage;
  final String text;
  final String linkedHouseId;
  final List<double>? bgTransform;

  factory CampanelloData.fromBackend({
    required Map<String, dynamic> row,
    required ImageProvider backgroundImage,
    required String text,
    required String linkedHouseId,
    List<double>? bgTransform,
  }) {
    return CampanelloData(
      id: row['id']?.toString() ?? '',
      campanelloHinooId: row['campanello_hinoo_id']?.toString(),
      ownerId: row['owner_id']?.toString(),
      backgroundImage: backgroundImage,
      text: text,
      linkedHouseId: linkedHouseId,
      bgTransform: bgTransform,
    );
  }
}

class CasaData {
  const CasaData({
    this.text = '',
    required this.id,
    required this.backgroundImage,
    this.bgTransform,
    required this.bgScale,
    required this.bgOffsetX,
    required this.bgOffsetY,
  });

  final String id;
  final ImageProvider backgroundImage;
  final List<double>? bgTransform;
  final String text;
  final double bgScale;
  final double bgOffsetX;
  final double bgOffsetY;

  factory CasaData.fromBackend({
    required Map<String, dynamic> row,
    required ImageProvider backgroundImage,
    required double bgScale,
    required double bgOffsetX,
    required double bgOffsetY,
  }) {
    return CasaData(
      text: row['house_text']?.toString() ?? '',
      id: row['id']?.toString() ?? '',
      backgroundImage: backgroundImage,
      bgTransform: _parseTransform(row['bg_transform']),
      bgScale: bgScale,
      bgOffsetX: bgOffsetX,
      bgOffsetY: bgOffsetY,
    );
  }

  static List<double>? _parseTransform(dynamic raw) {
    if (raw is! List) return null;
    final values = <double>[];
    for (final value in raw) {
      if (value is! num) return null;
      values.add(value.toDouble());
    }
    return List<double>.unmodifiable(values);
  }
}

class CampanelloPageData {
  const CampanelloPageData._({
    required this.isIntro,
    required this.text,
    this.campanello,
  });

  factory CampanelloPageData.intro(String text) {
    return CampanelloPageData._(isIntro: true, text: text);
  }

  factory CampanelloPageData.campanello(CampanelloData campanello) {
    return CampanelloPageData._(
      isIntro: false,
      text: campanello.text,
      campanello: campanello,
    );
  }

  final bool isIntro;
  final String text;
  final CampanelloData? campanello;
}

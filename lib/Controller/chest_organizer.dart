import '../Entities/casa_share_mode.dart';

class ChestOrganization<T> {
  const ChestOrganization({
    required this.items,
    required this.conversationItemCount,
    required this.latestNotificationItemIndex,
  });

  final List<T> items;
  final int conversationItemCount;
  final int latestNotificationItemIndex;
}

class ChestNotificationTarget {
  const ChestNotificationTarget({
    required this.conversationId,
    required this.itemIndex,
  });

  final String conversationId;
  final int itemIndex;

  bool get isDetached => itemIndex < 0;
}

/// Regole pure di ordinamento e raggruppamento dello Scrigno.
class ChestOrganizer {
  const ChestOrganizer._();

  static bool matchesCasaFilter({
    required CasaChestFilter? filter,
    required bool isFromMoonSaved,
    required bool hasConversation,
  }) {
    switch (filter) {
      case null:
        return true;
      case CasaChestFilter.authored:
        return !hasConversation && !isFromMoonSaved;
      case CasaChestFilter.moonSaved:
        return !hasConversation && isFromMoonSaved;
      case CasaChestFilter.all:
        return true;
    }
  }

  static ChestOrganization<T> organize<T>({
    required List<T> items,
    required DateTime Function(T item) createdAtOf,
    required String Function(T item) stableIdOf,
    required DateTime? Function(T item) latestReplyOf,
    required DateTime? Function(T item) latestNotificationOf,
    required String? Function(T item) conversationIdOf,
  }) {
    int compareCreatedAt(T a, T b) {
      final byCreated = createdAtOf(b).compareTo(createdAtOf(a));
      if (byCreated != 0) return byCreated;
      return stableIdOf(a).compareTo(stableIdOf(b));
    }

    DateTime activityOf(T item) {
      final createdAt = createdAtOf(item);
      final latestReply = latestReplyOf(item);
      return latestReply != null && latestReply.isAfter(createdAt)
          ? latestReply
          : createdAt;
    }

    final ordered = List<T>.of(items)
      ..sort((a, b) {
        final byActivity = activityOf(b).compareTo(activityOf(a));
        return byActivity != 0 ? byActivity : compareCreatedAt(a, b);
      });
    final regrouped = <T>[];
    final consumed = <int>{};

    for (var i = 0; i < ordered.length; i++) {
      if (consumed.contains(i)) continue;
      final item = ordered[i];
      final conversationId = conversationIdOf(item);
      if (conversationId == null || conversationId.isEmpty) {
        regrouped.add(item);
        consumed.add(i);
        continue;
      }

      final group = <T>[];
      final groupIndexes = <int>[];
      for (var j = i; j < ordered.length; j++) {
        if (consumed.contains(j)) continue;
        final candidate = ordered[j];
        if (conversationIdOf(candidate) == conversationId) {
          group.add(candidate);
          groupIndexes.add(j);
        }
      }

      if (group.length <= 1) {
        regrouped.add(item);
        consumed.add(i);
        continue;
      }

      group.sort((a, b) {
        final byActivity = activityOf(b).compareTo(activityOf(a));
        return byActivity != 0 ? byActivity : compareCreatedAt(a, b);
      });
      // Ogni conversazione occupa una sola slide del carosello. La slide
      // renderizza poi l'intero thread tramite UnifiedThreadView.
      regrouped.add(group.first);
      consumed.addAll(groupIndexes);
    }

    return ChestOrganization<T>(
      items: List.unmodifiable(regrouped),
      conversationItemCount: items
          .where((item) => latestReplyOf(item) != null)
          .length,
      latestNotificationItemIndex: _latestNotificationIndex(
        regrouped,
        latestNotificationOf,
      ),
    );
  }

  static int _latestNotificationIndex<T>(
    List<T> items,
    DateTime? Function(T item) latestNotificationOf,
  ) {
    var latestIndex = -1;
    DateTime? latestDate;
    for (var i = 0; i < items.length; i++) {
      final candidate = latestNotificationOf(items[i]);
      if (candidate != null &&
          (latestDate == null || candidate.isAfter(latestDate))) {
        latestDate = candidate;
        latestIndex = i;
      }
    }
    return latestIndex;
  }

  /// Individua la conversazione dell'ultima risposta ricevuta anche quando
  /// usa un conversation_id nuovo e quindi non ha ancora una slide radice
  /// nello Scrigno.
  static ChestNotificationTarget? latestNotificationTarget<T>({
    required List<T> items,
    required String? Function(T item) conversationIdOf,
    required Iterable<Map<String, DateTime>> notifications,
  }) {
    String? latestConversationId;
    DateTime? latestDate;
    for (final notificationMap in notifications) {
      for (final entry in notificationMap.entries) {
        if (entry.key.isEmpty ||
            (latestDate != null && !entry.value.isAfter(latestDate))) {
          continue;
        }
        latestConversationId = entry.key;
        latestDate = entry.value;
      }
    }
    if (latestConversationId == null) return null;
    return ChestNotificationTarget(
      conversationId: latestConversationId,
      itemIndex: items.indexWhere(
        (item) => conversationIdOf(item) == latestConversationId,
      ),
    );
  }
}

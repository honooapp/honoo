import 'saved_content_edit_frame.dart';
import 'package:flutter/material.dart';

import '../Entities/chest_item.dart';
import '../Entities/conversation_entry.dart';
import '../Entities/hinoo_thread_entry.dart';
import '../Entities/honoo.dart';
import '../Services/supabase_provider.dart';
import '../UI/hinoo_thread_view.dart';
import '../UI/hinoo_typography.dart';
import '../UI/hinoo_viewer.dart';
import '../UI/honoo_card.dart';
import '../UI/unified_thread_view.dart';
import '../Utility/chest_content_style.dart';
import '../Utility/responsive_layout.dart';

class ChestItemView extends StatelessWidget {
  const ChestItemView({
    super.key,
    required this.item,
    required this.availableHeight,
    required this.maxWidth,
    required this.honooMetrics,
    required this.repaintKey,
    required this.hinooRepliesByRoot,
    required this.isNormalMode,
    required this.isActive,
    required this.highlightLatest,
    required this.focusConversationId,
    required this.revealEntryId,
    required this.onSelectConversationEntry,
    required this.onDownload,
    required this.conversationRefreshToken,
    this.onSaved,
  });

  final VoidCallback? onSaved;
  final ChestItem item;
  final double availableHeight;
  final double maxWidth;
  final HonooBuilderMetrics honooMetrics;
  final GlobalKey repaintKey;
  final Map<String, List<HinooThreadEntry>> hinooRepliesByRoot;
  final bool isNormalMode;
  final bool isActive;
  final bool highlightLatest;
  final String? focusConversationId;
  final String? revealEntryId;
  final ValueChanged<ConversationEntry> onSelectConversationEntry;
  final ValueChanged<GlobalKey> onDownload;
  final int conversationRefreshToken;

  @override
  Widget build(BuildContext context) {
    final identity = item.when(
      honoo: (honoo) {
        final fallback = honoo.id != 0
            ? honoo.id.toString()
            : item.createdAt.toIso8601String();
        return 'honoo_${honoo.dbId ?? fallback}';
      },
      hinoo: (hinoo) => 'hinoo_${hinoo.id}',
    );
    final isHonoo = item.honoo != null;
    final hinooSize = ResponsiveLayout.fitAspectRatio(
      maxWidth,
      availableHeight,
      HinooTypography.aspectRatio,
    );
    final cardWidth = isHonoo ? honooMetrics.width : hinooSize.width;
    final cardHeight = isHonoo ? honooMetrics.height : hinooSize.height;
    final viewerUserId = SupabaseProvider.client.auth.currentUser?.id;
    final pageStyle = ChestContentStyle.forItem(
      item,
      viewerUserId: viewerUserId,
    );
    final content = item.when(
      honoo: (honoo) => _buildHonoo(honoo),
      hinoo: (hinoo) => _buildHinoo(hinoo, cardWidth, cardHeight),
    );
    final isConversation = item.when(
      honoo: (honoo) =>
          isNormalMode &&
          honoo.conversationId != null &&
          honoo.conversationId!.isNotEmpty,
      hinoo: (hinoo) {
        final conversationId =
            hinoo.conversationId ?? hinoo.draft.conversationId;
        return (isNormalMode &&
                conversationId != null &&
                conversationId.isNotEmpty) ||
            (hinooRepliesByRoot[hinoo.id]?.isNotEmpty ?? false);
      },
    );
    final card = isConversation
        ? content
        : ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(width: cardWidth, child: content),
          );
    final keyedCard = KeyedSubtree(
      key: ValueKey(identity),
      child: ColoredBox(
        color: isConversation ? Colors.transparent : pageStyle.backgroundColor,
        child: SizedBox(width: maxWidth, height: availableHeight, child: card),
      ),
    );
    if (!isConversation) {
      return SavedContentEditFrame(
        width: cardWidth,
        height: cardHeight,
        honoo: item.honoo,
        hinoo: item.hinoo?.draft,
        hinooId: item.hinoo?.id,
        ownerId: item.hinoo?.ownerId,
        onSaved: onSaved ?? () {},
        child: keyedCard,
      );
    }
    return keyedCard;
  }

  Widget _buildHonoo(Honoo honoo) {
    final conversationId = honoo.conversationId;
    if (isNormalMode && conversationId != null && conversationId.isNotEmpty) {
      return _unifiedThread(conversationId);
    }
    return SizedBox(
      width: maxWidth,
      height: availableHeight,
      child: HonooCard(
        honoo: honoo,
        downloadBoundaryKey: repaintKey,
        onDownloadTap: () => onDownload(repaintKey),
      ),
    );
  }

  Widget _buildHinoo(
    ChestHinooItem hinoo,
    double cardWidth,
    double cardHeight,
  ) {
    final conversationId = hinoo.conversationId ?? hinoo.draft.conversationId;
    if (isNormalMode && conversationId != null && conversationId.isNotEmpty) {
      return _unifiedThread(conversationId);
    }
    final replies = hinooRepliesByRoot[hinoo.id] ?? const [];
    if (replies.isEmpty) {
      return HinooViewer(
        draft: hinoo.draft,
        maxHeight: availableHeight,
        maxWidth: maxWidth,
        authorId: hinoo.ownerId,
        onDownloadCanvasTap: onDownload,
      );
    }
    return HinooThreadView(
      root: hinoo.draft,
      rootAuthorId: hinoo.ownerId,
      replies: replies,
      maxHeight: cardHeight,
      maxWidth: cardWidth,
      onDownloadTap: onDownload,
    );
  }

  Widget _unifiedThread(String conversationId) => UnifiedThreadView(
    conversationId: conversationId,
    maxWidth: maxWidth,
    maxHeight: availableHeight,
    isActive: isActive,
    onSelect: onSelectConversationEntry,
    highlightLatest:
        highlightLatest &&
        (focusConversationId == null || focusConversationId == conversationId),
    preferLatestReceived: highlightLatest && focusConversationId == null,
    revealEntryId:
        isActive &&
            (focusConversationId == null ||
                focusConversationId == conversationId)
        ? revealEntryId
        : null,
    refreshToken: conversationRefreshToken,
  );
}

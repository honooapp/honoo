import 'package:flutter/material.dart';

import '../Entities/chest_item.dart';
import '../Entities/conversation_entry.dart';
import '../Entities/hinoo.dart';
import '../Entities/honoo.dart';
import '../Utility/honoo_colors.dart';
import 'responsive_footer_bar.dart';

class ChestFooter extends StatelessWidget {
  const ChestFooter({
    super.key,
    required this.item,
    required this.selectedConversationEntry,
    required this.currentUserId,
    required this.iconSize,
    required this.gap,
    required this.bottomPadding,
    required this.onHome,
    required this.onInfo,
    required this.onSendHonooToMoon,
    required this.onReplyToHonoo,
    required this.onDeleteHonoo,
    required this.onSendHinooToMoon,
    required this.onReplyToHinoo,
    required this.onDeleteHinoo,
    required this.onReplyToConversationEntry,
    required this.onSendConversationEntryToMoon,
    this.foregroundColor = HonooColor.onBackground,
    this.isAdmin = false,
    this.isConversation = false,
  });

  final bool isAdmin;
  final bool isConversation;
  final ChestItem? item;
  final ConversationEntry? selectedConversationEntry;
  final String? currentUserId;
  final double iconSize;
  final double gap;
  final double bottomPadding;
  final VoidCallback onHome;
  final VoidCallback onInfo;
  final ValueChanged<Honoo> onSendHonooToMoon;
  final ValueChanged<Honoo> onReplyToHonoo;
  final ValueChanged<Honoo> onDeleteHonoo;
  final ValueChanged<ChestHinooItem> onSendHinooToMoon;
  final ValueChanged<ChestHinooItem> onReplyToHinoo;
  final ValueChanged<ChestHinooItem> onDeleteHinoo;
  final ValueChanged<ConversationEntry> onReplyToConversationEntry;
  final ValueChanged<ConversationEntry> onSendConversationEntryToMoon;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    final actions = <ResponsiveFooterAction>[
      _action(
        asset: 'assets/icons/home.svg',
        label: 'Home',
        tooltip: 'Home',
        onPressed: onHome,
      ),
      _action(
        asset: 'assets/icons/info.svg',
        label: 'Info',
        tooltip: 'Info',
        onPressed: onInfo,
      ),
    ];

    item?.when(
      honoo: (honoo) => _addHonooActions(actions, honoo),
      hinoo: (hinoo) => _addHinooActions(actions, hinoo),
    );

    final selectedEntry = selectedConversationEntry ?? _standaloneReplyEntry;
    if (selectedEntry != null) {
      actions.removeWhere((action) => action.tooltip == 'Rispondi');
    }
    if (_canReplyTo(selectedEntry)) {
      actions.add(
        _replyAction(() => onReplyToConversationEntry(selectedEntry!)),
      );
    }

    return ResponsiveFooterBar(
      useSafeArea: false,
      bottomPadding: bottomPadding,
      desiredGap: gap,
      minGap: 16,
      height: iconSize,
      // Reserve each action's position while the selected thread is loading.
      // Hidden slots have no button, tooltip or accessibility action.
      actions: [
        for (final tooltip in const [
          'Home',
          'Info',
          'Spedisci sulla Luna',
          'Cancella',
          'Rispondi',
        ])
          actions.where((action) => action.tooltip == tooltip).firstOrNull ??
              ResponsiveFooterAction(
                asset: '',
                size: iconSize,
                tooltip: tooltip,
                visible: false,
              ),
      ],
    );
  }

  void _addHonooActions(List<ResponsiveFooterAction> actions, Honoo honoo) {
    final isPersonal = honoo.type == HonooType.personal;
    final isFromMoonSaved = honoo.isFromMoonSaved == true;
    final selectedEntryToPublish = _selectedEntryToPublish(honoo);
    final isMine = _isMine(honoo.userId);

    if (selectedConversationEntry == null &&
        isPersonal &&
        isMine &&
        !isFromMoonSaved) {
      actions.add(_moonAction(() => onSendHonooToMoon(honoo)));
    } else if (isFromMoonSaved) {
      actions.add(_replyAction(() => onReplyToHonoo(honoo)));
    }

    if (isAdmin ||
        !(isConversation ||
            selectedConversationEntry != null ||
            honoo.conversationId?.isNotEmpty == true ||
            honoo.hasReplies ||
            honoo.type == HonooType.answer)) {
      actions.add(_deleteAction(() => onDeleteHonoo(honoo)));
    }

    if (selectedEntryToPublish != null) {
      if (selectedEntryToPublish.id == honoo.dbId) {
        actions.add(_moonAction(() => onSendHonooToMoon(honoo)));
      } else {
        actions.add(
          _moonAction(
            () => onSendConversationEntryToMoon(selectedEntryToPublish),
          ),
        );
      }
    }
  }

  ConversationEntry? _selectedEntryToPublish(Honoo honoo) {
    final entry = selectedConversationEntry;
    final conversationId = honoo.conversationId;
    if (entry == null ||
        conversationId == null ||
        conversationId.isEmpty ||
        entry.kind == ConversationEntryKind.deleted) {
      return null;
    }
    final isMine = _isMine(entry.ownerId);
    final isPublishableEntry = entry.kind == ConversationEntryKind.honoo
        ? entry.honoo!.type != HonooType.moon
        : entry.hinoo!.type != HinooType.moon;
    return isMine && isPublishableEntry && !entry.isFromMoonSaved
        ? entry
        : null;
  }

  bool _isMine(String? ownerId) =>
      ownerId != null && currentUserId != null && ownerId == currentUserId;

  ConversationEntry? get _standaloneReplyEntry => item?.when(
    honoo: (h) =>
        h.type == HonooType.answer ? ConversationEntry.honoo(h) : null,
    hinoo: (h) => h.draft.type == HinooType.answer
        ? ConversationEntry.hinoo(
            h.draft,
            createdAt: h.createdAt,
            ownerId: h.ownerId,
            id: h.id,
            isFromMoonSaved: h.isFromMoonSaved,
          )
        : null,
  );

  bool _canReplyTo(ConversationEntry? entry) =>
      entry != null &&
      entry.kind != ConversationEntryKind.deleted &&
      entry.id != null &&
      entry.id!.isNotEmpty;

  void _addHinooActions(
    List<ResponsiveFooterAction> actions,
    ChestHinooItem hinoo,
  ) {
    final isPersonal = hinoo.draft.type == HinooType.personal;
    final isFromMoonSaved = hinoo.isFromMoonSaved;
    final selectedEntryToPublish = _selectedEntryToPublishForHinoo(hinoo);
    if (selectedConversationEntry == null &&
        isPersonal &&
        _isMine(hinoo.ownerId) &&
        !isFromMoonSaved) {
      actions.add(_moonAction(() => onSendHinooToMoon(hinoo)));
    } else if (isFromMoonSaved) {
      actions.add(_replyAction(() => onReplyToHinoo(hinoo)));
    }
    if (isAdmin ||
        !(isConversation ||
            selectedConversationEntry != null ||
            hinoo.conversationId?.isNotEmpty == true ||
            hinoo.draft.conversationId?.isNotEmpty == true ||
            hinoo.draft.type == HinooType.answer)) {
      actions.add(_deleteAction(() => onDeleteHinoo(hinoo)));
    }

    if (selectedEntryToPublish != null) {
      if (selectedEntryToPublish.id == hinoo.id) {
        actions.add(_moonAction(() => onSendHinooToMoon(hinoo)));
      } else {
        actions.add(
          _moonAction(
            () => onSendConversationEntryToMoon(selectedEntryToPublish),
          ),
        );
      }
    }
  }

  ConversationEntry? _selectedEntryToPublishForHinoo(ChestHinooItem hinoo) {
    final entry = selectedConversationEntry;
    final conversationId = hinoo.conversationId ?? hinoo.draft.conversationId;
    if (entry == null ||
        conversationId == null ||
        conversationId.isEmpty ||
        entry.kind == ConversationEntryKind.deleted) {
      return null;
    }
    final isPublishableEntry = entry.kind == ConversationEntryKind.honoo
        ? entry.honoo!.type != HonooType.moon
        : entry.hinoo!.type != HinooType.moon;
    return _isMine(entry.ownerId) &&
            isPublishableEntry &&
            !entry.isFromMoonSaved
        ? entry
        : null;
  }

  ResponsiveFooterAction _moonAction(VoidCallback onPressed) => _action(
    asset: 'assets/icons/moon.svg',
    label: 'Luna',
    tooltip: 'Spedisci sulla Luna',
    onPressed: onPressed,
  );

  ResponsiveFooterAction _replyAction(VoidCallback onPressed, {Color? color}) =>
      _action(
        asset: 'assets/icons/reply.svg',
        label: 'Rispondi',
        tooltip: 'Rispondi',
        onPressed: onPressed,
        color: color,
      );

  ResponsiveFooterAction _deleteAction(VoidCallback onPressed) => _action(
    asset: 'assets/Cestino.svg',
    label: 'Cancella',
    tooltip: 'Cancella',
    onPressed: onPressed,
  );

  ResponsiveFooterAction _action({
    required String asset,
    required String label,
    required String tooltip,
    required VoidCallback onPressed,
    bool applyColorFilter = true,
    Color? color,
  }) => ResponsiveFooterAction(
    asset: asset,
    semanticsLabel: label,
    colorFilter: applyColorFilter
        ? ColorFilter.mode(color ?? foregroundColor, BlendMode.srcIn)
        : null,
    size: iconSize,
    splashRadius: 25,
    tooltip: tooltip,
    onPressed: onPressed,
  );
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../Entities/chest_item.dart';
import '../Entities/conversation_entry.dart';
import '../Entities/conversation_link.dart';
import '../Entities/honoo.dart';
import '../Entities/hinoo.dart';
import '../Widgets/honoo_dialogs.dart';
import '../Widgets/responsive_footer_bar.dart';
import 'new_honoo_page.dart';
import 'new_hinoo_page.dart';
import '../Services/house_shared_content_service.dart';
import '../UI/hinoo_viewer.dart';
import '../UI/honoo_card.dart';
import '../UI/unified_thread_view.dart';
import '../Utility/chest_content_style.dart';
import '../Services/supabase_provider.dart';
import '../Services/conversation_service.dart';
import 'home_page.dart';
import '../Widgets/honoo_app_title.dart';
import '../Widgets/loading_spinner.dart';

class SharedHouseChestPage extends StatefulWidget {
  const SharedHouseChestPage({
    super.key,
    required this.ownerId,
    this.conversationLoader,
  });

  final String ownerId;
  final Future<List<ConversationEntry>> Function(String conversationId)?
  conversationLoader;

  @override
  State<SharedHouseChestPage> createState() => _SharedHouseChestPageState();
}

class _SharedHouseChestPageState extends State<SharedHouseChestPage> {
  final HouseSharedContentService _service = HouseSharedContentService();
  final PageController _pageController = PageController();
  List<ChestItem> _items = const [];
  bool _loading = true;
  Object? _error;
  int _index = 0;
  ConversationEntry? _selectedEntry;

  ChestContentStyle get _style {
    final viewerId = SupabaseProvider.client.auth.currentUser?.id;
    if (_selectedEntry != null) {
      return ChestContentStyle.forConversationEntry(
        _selectedEntry!,
        viewerUserId: viewerId,
      );
    }
    return _items.isEmpty
        ? ChestContentStyle.own
        : ChestContentStyle.forItem(_items[_index], viewerUserId: viewerId);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await _service.fetch(widget.ownerId);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _style.backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: Center(
                      child: HonooAppTitle(color: _style.logoColor),
                    ),
                  ),
                  PositionedDirectional(
                    start: 8,
                    child: IconButton(
                      tooltip: 'Torna al campanello',
                      color: _style.foregroundColor,
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _body()),
            ResponsiveFooterBar(
              useSafeArea: false,
              actions: [
                ResponsiveFooterAction(
                  asset: 'assets/icons/home.svg',
                  size: 32,
                  tooltip: 'Home',
                  colorFilter: ColorFilter.mode(
                    _style.foregroundColor,
                    BlendMode.srcIn,
                  ),
                  onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const HomePage()),
                    (route) => false,
                  ),
                ),
                ResponsiveFooterAction(
                  asset: 'assets/icons/info.svg',
                  size: 32,
                  tooltip: 'Info',
                  colorFilter: ColorFilter.mode(
                    _style.foregroundColor,
                    BlendMode.srcIn,
                  ),
                  onPressed: () => showHonooMessageDialog(
                    context,
                    title: 'Scrigno condiviso',
                    duration: const Duration(seconds: 20),
                    message:
                        'Scorri tra gli honoo e gli hinoo condivisi in questa casa. '
                        'Scorri in verticale per leggere le conversazioni. '
                        'Premi Rispondi per rispondere al contenuto selezionato.',
                  ),
                ),
                if (!_loading &&
                    _error == null &&
                    _items.isNotEmpty &&
                    _selectedEntry?.kind != ConversationEntryKind.deleted)
                  ResponsiveFooterAction(
                    asset: 'assets/icons/reply.svg',
                    size: 32,
                    tooltip: 'Rispondi',
                    semanticsLabel: 'Rispondi',
                    colorFilter: ColorFilter.mode(
                      _style.foregroundColor,
                      BlendMode.srcIn,
                    ),
                    onPressed: _reply,
                  ),
              ],
            ),
            if (_items.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  '${_index + 1} / ${_items.length}',
                  style: GoogleFonts.arvo(
                    color: _style.foregroundColor,
                    fontSize: 13,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return Center(child: LoadingSpinner(color: _style.foregroundColor));
    }
    if (_error != null) {
      return _message('Non riesco ad aprire lo scrigno. Riprova.');
    }
    if (_items.isEmpty) {
      return _message('Non ci sono ancora contenuti da mostrare.');
    }
    return LayoutBuilder(
      builder: (context, constraints) => PageView.builder(
        key: const ValueKey('shared-house-content'),
        controller: _pageController,
        itemCount: _items.length,
        onPageChanged: (value) => setState(() {
          _index = value;
          _selectedEntry = null;
        }),
        itemBuilder: (context, index) {
          final item = _items[index];
          final conversationId = item.when(
            honoo: (honoo) {
              final explicitId = honoo.conversationId;
              if (explicitId != null && explicitId.isNotEmpty) {
                return explicitId;
              }
              return honoo.hasReplies ? honoo.dbId : null;
            },
            hinoo: (hinoo) =>
                hinoo.conversationId ?? hinoo.draft.conversationId,
          );
          if (conversationId != null && conversationId.isNotEmpty) {
            return UnifiedThreadView(
              conversationId: conversationId,
              maxWidth: constraints.maxWidth,
              maxHeight: constraints.maxHeight,
              isActive: index == _index,
              conversationLoader: (id) async {
                final entries =
                    await (widget.conversationLoader ??
                        ConversationService.fetchConversation)(id);
                final root = item.when(
                  honoo: ConversationEntry.honoo,
                  hinoo: (h) => ConversationEntry.hinoo(
                    h.draft,
                    id: h.id,
                    ownerId: h.ownerId,
                    createdAt: h.createdAt,
                    isFromMoonSaved: h.isFromMoonSaved,
                  ),
                );
                if (entries.any((entry) => entry.id == root.id)) return entries;
                return [root, ...entries];
              },
              onSelect: (entry) {
                if (mounted &&
                    index == _index &&
                    !identical(entry, _selectedEntry)) {
                  setState(() => _selectedEntry = entry);
                }
              },
            );
          }
          return item.when(
            honoo: (honoo) => Center(
              child: SizedBox(
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                child: HonooCard(honoo: honoo),
              ),
            ),
            hinoo: (hinoo) => Center(
              child: HinooViewer(
                draft: hinoo.draft,
                maxWidth: constraints.maxWidth,
                maxHeight: constraints.maxHeight,
                authorId: hinoo.ownerId,
                gapColor: ChestContentStyle.forItem(
                  item,
                  viewerUserId: SupabaseProvider.client.auth.currentUser?.id,
                ).backgroundColor,
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _reply() async {
    // Capture the selected content before opening the choice dialog.
    final item = _items[_index];
    final entry = _selectedEntry;
    if (entry?.kind == ConversationEntryKind.deleted) return;
    final parentId = entry?.id ?? item.honoo?.dbId ?? item.hinoo?.id;
    if (parentId == null || parentId.isEmpty) return;
    final choice = await _showReplyChoice();
    if (choice == null || !mounted) return;
    final link = ConversationLink.fromParent(
      parentId: parentId,
      parentConversationId:
          entry?.honoo?.conversationId ??
          entry?.hinoo?.conversationId ??
          item.honoo?.conversationId ??
          item.hinoo?.conversationId ??
          item.hinoo?.draft.conversationId ??
          (item.honoo?.hasReplies == true ? item.honoo?.dbId : null),
      recipientId: entry?.ownerId ?? widget.ownerId,
    );
    final targetContentName = entry != null
        ? (entry.kind == ConversationEntryKind.honoo ? 'honoo' : 'hinoo')
        : (item.honoo != null ? 'honoo' : 'hinoo');
    await Navigator.of(context).push<Object?>(
      MaterialPageRoute(
        builder: (_) => choice == _ReplyChoice.honoo
            ? NewHonooPage(
                targetContentName: targetContentName,
                forcedType: HonooType.answer,
                recipientTag: link.recipientId,
                replyTo: link.replyTo,
                conversationId: link.conversationId,
                returnToPreviousOnAnswer: true,
              )
            : NewHinooPage(
                targetContentName: targetContentName,
                forcedType: HinooType.answer,
                recipientTag: link.recipientId,
                replyTo: link.replyTo,
                conversationId: link.conversationId,
                returnToPreviousOnAnswer: true,
              ),
      ),
    );
  }

  Future<_ReplyChoice?> _showReplyChoice() {
    return showDialog<_ReplyChoice>(
      context: context,
      barrierDismissible: true,
      builder: (_) => HonooDialogShell(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Vuoi rispondere con\n un honoo o un hinoo?',
                style: HonooDialogStyles.title(),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () =>
                      Navigator.of(context).pop(_ReplyChoice.honoo),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'honoo',
                    style: HonooDialogStyles.primaryAction(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () =>
                      Navigator.of(context).pop(_ReplyChoice.hinoo),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'hinoo',
                    style: HonooDialogStyles.primaryAction(),
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(foregroundColor: Colors.white54),
                child: Text(
                  'Annulla',
                  style: HonooDialogStyles.tertiaryAction(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _message(String value) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Text(
        value,
        textAlign: TextAlign.center,
        style: GoogleFonts.arvo(color: _style.foregroundColor, fontSize: 18),
      ),
    ),
  );
}

enum _ReplyChoice { honoo, hinoo }

import 'dart:async';
import 'package:uuid/uuid.dart';
import '../Services/reply_draft_store.dart';
import '../Widgets/honoo_back_button.dart';
import 'package:flutter/material.dart';
import 'package:honoo/Services/honoo_service.dart';
import 'package:honoo/UI/honoo_builder.dart';
import 'package:honoo/Utility/honoo_colors.dart';
import 'package:honoo/Widgets/loading_spinner.dart';
import 'package:honoo/Widgets/honoo_dialogs.dart';
import 'package:sizer/sizer.dart';
import 'package:honoo/Widgets/responsive_footer_bar.dart';
import 'package:honoo/Widgets/honoo_app_title.dart';
import '../Entities/honoo.dart';
import '../Entities/conversation_link.dart';
import '../Entities/reply_navigation_result.dart';
import '../Widgets/repeated_reply_prompt.dart';
import 'package:honoo/Services/supabase_provider.dart';
import 'package:honoo/Controller/honoo_controller.dart';
import 'chest_page.dart';
import '../Utility/inline_text_formatting.dart';

class ReplyHonooPage extends StatefulWidget {
  final Honoo originalHonoo;

  final String initialHintText;
  final String initialImageHint;

  const ReplyHonooPage({
    super.key,
    required this.originalHonoo,
    this.initialHintText = 'Scrivi la tua risposta',
    this.initialImageHint = 'Aggiungi un’immagine (opzionale)',
    this.returnToPreviousOnAnswer = false,
    this.targetContentName = 'honoo',
  });

  final bool returnToPreviousOnAnswer;
  final String targetContentName;

  @override
  State<ReplyHonooPage> createState() => _ReplyHonooPageState();
}

class _ReplyHonooPageState extends State<ReplyHonooPage> {
  String _text = '';
  String? _imageUrl;

  bool _isSending = false;
  bool _sentOnce = false;
  bool _isReplyConfirmed = false;

  ReplyDraftStore? _draftStore;
  String? _draftUserId;
  bool _loadingDraft = true;
  bool _draftSaveFailed = false;
  String? _requestId;
  String? _pendingConversationId;
  String? _pendingRecipientId;
  String? _initialText;
  String? _initialImage;

  @override
  void initState() {
    super.initState();
    final userId = SupabaseProvider.client.auth.currentUser?.id;
    _draftUserId = userId;
    if (userId != null) {
      _draftStore = ReplyDraftStore(
        userId,
        widget.originalHonoo.dbId ?? widget.originalHonoo.id.toString(),
      );
    }
    _restoreDraft();
  }

  Future<void> _restoreDraft() async {
    try {
      final draft = await _draftStore?.load();
      if (!mounted) return;
      if (draft != null) {
        _text = draft['text'] as String? ?? '';
        _imageUrl = draft['image'] as String?;
        _initialText = _text;
        _initialImage = _imageUrl;
        _requestId = draft['requestId'] as String?;
        _pendingConversationId = draft['conversationId'] as String?;
        _pendingRecipientId = draft['recipientId'] as String?;
        _isReplyConfirmed = _requestId != null;
      }
    } catch (_) {
      _draftSaveFailed = true;
    }
    if (mounted) setState(() => _loadingDraft = false);
  }

  Future<void> _saveDraft() async {
    await _draftStore?.save({
      'text': _text,
      'image': _imageUrl,
      'requestId': _requestId,
      'conversationId': _pendingConversationId,
      'recipientId': _pendingRecipientId,
    });
  }

  Future<void> _autosave() async {
    try {
      await _saveDraft();
      if (mounted && _draftSaveFailed) setState(() => _draftSaveFailed = false);
    } catch (_) {
      if (mounted) setState(() => _draftSaveFailed = true);
    }
  }

  void _onHonooChanged(String text, String? imageUrl) {
    if (_isSending || _requestId != null) return;
    setState(() {
      _text = text;
      _imageUrl = imageUrl;
      _isReplyConfirmed = false;
    });
    unawaited(_autosave());
  }

  Future<bool> _confirmReply() async {
    if (!InlineTextFormatting.hasVisibleText(_text)) {
      if (mounted) {
        showHonooToast(
          context,
          message: 'Scrivi qualcosa prima di confermare.',
        );
      }
      return false;
    }
    if (mounted) setState(() => _isReplyConfirmed = true);
    return true;
  }

  Future<void> _sendReply() async {
    if (_isSending) return;
    if (_sentOnce) {
      if (!mounted) return;
      await showHonooMessageDialog(
        context,
        message: 'Risposta già inviata',
        duration: const Duration(milliseconds: 1400),
      );
      return;
    }
    if (!InlineTextFormatting.hasVisibleText(_text)) return;

    setState(() => _isSending = true);

    final currentUser = SupabaseProvider.client.auth.currentUser;
    if (currentUser == null || currentUser.id != _draftUserId) {
      if (mounted) {
        setState(() => _isSending = false);
        showHonooToast(context, message: 'Accedi prima di rispondere.');
      }
      return;
    }

    try {
      final now = DateTime.now().toIso8601String();

      final String replyTarget =
          widget.originalHonoo.dbId ?? widget.originalHonoo.id.toString();
      final defaultLink = ConversationLink.fromParent(
        parentId: replyTarget,
        parentConversationId: widget.originalHonoo.conversationId,
        recipientId: ConversationLink.recipientForParent(
          ownerId: widget.originalHonoo.userId,
          parentRecipientId: widget.originalHonoo.recipientTag,
          currentUserId: currentUser.id,
        ),
      );
      final conversationId =
          _pendingConversationId ??
          await chooseReplyConversation(
            context: context,
            parentId: replyTarget,
            defaultConversationId: defaultLink.conversationId,
            contentName: widget.targetContentName,
          );
      if (conversationId == null || !mounted) {
        if (mounted) setState(() => _isSending = false);
        return;
      }
      final link = ConversationLink(
        replyTo: defaultLink.replyTo,
        conversationId: conversationId,
        recipientId: _pendingRecipientId ?? defaultLink.recipientId,
      );
      final newHonoo = Honoo(
        0,
        _text,
        _imageUrl ?? '',
        now,
        now,
        currentUser.id,
        HonooType.answer,
        link.replyTo,
        link.recipientId,
      )..conversationId = link.conversationId;

      _requestId ??= const Uuid().v4();
      _pendingConversationId = link.conversationId;
      _pendingRecipientId = link.recipientId;
      // Persist before contacting the server, so reopening retries the same send.
      await _saveDraft();
      // Assicura che il root sia nello Scrigno se arriviamo dalla Luna
      if (widget.originalHonoo.type == HonooType.moon) {
        await HonooController().saveToChest(
          widget.originalHonoo.copyWith(isFromMoonSaved: true),
        );
      }

      final replyId = await HonooService.publishReplyOnce(
        newHonoo,
        _requestId!,
      );

      _sentOnce = true;
      try {
        await _draftStore?.save(null);
      } catch (_) {
        // Keep the persisted request identity: reopening can confirm it safely.
      }
      if (!mounted) return;
      setState(() => _isSending = false);
      await showReplySavedDialog(context, contentName: 'honoo');
      if (!mounted) return;
      if (widget.returnToPreviousOnAnswer) {
        Navigator.of(context).pop(
          ReplyNavigationResult(
            conversationId: link.conversationId,
            replyId: replyId,
          ),
        );
        return;
      }
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => ChestPage(
            focusReplies: true,
            focusConversationId: link.conversationId,
            focusReplyId: replyId,
            highlightLatest: true,
          ),
        ),
        (route) => false,
      );
    } catch (e) {
      debugPrint('Errore invio reply: $e');
      if (!mounted) return;
      showHonooToast(
        context,
        message:
            'Invio non confermato. Riprova: la risposta non verrà duplicata.',
      );
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isSending,
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: HonooColor.background,
        body: SafeArea(
          maintainBottomViewPadding: true,
          child: Column(
            children: [
              SizedBox(
                height: 52,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Center(child: HonooAppTitle()),
                    Positioned(
                      left: 8,
                      child: HonooBackButton(enabled: !_isSending),
                    ),
                  ],
                ),
              ),
              if (_draftSaveFailed)
                const Text(
                  'Bozza non salvata: non chiudere questa pagina.',
                  style: TextStyle(color: Colors.white),
                ),
              if (_requestId != null && !_isSending && !_sentOnce)
                const Text(
                  'Invio da confermare. Riprova per verificarlo.',
                  style: TextStyle(color: Colors.white),
                ),
              Expanded(
                child: _loadingDraft
                    ? const Center(child: LoadingSpinner(color: Colors.white))
                    : AbsorbPointer(
                        absorbing: _isSending || _requestId != null,
                        child: HonooBuilder(
                          onHonooChanged: _onHonooChanged,
                          initialText: _initialText,
                          initialImageUrl: _initialImage,
                          textHint: widget.initialHintText,
                          imageHint: widget.initialImageHint,
                          onImageConfirmed: _confirmReply,
                          requireExplicitConfirmation: true,
                        ),
                      ),
              ),
              SizedBox(height: 2.h),
              ResponsiveFooterBar(
                useSafeArea: true,
                bottomPadding: 8,
                desiredGap: 28,
                minGap: 16,
                height: 44,
                actions: [
                  if (_isReplyConfirmed)
                    ResponsiveFooterAction(
                      asset: "assets/icons/reply.svg",
                      semanticsLabel: 'Invia risposta',
                      size: 44,
                      splashRadius: 28,
                      tooltip: 'Invia risposta',
                      colorFilter: const ColorFilter.mode(
                        Colors.white,
                        BlendMode.srcIn,
                      ),
                      onPressed: _isSending ? null : _sendReply,
                    ),
                ],
              ),
              if (_isSending)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: LoadingSpinner(color: Colors.white),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

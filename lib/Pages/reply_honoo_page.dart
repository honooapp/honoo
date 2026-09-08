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

  void _onHonooChanged(String text, String? imageUrl) {
    setState(() {
      _text = text;
      _imageUrl = imageUrl;
      _isReplyConfirmed = false;
    });
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
    if (currentUser == null) {
      if (mounted) {
        setState(() => _isSending = false);
        showHonooToast(context, message: 'Accedi prima di rispondere.');
      }
      return;
    }

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
    final conversationId = await chooseReplyConversation(
      context: context,
      parentId: replyTarget,
      defaultConversationId: defaultLink.conversationId,
      contentName: widget.targetContentName,
    );
    if (conversationId == null || !mounted) {
      setState(() => _isSending = false);
      return;
    }
    final link = ConversationLink(
      replyTo: defaultLink.replyTo,
      conversationId: conversationId,
      recipientId: defaultLink.recipientId,
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

    try {
      // Assicura che il root sia nello Scrigno se arriviamo dalla Luna
      if (widget.originalHonoo.type == HonooType.moon) {
        await HonooController().saveToChest(
          widget.originalHonoo.copyWith(isFromMoonSaved: true),
        );
      }

      final replyId = await HonooService.publishHonooAndReturnId(newHonoo);

      if (!mounted) return;

      _sentOnce = true;
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
      showHonooToast(context, message: 'Errore. Riprova più tardi.');
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: HonooColor.background,
      body: SafeArea(
        maintainBottomViewPadding: true,
        child: Column(
          children: [
            const SizedBox(height: 52, child: Center(child: HonooAppTitle())),
            Expanded(
              child: HonooBuilder(
                onHonooChanged: _onHonooChanged,
                initialText: null,
                textHint: widget.initialHintText,
                imageHint: widget.initialImageHint,
                onImageConfirmed: _confirmReply,
                requireExplicitConfirmation: true,
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
    );
  }
}

import '../Services/hinoo_service.dart';
// lib/Pages/new_hinoo_page.dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:honoo/Services/supabase_provider.dart';
import 'package:honoo/Services/house_invite_service.dart';
import 'package:honoo/Services/auth_navigation_service.dart';

import 'package:honoo/Utility/honoo_colors.dart';
import 'package:honoo/Widgets/honoo_dialogs.dart';
import 'package:honoo/Widgets/honoo_app_title.dart';
import 'package:honoo/Widgets/responsive_footer_bar.dart';
import 'package:honoo/Utility/responsive_layout.dart';

import 'package:honoo/Controller/hinoo_controller.dart';
import 'package:honoo/UI/hinoo_typography.dart';

import '../UI/hinoo_builder.dart';

import 'chest_page.dart';
import 'home_page.dart';
import 'placeholder_page.dart';
import '../Entities/hinoo.dart';
import '../Entities/reply_navigation_result.dart';
import 'casa_builder_page.dart';
import '../Widgets/conversation_notification_prompt.dart';
import '../Widgets/repeated_reply_prompt.dart';
import '../Widgets/text_box_download_button.dart';

enum CampanelloEditMode { image, text }

class NewHinooPage extends StatefulWidget {
  const NewHinooPage({
    super.key,
    this.isReply = false,
    this.isCampanello = false,
    this.forcedType,
    this.recipientTag,
    this.returnSavedId = false,
    this.replyTo,
    this.conversationId,
    this.returnToPreviousOnAnswer = false,
    this.targetContentName = 'hinoo',
    this.initialDraft,
    this.editingCampanelloId,
    this.editingHinooId,
    this.campanelloEditMode,
  });

  final bool isReply;
  final bool isCampanello;
  final HinooType? forcedType;
  final String? recipientTag;
  final bool returnSavedId;
  final String? replyTo;
  final String? conversationId;
  final bool returnToPreviousOnAnswer;
  final String targetContentName;
  final HinooDraft? initialDraft;
  final String? editingCampanelloId;
  final String? editingHinooId;
  final CampanelloEditMode? campanelloEditMode;

  @override
  State<NewHinooPage> createState() => _NewHinooPageState();
}

class _NewHinooPageState extends State<NewHinooPage>
    with SingleTickerProviderStateMixin {
  final GlobalKey _builderKey = GlobalKey();

  final _controller = HinooController();
  bool _savedToChest = false;
  String? _savedHinooId;
  late final AnimationController _chestBounceController;
  late final Animation<double> _chestBounce;

  double _lastCanvasHeight = 0;
  String _builderStep = 'changeBg';
  int _currentTextLength = 0;
  bool _bgUploadInProgress = false;
  bool _hasBackground = false;
  bool _campanelloEditStarted = false;
  Size? _unobstructedCanvasSize;

  bool get _isWriteStep => _builderStep == 'writeText';
  bool get _hasMinTextForDownload => _currentTextLength >= 1;

  static const double _titleH = 65;
  static const String _kWriteHint = 'Scrivi qui il tuo testo';

  @override
  void initState() {
    super.initState();
    _chestBounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _chestBounce = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.0,
          end: 1.18,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 45,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.18,
          end: 0.95,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 25,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0.95,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 30,
      ),
    ]).animate(_chestBounceController);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final dyn = _builderKey.currentState as dynamic;
      final draft = dyn?.exportDraft?.call();
      if (!mounted) return;
      setState(() => _applyDraftToLocalState(draft));
      final editMode = widget.campanelloEditMode;
      if (editMode == CampanelloEditMode.image) {
        _beginCampanelloImageEdit();
      } else if (editMode == CampanelloEditMode.text) {
        _beginCampanelloTextEdit();
      }
    });
  }

  @override
  void dispose() {
    _chestBounceController.dispose();
    super.dispose();
  }

  void _onHinooChanged(dynamic draft) {
    setState(() {
      if (_savedToChest) _savedToChest = false;
      _applyDraftToLocalState(draft);
    });
  }

  void setEditorStateForTesting({
    required String step,
    required bool hasBackground,
    int textLength = 0,
  }) {
    setState(() {
      _builderStep = step;
      _hasBackground = hasBackground;
      _currentTextLength = textLength;
    });
  }

  void _applyDraftToLocalState(dynamic draft) {
    if (draft is! Map) return;

    final dynamic ch = draft['canvasHeight'];
    if (ch is num) _lastCanvasHeight = ch.toDouble();

    final dynamic rawStep = draft['step'];
    if (rawStep is String && rawStep.isNotEmpty) {
      _builderStep = rawStep;
    }

    _bgUploadInProgress = draft['isUploadingBg'] == true;
    _hasBackground = draft['hasBg'] == true;

    int detectedLength = 0;
    final dynamic rawLength = draft['textLength'];
    if (rawLength is int) {
      detectedLength = rawLength;
    } else {
      final dynamic rawText = draft['text'];
      if (rawText is String) detectedLength = rawText.trim().length;
    }
    _currentTextLength = detectedLength;
  }

  Future<void> _onPngExported(Uint8List bytes) async {
    if (!mounted) return;
    showHonooToast(
      context,
      message: 'PNG generato: pronto per salvare o condividere.',
    );
  }

  Future<void> _submitHinoo() async {
    const String writeHint = _kWriteHint;
    final dynamic rawDraft = (_builderKey.currentState as dynamic)
        ?.exportDraft();
    final pages = (rawDraft is Map) ? (rawDraft['pages'] as List?) : null;
    if (rawDraft == null || pages == null || pages.isEmpty) {
      if (!mounted) return;
      showHonooToast(context, message: writeHint);
      return;
    }

    var hinooDraft = _convertRawBuilderDraft(rawDraft);

    final user = SupabaseProvider.client.auth.currentUser;
    if (user == null) {
      if (!mounted) return;
      await AuthNavigationService.ensureLoggedIn(context);
      return;
    }

    // Se il builder sta ancora caricando lo sfondo, fermati
    if (rawDraft['isUploadingBg'] == true || _bgUploadInProgress) {
      if (!mounted) return;
      showHonooToast(
        context,
        message: 'Attendi il caricamento dello sfondo prima di continuare.',
      );
      return;
    }

    // ✅ SALVATAGGIO OGGETTO: bgUrl obbligatorio (persistenza)
    // (La preview serve per download/UX, ma non basta per creare l'oggetto persistente)
    final bool missingPersistedBg = hinooDraft.pages.any(
      (slide) =>
          slide.backgroundImage == null || slide.backgroundImage!.isEmpty,
    );

    if (missingPersistedBg) {
      if (!mounted) return;
      showHonooToast(
        context,
        message:
            'Per salvare l\'hinoo nello Scrigno,\n premi ✓\n e conferma prima\n il caricamento dell\'immagine.',
      );
      return;
    }

    if (rawDraft['isUploadingBg'] == true || _bgUploadInProgress) {
      if (!mounted) return;
      showHonooToast(
        context,
        message: 'Attendi il caricamento dello sfondo prima di continuare.',
      );
      return;
    }

    final bool hasMissingBg = hinooDraft.pages.any(
      (slide) =>
          (slide.backgroundImage == null || slide.backgroundImage!.isEmpty),
    );
    if (hasMissingBg) {
      final bool hasPreview = rawDraft['bgPreviewBytes'] != null;

      //  se ho preview, l'immagine ESISTE → NON errore
      if (hasPreview) {
        // qui non fare nulla: l'utente può
        // - salvare più tardi
        // - oppure scaricare
      } else {
        // ❌ qui sì: manca davvero lo sfondo
        showHonooToast(
          context,
          message:
              'Non siamo riusciti a salvare lo sfondo. Riprova a caricare l\'immagine.',
        );
        return;
      }
    }

    final validationErrors = _controller.validateDraft(hinooDraft);
    if (validationErrors.isNotEmpty) {
      if (!mounted) return;
      // Se manca il testo, mostra l'hint invece del dialog/testo generico
      final hasMissingText = validationErrors.any(
        (e) => e.toLowerCase().contains('testo'),
      );
      if (hasMissingText) {
        showHonooToast(context, message: writeHint);
      } else {
        final errorText =
            'Bozza non valida:\n- ${validationErrors.join('\n- ')}';
        showHonooToast(context, message: errorText);
      }
      return;
    }

    final userId = SupabaseProvider.client.auth.currentUser?.id;
    if (hinooDraft.type == HinooType.answer &&
        widget.replyTo?.isNotEmpty == true) {
      final selectedConversationId = await chooseReplyConversation(
        context: context,
        parentId: widget.replyTo!,
        defaultConversationId: hinooDraft.conversationId ?? widget.replyTo!,
        contentName: widget.targetContentName,
      );
      if (selectedConversationId == null || !mounted) return;
      hinooDraft = hinooDraft.copyWith(conversationId: selectedConversationId);
    }
    final bool shouldOfferNotifications =
        _savedHinooId == null &&
        widget.editingHinooId == null &&
        userId != null &&
        hinooDraft.type == HinooType.personal &&
        await ConversationNotificationPrompt.shouldOfferForFirstConversation(
          userId,
        );

    try {
      if (widget.returnSavedId) {
        final hinooId = await _controller.saveToChestAndReturnId(hinooDraft);
        if (!mounted) return;
        showHonooToast(context, message: 'hinoo salvato.');
        Navigator.of(context).pop(hinooId);
        return;
      }

      if (widget.isCampanello) {
        final String? editingId = widget.editingCampanelloId;
        if (editingId != null && editingId.isNotEmpty) {
          await HouseInviteService().updateCampanello(
            campanelloHinooId: editingId,
            campanello: hinooDraft,
          );
          if (!mounted) return;
          await showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (_) => const HonooConfirmDialog(
              title: 'la modifica è stata effettuata',
              confirmLabel: 'OK',
              showCancel: false,
            ),
          );
          if (!mounted) return;
          Navigator.of(context).pop(true);
          return;
        }
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => CasaBuilderPage(campanello: hinooDraft),
          ),
        );
        return;
      }

      final bool isAnswer =
          (hinooDraft.type == HinooType.answer) || widget.isReply;
      final existingId = _savedHinooId ?? widget.editingHinooId;
      final String savedHinooId;
      if (existingId != null) {
        await HinooService.updateContent(
          id: existingId,
          draft:
              widget.initialDraft?.copyWith(pages: hinooDraft.pages) ??
              hinooDraft,
        );
        savedHinooId = existingId;
      } else {
        savedHinooId = await _controller.saveToChestAndReturnId(hinooDraft);
        if (!isAnswer) _savedHinooId = savedHinooId;
      }
      if (!mounted) return;
      setState(() => _savedToChest = true);
      _chestBounceController.forward(from: 0);
      if (shouldOfferNotifications) {
        await ConversationNotificationPrompt.show(context);
        if (!mounted) return;
      }
      if (isAnswer) {
        await showReplySavedDialog(context, contentName: 'hinoo');
        if (!mounted) return;
        final conversationId = hinooDraft.conversationId;
        if (widget.returnToPreviousOnAnswer) {
          Navigator.of(context).pop(
            ReplyNavigationResult(
              conversationId: conversationId!,
              replyId: savedHinooId,
            ),
          );
          return;
        }
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => ChestPage(
              focusReplies: true,
              focusConversationId: conversationId,
              focusReplyId: savedHinooId,
              highlightLatest: true,
            ),
          ),
          (route) => false,
        );
        return;
      }
      if (!widget.isReply && !widget.isCampanello) {
        final bool? sendToMoon = await showDialog<bool>(
          context: context,
          barrierDismissible: true,
          builder: (_) => const HonooConfirmDialog(
            title: "L'hinoo è stato salvato nel tuo Scrigno.",
            message: 'Vuoi spedirlo anche sulla Luna,\nper mostrarlo a tutti?',
            confirmLabel: 'Sì',
            cancelLabel: 'No',
          ),
        );
        if (sendToMoon == true && mounted) {
          try {
            final result = await _controller.sendToMoon(hinooDraft);
            if (!mounted) return;
            final text = result == HinooMoonResult.published
                ? "L'hinoo è anche sulla Luna."
                : 'hinoo già presente sulla Luna.';
            showHonooToast(context, message: text);
          } catch (e) {
            if (!mounted) return;
            showHonooToast(context, message: 'Errore: $e');
          }
        }
      }
    } catch (e) {
      if (!mounted) return;
      showHonooToast(context, message: 'Errore: $e');
    }
  }

  HinooDraft _convertRawBuilderDraft(Map raw) {
    final List<dynamic> rawPages = (raw['pages'] as List<dynamic>? ?? []);
    final List<HinooSlide> slides = [];

    for (final p in rawPages) {
      if (p is Map) {
        final bgUrl = p['bgUrl'] as String?;
        // Preserve the editor string verbatim: leading/trailing manual line
        // breaks are part of the text's visual position on the canvas.
        final txt = (p['text'] as String?) ?? '';
        final textColorVal = (p['textColor'] as int?) ?? 0xFFFFFFFF;
        final isTextWhite = textColorVal == const Color(0xFFFFFFFF).toARGB32();

        double scale = 1.0;
        double offX = 0.0;
        double offY = 0.0;
        List<double>? normalizedTransform;

        final tr = p['bgTransform'];
        if (tr is List && tr.length == 16) {
          final List<double> m = tr.map((e) => (e as num).toDouble()).toList();
          scale = m[0];

          const double designHeight = 1920;
          const double designWidth = 1080;
          final double canvasH = _lastCanvasHeight > 0
              ? _lastCanvasHeight
              : designHeight;
          final double canvasW = canvasH * (9 / 16);
          final double factorX = canvasW != 0 ? designWidth / canvasW : 1.0;
          final double factorY = canvasH != 0 ? designHeight / canvasH : 1.0;

          normalizedTransform = List<double>.from(m);
          normalizedTransform[12] = m[12] * factorX;
          normalizedTransform[13] = m[13] * factorY;

          offX = normalizedTransform[12];
          offY = normalizedTransform[13];
        }

        slides.add(
          HinooSlide(
            backgroundImage: bgUrl,
            text: txt,
            isTextWhite: isTextWhite,
            bgScale: scale,
            bgOffsetX: offX,
            bgOffsetY: offY,
            bgTransform: normalizedTransform,
          ),
        );
      }
    }

    final HinooType type = widget.isCampanello
        ? HinooType.personal
        : (widget.forcedType ??
              (widget.isReply ? HinooType.answer : HinooType.personal));

    // Se è una risposta e non è stato passato esplicitamente un conversationId,
    // usa replyTo come conversationId per garantire il raggruppamento.
    final String? convId = widget.conversationId ?? widget.replyTo;

    return HinooDraft(
      pages: slides,
      type: type,
      recipientTag: widget.recipientTag,
      replyTo: widget.replyTo,
      conversationId: convId,
      baseCanvasHeight: _lastCanvasHeight > 0 ? _lastCanvasHeight : null,
    );
  }

  // rimosso: submit to moon non più utilizzato in questa pagina

  double _contentMaxWidth(double w) {
    return w;
  }

  Future<bool> _triggerDownloadFromBuilder() async {
    final dyn = _builderKey.currentState as dynamic;
    if (dyn?.openDownloadDialogPublic != null) {
      final dynamic saved = await dyn.openDownloadDialogPublic();
      return saved == true;
    } else {
      _warnMissingApi('_triggerDownloadFromBuilder → openDownloadDialogPublic');
      return false;
    }
  }

  Future<void> _handleDownloadTap() async {
    if (!_hasMinTextForDownload) {
      if (!mounted) return;
      showHonooToast(
        context,
        message: 'Scrivi almeno 1 carattere prima di scaricare',
      );
      return;
    }

    final user = SupabaseProvider.client.auth.currentUser;
    if (user == null) {
      if (!mounted) return;
      await AuthNavigationService.ensureLoggedIn(context);
      return;
    }

    await _triggerDownloadFromBuilder();
  }

  void _warnMissingApi(String what) {
    if (!mounted) return;
    showHonooToast(context, message: 'Collega API del builder: $what');
  }

  void _replaceEditorImage() {
    final dynamic builder = _builderKey.currentState;
    builder?.replaceBackgroundPublic?.call();
  }

  void _beginCampanelloImageEdit() {
    if (!mounted) return;
    setState(() => _campanelloEditStarted = true);
    _replaceEditorImage();
  }

  void _beginCampanelloTextEdit() {
    if (!mounted) return;
    setState(() => _campanelloEditStarted = true);
    final dynamic builder = _builderKey.currentState;
    builder?.editTextPublic?.call();
  }

  Future<void> _saveEditorImage() async {
    final dynamic builder = _builderKey.currentState;
    builder?.confirmBackgroundPublic?.call();
    if (widget.isCampanello &&
        (widget.editingCampanelloId?.isNotEmpty ?? false)) {
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) await _submitHinoo();
    }
  }

  Future<void> _deleteEditorContent() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const HonooConfirmDialog(
        title: 'Vuoi davvero eliminare questo hinoo?',
        message: 'L’operazione non è reversibile',
        confirmLabel: 'Sì',
        cancelLabel: 'No',
      ),
    );
    if (confirmed != true || !mounted) return;

    final dynamic builder = _builderKey.currentState;
    builder?.clearContentPublic?.call();
  }

  Widget _buildImageEditingControls() {
    const double confirmIconSize = 30;
    const double secondaryActionIconSize = confirmIconSize * 0.82;

    return IgnorePointer(
      ignoring: _bgUploadInProgress,
      child: Opacity(
        opacity: _bgUploadInProgress ? 0.65 : 1,
        child: Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Tooltip(
                  message: 'Sostituisci immagine',
                  preferBelow: false,
                  child: IconButton(
                    key: const Key('hinoo-replace-editing-image'),
                    onPressed: _replaceEditorImage,
                    padding: EdgeInsets.zero,
                    iconSize: secondaryActionIconSize,
                    color: HonooColor.onBackground,
                    icon: SvgPicture.asset(
                      'assets/icons/immagine.svg',
                      width: secondaryActionIconSize,
                      height: secondaryActionIconSize,
                      colorFilter: const ColorFilter.mode(
                        HonooColor.onBackground,
                        BlendMode.srcIn,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: Tooltip(
                  message: 'Salva immagine',
                  preferBelow: false,
                  child: IconButton(
                    key: const Key('hinoo-save-editing-image'),
                    onPressed: _saveEditorImage,
                    padding: EdgeInsets.zero,
                    icon: SvgPicture.asset(
                      'assets/icons/ok.svg',
                      width: confirmIconSize,
                      height: confirmIconSize,
                      colorFilter: const ColorFilter.mode(
                        HonooColor.onBackground,
                        BlendMode.srcIn,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: IconButton(
                key: const Key('hinoo-delete-editing-content'),
                tooltip: 'Cancella hinoo',
                onPressed: _deleteEditorContent,
                padding: EdgeInsets.zero,
                icon: SvgPicture.asset(
                  'assets/Cestino.svg',
                  width: secondaryActionIconSize,
                  height: secondaryActionIconSize,
                  colorFilter: const ColorFilter.mode(
                    HonooColor.onBackground,
                    BlendMode.srcIn,
                  ),
                ),
              ),
            ),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: Tooltip(
                  message: 'Modifica testo',
                  preferBelow: false,
                  child: IconButton(
                    key: const Key('hinoo-edit-text'),
                    onPressed: _beginCampanelloTextEdit,
                    padding: EdgeInsets.zero,
                    iconSize: secondaryActionIconSize,
                    color: HonooColor.onBackground,
                    icon: SvgPicture.asset(
                      'assets/icons/modifica testo.svg',
                      width: secondaryActionIconSize,
                      height: secondaryActionIconSize,
                      colorFilter: const ColorFilter.mode(
                        HonooColor.onBackground,
                        BlendMode.srcIn,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditorControls() {
    final bool editingExistingCampanello =
        widget.isCampanello &&
        (widget.editingCampanelloId?.isNotEmpty ?? false);
    if (editingExistingCampanello) {
      if (_campanelloEditStarted && _builderStep == 'changeBg') {
        return _buildImageEditingControls();
      }
      const double actionSize = 30;
      return SizedBox(
        key: const Key('campanello-editor-controls'),
        height: 40,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextBoxDownloadButton(
              key: const Key('campanello-edit-image'),
              onPressed: _beginCampanelloImageEdit,
              tooltip: 'Modifica immagine',
              size: actionSize,
              asset: 'assets/icons/immagine.svg',
            ),
            if (_campanelloEditStarted)
              TextBoxDownloadButton(
                key: const Key('campanello-save-changes'),
                onPressed: _submitHinoo,
                tooltip: 'Conferma e salva',
                size: actionSize,
                asset: 'assets/icons/ok.svg',
              )
            else
              const SizedBox(width: actionSize, height: actionSize),
            TextBoxDownloadButton(
              key: const Key('campanello-edit-text'),
              onPressed: _beginCampanelloTextEdit,
              tooltip: 'Modifica testo',
              size: actionSize,
              asset: 'assets/icons/modifica testo.svg',
            ),
          ],
        ),
      );
    }
    return SizedBox(
      key: const Key('hinoo-editor-controls'),
      height: 40,
      child: _builderStep == 'changeBg' && _hasBackground
          ? _buildImageEditingControls()
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextBoxDownloadButton(
                  key: const Key('hinoo-edit-image'),
                  onPressed: _replaceEditorImage,
                  tooltip: 'Modifica immagine',
                  asset: 'assets/icons/immagine.svg',
                ),
                TextBoxDownloadButton(
                  key: const Key('hinoo-edit-text'),
                  onPressed: _beginCampanelloTextEdit,
                  tooltip: 'Modifica testo',
                  asset: 'assets/icons/modifica testo.svg',
                ),
              ],
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const double contentTopPadding = 0;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: HonooColor.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, viewport) {
            final double keyboard = MediaQuery.of(context).viewInsets.bottom;
            final bool kbOpen = keyboard > 0;
            final double safeBottom = MediaQuery.of(context).viewPadding.bottom;

            final double viewW = viewport.maxWidth;
            final double viewH = viewport.maxHeight;
            final double targetMaxW = _contentMaxWidth(viewW);
            final ResponsiveLayoutMode layoutMode =
                ResponsiveLayout.modeForWidth(viewW);
            final double footerIconSize =
                ResponsiveLayout.footerIconSizeForMode(layoutMode);
            final double footerGap = ResponsiveLayout.footerGapForMode(
              layoutMode,
            );
            final double footerBottomPadding =
                ResponsiveLayout.footerBottomPaddingForMode(layoutMode);
            final double footerSpacing = footerBottomPadding + safeBottom;
            final double footerTopSpacing = footerSpacing / 2;
            final double footerBottomSpacing = footerSpacing - footerTopSpacing;
            final double footerReserved =
                footerIconSize + footerTopSpacing + footerBottomSpacing;

            final double availableH =
                (viewH - _titleH - contentTopPadding - footerReserved).clamp(
                  0.0,
                  double.infinity,
                );
            const double editorControlsHeight = 40;
            const double editorControlsGap = 4;
            final double canvasAvailableH =
                (availableH - editorControlsHeight - editorControlsGap).clamp(
                  0.0,
                  double.infinity,
                );

            const double ar = 9 / 16;
            double canvasW = targetMaxW;
            double canvasH = canvasW / ar;
            if (canvasH > canvasAvailableH) {
              canvasH = canvasAvailableH;
              canvasW = canvasH * ar;
            }
            if (kbOpen && _unobstructedCanvasSize != null) {
              canvasW = _unobstructedCanvasSize!.width;
              canvasH = _unobstructedCanvasSize!.height;
            } else if (!kbOpen) {
              _unobstructedCanvasSize = Size(canvasW, canvasH);
            }
            _lastCanvasHeight = HinooTypography.baselineCanvasHeight;

            final Widget mainColumn = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: _titleH,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                    child: Align(
                      alignment: Alignment.center,
                      child: HonooAppTitle(
                        onTap: () {
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(
                              builder: (_) => const PlaceholderPage(),
                            ),
                            (route) => false,
                          );
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: contentTopPadding),
                SizedBox(
                  height: availableH,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: targetMaxW),
                      child: SizedBox(
                        width: canvasW,
                        height:
                            editorControlsHeight + editorControlsGap + canvasH,
                        child: Column(
                          children: [
                            _buildEditorControls(),
                            const SizedBox(height: editorControlsGap),
                            SizedBox(
                              key: const Key('hinoo-editor-card'),
                              width: canvasW,
                              height: canvasH,
                              child: ClipRect(
                                child: HinooBuilder(
                                  key: _builderKey,
                                  onHinooChanged: _onHinooChanged,
                                  onPngExported: _onPngExported,
                                  hintText: _kWriteHint,
                                  useCampanelloPadding: widget.isCampanello,
                                  downloadContentName: widget.isCampanello
                                      ? 'campanello'
                                      : 'hinoo',
                                  backgroundPromptText: widget.isCampanello
                                      ? 'Scrivi qui\n'
                                            'tutto quello che vuoi\n'
                                            'per la pagina\n'
                                            'del tuo campanello'
                                      : null,
                                  initialDraft: widget.initialDraft,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: footerReserved),
              ],
            );

            final Widget content = kbOpen
                ? SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.manual,
                    padding: EdgeInsets.only(bottom: keyboard),
                    physics: const ClampingScrollPhysics(),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: viewH),
                      child: mainColumn,
                    ),
                  )
                : mainColumn;

            return Stack(
              clipBehavior: Clip.none,
              children: [
                content,
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    ignoring: kbOpen,
                    child: ResponsiveFooterBar(
                      bottomPadding: footerBottomSpacing,
                      desiredGap: footerGap,
                      minGap: 16,
                      height: footerIconSize,
                      actions: [
                        ResponsiveFooterAction(
                          asset: "assets/icons/home.svg",
                          semanticsLabel: 'Home',
                          colorFilter: const ColorFilter.mode(
                            HonooColor.onBackground,
                            BlendMode.srcIn,
                          ),
                          size: footerIconSize,
                          splashRadius: 25,
                          tooltip: 'Home',
                          onPressed: () {
                            Navigator.of(context).pushAndRemoveUntil(
                              MaterialPageRoute(
                                builder: (_) => const HomePage(),
                              ),
                              (route) => false,
                            );
                          },
                        ),
                        ResponsiveFooterAction(
                          asset: "assets/icons/chest.svg",
                          semanticsLabel: 'Chest',
                          size: footerIconSize,
                          splashRadius: 40,
                          tooltip: 'Apri il tuo Cuore',
                          icon: AnimatedBuilder(
                            animation: _chestBounce,
                            builder: (context, child) => Transform.scale(
                              scale: _chestBounce.value,
                              child: child,
                            ),
                            child: SvgPicture.asset(
                              "assets/icons/chest.svg",
                              width: footerIconSize,
                              height: footerIconSize,
                            ),
                          ),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ChestPage(),
                              ),
                            );
                          },
                        ),
                        if (_isWriteStep &&
                            _currentTextLength > 0 &&
                            !(widget.isCampanello &&
                                (widget.editingCampanelloId?.isNotEmpty ??
                                    false)))
                          ResponsiveFooterAction(
                            asset: "assets/icons/ok.svg",
                            semanticsLabel:
                                ((widget.isReply ||
                                    widget.forcedType == HinooType.answer)
                                ? 'Invia'
                                : (widget.isCampanello
                                      ? 'Salva il campanello'
                                      : 'OK')),
                            size: footerIconSize,
                            splashRadius: 25,
                            tooltip:
                                (widget.isReply ||
                                    widget.forcedType == HinooType.answer)
                                ? 'Invia'
                                : (widget.isCampanello
                                      ? 'Salva il campanello'
                                      : 'Salva hinoo'),
                            onPressed: _submitHinoo,
                          ),
                        if (_isWriteStep)
                          ResponsiveFooterAction(
                            asset: 'assets/icons/download.svg',
                            semanticsLabel: 'Download',
                            size: footerIconSize,
                            splashRadius: 25,
                            tooltip: 'Salva sul dispositivo',
                            onPressed: _handleDownloadTap,
                            colorFilter: const ColorFilter.mode(
                              HonooColor.onBackground,
                              BlendMode.srcIn,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

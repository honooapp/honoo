import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:honoo/Utility/honoo_colors.dart';
import 'package:honoo/Services/supabase_provider.dart';

import '../Entities/honoo.dart';
import '../Entities/reply_navigation_result.dart';
import '../Services/honoo_image_uploader.dart';
import '../Services/auth_navigation_service.dart';
import '../UI/honoo_builder.dart';
import 'package:honoo/Services/honoo_service.dart';
import 'package:honoo/Services/duplication_result.dart';

import 'chest_page.dart';
import 'new_hinoo_page.dart';
import 'home_page.dart';
import '../Widgets/honoo_dialogs.dart';
import '../Widgets/honoo_app_title.dart';
import '../UI/HonooBuilder/dialogs/name_honoo_dialog.dart';
import 'placeholder_page.dart';
import '../Utility/responsive_layout.dart';
import '../Utility/inline_text_formatting.dart';
import '../Widgets/responsive_footer_bar.dart';
import '../Widgets/conversation_notification_prompt.dart';
import '../Widgets/repeated_reply_prompt.dart';
import 'package:uuid/uuid.dart';

class NewHonooPage extends StatefulWidget {
  const NewHonooPage({
    super.key,
    this.forcedType,
    this.recipientTag,
    this.returnSavedId = false,
    this.conversationId,
    this.replyTo,
    this.returnToPreviousOnAnswer = false,
    this.targetContentName = 'honoo',
    this.editingHonoo,
    this.editImage = false,
  });

  final Honoo? editingHonoo;
  final bool editImage;
  final HonooType? forcedType;
  final String? recipientTag;
  final bool returnSavedId;
  final String? conversationId;
  final String? replyTo;
  final bool returnToPreviousOnAnswer;
  final String targetContentName;

  @override
  State<NewHonooPage> createState() => _NewHonooPageState();
}

class _NewHonooPageState extends State<NewHonooPage> {
  final GlobalKey<HonooBuilderState> _builderKey =
      GlobalKey<HonooBuilderState>();

  double? _initialViewH;

  String _text = '';
  String _imageUrl = '';

  /// cache dell’URL immagine definitiva (dopo upload/risoluzione)
  String? _finalImageUrlCache;

  /// contenuto effettivamente SALVATO (per evitare reset dello stato da update identici)
  String _lastSavedRawImage = '';
  bool _hasMinTextForDownload = false;
  bool _isImageEditorVisible = false;

  @override
  void initState() {
    super.initState();
    final original = widget.editingHonoo;
    if (original != null) {
      _text = original.text;
      _imageUrl = original.image;
      _hasMinTextForDownload = InlineTextFormatting.hasVisibleText(_text);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (widget.editImage) {
          _builderKey.currentState?.editImagePublic();
        } else {
          _builderKey.currentState?.editTextPublic();
        }
      });
    }
  }

  void _onImageEditorVisibilityChanged(bool isVisible) {
    if (_isImageEditorVisible == isVisible) return;
    setState(() => _isImageEditorVisible = isVisible);
  }

  /// Aggiorna solo se cambia DAVVERO e non è identico all’ultimo SALVATO.
  void _onHonooChanged(String text, String imageUrl) {
    // se identico allo stato attuale → nessun rebuild inutile
    if (text == _text && imageUrl == _imageUrl) return;

    setState(() {
      _text = text;
      _imageUrl = imageUrl;

      _hasMinTextForDownload = InlineTextFormatting.hasVisibleText(text);

      // resetta eventuali indicatori se il contenuto è DIVERSO da quello salvato

      // se cambia l’immagine rispetto a QUELLA SALVATA, invalida cache
      if (imageUrl != _lastSavedRawImage) {
        _finalImageUrlCache = null;
      }
    });
  }

  String? _savedHonooId;

  Future<void> _offerMoonAfterSave() async {
    final send = await showDialog<bool>(
      context: context,
      builder: (_) => const HonooConfirmDialog(
        title: "L'honoo è stato salvato nel tuo Scrigno.",
        message: "Vuoi spedirlo anche sulla Luna,\nper mostrarlo a tutti?",
        confirmLabel: "Sì",
        cancelLabel: "No",
      ),
    );
    if (send == true && mounted) await _submitToMoon();
  }

  Future<bool> _submitHonoo() async {
    final user = SupabaseProvider.client.auth.currentUser;

    // Se la sessione scade, apri direttamente il login e conserva l'editor.
    if (user == null) {
      if (!mounted) return false;
      await AuthNavigationService.ensureLoggedIn(context);
      return false;
    }

    // 2) Validazioni minime (testo + immagine)
    if (!InlineTextFormatting.hasVisibleText(_text)) {
      if (!mounted) return false;
      showHonooToast(context, message: 'Scrivi qualcosa prima di salvare.');
      return false;
    }

    if (_imageUrl.trim().isEmpty) {
      if (!mounted) return false;
      showHonooToast(context, message: 'Carica un’immagine prima di salvare.');
      return false;
    }

    // 3) Risolvi URL definitivo (usa cache se già risolto)
    final String? finalImageUrl =
        _finalImageUrlCache ?? await _resolveFinalImageUrl(_imageUrl);

    if (finalImageUrl == null || finalImageUrl.isEmpty) {
      if (!mounted) return false;
      showHonooToast(
        context,
        message: 'Immagine non valida. Ricaricala e riprova.',
      );
      return false;
    }

    final original = widget.editingHonoo;
    final savedId = _savedHonooId ?? original?.dbId;
    if (savedId != null) {
      try {
        await HonooService.updateContent(
          id: savedId,
          text: _text,
          imageUrl: finalImageUrl,
        );
        if (!mounted) return false;
        _finalImageUrlCache = finalImageUrl;
        _lastSavedRawImage = _imageUrl;
        await _offerMoonAfterSave();
        return true;
      } catch (error) {
        if (mounted) {
          showHonooToast(context, message: 'Modifica non salvata: $error');
        }
        return false;
      }
    }

    // 4) Crea e salva
    final HonooType type = widget.forcedType ?? HonooType.personal;
    // conversation: se risposta usa quella fornita; altrimenti genera una nuova
    String conversationId = widget.conversationId ?? const Uuid().v4();
    if (type == HonooType.answer && widget.replyTo?.isNotEmpty == true) {
      if (!mounted) return false;
      final selectedConversationId = await chooseReplyConversation(
        context: context,
        parentId: widget.replyTo!,
        defaultConversationId: conversationId,
        contentName: widget.targetContentName,
      );
      if (selectedConversationId == null || !mounted) return false;
      conversationId = selectedConversationId;
    }
    final newHonoo = Honoo(
      0,
      _text,
      finalImageUrl,
      DateTime.now().toIso8601String(),
      DateTime.now().toIso8601String(),
      user.id,
      type,
      widget.replyTo,
      widget.recipientTag,
    )..conversationId = conversationId;

    try {
      if (widget.returnSavedId) {
        final id = await HonooService.publishHonooAndReturnId(newHonoo);
        if (!mounted) return false;
        showHonooToast(context, message: 'honoo salvato.');
        Navigator.of(context).pop(id);
        return true;
      }

      final savedReplyId = type == HonooType.answer
          ? await HonooService.publishHonooAndReturnId(newHonoo)
          : null;
      if (savedReplyId == null) {
        _savedHonooId = await HonooService.publishHonooAndReturnId(newHonoo);
      }

      if (!mounted) return false;
      setState(() {
        _finalImageUrlCache = finalImageUrl;
        _lastSavedRawImage = _imageUrl;
      });

      final bool shouldOfferNotifications =
          type == HonooType.personal &&
          await ConversationNotificationPrompt.shouldOfferForFirstConversation(
            user.id,
          );
      if (!mounted) return false;

      if (shouldOfferNotifications) {
        await ConversationNotificationPrompt.show(context);
        if (!mounted) return false;
      }

      if (type == HonooType.answer) {
        await showReplySavedDialog(context, contentName: 'honoo');
        if (!mounted) return false;
        if (widget.returnToPreviousOnAnswer) {
          Navigator.of(context).pop(
            ReplyNavigationResult(
              conversationId: conversationId,
              replyId: savedReplyId!,
            ),
          );
          return true;
        }
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => ChestPage(
              focusReplies: true,
              focusConversationId: conversationId,
              focusReplyId: savedReplyId,
              highlightLatest: true,
            ),
          ),
          (route) => false,
        );
        return true;
      }

      await _offerMoonAfterSave();
      return true;
    } catch (e, st) {
      debugPrint('publishHonoo failed: $e\n$st');
      if (!mounted) return false;
      showHonooToast(context, message: 'Errore: $e');
      return false;
    }
  }

  Future<bool> _submitToMoon() async {
    try {
      final String? finalImageUrl =
          _finalImageUrlCache ?? await _resolveFinalImageUrl(_imageUrl);

      final honooForMoon = Honoo(
        0,
        _text,
        finalImageUrl ?? '',
        DateTime.now().toIso8601String(),
        DateTime.now().toIso8601String(),
        SupabaseProvider.client.auth.currentUser?.id ?? '',
        HonooType.personal,
        null,
        null,
      );

      final result = await HonooService.duplicateToMoon(honooForMoon);

      if (!mounted) return false;
      showHonooToast(
        context,
        message: result == DuplicationResult.inserted
            ? "L'honoo è anche sulla Luna."
            : 'Già presente sulla Luna.',
      );
      return true;
    } catch (e, st) {
      debugPrint('duplicateToMoon failed: $e\n$st');
      if (mounted) {
        showHonooToast(context, message: 'Errore: $e');
      }
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

    final state = _builderKey.currentState;
    if (state == null) {
      showHonooToast(context, message: 'Impossibile avviare il download.');
      return;
    }

    if (!state.hasImage) {
      showHonooToast(context, message: "Inserisci prima un'immagine");
      return;
    }

    final user = SupabaseProvider.client.auth.currentUser;
    if (user == null) {
      if (!mounted) return;
      await AuthNavigationService.ensureLoggedIn(context);
      return;
    }

    final String? desiredName = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (_) => NameHonooDialog(initialValue: _defaultHonooFileName()),
    );
    final String? trimmed = desiredName?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return;
    }

    if (!mounted) return;
    await state.downloadHonooPublic(context, fileName: trimmed);
  }

  void _onBuilderFocusChanged(bool hasFocus) {
    if (mounted) setState(() {});
  }

  Widget _withoutKeyboardInsets(BuildContext context, Widget child) {
    final MediaQueryData mediaQuery = MediaQuery.of(context);
    return MediaQuery(
      data: mediaQuery.copyWith(viewInsets: EdgeInsets.zero),
      child: child,
    );
  }

  Future<String?> _resolveFinalImageUrl(String raw) async {
    final s = raw.trim();
    if (s.isEmpty) return null;

    if (s.startsWith('http://') || s.startsWith('https://')) return s;

    if (kIsWeb && s.startsWith('blob:')) {
      if (mounted) {
        showHonooToast(
          context,
          message: 'Immagine locale (blob) non caricabile dal browser.',
        );
      }
      return null;
    }

    final uploaded = await HonooImageUploader.uploadImageFromPath(s);
    return uploaded;
  }

  String _defaultHonooFileName() {
    final String text = _text.trim();
    if (text.isEmpty) return 'honoo';
    final String slug = text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp('_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    if (slug.isEmpty) return 'honoo';
    return slug.length > 32 ? slug.substring(0, 32) : slug;
  }

  @override
  Widget build(BuildContext context) {
    // Header compatto per ridurre il gap sopra l’honoo
    const double headerH = 52;
    final double safeBottom = MediaQuery.of(context).viewPadding.bottom;

    const double contentTopPadding = 0;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: HonooColor.background,
      body: SafeArea(
        maintainBottomViewPadding: true,
        child: LayoutBuilder(
          builder: (context, viewport) {
            final double viewW = viewport.maxWidth;

            _initialViewH ??= viewport.maxHeight;
            final double viewH = _initialViewH!;

            final ResponsiveLayoutMode layoutMode =
                ResponsiveLayout.modeForWidth(viewW);
            final double targetMaxW = ResponsiveLayout.contentMaxWidthForMode(
              layoutMode,
              viewW,
            );
            final double footerIconSize =
                ResponsiveLayout.footerIconSizeForMode(layoutMode);
            final double footerGap = ResponsiveLayout.footerGapForMode(
              layoutMode,
            );
            final double footerBottomPadding =
                ResponsiveLayout.footerBottomPaddingForMode(layoutMode);
            final double footerContentH = footerIconSize;
            final double footerSpacing = footerBottomPadding + safeBottom;
            final double footerTopSpacing = footerSpacing / 2;
            final double footerBottomSpacing = footerSpacing - footerTopSpacing;

            // Altezza riservata al footer (3 pulsanti)
            final double footerReserved =
                footerContentH + footerTopSpacing + footerBottomSpacing;

            // Altezza disponibile per il box honoo
            final double availableH =
                (viewH - headerH - contentTopPadding - footerReserved).clamp(
                  0.0,
                  double.infinity,
                );
            final double builderAvailableH = availableH;

            final HonooBuilderMetrics metrics =
                ResponsiveLayout.honooBuilderMetrics(
                  availableHeight: builderAvailableH,
                  maxWidth: targetMaxW,
                  mode: layoutMode,
                  enforceDesktopBaseline: false,
                );
            final double editorScale = _isImageEditorVisible
                ? math.min(
                    targetMaxW / HonooBuilder.baselineImageSize,
                    builderAvailableH /
                        (HonooBuilder.baselineTotalHeight +
                            HonooBuilder.baselineEditingToolbarHeight),
                  )
                : 0;
            final double builderWidth = _isImageEditorVisible
                ? HonooBuilder.baselineImageSize * editorScale
                : metrics.width;
            final double builderHeight = _isImageEditorVisible
                ? (HonooBuilder.baselineTotalHeight +
                          HonooBuilder.baselineEditingToolbarHeight) *
                      editorScale
                : metrics.height;
            final double editorGroupHeight = builderHeight;
            final double editorGroupTop =
                headerH +
                contentTopPadding +
                math.max(0, (availableH - editorGroupHeight) / 2);
            final double footerTop =
                editorGroupTop + editorGroupHeight + footerTopSpacing;

            final Widget content = Stack(
              clipBehavior: Clip.none,
              children: [
                // ===== HEADER + HONOO (full height) =====
                Column(
                  children: [
                    SizedBox(
                      height: headerH,
                      child: Center(
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
                    const SizedBox(height: contentTopPadding),
                    SizedBox(
                      height: availableH,
                      child: Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 90),
                          curve: Curves.easeOutCubic,
                          constraints: BoxConstraints(maxWidth: targetMaxW),
                          child: SizedBox(
                            width: builderWidth,
                            height: editorGroupHeight,
                            child: Column(
                              children: [
                                SizedBox(
                                  width: builderWidth,
                                  height: builderHeight,
                                  child: ClipRect(
                                    child: HonooBuilder(
                                      key: _builderKey,
                                      initialText: widget.editingHonoo?.text,
                                      initialImageUrl:
                                          widget.editingHonoo?.image,
                                      onHonooChanged: _onHonooChanged,
                                      onFocusChanged: _onBuilderFocusChanged,
                                      showCharacterCounter: true,
                                      imageConfirmIconDisplaySize:
                                          footerIconSize,
                                      onImageConfirmed: () => _submitHonoo(),
                                      onImageEditorVisibilityChanged:
                                          _onImageEditorVisibilityChanged,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                // ===== FOOTER: Home – Chest – (OK|Luna) =====
                Positioned(
                  top: footerTop,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: SizedBox(
                      key: const Key('honoo-editor-footer'),
                      width: builderWidth,
                      child: ResponsiveFooterBar(
                        bottomPadding: 0,
                        desiredGap: footerGap,
                        minGap: 16,
                        height: footerContentH,
                        useSafeArea: false,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        expandToAvailableWidth: true,
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
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const ChestPage(),
                                ),
                              );
                            },
                          ),
                          if (widget.forcedType != HonooType.answer)
                            ResponsiveFooterAction(
                              asset: "assets/icons/testo.svg",
                              semanticsLabel: 'Piuma',
                              colorFilter: const ColorFilter.mode(
                                HonooColor.onBackground,
                                BlendMode.srcIn,
                              ),
                              size: footerIconSize,
                              splashRadius: 25,
                              tooltip: 'Scrivi hinoo',
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const NewHinooPage(),
                                  ),
                                );
                              },
                            ),
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
                ),
              ],
            );
            return _withoutKeyboardInsets(context, content);
          },
        ),
      ),
    );
  }
}

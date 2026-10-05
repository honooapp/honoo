import '../Widgets/content_edit_frame.dart';
// lib/UI/honoo_builder.dart
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:honoo/Utility/heic_converter.dart' as heic;

import 'package:honoo/Services/supabase_provider.dart';
import 'package:honoo/Services/auth_navigation_service.dart';
import 'package:honoo/Utility/honoo_colors.dart';
import 'package:honoo/Utility/typographic_substitutions_formatter.dart';
import 'package:honoo/Widgets/honoo_dialogs.dart';
import 'package:honoo/Widgets/loading_spinner.dart';
import 'package:honoo/Widgets/gallery_save_dialog.dart';
import 'package:honoo/Utility/inline_text_formatting.dart';
import 'package:honoo/Widgets/cover_transform_image.dart';
import 'package:honoo/UI/HinooBuilder/services/download_saver.dart';
import 'package:honoo/Widgets/width_limited_multiline_field.dart';
import 'package:honoo/Widgets/text_box_download_button.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:honoo/web/heic_converter.dart' as heicweb;

import '../Services/honoo_image_uploader.dart';

class HonooBuilder extends StatefulWidget {
  static const int maxTextCharacters = 144;
  static const double baselineImageSize = 360.0;
  static const double baselineGap = 9.0;
  static const double baselineEditingToolbarHeight = 48.0;
  static const double baselineTextHeight = baselineImageSize / 2;
  static const double baselineTotalHeight =
      baselineImageSize + baselineGap + baselineTextHeight;

  @visibleForTesting
  static double baselineIconSizeForDisplay(
    double displaySize,
    double canvasScale,
  ) => displaySize / (canvasScale > 0 ? canvasScale : 1);

  final void Function(String text, String imageUrl)? onHonooChanged;
  final ValueChanged<bool>? onFocusChanged;
  final String? initialText;
  final String? initialImageUrl;
  final String? textHint;
  final String? imageHint;
  final VoidCallback? onDownloadTap;
  final bool showDownloadButton;
  final bool showCharacterCounter;
  final double? imageConfirmIconDisplaySize;
  final Future<bool> Function()? onImageConfirmed;
  final ValueChanged<bool>? onImageEditorVisibilityChanged;
  final bool requireExplicitConfirmation;

  const HonooBuilder({
    super.key,
    this.onHonooChanged,
    this.onFocusChanged,
    this.initialText,
    this.initialImageUrl,
    this.textHint,
    this.imageHint,
    this.onDownloadTap,
    this.showDownloadButton = true,
    this.showCharacterCounter = true,
    this.imageConfirmIconDisplaySize,
    this.onImageConfirmed,
    this.onImageEditorVisibilityChanged,
    this.requireExplicitConfirmation = false,
  });

  @override
  State<HonooBuilder> createState() => HonooBuilderState();
}

class HonooBuilderState extends State<HonooBuilder> {
  final FormattedTextEditingController _textCtrl =
      FormattedTextEditingController();
  final FocusNode _textFocus = FocusNode();

  Uint8List? _imageBytes;

  // preview zoommata “confermata”
  Uint8List? _confirmedPreviewBytes;

  // trasformazioni zoom/pan
  final TransformationController _imageController = TransformationController();
  static const double _imageMinScale =
      1.0; // non permettere zoom-out sotto il fill
  static const double _imageMaxScale = 5.0;
  double _imageScale = _imageMinScale;

  bool _imageConfirmed = false;
  bool _isUploadingFinal = false;
  bool _hideEditorActionsForCapture = false;
  bool _isEditingText = false;

  bool get hasImage => _imageBytes != null;
  bool get _showImageEditingToolbar =>
      !_imageConfirmed && (hasImage || widget.requireExplicitConfirmation);

  @visibleForTesting
  void setImageBytesForTesting(Uint8List bytes) {
    _textFocus.unfocus();
    setState(() {
      _imageBytes = bytes;
      _publicImageUrl = '';
      _imageConfirmed = false;
      _isUploadingFinal = false;
      _isEditingText = false;
      _confirmedPreviewBytes = null;
      _imageScale = _imageMinScale;
    });
    widget.onImageEditorVisibilityChanged?.call(true);
    _emitChange();
  }

  // url pubblico su supabase della PNG zoommata
  String _publicImageUrl = '';

  // key: area immagine zoomata
  final GlobalKey _imageBoundaryKey = GlobalKey();

  // key: intero honoo (testo + immagine) per export
  final GlobalKey _captureKey = GlobalKey();

  @override
  void initState() {
    super.initState();

    if (widget.initialText != null && widget.initialText!.isNotEmpty) {
      _textCtrl.text = widget.initialText!;
    }

    _publicImageUrl = widget.initialImageUrl ?? '';
    _imageConfirmed = _publicImageUrl.isNotEmpty;

    _textCtrl.addListener(_handleTextChanged);
    _textFocus.addListener(_handleFocusChange);
    _imageController.addListener(_handleImageTransform);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onFocusChanged?.call(_textFocus.hasFocus);
    });
  }

  @override
  void dispose() {
    _textCtrl.removeListener(_handleTextChanged);
    _textCtrl.dispose();

    _textFocus.removeListener(_handleFocusChange);
    _textFocus.dispose();

    _imageController.removeListener(_handleImageTransform);
    _imageController.dispose();

    super.dispose();
  }

  void _emitChange() {
    widget.onHonooChanged?.call(_textCtrl.text, _publicImageUrl);
  }

  void _handleTextChanged() {
    if (widget.requireExplicitConfirmation && _imageConfirmed && mounted) {
      setState(() => _imageConfirmed = false);
    }
    _emitChange();
  }

  void _handleFocusChange() {
    widget.onFocusChanged?.call(_textFocus.hasFocus);
    setState(() {
      if (_textFocus.hasFocus) _isEditingText = true;
    });
  }

  void _handleImageTransform() {
    final double newScale = _extractScale(_imageController.value);
    if ((newScale - _imageScale).abs() > 0.005) {
      setState(() => _imageScale = newScale);
    }
  }

  double _extractScale(Matrix4 matrix) {
    final Float64List storage = matrix.storage;
    final double sx = storage[0].abs();
    final double sy = storage[5].abs();
    final double raw = (sx > 0 && sy > 0)
        ? (sx + sy) / 2
        : (sx > 0 ? sx : (sy > 0 ? sy : _imageMinScale));
    return raw.clamp(_imageMinScale, _imageMaxScale).toDouble();
  }

  void _updateImageScale(double scale) {
    final double clamped = scale
        .clamp(_imageMinScale, _imageMaxScale)
        .toDouble();

    final Matrix4 current = _imageController.value.clone();
    final Float64List values = current.storage;
    final double adjustedTx = values[12];
    final double adjustedTy = values[13];

    _imageController.value = Matrix4.identity()
      ..translateByDouble(adjustedTx, adjustedTy, 0, 1)
      ..scaleByDouble(clamped, clamped, clamped, 1);

    setState(() => _imageScale = clamped);
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final XFile? selected = await picker.pickImage(
        source: ImageSource.gallery,
      );
      if (selected == null) return;

      Uint8List bytes = await selected.readAsBytes();
      // Web: conversione HEIC → WEBP (fallback PNG) prima della preview
      if (kIsWeb) {
        try {
          final converted = await heicweb.convertHeicToWebSafe(
            bytes,
            selected.name,
          );
          if (converted != null && converted.isNotEmpty) {
            bytes = converted;
          } else {
            final lower = selected.name.toLowerCase();
            if (lower.endsWith('.heic') || lower.endsWith('.heif')) {
              if (mounted) {
                showHonooToast(
                  context,
                  message: 'Formato HEIC non supportato dal browser',
                );
              }
              return;
            }
          }
        } catch (e) {
          debugPrint('HEIC web conversion failed (honoo): $e');
          final lower = selected.name.toLowerCase();
          if (lower.endsWith('.heic') || lower.endsWith('.heif')) {
            if (mounted) {
              showHonooToast(
                context,
                message: 'Formato HEIC non supportato dal browser',
              );
            }
            return;
          }
        }
      } else {
        // Mobile/desktop: comportamento invariato (eventuale HEIC gestito dai codec nativi)
        final name = (selected.name).toLowerCase();
        if (name.endsWith('.heic') || name.endsWith('.heif')) {
          final converted = await heic.heicToPng(bytes);
          if (converted != null && converted.isNotEmpty) {
            bytes = converted;
          }
        }
      }

      _imageController.value = Matrix4.identity();
      _textFocus.unfocus();

      setState(() {
        _imageBytes = bytes;

        // reset stato
        _publicImageUrl = '';
        _imageConfirmed = false;
        _isUploadingFinal = false;
        _isEditingText = false;
        _confirmedPreviewBytes = null;
        _imageScale = _imageMinScale;
      });
      widget.onImageEditorVisibilityChanged?.call(true);

      _emitChange();
    } catch (e) {
      if (!mounted) return;
      showHonooToast(context, message: 'Errore selezione immagine: $e');
    }
  }

  Future<Uint8List?> _captureZoomedImagePng() async {
    final boundary =
        _imageBoundaryKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) return null;

    try {
      // Prendi le info necessarie prima dell'await per evitare lint
      final double deviceRatio = View.of(context).devicePixelRatio;

      // Assicurati che il frame corrente sia completamente layouttato
      await Future<void>.delayed(Duration.zero);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return null;

      // In rari casi (layout immediato) la size può risultare 0
      if (boundary.size.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 16));
        if (!mounted) return null;
      }
      final Size logical = boundary.size;
      // 1080 px è sufficiente per la card e mantiene il PNG sotto i limiti
      // usuali di Supabase anche con fotografie molto dettagliate.
      const double maxOut = 1080.0;
      final double longEdge = logical.width > logical.height
          ? logical.width
          : logical.height;
      double pixelRatio = deviceRatio;
      if (longEdge * deviceRatio > maxOut && longEdge > 0) {
        pixelRatio = (maxOut / longEdge).clamp(1.0, deviceRatio);
      }
      final ui.Image img = await boundary.toImage(pixelRatio: pixelRatio);
      try {
        final ByteData? bd = await img.toByteData(
          format: ui.ImageByteFormat.png,
        );
        return bd?.buffer.asUint8List();
      } finally {
        img.dispose();
      }
    } catch (e) {
      debugPrint('Errore capture zoomed image: $e');
      return null;
    }
  }

  Future<void> _confirmImage() async {
    if (_imageConfirmed || !hasImage) return;

    final client = SupabaseProvider.client;
    final session = client.auth.currentSession;
    if (session == null) {
      if (!mounted) return;
      await AuthNavigationService.ensureLoggedIn(context);
      return;
    }

    setState(() => _isUploadingFinal = true);

    // 1) cattura PNG zoommata (dalla preview)
    final Uint8List? png = await _captureZoomedImagePng();
    if (png == null || png.isEmpty) {
      if (!mounted) return;
      setState(() => _isUploadingFinal = false);
      showHonooToast(
        context,
        message: 'Impossibile confermare: PNG non generato.',
      );
      return;
    }

    // 2) upload su supabase
    final String? publicUrl = await HonooImageUploader.uploadImageBytes(
      png,
      '.png',
    );
    if (publicUrl == null || publicUrl.isEmpty) {
      if (!mounted) return;
      setState(() => _isUploadingFinal = false);
      showHonooToast(context, message: 'Upload immagine finale fallito.');
      return;
    }

    if (!mounted) return;
    _publicImageUrl = publicUrl;
    _confirmedPreviewBytes = png;
    _emitChange();

    final bool saved = await widget.onImageConfirmed?.call() ?? true;
    if (!mounted) return;
    setState(() {
      _imageConfirmed = saved;
      _isUploadingFinal = false;
    });
    widget.onImageEditorVisibilityChanged?.call(!saved);
  }

  void editTextPublic() => _editText();
  Future<void> editImagePublic() => _pickImage();

  void _editText() {
    setState(() => _isEditingText = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _textFocus.requestFocus();
    });
  }

  void _returnToImageEditor() {
    _textFocus.unfocus();
    setState(() => _isEditingText = false);
  }

  Future<void> _saveEditedTextAndHonoo() async {
    _textFocus.unfocus();
    _emitChange();
    if (hasImage && !_imageConfirmed) {
      await _confirmImage();
      return;
    }

    final bool saved = await widget.onImageConfirmed?.call() ?? true;
    if (!mounted) return;
    setState(() => _imageConfirmed = saved);
    widget.onImageEditorVisibilityChanged?.call(!saved);
  }

  Future<Uint8List?> _captureHonooAsPng() async {
    final boundary =
        _captureKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) return null;

    try {
      // Prendi le info necessarie prima dell'await per evitare lint
      final double deviceRatio = View.of(context).devicePixelRatio;

      // Attendi la fine del frame per sicurezza (sopratutto in reply flow)
      await Future<void>.delayed(Duration.zero);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return null;
      final Size logical = boundary.size;
      const double maxOut = 2560.0;
      final double longEdge = logical.width > logical.height
          ? logical.width
          : logical.height;
      double pixelRatio = deviceRatio;
      if (longEdge * deviceRatio > maxOut && longEdge > 0) {
        pixelRatio = (maxOut / longEdge).clamp(1.0, deviceRatio);
      }
      final ui.Image base = await boundary.toImage(pixelRatio: pixelRatio);
      try {
        final ByteData? byteData = await base.toByteData(
          format: ui.ImageByteFormat.png,
        );
        return byteData?.buffer.asUint8List();
      } finally {
        base.dispose();
      }
    } catch (e) {
      debugPrint('Errore cattura honoo: $e');
      return null;
    }
  }

  Future<bool> downloadHonooPublic(
    BuildContext context, {
    String? fileName,
  }) async {
    if (!hasImage && _publicImageUrl.isEmpty) {
      showHonooToast(context, message: 'Devi prima caricare un’immagine.');
      return false;
    }

    setState(() => _hideEditorActionsForCapture = true);
    Uint8List? bytes;
    try {
      await WidgetsBinding.instance.endOfFrame;
      bytes = await TextBoxDownloadButton.hideWhileCapturing(
        _captureHonooAsPng,
      );
    } finally {
      if (mounted) {
        setState(() => _hideEditorActionsForCapture = false);
      }
    }
    if (bytes == null || bytes.isEmpty) {
      if (!context.mounted) return false;
      showHonooToast(context, message: 'Impossibile generare il file PNG.');
      return false;
    }

    final saver = getDownloadSaver();

    final String fallbackName =
        'honoo_${DateTime.now().millisecondsSinceEpoch}';
    final String rawName = (fileName != null && fileName.trim().isNotEmpty)
        ? fileName.trim()
        : fallbackName;

    // ✅ NON uso saveBytes (così non tocchi download_saver.dart)
    final DownloadSaveResult result = await saver.save([
      DownloadImage(filename: '$rawName.png', bytes: bytes),
    ]);

    if (!context.mounted) return false;
    await showDownloadSaveResult(
      context: context,
      contentName: 'honoo',
      result: result,
    );
    return true;
  }

  void resetContent() {
    setState(() {
      _textCtrl.clear();
      _imageBytes = null;

      _publicImageUrl = '';
      _imageController.value = Matrix4.identity();
      _imageScale = _imageMinScale;

      _imageConfirmed = false;
      _isUploadingFinal = false;
      _isEditingText = false;

      _confirmedPreviewBytes = null;
    });
    widget.onImageEditorVisibilityChanged?.call(false);

    _emitChange();
    widget.onFocusChanged?.call(false);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final double availW = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : media.size.width;
        final double rawH = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : media.size.height;
        final double availH = (rawH - media.padding.vertical).clamp(
          0.0,
          double.infinity,
        );

        if (availW <= 0 || availH <= 0) return const SizedBox.shrink();

        const double eps = 0.5;
        const double baselineTextHeight = HonooBuilder.baselineTextHeight;
        final double editingToolbarHeight = _showImageEditingToolbar
            ? HonooBuilder.baselineEditingToolbarHeight
            : 0;
        final double baselineTotalHeight =
            HonooBuilder.baselineTotalHeight + editingToolbarHeight;

        final double scaleW = availW / HonooBuilder.baselineImageSize;
        final double scaleH = (availH - eps) / baselineTotalHeight;
        final double scale = math
            .min(scaleW, scaleH)
            .clamp(0.0, double.infinity);

        final double displayW = HonooBuilder.baselineImageSize * scale;
        final double displayH = baselineTotalHeight * scale;

        final content = Center(
          child: SizedBox(
            width: displayW,
            height: displayH,
            child: FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                width: HonooBuilder.baselineImageSize,
                height: baselineTotalHeight,
                child: Column(
                  key: const Key('honoo-composed-content'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_showImageEditingToolbar)
                      SizedBox(
                        height: editingToolbarHeight,
                        width: HonooBuilder.baselineImageSize,
                        child: _buildImageEditingControls(scale),
                      ),

                    RepaintBoundary(
                      key: _captureKey,
                      child: SizedBox(
                        key: const Key('honoo-export-content'),
                        width: HonooBuilder.baselineImageSize,
                        height: HonooBuilder.baselineTotalHeight,
                        child: Column(
                          children: [
                            // ===== TEXT AREA =====
                            SizedBox(
                              height: baselineTextHeight,
                              width: HonooBuilder.baselineImageSize,
                              child: _buildTextArea(
                                HonooBuilder.baselineImageSize,
                              ),
                            ),

                            const SizedBox(height: HonooBuilder.baselineGap),

                            // ===== IMAGE AREA =====
                            ClipRRect(
                              borderRadius: BorderRadius.circular(5),
                              child: Container(
                                width: HonooBuilder.baselineImageSize,
                                height: HonooBuilder.baselineImageSize,
                                color: Colors
                                    .white, // cornice neutra come “foglio”
                                child: _buildImageArea(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        if (_showImageEditingToolbar) return content;
        return ContentEditFrame(
          width: displayW,
          height: displayH,
          onImage: _pickImage,
          onText: _editText,
          onSave: _publicImageUrl.isNotEmpty ? _saveEditedTextAndHonoo : null,
          child: content,
        );
      },
    );
  }

  Widget _buildTextArea(double imageSize) {
    return Container(
      key: const Key('honoo-text-area'),
      padding: EdgeInsets.zero,
      decoration: BoxDecoration(
        color: HonooColor.tertiary,
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Builder(
        builder: (context) {
          final textStyle = GoogleFonts.arvo(
            color: HonooColor.onTertiary,
            fontSize: 18,
            height: 1.4,
          );

          return Stack(
            children: [
              Positioned.fill(
                child: WidthLimitedMultilineField(
                  controller: _textCtrl,
                  focusNode: _textFocus,
                  style: textStyle,
                  maxLines: 5,
                  maxCharsPerLine: 32,
                  onChanged: () => setState(() {}),
                  preInputFormatters: const [
                    TypographicSubstitutionsFormatter(),
                  ],
                  additionalInputFormatters: const [
                    VisibleLengthLimitingTextInputFormatter(
                      HonooBuilder.maxTextCharacters,
                    ),
                  ],
                  horizontalPadding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
                  decoration: InputDecoration(
                    hintText: _textCtrl.text.isEmpty
                        ? (widget.textHint ?? 'Scrivi qui il tuo testo')
                        : null,
                    hintStyle: textStyle.copyWith(
                      color: HonooColor.background,
                      height: 1.2,
                    ),
                    border: InputBorder.none,
                    isCollapsed: true,
                  ),
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  autofocus: !_imageConfirmed && _imageBytes == null,
                  readOnly: _isUploadingFinal,
                  expands: true,
                  scrollPhysics: const ClampingScrollPhysics(),
                  cursorColor: Colors.black,
                  cursorWidth: 3,
                  cursorRadius: const Radius.circular(0),
                  enableInlineFormatting: true,
                ),
              ),
              if (widget.showCharacterCounter)
                Positioned(
                  bottom: 8,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Builder(
                      builder: (_) {
                        final int used = InlineTextFormatting.visibleLength(
                          _textCtrl.text,
                        );
                        final Color color =
                            used >= HonooBuilder.maxTextCharacters
                            ? HonooColor.secondary
                            : (used >= 120
                                  ? Colors.orangeAccent
                                  : HonooColor.onTertiary.withValues(
                                      alpha: 0.75,
                                    ));
                        return Text(
                          '$used/${HonooBuilder.maxTextCharacters}',
                          key: const Key('honoo-editor-character-counter'),
                          textAlign: TextAlign.center,
                          style: GoogleFonts.arvo(
                            color: color,
                            fontSize: 12,
                            height: 1.0,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              if (widget.onDownloadTap != null && widget.showDownloadButton)
                Positioned(
                  top: 8,
                  right: 8,
                  child: TextBoxDownloadButton(
                    onPressed: widget.onDownloadTap!,
                    tooltip: 'download',
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildImageEditingControls(double canvasScale) {
    final double confirmIconSize = widget.imageConfirmIconDisplaySize == null
        ? 44
        : HonooBuilder.baselineIconSizeForDisplay(
            widget.imageConfirmIconDisplaySize!,
            canvasScale,
          );
    final double resolvedConfirmIconSize = confirmIconSize
        .clamp(26, 34)
        .toDouble();
    final double secondaryActionIconSize = resolvedConfirmIconSize * 0.82;

    return SizedBox(
      key: const Key('honoo-image-editing-controls'),
      child: IgnorePointer(
        ignoring: _isUploadingFinal,
        child: Opacity(
          opacity: _isUploadingFinal ? 0.65 : 1,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Tooltip(
                    message: 'Sostituisci immagine',
                    preferBelow: false,
                    child: IconButton(
                      key: const Key('honoo-replace-editing-image'),
                      onPressed: _pickImage,
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
                  child: _isUploadingFinal
                      ? LoadingSpinner(
                          size: resolvedConfirmIconSize * 0.72,
                          color: HonooColor.onBackground,
                        )
                      : Tooltip(
                          message: 'Salva honoo',
                          preferBelow: false,
                          child: IconButton(
                            key: const Key('honoo-save'),
                            onPressed: _saveEditedTextAndHonoo,
                            padding: EdgeInsets.zero,
                            icon: SvgPicture.asset(
                              'assets/icons/ok.svg',
                              width: resolvedConfirmIconSize,
                              height: resolvedConfirmIconSize,
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
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Tooltip(
                    message: 'Modifica testo',
                    preferBelow: false,
                    child: IconButton(
                      key: const Key('honoo-edit-text'),
                      onPressed: _editText,
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
      ),
    );
  }

  Widget _buildImageArea() {
    return GestureDetector(
      key: const Key('honoo-image-area'),
      onTap: _imageBytes == null
          ? _pickImage
          : (_isEditingText && !_imageConfirmed ? _returnToImageEditor : null),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: Container(
          color: HonooColor.tertiary,
          child: _imageBytes == null && _publicImageUrl.isNotEmpty
              ? Image.network(_publicImageUrl, fit: BoxFit.cover)
              : _imageBytes == null
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Carica qui la tua immagine',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.arvo(
                        color: HonooColor.background,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 22),
                    SvgPicture.asset(
                      'assets/icons/immagine.svg',
                      width: 48,
                      height: 48,
                      colorFilter: const ColorFilter.mode(
                        HonooColor.primary,
                        BlendMode.srcIn,
                      ),
                    ),
                  ],
                )
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    // ✅ se confermata: mostra la PNG zoommata catturata
                    if (_imageConfirmed && _confirmedPreviewBytes != null)
                      Image.memory(
                        _confirmedPreviewBytes!,
                        fit: BoxFit.contain,
                        alignment: Alignment.center,
                      )
                    else
                      // ✅ PREVIEW (NO doppio zoom):
                      //    - niente FittedBox
                      //    - l’unico “fit” è sull’Image
                      RepaintBoundary(
                        key: _imageBoundaryKey,
                        child: CoverTransformImage(
                          image: MemoryImage(_imageBytes!),
                          transformationController: _imageController,
                          minScale: _imageMinScale,
                          maxScale: _imageMaxScale,
                        ),
                      ),
                    if (!_imageConfirmed && !_hideEditorActionsForCapture)
                      Positioned(
                        top: 10,
                        left: 18,
                        right: 18,
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 2,
                            activeTrackColor: HonooColor.background,
                            inactiveTrackColor: HonooColor.background
                                .withValues(alpha: 0.28),
                            thumbColor: Colors.white,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 7,
                            ),
                            overlayColor: Colors.white.withValues(alpha: 0.18),
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 14,
                            ),
                          ),
                          child: Slider(
                            key: const Key('honoo-image-zoom-slider'),
                            value: _imageScale,
                            min: _imageMinScale,
                            max: _imageMaxScale,
                            divisions: 40,
                            onChanged: _updateImageScale,
                          ),
                        ),
                      ),
                    if (_imageConfirmed && !_hideEditorActionsForCapture)
                      Positioned(
                        left: 12,
                        bottom: 12,
                        child: TextButton.icon(
                          key: const Key('honoo-replace-confirmed-image'),
                          onPressed: _pickImage,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor: Colors.black.withValues(
                              alpha: 0.55,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: SvgPicture.asset(
                            'assets/icons/immagine.svg',
                            width: 20,
                            height: 20,
                            colorFilter: const ColorFilter.mode(
                              Colors.white,
                              BlendMode.srcIn,
                            ),
                          ),
                          label: Text(
                            'Sostituisci immagine',
                            style: GoogleFonts.arvo(fontSize: 13),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

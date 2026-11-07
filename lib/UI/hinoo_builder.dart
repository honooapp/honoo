// lib/UI/HinooBuilder/hinoobuilder.dart
// ============================================================================
// HinooBuilder – due pulsanti bianchi in ROW sopra il canvas,
// Canvas 9:16 in Card (r=5), anteprime SOTTO al canvas.
// Nessun overlay sopra il canvas o le anteprime.
// ============================================================================

import 'dart:ui' as ui;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:honoo/Utility/inline_text_formatting.dart';
import 'package:flutter/rendering.dart';

import 'HinooBuilder/overlays/cambia_sfondo.dart';
import 'HinooBuilder/overlays/colore_testo.dart';
import 'HinooBuilder/overlays/scrivi_hinoo.dart';
import 'package:image_picker/image_picker.dart';
import 'package:honoo/Services/supabase_provider.dart';
import '../Services/hinoo_storage_uploader.dart';
import 'package:honoo/Widgets/honoo_dialogs.dart';
import 'package:honoo/Widgets/gallery_save_dialog.dart';
import 'package:honoo/Widgets/cover_transform_image.dart';
import 'package:honoo/Utility/heic_converter.dart' as heic;
import 'package:honoo/Utility/image_upload_encoder.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:honoo/web/heic_converter.dart' as heicweb;
import 'package:honoo/UI/HinooBuilder/dialogs/anteprima_png.dart';
import 'package:honoo/UI/HinooBuilder/dialogs/download_hinoo_dialog.dart';
import 'package:honoo/UI/HinooBuilder/services/download_saver.dart';
import 'package:honoo/Widgets/text_box_download_button.dart';
import 'package:honoo/UI/HinooBuilder/dialogs/name_hinoo_dialog.dart';
import 'package:honoo/UI/hinoo_export_spec.dart';
import 'package:honoo/UI/hinoo_typography.dart';
import 'package:honoo/Entities/hinoo.dart';

// Import coerenti con la struttura HinooBuilder

// Wizard step (solo uno alla volta)
enum _WizardStep { changeBg, pickColor, writeText }

// ============================================================================
// Widget pubblico (callback opzionali)
// ============================================================================
class HinooBuilder extends StatefulWidget {
  const HinooBuilder({
    super.key,
    this.onHinooChanged, // notifica il draft quando cambia qualcosa
    this.onPngExported, // PNG generato (anteprima)
    this.hintText,
    this.backgroundPromptText,
    this.initialDraft,
    this.centerTextVertically = true,
    this.useCampanelloPadding = false,
    this.downloadContentName = 'hinoo',
  });

  final ValueChanged<dynamic>? onHinooChanged;
  final ValueChanged<Uint8List>? onPngExported;
  final String? hintText;
  final String? backgroundPromptText;
  final HinooDraft? initialDraft;
  final bool centerTextVertically;
  final bool useCampanelloPadding;
  final String downloadContentName;

  @override
  State<HinooBuilder> createState() => _HinooBuilderState();
}

// ============================================================================
// Stato/Orchestrazione
// ============================================================================
class _HinooBuilderState extends State<HinooBuilder> {
  // Core
  final GlobalKey _captureKey =
      GlobalKey(); // SOLO il canvas è sotto questa key
  final FormattedTextEditingController _textController =
      FormattedTextEditingController();
  final FocusNode _textFocus = FocusNode();

  // Modello semplificato (sostituisci "dynamic" con il tuo tipo Slide/Page)
  final List<dynamic> _pages = <dynamic>[];
  int _current = 0;

  // Trasformazioni testo sul canvas
  double _canvasHeight = 0;

  // Stato UI
  Uint8List? _localBgPreviewBytes; // preview locale dello sfondo
  String? _bgPublicUrl; // URL pubblico su storage
  Color _txtColor = Colors.white;
  _WizardStep _step = _WizardStep.changeBg;
  bool _bgChosen = false; // abilita bottone OK per procedere
  bool _isUploadingBg = false;
  static const double _bgMinScale = 1.0;
  static const double _bgMaxScale = 5.0;
  // min scale effettivo per l'interazione: almeno il fill iniziale
  double _bgMinInteractiveScale = _bgMinScale;
  final TransformationController _bgController = TransformationController();
  Matrix4? _bgLockedMatrix;
  double _bgScale = _bgMinScale;

  // Export/anteprima
  Uint8List? _lastPreviewBytes;
  String? _exportFilenameHint;
  String? _lastFileBaseName;

  // ========================================================================
  // Lifecycle
  // ========================================================================
  @override
  void initState() {
    super.initState();
    final HinooDraft? initialDraft = widget.initialDraft;
    if (initialDraft != null && initialDraft.pages.isNotEmpty) {
      _pages.addAll(
        initialDraft.pages.map(
          (slide) => {
            'text': slide.text,
            'bgUrl': slide.backgroundImage,
            'textColor': (slide.isTextWhite ? Colors.white : Colors.black)
                .toARGB32(),
            if (slide.bgTransform != null)
              'bgTransform': List<double>.from(slide.bgTransform!)
            else
              'bgTransform':
                  (Matrix4.identity()
                        ..translateByDouble(
                          slide.bgOffsetX,
                          slide.bgOffsetY,
                          0,
                          1,
                        )
                        ..scaleByDouble(
                          slide.bgScale,
                          slide.bgScale,
                          slide.bgScale,
                          1,
                        ))
                      .storage
                      .toList(),
          },
        ),
      );
      _applySlideState(_pages.first);
      _step = _WizardStep.writeText;
      _bgMinInteractiveScale = _bgScale;
    } else if (_pages.isEmpty) {
      _pages.add(_createEmptySlide());
    }
    _textController.addListener(
      () => _onCanvasTextChanged(_textController.text),
    );
    _bgController.addListener(_handleBgTransform);
    _bgScale = _extractScaleFromMatrix(_bgController.value);
  }

  @override
  void dispose() {
    _textController.removeListener(() {}); // safety no-op
    _textController.dispose();
    _textFocus.dispose();
    _bgController.removeListener(_handleBgTransform);
    _bgController.dispose();
    super.dispose();
  }

  void _handleBgTransform() {
    final Matrix4 currentMatrix = _bgController.value.clone();
    final double newScale = _extractScaleFromMatrix(currentMatrix);

    if (_bgChosen) {
      setState(() {
        _bgScale = newScale;
        for (var i = 0; i < _pages.length; i++) {
          _pages[i] = _copySlideWithBgTransform(_pages[i], currentMatrix);
        }
      });
      _notifyChanged();
    } else if ((newScale - _bgScale).abs() > 0.005) {
      setState(() => _bgScale = newScale);
    }
  }

  double _extractScaleFromMatrix(Matrix4 matrix) {
    final Float64List values = matrix.storage;
    final double sx = values[0].abs();
    final double sy = values[5].abs();
    double raw;
    if (sx > 0 && sy > 0) {
      raw = (sx + sy) / 2;
    } else if (sx > 0) {
      raw = sx;
    } else if (sy > 0) {
      raw = sy;
    } else {
      raw = _bgMinScale;
    }
    return raw.clamp(_bgMinScale, _bgMaxScale).toDouble();
  }

  void _updateBgScale(double scale) {
    final double clamped = scale.clamp(_bgMinScale, _bgMaxScale).toDouble();
    final Matrix4 current = _bgController.value.clone();
    final Float64List values = current.storage;
    final double tx = values[12];
    final double ty = values[13];
    final Matrix4 updated = Matrix4.identity()
      ..setEntry(0, 0, clamped)
      ..setEntry(1, 1, clamped)
      ..setTranslationRaw(tx, ty, 0);
    _bgController.value = updated;
  }

  void _applySlideState(dynamic slide) {
    final String text = _extractTextFromSlide(slide);
    if (_textController.text != text) {
      _textController.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }

    final Color? textColor = _extractTextColorFromSlide(slide);
    if (textColor != null) {
      _txtColor = textColor;
    }

    final String? bgUrl = _extractBgUrlFromSlide(slide);
    _bgPublicUrl = (bgUrl != null && bgUrl.isNotEmpty) ? bgUrl : null;

    final Matrix4? transform = _extractBgTransformFromSlide(slide);
    if (transform != null) {
      _bgLockedMatrix = transform.clone();
      _bgController.value = transform.clone();
    } else if (_bgLockedMatrix != null) {
      _bgLockedMatrix = null;
      _bgController.value = Matrix4.identity();
    }

    _bgScale = _extractScaleFromMatrix(_bgController.value);
    _bgChosen =
        _localBgPreviewBytes != null ||
        (_bgPublicUrl != null && _bgPublicUrl!.isNotEmpty);
  }

  void _resetToBlankState() {
    _textController.clear();
    _txtColor = Colors.white;
    _localBgPreviewBytes = null;
    _bgPublicUrl = null;
    _bgLockedMatrix = null;
    _bgController.value = Matrix4.identity();
    _bgScale = _bgMinScale;
    _bgChosen = false;
    _step = _WizardStep.changeBg;
  }

  Future<bool> _openDownloadDialog() async {
    if (!mounted || _pages.isEmpty) return false;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const DownloadHinooDialog(),
    );
    if (confirmed != true) return false;
    if (!mounted) return false;
    final String? chosenName = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (_) => NameHinooDialog(initialValue: _lastFileBaseName),
    );
    final String? trimmed = chosenName?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return false;
    }
    if (!mounted) return false;
    _lastFileBaseName = trimmed;
    return _downloadHinoo(baseName: trimmed);
  }

  Future<bool> _downloadHinoo({String? baseName}) async {
    if (!mounted) return false;
    final BuildContext currentContext = context;
    final HinooExportMode exportMode = _resolveExportMode();
    bool progressVisible = false;
    final NavigatorState rootNavigator = Navigator.of(
      currentContext,
      rootNavigator: true,
    );
    Future<void> dismissProgressDialogIfNeeded() async {
      if (!mounted || !progressVisible) {
        return;
      }
      if (rootNavigator.canPop()) {
        rootNavigator.pop();
      }
      progressVisible = false;
    }

    if (mounted) {
      progressVisible = true;
      // ignore: unawaited_futures
      showDialog(
        context: currentContext,
        barrierDismissible: false,
        builder: (_) => const DownloadProgressDialog(),
      ).whenComplete(() => progressVisible = false);
    }

    final List<DownloadImage> images = <DownloadImage>[];
    final DownloadSaver saver = getDownloadSaver();
    final String fileBaseName = _prepareFileBaseName(baseName);

    try {
      await _waitForNextFrame();
      final Uint8List? bytes = await TextBoxDownloadButton.hideWhileCapturing(
        () => _captureCurrentCanvasBytes(exportMode: exportMode),
      );
      if (bytes != null) {
        final String filename = _resolveFileName(fileBaseName);
        images.add(DownloadImage(filename: filename, bytes: bytes));
      }

      if (images.isEmpty) {
        throw Exception('Impossibile generare le immagini.');
      }

      final DownloadSaveResult result = await saver.save(
        images,
        message: 'hinoo creati con honoo',
      );
      await dismissProgressDialogIfNeeded();
      if (!currentContext.mounted) return false;
      await showDownloadSaveResult(
        context: currentContext,
        contentName: widget.downloadContentName,
        result: result,
      );
      return true;
    } catch (e) {
      if (mounted) {
        await dismissProgressDialogIfNeeded();
        if (!currentContext.mounted) return false;
        showHonooToast(currentContext, message: 'Errore download: $e');
      }
      return false;
    } finally {
      if (mounted) {
        await dismissProgressDialogIfNeeded();
      }
    }
  }

  Future<Uint8List?> _captureCurrentCanvasBytes({
    HinooExportMode exportMode = HinooExportMode.mobile,
  }) async {
    try {
      final RenderRepaintBoundary? boundary =
          _captureKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final HinooExportSpec exportSpec = getHinooExportSpec(exportMode);
      // Limita il pixel ratio per evitare OOM nella generazione PNG
      final Size logical = boundary.size;
      const double maxOut = 2560.0; // lato lungo massimo del PNG esportato
      final double longEdge = logical.width > logical.height
          ? logical.width
          : logical.height;
      double effectivePixelRatio = exportSpec.pixelRatio;
      if (longEdge > 0) {
        final double maxPr = maxOut / longEdge;
        if (effectivePixelRatio > maxPr) {
          effectivePixelRatio = maxPr.clamp(1.0, effectivePixelRatio);
        }
      }
      assert(() {
        debugPrint(
          'Hinoo export boundary size: ${boundary.size.width}x${boundary.size.height}',
        );
        debugPrint(
          'Hinoo export mode: ${exportSpec.mode} ratio: $effectivePixelRatio',
        );
        return true;
      }());
      final ui.Image image = await boundary.toImage(
        pixelRatio: effectivePixelRatio,
      );
      try {
        assert(() {
          debugPrint('Hinoo export image size: ${image.width}x${image.height}');
          return true;
        }());
        final ByteData? byteData = await image.toByteData(
          format: ui.ImageByteFormat.png,
        );
        return byteData?.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    } catch (e) {
      debugPrint('capture canvas error: $e');
      return null;
    }
  }

  HinooExportMode _resolveExportMode() {
    final double logicalWidth = MediaQuery.of(context).size.width;
    return resolveHinooExportMode(logicalWidth: logicalWidth, isWeb: kIsWeb);
  }

  Future<void> _waitForNextFrame() async {
    await Future<void>.delayed(Duration.zero);
    await WidgetsBinding.instance.endOfFrame;
  }

  Color? _extractTextColorFromSlide(dynamic slide) {
    if (slide is Map && slide['textColor'] is int) {
      return Color(slide['textColor'] as int);
    }
    return null;
  }

  String? _extractBgUrlFromSlide(dynamic slide) {
    if (slide is Map && slide['bgUrl'] is String) {
      final String value = slide['bgUrl'] as String;
      if (value.isNotEmpty) return value;
    }
    return null;
  }

  Matrix4? _extractBgTransformFromSlide(dynamic slide) {
    if (slide is Map) {
      final dynamic raw = slide['bgTransform'];
      if (raw is List && raw.length == 16) {
        final List<double> values = raw
            .map((dynamic e) => (e as num).toDouble())
            .toList();
        return Matrix4.fromList(values);
      }
    }
    return null;
  }

  // ========================================================================
  // Helpers / API pubbliche
  // ========================================================================
  void goToPublic(int index) => _goTo(index); // vai alla pagina i
  void addPagePublic() {} // hinoo a pagina singola
  void reorderPagesPublic(int oldIndex, int newIndex) {}

  void deleteCurrentPagePublic() => _deleteCurrentPage(); // già usata
  void clearContentPublic() => _clearContent();
  Future<void> openPreviewDialogPublic() => _openPreviewDialog();
  Future<bool> openDownloadDialogPublic() => _openDownloadDialog();
  Future<bool> downloadAllPagesPublic({String? baseName}) =>
      _downloadHinoo(baseName: baseName);
  Future<void> replaceBackgroundPublic() => _pickAndUploadBackground();
  void confirmBackgroundPublic() => _confirmBgAndLock();
  void editTextColorPublic() {
    if (!_bgChosen || _isUploadingBg) return;
    _textFocus.unfocus();
    setState(() => _step = _WizardStep.pickColor);
    _notifyChanged();
  }

  void editTextPublic() {
    setState(() => _step = _WizardStep.writeText);
    _textFocus.requestFocus();
    _notifyChanged();
  }

  String _prepareFileBaseName(String? raw) {
    const String fallback = 'hinoo';
    final String? source = raw ?? _lastFileBaseName;
    if (source == null) return fallback;
    String base = source.trim();
    if (base.isEmpty) return fallback;
    base = base.replaceAll(RegExp(r'\s+'), '_');
    base = base.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    if (base.isEmpty) return fallback;
    return base;
  }

  String _resolveFileName(String baseName) {
    return '$baseName.png';
  }

  dynamic exportDraft() {
    final Matrix4? currentTransform = _effectiveBgTransform();
    return {
      'pages': _pages, // sostituisci col tuo tipo slide/pagina
      'currentIndex': _current,
      'text': _textController.text,
      'textLength': InlineTextFormatting.visibleText(
        _textController.text,
      ).trim().length,
      'textColor': _txtColor.toARGB32(),
      'hasBg': _localBgPreviewBytes != null || _bgPublicUrl != null,
      'bgUrl': _bgPublicUrl,
      'bgTransform': currentTransform?.storage.toList(),
      'canvasHeight': _canvasHeight,
      'step': _step.name,
      'isUploadingBg': _isUploadingBg,
      // preview immediata per thumbnails quando non c'è ancora un URL pubblico
      'bgPreviewBytes': _localBgPreviewBytes,
    };
  }

  void _notifyChanged() {
    final cb = widget.onHinooChanged;
    if (cb != null) cb(exportDraft());
  }

  // ========================================================================
  // Build — ROW pulsanti sopra, canvas 9:16 al centro, anteprime sotto
  // ========================================================================
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double maxW = constraints.maxWidth;
        final double maxH = constraints.maxHeight;
        const double baselineW = HinooTypography.baselineCanvasWidth;
        const double baselineH = HinooTypography.baselineCanvasHeight;

        double scale = 1.0;
        if (maxW.isFinite && maxW > 0 && maxH.isFinite && maxH > 0) {
          scale = math.min(maxW / baselineW, maxH / baselineH);
        } else if (maxW.isFinite && maxW > 0) {
          scale = maxW / baselineW;
        } else if (maxH.isFinite && maxH > 0) {
          scale = maxH / baselineH;
        }
        if (!scale.isFinite || scale <= 0) {
          scale = 1.0;
        }

        final double displayW = baselineW * scale;
        final double displayH = baselineH * scale;

        _canvasHeight = baselineH;

        const BorderRadius canvasRadius = BorderRadius.all(Radius.circular(5));

        return Center(
          child: SizedBox(
            width: displayW,
            height: displayH,
            child: FittedBox(
              fit: BoxFit.contain,
              child: _buildLogicalCanvas(
                context,
                key: _captureKey,
                canvasRadius: canvasRadius,
              ),
            ),
          ),
        );
      },
    );
  }

  // ========================================================================
  // Canvas (SOLO contenuto esportabile) — dentro la Card
  // ========================================================================
  Widget _buildLogicalCanvas(
    BuildContext context, {
    required Key key,
    required BorderRadius canvasRadius,
  }) {
    return RepaintBoundary(
      key: key,
      child: SizedBox(
        width: HinooTypography.baselineCanvasWidth,
        height: HinooTypography.baselineCanvasHeight,
        child: Card(
          elevation: 0,
          margin: EdgeInsets.zero,
          color: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: canvasRadius),
          clipBehavior: Clip.antiAlias,
          child: _buildCanvasContents(context),
        ),
      ),
    );
  }

  Widget _buildCanvasContents(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Sfondo: usa sempre un unico percorso (asset di default oppure preview selezionata)
        Builder(
          builder: (_) {
            final ImageProvider background = _localBgPreviewBytes != null
                ? MemoryImage(_localBgPreviewBytes!)
                : (_bgPublicUrl != null && _bgPublicUrl!.isNotEmpty
                      ? NetworkImage(_bgPublicUrl!)
                      : const AssetImage(
                          'assets/images/hinoo_default_1080x1920.png',
                        ));
            final bool interactive =
                (_step == _WizardStep.changeBg &&
                _bgChosen &&
                _localBgPreviewBytes != null);
            if (!interactive && _bgLockedMatrix != null) {
              _bgController.value = _bgLockedMatrix!.clone();
            }
            return CoverTransformImage(
              image: background,
              transformationController: _bgController,
              interactive: interactive,
              minScale: _bgMinInteractiveScale,
              maxScale: _bgMaxScale,
            );
          },
        ),

        // Overlays sequenziali: uno solo alla volta
        if (_step == _WizardStep.changeBg) ...[
          CambiaSfondoOverlay(
            onTapChange: _pickAndUploadBackground,
            promptText: widget.backgroundPromptText,
            showControls: _bgChosen && _localBgPreviewBytes != null,
            isUploading: _isUploadingBg,
            currentScale: _bgScale,
            minScale: _bgMinInteractiveScale,
            maxScale: _bgMaxScale,
            onScaleChanged: _bgChosen ? _updateBgScale : null,
            useCompactControls: true,
          ),
        ] else if (_step == _WizardStep.pickColor)
          ColoreTestoOverlay(
            onPick: (c) {
              setState(() {
                _txtColor = c;
                // Propaga il colore su TUTTE le pagine per anteprime fedeli
                for (var i = 0; i < _pages.length; i++) {
                  _pages[i] = _copySlideWithTextColor(
                    _pages[i],
                    _txtColor.toARGB32(),
                  );
                }
                _step = _WizardStep.writeText;
              });
              _scheduleAutosave();
              FocusScope.of(context).requestFocus(_textFocus);
              _notifyChanged();
            },
          )
        else if (_step == _WizardStep.writeText)
          ScriviHinooOverlay(
            controller: _textController,
            focusNode: _textFocus,
            textColor: _txtColor,
            hintText: widget.hintText,
            centerTextVertically: widget.centerTextVertically,
            useCampanelloPadding: widget.useCampanelloPadding,
          ),
      ],
    );
  }

  // ========================================================================
  // Gestione testo/pagine/riordino
  // ========================================================================
  void _onCanvasTextChanged(String v) {
    final s = _pages[_current];
    final updated = _copySlideWithText(s, v);
    setState(() => _pages[_current] = updated);
    _scheduleAutosave();
    _notifyChanged();
  }

  void _goTo(int index) {
    if (index < 0 || index >= _pages.length) return;
    setState(() {
      _current = index;
      _applySlideState(_pages[_current]);
    });
  }

  // Elimina pagina corrente (con conferma)
  Future<void> _deleteCurrentPage() async {
    if (_pages.isEmpty) return;

    final bool? ok = await showHonooDeleteDialog(
      context,
      target: HonooDeletionTarget.hinoo,
    );

    if (ok != true) return;

    final int removedIndex = _current;

    setState(() {
      if (_pages.length > 1) {
        _pages.removeAt(removedIndex);
        final int newIndex = removedIndex > 0 ? removedIndex - 1 : 0;
        _current = newIndex.clamp(0, _pages.length - 1);
        _applySlideState(_pages[_current]);
      } else {
        _resetToBlankState();
        _pages[0] = _createEmptySlide();
        _current = 0;
      }
    });

    _scheduleAutosave();
    _notifyChanged();
  }

  void _clearContent() {
    if (_pages.isEmpty) {
      _pages.add(_createEmptySlide());
    }

    setState(() {
      _resetToBlankState();
      _pages
        ..clear()
        ..add(_createEmptySlide());
      _current = 0;
    });

    _scheduleAutosave();
    _notifyChanged();
  }

  // ========================================================================
  // Export PNG + Dialog
  // ========================================================================
  Future<void> _openPreviewDialog() async {
    await _renderCanvasAsPng();
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => AnteprimaPNG(
        previewBytes: _lastPreviewBytes,
        filenameHint: _exportFilenameHint,
        onSavePng: _exportCanvasPng,
        onClose: () => Navigator.of(context).pop(),
      ),
    );
  }

  Future<void> _renderCanvasAsPng() async {
    final Uint8List? bytes = await _captureCurrentCanvasBytes(
      exportMode: _resolveExportMode(),
    );
    if (bytes == null) return;
    setState(() {
      _lastPreviewBytes = bytes;
      _exportFilenameHint =
          'hinoo_${DateTime.now().millisecondsSinceEpoch}.png';
    });
    final ValueChanged<Uint8List>? cb = widget.onPngExported;
    if (cb != null) cb(bytes);
  }

  Future<void> _exportCanvasPng() async {
    final bytes = _lastPreviewBytes;
    if (bytes == null || bytes.isEmpty) {
      debugPrint('Nessun PNG da esportare');
      return;
    }

    final saver = getDownloadSaver();
    final filename =
        _exportFilenameHint ??
        'hinoo_${DateTime.now().millisecondsSinceEpoch}.png';
    try {
      final DownloadSaveResult result = await saver.save([
        DownloadImage(filename: filename, bytes: bytes),
      ]);
      if (!mounted) return;
      await showDownloadSaveResult(
        context: context,
        contentName: widget.downloadContentName,
        result: result,
      );
    } catch (e) {
      debugPrint('Errore durante il salvataggio/condivisione: $e');
      if (mounted) {
        showHonooToast(context, message: 'Errore durante il salvataggio: $e');
      }
    } finally {
      if (mounted) {
        Navigator.of(context).maybePop();
      }
    }
  }

  // ========================================================================
  // Autosave/Notify – collega al tuo servizio
  // ========================================================================
  void _scheduleAutosave() {
    // debounce/save
  }

  void _confirmBgAndLock() {
    if (_isUploadingBg) {
      showHonooToast(context, message: 'Attendi il caricamento dello sfondo.');
      return;
    }
    if (!_bgChosen &&
        _localBgPreviewBytes == null &&
        (_bgPublicUrl == null || _bgPublicUrl!.isEmpty)) {
      showHonooToast(
        context,
        message: 'Carica l\'immagine dello sfondo prima di proseguire.',
      );
      return;
    }
    setState(() {
      _bgLockedMatrix = _bgController.value.clone();
      _bgScale = _extractScaleFromMatrix(_bgLockedMatrix!);
      // Propaga la trasformazione a tutte le pagine
      for (var i = 0; i < _pages.length; i++) {
        _pages[i] = _copySlideWithBgTransform(_pages[i], _bgLockedMatrix!);
      }
      _step = _WizardStep.pickColor;
    });
    _notifyChanged();
    _scheduleAutosave();
  }

  // ========================================================================
  // Cambio sfondo – picking + upload storage (come HonooBuilder, adattato 9:16)
  // ========================================================================
  Future<void> _pickAndUploadBackground() async {
    try {
      final picker = ImagePicker();
      final XFile? selected = await picker.pickImage(
        source: ImageSource.gallery,
      );
      if (selected == null) return;

      // Preview locale immediata
      Uint8List bytes = await selected.readAsBytes();
      if (kIsWeb) {
        try {
          // Web: preferisci WEBP, fallback PNG
          final converted = await heicweb.convertHeicToWebSafe(
            bytes,
            selected.name,
          );
          if (converted != null && converted.isNotEmpty) {
            bytes = converted;
          } else {
            final String lower = selected.name.toLowerCase();
            if (lower.endsWith('.heic') || lower.endsWith('.heif')) {
              // HEIC non convertibile dal browser → notifica utente e interrompi
              if (mounted) {
                showHonooToast(
                  context,
                  message: 'Formato HEIC non supportato dal browser',
                );
              }
              setState(() => _isUploadingBg = false);
              return; // non procedere con upload
            }
          }
        } catch (e) {
          debugPrint('HEIC web conversion failed (hinoo): $e');
          final String lower = selected.name.toLowerCase();
          if (lower.endsWith('.heic') || lower.endsWith('.heif')) {
            if (mounted) {
              showHonooToast(
                context,
                message: 'Formato HEIC non supportato dal browser',
              );
            }
            setState(() => _isUploadingBg = false);
            return;
          }
        }
      } else {
        final name = (selected.name).toLowerCase();
        if (name.endsWith('.heic') || name.endsWith('.heif')) {
          final converted = await heic.heicToPng(bytes);
          if (converted != null && converted.isNotEmpty) {
            bytes = converted;
          }
        }
      }
      final Matrix4 initialMatrix = await _fitBackgroundToCanvas(bytes);
      final double initialScale = _extractScaleFromMatrix(initialMatrix);
      setState(() {
        _step = _WizardStep.changeBg;
        _localBgPreviewBytes = bytes;
        _bgChosen = true; // abilita OK per procedere
        _bgLockedMatrix = null;
        _bgScale = initialScale;
        _bgMinInteractiveScale = initialScale;
        _isUploadingBg = true;
      });
      _bgController.value = initialMatrix;

      await _persistBgUrl(bytes);
      if (!mounted) return;
      setState(() {
        _isUploadingBg = false;
      });
      _notifyChanged();
    } catch (e) {
      debugPrint('Errore cambio sfondo: $e');
      if (mounted) {
        setState(() {
          _isUploadingBg = false;
        });
      }
      if (mounted) {
        showHonooToast(context, message: 'Errore sfondo: $e');
      }
    }
  }

  Future<void> _persistBgUrl(Uint8List bytes) async {
    try {
      final client = SupabaseProvider.client;
      final user = client.auth.currentUser;
      if (user == null) {
        setState(() {
          _bgPublicUrl = null;
          _isUploadingBg = false;
        });
        return; // opzionale: consenti preview locale senza upload
      }

      // Normalizza JPEG/PNG/WebP (e gli HEIC già convertiti) in un JPEG
      // orientato e limitato: evita il limite Storage con foto moderne da
      // telefono/tablet e rende identico il comportamento su web e mobile.
      final encoded = await encodeImageForUpload(bytes);
      final Uint8List toUpload = encoded.bytes;
      final String finalExt = encoded.extension;

      final url = await HinooStorageUploader.uploadBackground(
        bytes: toUpload,
        ext: finalExt,
        userId: user.id,
      );
      setState(() {
        _bgPublicUrl = url;
      });

      // Propaga su tutte le pagine esistenti
      setState(() {
        for (var i = 0; i < _pages.length; i++) {
          _pages[i] = _copySlideWithBgUrl(_pages[i], url);
        }
      });
      _notifyChanged();
      _scheduleAutosave();
    } catch (e) {
      debugPrint('Upload sfondo fallito: $e');
      if (mounted) {
        setState(() {
          _bgPublicUrl = null;
          _isUploadingBg = false;
        });
        if (kIsWeb && e.toString().toLowerCase().contains('heic')) {
          showHonooToast(
            context,
            message: 'Formato HEIC non supportato dal browser',
          );
        } else {
          showHonooToast(
            context,
            message: 'Caricamento sfondo fallito. Riprova.',
          );
        }
      }
    }
  }

  Future<Matrix4> _fitBackgroundToCanvas(Uint8List bytes) async {
    try {
      // Verifica che i byte siano decodificabili. Il riempimento e il
      // centraggio sono gia applicati da Image con BoxFit.cover: aggiungere
      // qui un secondo fit basato sui pixel originali spostava la fotografia.
      await decodeImageFromList(bytes);
      return Matrix4.identity();
    } catch (error, stackTrace) {
      debugPrint('[HinooBuilder] image validation failed: $error\n$stackTrace');
      return Matrix4.identity();
    }
  }

  // rimosso: estensione non più necessaria (conversione sempre in PNG)

  // ========================================================================
  // Utility basiche per slide (se non hai un model)
  // ============================================================================
  dynamic _createEmptySlide() => {
    'text': '',
    'bgUrl': _bgPublicUrl,
    'textColor': _txtColor.toARGB32(),
    if (_effectiveBgTransform() != null)
      'bgTransform': _effectiveBgTransform()!.storage.toList(),
  };

  dynamic _copySlideWithText(dynamic slide, String text) {
    if (slide is Map) return {...slide, 'text': text};
    return slide;
  }

  dynamic _copySlideWithBgUrl(dynamic slide, String url) {
    if (slide is Map) return {...slide, 'bgUrl': url};
    return slide;
  }

  String _extractTextFromSlide(dynamic slide) {
    if (slide is Map && slide['text'] is String) return slide['text'] as String;
    return '';
  }

  dynamic _copySlideWithBgTransform(dynamic slide, Matrix4 m) {
    if (slide is Map) {
      return {...slide, 'bgTransform': m.storage.toList()};
    }
    return slide;
  }

  dynamic _copySlideWithTextColor(dynamic slide, int colorValue) {
    if (slide is Map) return {...slide, 'textColor': colorValue};
    return slide;
  }

  Matrix4? _effectiveBgTransform() {
    if (_bgLockedMatrix != null) {
      return _bgLockedMatrix!.clone();
    }
    if (!_bgChosen && _bgPublicUrl == null && _localBgPreviewBytes == null) {
      return null;
    }
    return _bgController.value.clone();
  }
}

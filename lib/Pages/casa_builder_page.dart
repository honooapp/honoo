import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:honoo/Entities/hinoo.dart';
import 'package:honoo/Services/hinoo_storage_uploader.dart';
import 'package:honoo/Services/house_invite_service.dart';
import 'package:honoo/Services/supabase_provider.dart';
import 'package:honoo/UI/HinooBuilder/overlays/cambia_sfondo.dart';
import 'package:honoo/UI/hinoo_typography.dart';
import 'package:honoo/Utility/honoo_colors.dart';
import 'package:honoo/Utility/responsive_layout.dart';
import 'package:honoo/Widgets/honoo_dialogs.dart';
import 'package:honoo/Widgets/loading_spinner.dart';
import 'package:honoo/Widgets/cover_transform_image.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';

import 'home_page.dart';

class CasaBuilderPage extends StatefulWidget {
  const CasaBuilderPage({
    super.key,
    required this.campanello,
    this.editingCampanelloId,
    this.initialHouseImageUrl,
    this.initialTransform,
  });

  final HinooDraft campanello;
  final String? editingCampanelloId;
  final String? initialHouseImageUrl;
  final List<double>? initialTransform;

  @override
  State<CasaBuilderPage> createState() => _CasaBuilderPageState();
}

class _CasaBuilderPageState extends State<CasaBuilderPage> {
  final HouseInviteService _inviteService = HouseInviteService();
  final TransformationController _imageController = TransformationController();
  ImageProvider? _imageProvider;
  Uint8List? _pickedImageBytes;
  String _pickedImageExtension = 'jpg';
  bool _isSaving = false;
  bool _isUploadingImage = false;
  bool _hasPickedImage = false;
  double _imageScale = 1.0;
  static const double _imageMinScale = 1.0;
  static const double _imageMaxScale = 5.0;
  String? _error;

  @override
  void initState() {
    super.initState();
    final String? initialUrl = widget.initialHouseImageUrl;
    if (initialUrl != null && initialUrl.isNotEmpty) {
      _imageProvider = NetworkImage(initialUrl);
    }
    final List<double>? initialTransform = widget.initialTransform;
    if (initialTransform != null && initialTransform.length == 16) {
      _imageController.value = Matrix4.fromList(initialTransform);
      _imageScale = _extractScaleFromMatrix(_imageController.value);
    }
    _imageController.addListener(_handleImageTransform);
  }

  @override
  void dispose() {
    _imageController.removeListener(_handleImageTransform);
    _imageController.dispose();
    super.dispose();
  }

  void _handleImageTransform() {
    final Matrix4 currentMatrix = _imageController.value.clone();
    final double newScale = _extractScaleFromMatrix(currentMatrix);
    if ((newScale - _imageScale).abs() > 0.005) {
      setState(() => _imageScale = newScale);
    }
  }

  double _extractScaleFromMatrix(Matrix4 matrix) {
    final Float64List values = matrix.storage;
    final double sx = values[0].abs();
    final double sy = values[5].abs();
    if (sx > 0 && sy > 0) {
      return ((sx + sy) / 2).clamp(_imageMinScale, _imageMaxScale).toDouble();
    }
    if (sx > 0) return sx.clamp(_imageMinScale, _imageMaxScale).toDouble();
    if (sy > 0) return sy.clamp(_imageMinScale, _imageMaxScale).toDouble();
    return _imageMinScale;
  }

  void _updateImageScale(double scale) {
    final double clamped = scale
        .clamp(_imageMinScale, _imageMaxScale)
        .toDouble();
    final Matrix4 current = _imageController.value.clone();
    final Float64List values = current.storage;
    final double currentScale = _extractScaleFromMatrix(current);
    final double safeScale = currentScale <= 0 ? _imageMinScale : currentScale;
    final double tx = values[12];
    final double ty = values[13];
    final double adjustedTx = tx * (safeScale / clamped);
    final double adjustedTy = ty * (safeScale / clamped);
    _imageController.value = Matrix4.identity()
      ..translateByDouble(adjustedTx, adjustedTy, 0, 1)
      ..scaleByDouble(clamped, clamped, clamped, 1);
  }

  void _nudgeImageScale(double delta) {
    _updateImageScale(_imageScale + delta);
  }

  void _resetImageTransform() {
    _imageController.value = Matrix4.identity();
    setState(() => _imageScale = _imageMinScale);
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final XFile? selected = await picker.pickImage(
        source: ImageSource.gallery,
      );
      if (selected == null) return;

      final Uint8List bytes = await selected.readAsBytes();
      setState(() {
        _imageProvider = MemoryImage(bytes);
        _pickedImageBytes = bytes;
        final extension = selected.name.split('.').last.toLowerCase();
        _pickedImageExtension =
            {'jpg', 'jpeg', 'png', 'webp'}.contains(extension)
            ? extension
            : 'jpg';
        _imageScale = _imageMinScale;
        _hasPickedImage = true;
      });
      _resetImageTransform();
    } catch (e) {
      if (!mounted) return;
      showHonooToast(context, message: 'Errore immagine: $e');
    }
  }

  Future<void> _saveCasa() async {
    if (_isSaving || _isUploadingImage) return;
    if (_imageProvider == null) {
      showHonooToast(
        context,
        message: 'Carica prima un\'immagine per la tua casa.',
      );
      return;
    }
    setState(() {
      _isSaving = true;
      _error = null;
    });
    String? newlyUploadedImageUrl;
    String? authenticatedUserId;
    try {
      final user = SupabaseProvider.client.auth.currentUser;
      if (user == null) {
        throw Exception('Utente non autenticato.');
      }
      authenticatedUserId = user.id;

      String imageUrl = widget.initialHouseImageUrl ?? '';
      if (_hasPickedImage || imageUrl.isEmpty) {
        setState(() => _isUploadingImage = true);
        final Uint8List? imageBytes = _pickedImageBytes;
        if (imageBytes == null || imageBytes.isEmpty) {
          throw Exception('Impossibile leggere l\'immagine della casa.');
        }
        imageUrl = await HinooStorageUploader.uploadBackground(
          bytes: imageBytes,
          ext: _pickedImageExtension,
          userId: user.id,
          // L'immagine originale può essere pesante e sui collegamenti più
          // lenti può richiedere più dei 15 secondi usati dagli upload normali.
          writeTimeout: const Duration(minutes: 1),
        );
        newlyUploadedImageUrl = imageUrl;
        setState(() => _isUploadingImage = false);
      }

      final String? editingId = widget.editingCampanelloId;
      if (editingId != null && editingId.isNotEmpty) {
        await _inviteService.updateHouse(
          campanelloHinooId: editingId,
          houseImageUrl: imageUrl,
          bgTransform: _imageController.value.storage.toList(),
        );
      } else {
        await _inviteService.createHouseWithCampanello(
          campanello: widget.campanello,
          houseImageUrl: imageUrl,
          bgTransform: _imageController.value.storage.toList(),
        );
      }

      final oldImageUrl = widget.initialHouseImageUrl;
      if (newlyUploadedImageUrl != null &&
          oldImageUrl != null &&
          oldImageUrl.isNotEmpty &&
          oldImageUrl != newlyUploadedImageUrl) {
        try {
          await HinooStorageUploader.deleteBackgroundUrl(
            url: oldImageUrl,
            userId: user.id,
          );
        } catch (cleanupError) {
          debugPrint('[CasaBuilder] old image cleanup failed: $cleanupError');
        }
      }

      if (!mounted) return;
      showHonooToast(
        context,
        message: editingId == null ? 'Casa creata.' : 'Casa aggiornata.',
      );
      if (editingId != null) {
        Navigator.of(context).pop(true);
        return;
      }
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomePage()),
        (route) => false,
      );
    } catch (e) {
      if (newlyUploadedImageUrl != null && authenticatedUserId != null) {
        var canDeleteUpload = false;
        try {
          canDeleteUpload = !await _inviteService.isHouseUsingImage(
            userId: authenticatedUserId,
            imageUrl: newlyUploadedImageUrl,
          );
        } catch (verificationError) {
          debugPrint(
            '[CasaBuilder] image cleanup verification failed: '
            '$verificationError',
          );
        }
        if (canDeleteUpload) {
          try {
            await HinooStorageUploader.deleteBackgroundUrl(
              url: newlyUploadedImageUrl,
              userId: authenticatedUserId,
            );
          } catch (cleanupError) {
            debugPrint(
              '[CasaBuilder] failed upload cleanup failed: $cleanupError',
            );
          }
        }
      }
      if (!mounted) return;
      setState(() => _error = 'Errore creazione casa: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _isUploadingImage = false;
        });
      }
    }
  }

  Widget _buildEmptyOverlay() {
    return Align(
      alignment: Alignment.center,
      child: GestureDetector(
        onTap: _pickImage,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Carica qui\n'
                'l\'immagine\n'
                'della tua stanza\n'
                'più bella',
                textAlign: TextAlign.center,
                style: GoogleFonts.lora(color: Colors.white, fontSize: 16),
              ),
              const SizedBox(height: 22),
              SvgPicture.asset(
                'assets/icons/immagine.svg',
                width: 48,
                height: 48,
                colorFilter: const ColorFilter.mode(
                  Colors.white,
                  BlendMode.srcIn,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HonooColor.background,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final double maxWidth = constraints.maxWidth;
          final double maxHeight = constraints.maxHeight;
          final ResponsiveLayoutMode layoutMode = ResponsiveLayout.modeForWidth(
            maxWidth,
          );
          final bool isMobile = layoutMode == ResponsiveLayoutMode.mobile;
          final double targetMaxWidth = isMobile
              ? maxWidth
              : ResponsiveLayout.contentMaxWidth(maxWidth);
          final double footerIconSize = ResponsiveLayout.footerIconSizeForMode(
            layoutMode,
          );
          final double footerBottomPadding =
              ResponsiveLayout.footerBottomPaddingForMode(layoutMode) +
              (isMobile ? 0 : 12);
          final double safeBottom = MediaQuery.of(context).viewPadding.bottom;
          final double footerSpacing = footerBottomPadding + safeBottom;
          final double footerTopSpacing = footerSpacing / 2;
          final double footerBottomSpacing = footerSpacing - footerTopSpacing;
          final double footerReserved = isMobile
              ? 0
              : footerIconSize + footerTopSpacing + footerBottomSpacing;
          final double availableHeight = isMobile
              ? maxHeight
              : (maxHeight - footerReserved).clamp(0.0, double.infinity);
          final Size canvasSize = isMobile
              ? Size(maxWidth, availableHeight)
              : ResponsiveLayout.fitAspectRatio(
                  targetMaxWidth,
                  availableHeight,
                  HinooTypography.aspectRatio,
                );
          final double scrignoSize = math.min(
            footerIconSize * 4,
            math.min(canvasSize.width, canvasSize.height),
          );
          final double topSafe = MediaQuery.of(context).viewPadding.top;

          final Widget content = SizedBox(
            width: canvasSize.width,
            height: canvasSize.height,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Center(
                  child: SizedBox(
                    width: canvasSize.width,
                    height: canvasSize.height,
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: SizedBox(
                        width: HinooTypography.baselineCanvasWidth,
                        height: HinooTypography.baselineCanvasHeight,
                        child: CoverTransformImage(
                          image:
                              _imageProvider ??
                              const AssetImage('assets/stanza-02_carta.jpg'),
                          transformationController: _imageController,
                          interactive: _imageProvider != null,
                          minScale: _imageMinScale,
                          maxScale: _imageMaxScale,
                        ),
                      ),
                    ),
                  ),
                ),
                IgnorePointer(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: EdgeInsets.only(bottom: footerBottomSpacing),
                      child: SizedBox(
                        width: scrignoSize,
                        height: scrignoSize,
                        child: Image.asset(
                          'assets/icons/scrigno_di_carta.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                ),
                if (_imageProvider == null)
                  _buildEmptyOverlay()
                else
                  CambiaSfondoOverlay(
                    onTapChange: _pickImage,
                    showControls: true,
                    isUploading: _isUploadingImage,
                    currentScale: _imageScale,
                    minScale: _imageMinScale,
                    maxScale: _imageMaxScale,
                    onScaleChanged: _updateImageScale,
                    onZoomIn: _imageScale < _imageMaxScale
                        ? () => _nudgeImageScale(0.1)
                        : null,
                    onZoomOut: _imageScale > _imageMinScale
                        ? () => _nudgeImageScale(-0.1)
                        : null,
                    onResetTransform: _resetImageTransform,
                  ),
                Positioned(
                  top: topSafe + 12,
                  right: 12,
                  child: _isSaving
                      ? const SizedBox(
                          width: 44,
                          height: 44,
                          child: LoadingSpinner(color: Colors.white),
                        )
                      : IconButton(
                          iconSize: 44,
                          tooltip: 'Salva casa',
                          onPressed: _saveCasa,
                          icon: SvgPicture.asset(
                            'assets/icons/ok.svg',
                            width: 44,
                            height: 44,
                            colorFilter: const ColorFilter.mode(
                              HonooColor.onBackground,
                              BlendMode.srcIn,
                            ),
                          ),
                        ),
                ),
              ],
            ),
          );

          return Stack(
            fit: StackFit.expand,
            children: [
              Center(child: content),
              if (_error != null)
                Positioned(
                  left: 24,
                  right: 24,
                  bottom: footerBottomSpacing + 24,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.lora(
                        color: Colors.white,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

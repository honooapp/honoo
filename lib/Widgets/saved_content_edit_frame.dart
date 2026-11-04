import 'package:flutter/material.dart';
import '../Entities/honoo.dart';
import '../Entities/hinoo.dart';
import '../Pages/new_honoo_page.dart';
import '../Pages/new_hinoo_page.dart';
import '../Services/supabase_provider.dart';
import 'content_edit_frame.dart';

class SavedContentEditFrame extends StatelessWidget {
  const SavedContentEditFrame({
    super.key,
    required this.child,
    required this.width,
    required this.height,
    required this.onSaved,
    this.honoo,
    this.hinoo,
    this.hinooId,
    this.ownerId,
    this.overlayControls = false,
  });
  final bool overlayControls;
  final Widget child;
  final double width;
  final double height;
  final Honoo? honoo;
  final HinooDraft? hinoo;
  final String? hinooId;
  final String? ownerId;
  final VoidCallback onSaved;

  @override
  Widget build(BuildContext context) {
    final userId = SupabaseProvider.client.auth.currentUser?.id;
    final originalOwner = honoo?.userId ?? ownerId;
    final copied = honoo?.isFromMoonSaved ?? hinoo?.isFromMoonSaved ?? false;
    if (userId == null ||
        originalOwner != userId ||
        copied ||
        (honoo?.dbId ?? hinooId)?.isNotEmpty != true) {
      return child;
    }
    Future<void> edit(bool image) async {
      await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => honoo != null
              ? NewHonooPage(editingHonoo: honoo, editImage: image)
              : NewHinooPage(
                  initialDraft: hinoo,
                  editingHinooId: hinooId,
                  campanelloEditMode: image
                      ? CampanelloEditMode.image
                      : CampanelloEditMode.text,
                ),
        ),
      );
      if (context.mounted) onSaved();
    }

    return ContentEditFrame(
      overlayControls: overlayControls,
      width: width,
      height: height,
      onImage: () => edit(true),
      onText: () => edit(false),
      child: child,
    );
  }
}

import '../../../Services/action_animation.dart';
import 'download_saver_base.dart';
import 'download_saver_io.dart'
    if (dart.library.html) 'download_saver_web.dart';

export 'download_saver_base.dart';

DownloadSaver getDownloadSaver() =>
    _AnimatedDownloadSaver(getDownloadSaverImpl());

class _AnimatedDownloadSaver implements DownloadSaver {
  _AnimatedDownloadSaver(this.delegate);
  final DownloadSaver delegate;

  @override
  Future<DownloadSaveResult> save(
    List<DownloadImage> images, {
    String? message,
  }) async {
    final result = await delegate.save(images, message: message);
    if (images.isNotEmpty && !result.cancelled) {
      await ActionAnimations.play(ActionAnimation.device);
    }
    return result;
  }

  @override
  Future<bool> openSavedImage(DownloadSaveResult result) =>
      delegate.openSavedImage(result);
}

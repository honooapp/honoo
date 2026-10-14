/// Awaited presentation hook: persistence works independently of the UI.
enum ActionAnimation {
  moon('sulla_luna'),
  chest('nello_scrigno'),
  elsewhere('honoo_altrove'),
  device('honoo_salvati');

  const ActionAnimation(this.assetName);
  final String assetName;
  String get asset => 'assets/animations/$assetName.mp4';
}

class ActionAnimations {
  static Future<void> Function(ActionAnimation)? presenter;

  static Future<void> play(ActionAnimation animation) async {
    try {
      await presenter?.call(animation);
    } catch (_) {
      // A presentation failure must never turn a completed save into an error.
    }
  }

  static Future<void> forDestination(String destination) =>
      play(switch (destination) {
        'moon' => ActionAnimation.moon,
        'answer' || 'reply' => ActionAnimation.elsewhere,
        _ => ActionAnimation.chest,
      });
}

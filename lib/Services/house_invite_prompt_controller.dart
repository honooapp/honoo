import 'package:flutter/foundation.dart';

/// Bridges an explicit "resume house creation" action to the global invite
/// listener without coupling feature pages to the app navigator.
class HouseInvitePromptController {
  HouseInvitePromptController._();

  static final ValueNotifier<int> requests = ValueNotifier<int>(0);

  static void requestOpen() => requests.value++;
}

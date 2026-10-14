import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honoo/Services/action_animation.dart';
import 'package:honoo/Widgets/action_animation_host.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

class _Player extends VideoPlayerPlatform {
  final streams = <int, StreamController<VideoEvent>>{};
  final assets = <String?>[];
  bool fail = false;
  bool blockAutoplay = false;
  final volumes = <int, double>{};
  final playCalls = <int>[];
  @override
  Future<void> init() async {}
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = streams.length;
    final stream = streams[id] = StreamController<VideoEvent>();
    assets.add(options.dataSource.asset);
    if (fail) {
      stream.addError(
        PlatformException(code: 'unavailable', message: 'Video unavailable'),
      );
    } else {
      stream.add(
        VideoEvent(
          eventType: VideoEventType.initialized,
          size: const Size(1080, 1920),
          duration: const Duration(seconds: 3),
        ),
      );
    }
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => streams[playerId]!.stream;
  @override
  Future<void> dispose(int playerId) async {
    unawaited(streams[playerId]!.close());
  }

  @override
  Future<void> play(int playerId) async {
    playCalls.add(playerId);
    if (blockAutoplay) {
      streams[playerId]!.addError(
        PlatformException(code: 'NotAllowedError', message: 'Autoplay blocked'),
      );
    }
  }

  @override
  Future<void> pause(int playerId) async {}
  @override
  Future<void> setLooping(int playerId, bool looping) async {}
  @override
  Future<void> setVolume(int playerId, double volume) async {
    volumes[playerId] = volume;
  }

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}
  @override
  Future<void> seekTo(int playerId, Duration position) async {}
  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;
  @override
  Widget buildView(int playerId) => const SizedBox();
}

void main() {
  late _Player player;
  setUp(() {
    player = _Player();
    VideoPlayerPlatform.instance = player;
  });
  tearDown(() => ActionAnimations.presenter = null);

  testWidgets('covers app, preserves ratio, waits for end and queues actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ActionAnimationHost(child: MaterialApp(home: Text('page'))),
    );
    var completed = false;
    ActionAnimations.play(ActionAnimation.moon).then((_) => completed = true);
    var secondDone = false;
    ActionAnimations.play(ActionAnimation.chest).then((_) => secondDone = true);
    await tester.pump();
    await tester.pump();
    expect(completed, isFalse);
    expect(player.assets, [ActionAnimation.moon.asset]);
    expect(player.volumes[0], 1);
    expect(
      tester.widget<FittedBox>(find.byType(FittedBox)).fit,
      BoxFit.contain,
    );
    expect(
      tester.getSize(find.byType(AbsorbPointer).last),
      const Size(800, 600),
    );
    player.streams[0]!.add(VideoEvent(eventType: VideoEventType.completed));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(completed, isTrue);
    expect(player.assets, [
      ActionAnimation.moon.asset,
      ActionAnimation.chest.asset,
    ]);
    player.streams[1]!.add(VideoEvent(eventType: VideoEventType.completed));
    await tester.pump(const Duration(milliseconds: 100));
    expect(secondDone, isTrue);
    await tester.pump();
    expect(find.byType(FittedBox), findsNothing);
    expect(find.text('page'), findsOneWidget);
  });

  testWidgets(
    'playback errors release the operation and allow the next action',
    (tester) async {
      await tester.pumpWidget(
        const ActionAnimationHost(child: MaterialApp(home: Text('page'))),
      );
      player.fail = true;
      var failedDone = false;
      ActionAnimations.play(
        ActionAnimation.device,
      ).then((_) => failedDone = true);
      await tester.pump(const Duration(milliseconds: 100));
      expect(failedDone, isTrue);
      player.fail = false;
      var nextDone = false;
      ActionAnimations.play(
        ActionAnimation.elsewhere,
      ).then((_) => nextDone = true);
      await tester.pump();
      await tester.pump();
      player.streams[1]!.add(VideoEvent(eventType: VideoEventType.completed));
      await tester.pump(const Duration(milliseconds: 100));
      expect(nextDone, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('stalled playback is released by timeout', (tester) async {
    await tester.pumpWidget(
      const ActionAnimationHost(child: MaterialApp(home: Text('page'))),
    );
    var done = false;
    ActionAnimations.play(ActionAnimation.device).then((_) => done = true);
    await tester.pump();
    await tester.pump(const Duration(seconds: 31));
    expect(done, isTrue);
    await tester.pump();
    expect(find.byType(FittedBox), findsNothing);
  });

  for (final size in [const Size(320, 640), const Size(1440, 900)]) {
    testWidgets('audio can resume after autoplay rejection at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      player.blockAutoplay = true;
      await tester.pumpWidget(
        const ActionAnimationHost(child: MaterialApp(home: Text('page'))),
      );
      var done = false;
      ActionAnimations.play(ActionAnimation.moon).then((_) => done = true);
      await tester.pump();
      await tester.pump();
      expect(done, isFalse);
      expect(find.text('Riproduci con audio'), findsOneWidget);
      expect(player.volumes[0], 1);
      expect(tester.getSize(find.byType(AbsorbPointer).last), size);
      player.blockAutoplay = false;
      await tester.tap(find.text('Riproduci con audio'));
      await tester.pump();
      expect(player.playCalls, [0, 0]);
      expect(find.text('Riproduci con audio'), findsNothing);
      expect(done, isFalse);
      player.streams[0]!.add(VideoEvent(eventType: VideoEventType.completed));
      await tester.pump(const Duration(milliseconds: 100));
      expect(done, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  for (final retry in [false, true]) {
    testWidgets('blocked audio releases navigation (retry: $retry)', (
      tester,
    ) async {
      player.blockAutoplay = true;
      await tester.pumpWidget(
        const ActionAnimationHost(child: MaterialApp(home: Text('page'))),
      );
      var done = false;
      ActionAnimations.play(ActionAnimation.device).then((_) => done = true);
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text(retry ? 'Riproduci con audio' : 'Continua'));
      await tester.pump();
      await tester.pump();
      expect(done, isTrue);
      expect(find.text('Riproduci con audio'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}

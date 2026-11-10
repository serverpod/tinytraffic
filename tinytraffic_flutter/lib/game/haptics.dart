import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_watchos/flutter_watchos.dart';

/// Moments in the game worth feeling.
enum HapticCue {
  tap,
  countdown,
  go,
  coin,
  lane,
  kerb,
  powerUp,
  nearMiss,
  lift,
  crash,
  explosion,
  newBest,
}

/// Haptic feedback on phones (Flutter's built-in `HapticFeedback`) and on the
/// Apple Watch (the Taptic Engine, through flutter_watchos). Does nothing on
/// the web and desktop.
///
/// On the watch, `HapticFeedback` goes nowhere (the watch engine doesn't
/// handle it), so the watch uses `WatchHaptics` instead. That needs
/// flutter_watchos's native code linked into the app; when it isn't, the
/// first failed call turns watch haptics off quietly.
class GameHaptics {
  bool enabled = true;

  final bool _watch = FlutterWatchosPlatform.isWatch;
  final bool _phone =
      !kIsWeb &&
      !FlutterWatchosPlatform.isWatch &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);
  bool _watchWorks = true;
  final Stopwatch _sinceCoin = Stopwatch()..start();

  void play(HapticCue cue) {
    if (!enabled) return;
    if (cue == HapticCue.coin || cue == HapticCue.lift) {
      // A row of coins arrives a few frames apart; one tick per row of them
      // is plenty, especially on the watch, whose taps are strong.
      final gap = _watch ? 350 : 70;
      if (_sinceCoin.elapsedMilliseconds < gap) return;
      _sinceCoin.reset();
    }
    if (_phone) {
      _phoneHaptic(cue);
    } else if (_watch && _watchWorks) {
      _watchHaptic(cue);
    }
  }

  void _phoneHaptic(HapticCue cue) {
    final Future<void> Function() feedback = switch (cue) {
      HapticCue.tap ||
      HapticCue.countdown ||
      HapticCue.lane ||
      HapticCue.coin => HapticFeedback.selectionClick,
      HapticCue.go ||
      HapticCue.nearMiss ||
      HapticCue.lift => HapticFeedback.lightImpact,
      HapticCue.kerb ||
      HapticCue.powerUp ||
      HapticCue.newBest => HapticFeedback.mediumImpact,
      HapticCue.crash || HapticCue.explosion => HapticFeedback.heavyImpact,
    };
    feedback().catchError((Object _) {});
  }

  void _watchHaptic(HapticCue cue) {
    final type = switch (cue) {
      HapticCue.tap ||
      HapticCue.countdown ||
      HapticCue.lane ||
      HapticCue.coin => WatchHapticType.click,
      HapticCue.go || HapticCue.powerUp => WatchHapticType.start,
      HapticCue.nearMiss => WatchHapticType.directionUp,
      HapticCue.lift || HapticCue.kerb => WatchHapticType.directionDown,
      HapticCue.crash => WatchHapticType.failure,
      HapticCue.explosion => WatchHapticType.stop,
      HapticCue.newBest => WatchHapticType.success,
    };
    try {
      WatchHaptics.play(type);
    } catch (e) {
      _watchWorks = false;
      debugPrint('Watch haptics unavailable: $e');
    }
  }
}

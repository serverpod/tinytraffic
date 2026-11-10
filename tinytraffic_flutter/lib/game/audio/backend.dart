/// Plays loaded sounds. The web uses the browser's own Web Audio API, which
/// works in every browser; devices use audioplayers (on the watch through
/// audioplayers_watchos).
abstract class AudioBackend {
  /// Loads `assets/audio/<file>` for each of [files], named by the file name
  /// without its extension.
  Future<void> load(List<String> files);

  /// Lets audio play: browsers only allow it from a tap or a key press, so
  /// this is called on every one that might start a sound.
  void unlock();

  /// Starts sound [name]; returns a handle for the calls below, or null.
  Object? play(String name, {double volume = 1, bool loop = false});

  void setVolume(Object handle, double volume);

  /// Changes the volume gradually over [time].
  void fade(Object handle, double volume, Duration time);

  /// Stops the sound after [time] (fading out over it).
  void stop(Object handle, Duration time);
}

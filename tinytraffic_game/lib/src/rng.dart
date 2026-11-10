/// A 32-bit xorshift generator that gives identical sequences on the Dart VM
/// and on the web.
///
/// It only uses shifts and xor, masked to 32 bits, so it never needs integers
/// wider than JavaScript can represent exactly (unlike multiply-based
/// generators).
class Rng {
  int _state;

  Rng(int seed) : _state = _scramble(seed);

  /// A generator derived from [seed] and a [stream] index, so that e.g. every
  /// track tile gets its own independent sequence.
  Rng.forStream(int seed, int stream)
    : _state = _scramble((seed ^ _scramble(stream + 0x9E3779B9)) & _mask);

  static const int _mask = 0xFFFFFFFF;

  static int _step(int x) {
    x ^= (x << 13) & _mask;
    x ^= x >> 17;
    x ^= (x << 5) & _mask;
    return x & _mask;
  }

  static int _scramble(int seed) {
    var x = (seed & _mask) ^ 0x6C8E9CF5;
    if (x == 0) x = 0x1234567;
    for (var i = 0; i < 6; i++) {
      x = _step(x);
    }
    return x;
  }

  /// The next raw 32-bit value.
  int nextUint32() {
    _state = _step(_state);
    return _state;
  }

  /// A double in [0, 1).
  double nextDouble() => nextUint32() / 4294967296.0;

  /// An int in [0, max).
  int nextInt(int max) => (nextDouble() * max).floor();

  /// An int in [min, max] (inclusive).
  int range(int min, int max) => min + nextInt(max - min + 1);

  /// A double in [min, max).
  double rangeD(double min, double max) => min + nextDouble() * (max - min);

  bool chance(double p) => nextDouble() < p;
}

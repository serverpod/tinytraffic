/// Lane changes from swipes, taps, keys and the watch's digital crown.
///
/// - A swipe left or right anywhere changes one lane as soon as the finger
///   has moved far enough; lift it to swipe again.
/// - A quick tap on the left or right half of the screen changes one lane
///   that way.
/// - The crown (or a mouse wheel standing in for it) changes a lane every
///   [crownStep] units it turns.
///
/// Changes wait in a short queue and are handed to the simulation one per
/// step ([take]).
class LaneInput {
  final List<int> _queue = [];

  /// Changes not yet taken; at most two wait, so a burst of input never
  /// steers the car long after the fact.
  static const int _maxQueued = 2;

  /// Horizontal distance (logical pixels) that makes a swipe.
  double swipeDistance = 28;

  double _width = 400;

  /// Sets the swipe distance from the screen width.
  void layout(double width) {
    _width = width;
    swipeDistance = (width * 0.06).clamp(14.0, 40.0);
  }

  int? _pointer;
  double _downX = 0, _downY = 0;
  bool _swiped = false;
  final Stopwatch _downTime = Stopwatch();

  void down(int pointer, double x, double y) {
    if (_pointer != null) return;
    _pointer = pointer;
    _downX = x;
    _downY = y;
    _swiped = false;
    _downTime
      ..reset()
      ..start();
  }

  void move(int pointer, double x, double y) {
    if (pointer != _pointer || _swiped) return;
    final dx = x - _downX, dy = y - _downY;
    if (dx.abs() >= swipeDistance && dx.abs() > dy.abs() * 0.8) {
      _swiped = true;
      push(dx > 0 ? 1 : -1);
    }
  }

  void up(int pointer, double x, double y) {
    if (pointer != _pointer) return;
    _pointer = null;
    if (_swiped) return;
    final dx = x - _downX, dy = y - _downY;
    // A tap: short and still. Its side of the screen picks the way.
    if (_downTime.elapsedMilliseconds < 350 &&
        dx.abs() < swipeDistance &&
        dy.abs() < swipeDistance) {
      push(x < _width / 2 ? -1 : 1);
    }
  }

  void cancel(int pointer) {
    if (pointer == _pointer) _pointer = null;
  }

  /// Queues a lane change, -1 left or 1 right. A change the other way
  /// cancels one still waiting.
  void push(int direction) {
    if (_queue.isNotEmpty && _queue.last == -direction) {
      _queue.removeLast();
      return;
    }
    if (_queue.length < _maxQueued) _queue.add(direction);
  }

  /// The next lane change for the simulation, or 0.
  int take() => _queue.isEmpty ? 0 : _queue.removeAt(0);

  // ---- Crown ----

  /// Crown units per lane change: a fifth of a turn (a full turn is 240
  /// units), so a lane change takes a deliberate turn. A mouse wheel notch
  /// is one lane change's worth.
  static const double crownStep = 48;

  /// Seconds after which a partial turn of the crown is forgotten.
  static const double crownForget = 0.5;

  double _crown = 0;
  double _sinceCrown = 0;

  /// Turns the crown by [units] (positive is clockwise, to the right).
  void crown(double units) {
    if (units == 0) return;
    // Turning back starts afresh.
    if (_crown != 0 && units.sign != _crown.sign) _crown = 0;
    _crown += units;
    _sinceCrown = 0;
    while (_crown.abs() >= crownStep) {
      final dir = _crown > 0 ? 1 : -1;
      _crown -= dir * crownStep;
      push(dir);
    }
  }

  void update(double dt) {
    _sinceCrown += dt;
    if (_sinceCrown > crownForget) _crown = 0;
  }

  void reset() {
    _queue.clear();
    _pointer = null;
    _crown = 0;
  }
}

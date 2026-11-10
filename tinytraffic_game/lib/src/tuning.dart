/// Every gameplay constant in one place. Changing any of these changes the
/// simulation, so bump [kSimVersion] whenever one changes (the server rejects
/// runs recorded by a different version).
library;

/// Version of the simulation rules. Recorded with every run.
const int kSimVersion = 5;

/// Simulation steps per second.
const int kTickRate = 60;
const double kDt = 1.0 / kTickRate;

// ---- World ----

/// One road tile is 12 x 12 m.
const double kTile = 12.0;
const double kHalfTile = 6.0;

/// Asphalt reaches this far either side of a road's centre line; beyond it
/// is the kerb.
const double kAsphaltHalfWidth = 5.55;

/// The road has three lanes, -1 (left), 0 and 1 (right), this far apart.
const double kLaneWidth = 3.6;
const int kLanes = 3;

// ---- Player car ----

/// Collision box of the player car (half extents), a little inside the
/// 2.2 x 4.5 m body so a graze is forgiven.
const double kCarHalfWidth = 0.9;
const double kCarHalfLength = 2.0;

/// Speed in m/s at launch, and the asymptote it climbs toward. Speeds are
/// measured along the road's centre line: on a corner every lane takes the
/// same time, so the outer lane is faster and the inner one slower.
const double kSpeedStart = 16.5;
const double kSpeedMax = 36.0;

/// Seconds after which the speed is half-way from start to max.
const double kSpeedHalfTime = 70.0;

/// Acceleration while launching from standstill (m/s^2).
const double kLaunchAccel = 9.0;

/// Seconds a lane change takes.
const double kLaneSwitchTime = 0.17;

// ---- Track generation ----

/// Tiles generated ahead of the player.
const int kTilesAhead = 18;

/// Tiles kept behind the player.
const int kTilesBehind = 6;

/// Track index over which difficulty ramps from 0 to 1.
const double kDifficultyTiles = 260.0;

// ---- Obstacle rows ----

/// Traffic comes in rows: cars side by side that block one or two lanes.
/// Rows are this many seconds apart for the player at the start, and at
/// full difficulty.
const double kRowGapEasy = 1.6;
const double kRowGapHard = 0.72;

/// Centre-line distance of the first row from the start.
const double kFirstRow = 70.0;

/// Below this gap (s) between rows, the free lane moves at most one lane.
const double kRowGapForTwoLanes = 1.25;

/// Difficulty (0..1) from which cars come the other way.
const double kOncomingFrom = 0.15;

/// Extra gap (s) between rows with a corner between them.
const double kCornerRoom = 0.45;

// ---- Coins and power-ups ----

const double kCoinPickupRadius = 1.9;

/// Pickup radius with the magnet: reaches every lane.
const double kMagnetRadius = 8.5;

/// How long power-ups last (s).
const double kMagnetTime = 8.0;
const double kDoubleTime = 10.0;

/// Coins for dodging out of a car's lane at the last moment.
const int kCloseCallBonus = 2;

/// Seconds before impact under which a dodge counts as a close call.
const double kCloseCallTime = 0.42;

// ---- Traffic ----

const int kMaxTraffic = 40;

/// Same-direction traffic crawls along and is overtaken; oncoming traffic
/// comes at you.
const double kTrafficSameSpeed = 6.0;
const double kTrafficOncomingSpeed = 9.0;

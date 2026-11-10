const _adjectives = [
  'Speedy',
  'Zippy',
  'Wobbly',
  'Turbo',
  'Lucky',
  'Sneaky',
  'Bouncy',
  'Swift',
  'Dizzy',
  'Plucky',
  'Sunny',
  'Rusty',
  'Shiny',
  'Jolly',
  'Brave',
  'Nifty',
  'Cosmic',
  'Funky',
  'Mighty',
  'Tiny',
  'Zesty',
  'Breezy',
  'Peppy',
  'Snappy',
];

const _animals = [
  'Otter',
  'Badger',
  'Fox',
  'Panda',
  'Gecko',
  'Koala',
  'Falcon',
  'Hedgehog',
  'Beaver',
  'Llama',
  'Penguin',
  'Moose',
  'Raccoon',
  'Walrus',
  'Hamster',
  'Squirrel',
  'Turtle',
  'Ferret',
  'Puffin',
  'Lemur',
  'Corgi',
  'Yak',
  'Owl',
  'Narwhal',
];

/// A friendly, stable nickname derived from a user id, e.g. "Wobbly Otter 42".
String nicknameFor(String userId) {
  var h = 0x811C9DC5;
  for (final c in userId.codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0xFFFFFFFF;
  }
  final adjective = _adjectives[h % _adjectives.length];
  final animal = _animals[(h ~/ 31) % _animals.length];
  final number = (h ~/ 977) % 100;
  return '$adjective $animal $number';
}

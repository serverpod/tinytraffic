import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'client.dart';
import 'ui/game_screen.dart';
import 'ui/kit.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The fonts ship in assets/google_fonts/, so they work offline and on the
  // Apple Watch (where google_fonts can't cache downloads).
  GoogleFonts.config.allowRuntimeFetching = false;
  await initializeClient();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const TinyTrafficApp());
}

class TinyTrafficApp extends StatelessWidget {
  const TinyTrafficApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tiny Traffic',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Palette.blue,
          primary: Palette.blue,
          secondary: Palette.coin,
        ),
        scaffoldBackgroundColor: Palette.sky,
      ),
      home: const GameScreen(),
    );
  }
}

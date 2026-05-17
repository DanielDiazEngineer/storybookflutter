// lib/main.dart
//
// Phase 3.5 (UX pass):
//  - App locked to landscape app-wide (content is landscape-painted)
//  - Theme tokens consolidated for the cozy-storybook aesthetic
//  - Reduce-motion is honored downstream via MediaQuery.disableAnimations

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'firebase_options.dart';
import 'screens/home_screen.dart';
import 'services/auth_service.dart';
import 'services/user_service.dart';

// ── Design tokens ───────────────────────────────────────────────────────────
// Centralised here so the redesign pass has a single source of truth.
// The intent: warm cream paper, ink-brown text, soft sky-blue accent,
// muted dusk for the reader's chrome.
class AppColors {
  static const cream = Color(0xFFFFF8F0);
  static const creamShade = Color(0xFFEDE8E0);
  static const ink = Color(0xFF3D2B1F);
  static const inkSoft = Color(0xFF9E8872);
  static const inkFaint = Color(0xFFBBAA99);
  static const accent = Color(0xFF6B9FD4);
  static const accentDark = Color(0xFF4D7FAE);
  static const dusk = Color(0xFF1A1A2E);
  static const success = Color(0xFF4CAF50);
  static const warmGold = Color(0xFFE8A020);
}

class AppRadius {
  static const card = 20.0;
  static const pill = 999.0;
  static const sheet = 28.0;
}

class AppDurations {
  static const press = Duration(milliseconds: 150);
  static const pageTurn = Duration(milliseconds: 350);
  static const hero = Duration(milliseconds: 450);
  static const chromeFade = Duration(milliseconds: 600);
  static const chromeIdle = Duration(seconds: 5);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase first — anything else that may touch Firebase services
  // (auth, firestore) needs the app initialized.
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await AuthService().ensureSignedIn();
  await UserService().ensureProfileExists();

  await dotenv.load(fileName: '.env');

  // Lock to landscape for the whole app. Stories are landscape-painted;
  // portrait would either letterbox or crop them.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Edge-to-edge so the reader can paint behind the system bars when desired.
  await SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.edgeToEdge,
  );

  runApp(const StorybookApp());
}

class StorybookApp extends StatelessWidget {
  const StorybookApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Storybook',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.accent,
          brightness: Brightness.light,
          primary: AppColors.accent,
          surface: AppColors.cream,
          onSurface: AppColors.ink,
        ),
        scaffoldBackgroundColor: AppColors.cream,
        useMaterial3: true,
        fontFamily: 'Georgia',
        // Override M3 defaults that read too sharp for storybook tone.
        cardTheme: CardThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
        ),
        chipTheme: ChipThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          backgroundColor: AppColors.creamShade,
          selectedColor: AppColors.accent,
          labelStyle: const TextStyle(
            color: AppColors.ink,
            fontFamily: 'Georgia',
          ),
          side: BorderSide.none,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

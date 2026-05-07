import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
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
          seedColor: const Color(0xFF6B9FD4), // soft sky blue
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        fontFamily: 'Georgia', // cozy storybook feel; swap later
      ),
      home: const HomeScreen(),
    );
  }
}
// lib/main.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'package:firebase_app_check/firebase_app_check.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Activate App Check with the debug provider for development
  await FirebaseAppCheck.instance.activate(
    androidProvider: AndroidProvider.debug,
    // If you target iOS as well, you can include:
    // appleProvider: AppleProvider.debug,
  );

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cache Box',
      // Define your custom theme
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Color(0xFF000000), // Background color
        primaryColor: Color(0xFF5F0707), // Theme 1 color
        appBarTheme: AppBarTheme(
          backgroundColor: Color(0xFF5F0707),
        ),
        colorScheme: ColorScheme.dark(
          primary: Color(0xFF5F0707), // Theme 1 color
          secondary: Color(0xFFEF8275), // Theme 2 color
          background: Color(0xFF000000),
          surface: Color(0xFF000000),
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onBackground: Colors.white,
          onSurface: Colors.white,
        ),
      ),
      home: LoginScreen(), // Initial screen for authentication
    );
  }
}

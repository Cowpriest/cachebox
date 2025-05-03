// lib/main.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'firebase_options.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/chat_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Initialize Firebase App Check  debug only
  await FirebaseAppCheck.instance.activate(
    //webRecaptchaSiteKey: 'your-public-site-key', // Required for web only
    androidProvider: AndroidProvider.debug, // Use debug for now
  );

  // Initialize Firebase App Check production only
  // await FirebaseAppCheck.instance.activate(
  //   androidProvider: AndroidProvider.playIntegrity,
  //   appleProvider: AppleProvider.deviceCheck,
  //   webRecaptchaSiteKey: 'your-public-site-key',
  // );

  // prints debug token.  erase when going to production.
  FirebaseAppCheck.instance.getToken().then((token) {
    print('🔥 AppCheck Debug token: $token');
  }).catchError((e) {
    print('❌ Failed to get AppCheck token: $e');
  });

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cache Box',
      theme: ThemeData(
        brightness: Brightness.dark,
        // your theme settings here...
      ),
      home: AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.active) {
          final User? user = snapshot.data;
          // If the user is signed in, show the ChatScreen; otherwise, show LoginScreen
          return user == null ? LoginScreen() : HomeScreen();
        }
        // Loading indicator while checking auth state
        return Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      },
    );
  }
}

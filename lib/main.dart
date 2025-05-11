// lib/main.dart
import 'package:cachebox/screens/group_list_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'firebase_options.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/chat_screen.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'globals.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // optionally, disable caching entirely
  //FirebaseFirestore.instance.settings =
  //    const Settings(persistenceEnabled: false);

  // ——— Point Firestore at the local emulator ———
  // FirebaseFirestore.instance.useFirestoreEmulator('10.0.0.86', 8080);
  // print('👉 butts Firestore emulator at 10.0.0.86:8080');

  //  send a ping!
  // await FirebaseFirestore.instance
  //     .collection('___debug')
  //     .doc('ping')
  //     .set({'ts': FieldValue.serverTimestamp()});
  // print('🔄 sent debug ping');

  await FirebaseAppCheck.instance.activate(
    androidProvider: AndroidProvider.debug,
  );

  FirebaseAppCheck.instance.getToken().then((token) {
    print('🔥 AppCheck Debug token: $token');
  }).catchError((e) {
    print('❌ Failed to get AppCheck token: $e');
  });

  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.yourapp.audio', // unique ID
    androidNotificationChannelName: 'Audio playback', // visible name
    androidNotificationOngoing: true, // make it sticky
  );
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cache Box',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        // pure black everywhere
        scaffoldBackgroundColor: Colors.black,
        canvasColor: Colors.black,
        appBarTheme: AppBarTheme(
          backgroundColor: const Color.fromARGB(255, 87, 0, 0),
          elevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle.light,
        ),
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
          return user == null ? LoginScreen() : GroupListScreen();
        }
        // Loading indicator while checking auth state
        return Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      },
    );
  }
}

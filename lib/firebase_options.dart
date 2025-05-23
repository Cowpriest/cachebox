// File generated by FlutterFire CLI.
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
///
/// Example:
/// ```dart
/// import 'firebase_options.dart';
/// // ...
/// await Firebase.initializeApp(
///   options: DefaultFirebaseOptions.currentPlatform,
/// );
/// ```
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAd3h6w06ahu90MzJ1qrZwtJV4JXsGPJlE',
    appId: '1:763586150584:web:d72165fac397bf84d3744d',
    messagingSenderId: '763586150584',
    projectId: 'cachebox',
    authDomain: 'cachebox.firebaseapp.com',
    storageBucket: 'cachebox.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDiV8WyJzJtnLsTSUGCfG9qcd1ZecYFGGo',
    appId: '1:763586150584:android:dabe44985fa2b0c5d3744d',
    messagingSenderId: '763586150584',
    projectId: 'cachebox',
    storageBucket: 'cachebox.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyA4RO5vc8DFOIHNFE7v8pSBYGkrpcW3jeM',
    appId: '1:763586150584:ios:1ac96c1c4fa6d531d3744d',
    messagingSenderId: '763586150584',
    projectId: 'cachebox',
    storageBucket: 'cachebox.firebasestorage.app',
    iosBundleId: 'com.example.cachebox',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyA4RO5vc8DFOIHNFE7v8pSBYGkrpcW3jeM',
    appId: '1:763586150584:ios:1ac96c1c4fa6d531d3744d',
    messagingSenderId: '763586150584',
    projectId: 'cachebox',
    storageBucket: 'cachebox.firebasestorage.app',
    iosBundleId: 'com.example.cachebox',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyAd3h6w06ahu90MzJ1qrZwtJV4JXsGPJlE',
    appId: '1:763586150584:web:2b42bc599bf142d5d3744d',
    messagingSenderId: '763586150584',
    projectId: 'cachebox',
    authDomain: 'cachebox.firebaseapp.com',
    storageBucket: 'cachebox.firebasestorage.app',
  );
}

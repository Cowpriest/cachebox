// lib/screens/login_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/material.dart';
import 'group_list_screen.dart';

class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  String? errorMessage;

  Future<UserCredential> signInWithGoogle() async {
    final googleSignIn = GoogleSignIn();
    final googleUser = await googleSignIn.signIn();
    if (googleUser == null) {
      throw Exception("Google sign-in aborted");
    }

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    // 1) Sign in to Firebase
    final userCredential =
        await FirebaseAuth.instance.signInWithCredential(credential);

    final user = userCredential.user!;
    // 2) Ensure the Firebase User.displayName is set
    if (user.displayName == null || user.displayName!.isEmpty) {
      await user.updateDisplayName(googleUser.displayName);
      await user.reload();
    }

    // 3) Upsert into Firestore `users/{uid}` doc
    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'displayName': user.displayName,
      'photoURL': user.photoURL,
      'email': user.email,
      'lastSignIn': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return userCredential;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CacheBox')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.login),
              label: const Text('Sign in with Google'),
              onPressed: () async {
                try {
                  await signInWithGoogle();
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => GroupListScreen()),
                  );
                } catch (e) {
                  setState(() {
                    errorMessage = "Failed to sign in with Google: $e";
                  });
                }
              },
            ),
            if (errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(errorMessage!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
    );
  }
}

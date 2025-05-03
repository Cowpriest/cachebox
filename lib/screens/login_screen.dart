// lib/screens/login_screen.dart
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'group_list_screen.dart'; // Navigate here after login
// import 'create_account_screen.dart'; // Optionally remove if not needed

class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // Remove controllers for email and password if they're not needed.
  // final TextEditingController _emailController = TextEditingController();
  // final TextEditingController _passwordController = TextEditingController();
  String? errorMessage;

  Future<UserCredential> signInWithGoogle() async {
    final GoogleSignIn googleSignIn = GoogleSignIn();
    final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
    if (googleUser == null) {
      throw Exception("Google sign-in aborted");
    }

    final GoogleSignInAuthentication googleAuth =
        await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    // Sign in to Firebase with the Google user credential
    UserCredential userCredential =
        await FirebaseAuth.instance.signInWithCredential(credential);

    // If the displayName is missing, update it using the Google account's displayName
    if (userCredential.user?.displayName == null ||
        userCredential.user!.displayName!.isEmpty) {
      await userCredential.user!.updateDisplayName(googleUser.displayName);
      // Optionally reload the user to ensure the profile is updated immediately
      await userCredential.user!.reload();
    }

    return userCredential;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('CacheBox')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Center(
              child: ElevatedButton.icon(
                icon: Icon(Icons.login),
                label: Text('Sign in with Google'),
                // onPressed: () async {
                //   try {
                //     await signInWithGoogle();
                //     Navigator.pushReplacement(
                //       context,
                //       MaterialPageRoute(builder: (_) => return user == null
                //         ? LoginScreen()
                //         : GroupListScreen();),
                //     );
                //   } catch (e) {
                //     setState(() {
                //       errorMessage = "Failed to sign in with Google: $e";
                //     });
                //   }
                // },
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
            ),
            if (errorMessage != null)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(errorMessage!, style: TextStyle(color: Colors.red)),
              ),
          ],
        ),
      ),
    );
  }
}

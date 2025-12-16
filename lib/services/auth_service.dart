// lib/services/auth_service.dart - FIXED VERSION
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService extends ChangeNotifier {
  bool _isLoading = false;
  bool get isLoading => _isLoading;
  
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // Configure GoogleSignIn for version 6.x
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
  );

  // ------------------- EMAIL/PASSWORD REGISTRATION -------------------
  Future<void> signUpWithEmail({
    required String email,
    required String password,
    required String name,
  }) async {
    try {
      _isLoading = true;
      notifyListeners();

      // 1. Create user in Firebase Authentication
      final UserCredential userCredential = 
          await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );

      final User user = userCredential.user!;
      final String uid = user.uid;

      // 2. Update display name in Auth profile
      await user.updateDisplayName(name);

      // 3. Save user data to Firestore 'users' collection
      await _firestore.collection('users').doc(uid).set({
        'uid': uid,
        'name': name,
        'email': email.trim(),
        'photoUrl': user.photoURL ?? '',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'postsCount': 0,
        'followers': 0,
        'following': 0,
        'isVerified': false,
        'bio': 'New Voyage traveler',
        'signInMethod': 'email',
      }, SetOptions(merge: true));

      // 4. Send email verification (optional but recommended)
      await user.sendEmailVerification();

    } on FirebaseAuthException catch (e) {
      throw _handleFirebaseAuthError(e);
    } catch (e) {
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ------------------- EMAIL/PASSWORD LOGIN -------------------
  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      _isLoading = true;
      notifyListeners();

      await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );
      
    } on FirebaseAuthException catch (e) {
      throw _handleFirebaseAuthError(e);
    } catch (e) {
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ------------------- GOOGLE SIGN IN (FIXED) -------------------
  Future<void> signInWithGoogle() async {
    try {
      _isLoading = true;
      notifyListeners();

      print('Starting Google Sign-In process...');

      // FIX 1: Force sign out and clear cache first
      try {
        await _googleSignIn.signOut();
        await _googleSignIn.disconnect();
        print('Cleared previous Google session');
      } catch (e) {
        print('Non-critical error clearing cache: $e');
      }

      // FIX 2: Trigger Google Sign In with error handling (v7.x API)
      final GoogleSignInAccount? googleUser;
      try {
        googleUser = await _googleSignIn.signIn();
        if (googleUser == null) {
          throw Exception('Google sign-in cancelled by user');
        }
        print('Google user obtained: ${googleUser.email}');
      } catch (e) {
        print('Google Sign-In error: $e');
        throw Exception('Failed to sign in with Google: ${e.toString()}');
      }

      // Get authentication details
      final GoogleSignInAuthentication googleAuth;
      try {
        googleAuth = await googleUser.authentication;
        print('Google authentication obtained');
      } catch (e) {
        print('Google auth error: $e');
        throw Exception('Failed to get authentication: ${e.toString()}');
      }

      // Create Firebase credential (v7.x uses accessToken and idToken)
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      print('Signing in to Firebase...');
      
      // Sign in to Firebase with Google credentials
      final UserCredential userCredential;
      try {
        userCredential = await _auth.signInWithCredential(credential);
        print('Firebase sign-in successful');
      } on FirebaseAuthException catch (e) {
        print('Firebase auth error: ${e.code} - ${e.message}');
        throw Exception(_handleFirebaseAuthError(e));
      }
      
      final User user = userCredential.user!;
      final String uid = user.uid;

      print('User authenticated: ${user.email}, UID: $uid');

      // Check if user exists in Firestore
      final userDoc = await _firestore.collection('users').doc(uid).get();
      
      // If user doesn't exist in Firestore, create their profile
      if (!userDoc.exists) {
        print('Creating new user in Firestore...');
        await _firestore.collection('users').doc(uid).set({
          'uid': uid,
          'name': user.displayName ?? googleUser.displayName ?? 'Google User',
          'email': user.email ?? googleUser.email ?? '',
          'photoUrl': user.photoURL ?? googleUser.photoUrl ?? '',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'postsCount': 0,
          'followers': 0,
          'following': 0,
          'isVerified': false,
          'bio': 'Google traveler',
          'signInMethod': 'google',
        }, SetOptions(merge: true));
        print('Firestore user created');
      } else {
        print('User already exists in Firestore');
        // Update last login timestamp
        await _firestore.collection('users').doc(uid).update({
          'updatedAt': FieldValue.serverTimestamp(),
          'lastLogin': FieldValue.serverTimestamp(),
        });
      }
      
      print('Google Sign-In completed successfully');
      
    } on FirebaseAuthException catch (e) {
      print('Firebase exception in Google sign-in: ${e.code} - ${e.message}');
      // Ensure loading is false on error
      _isLoading = false;
      notifyListeners();
      throw Exception(_handleFirebaseAuthError(e));
    } catch (e) {
      print('Unexpected error in Google sign-in: $e');
      // Ensure loading is false on error
      _isLoading = false;
      notifyListeners();
      rethrow;
    } finally {
      // Double-check loading is false
      if (_isLoading) {
        _isLoading = false;
        notifyListeners();
      }
      print('Google Sign-In loading state: $_isLoading');
    }
  }

  // ------------------- SIGN OUT (FIXED) -------------------
  Future<void> signOut() async {
    try {
      print('Starting sign out process...');
      
      // Sign out from Firebase
      await _auth.signOut();
      print('Firebase sign-out successful');
      
      // FIX: Clear Google Sign-In cache properly
      try {
        await _googleSignIn.signOut();
        await _googleSignIn.disconnect();
        print('Google Sign-In cache cleared');
      } catch (e) {
        print('Google sign-out error (non-critical): $e');
        // Continue even if Google sign-out fails
      }
      
      print('Sign-out completed');
    } catch (e) {
      print('Error signing out: $e');
      rethrow;
    }
  }

  // ------------------- CHECK IF USER IS SIGNED IN WITH GOOGLE -------------------
  Future<bool> isSignedInWithGoogle() async {
    try {
      // In v6.x, isSignedIn() is a method that returns a Future<bool>
      return await _googleSignIn.isSignedIn();
    } catch (e) {
      print('Error checking Google sign-in status: $e');
      return false;
    }
  }

  // ------------------- GET CURRENT GOOGLE USER -------------------
  Future<GoogleSignInAccount?> getCurrentGoogleUser() async {
    try {
      // In v6.x, currentUser is a getter that returns the current user
      return _googleSignIn.currentUser;
    } catch (e) {
      print('Error getting current Google user: $e');
      return null;
    }
  }

  // ------------------- PASSWORD RESET -------------------
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      throw _handleFirebaseAuthError(e);
    }
  }

  // ------------------- CURRENT USER -------------------
  User? get currentUser => _auth.currentUser;

  // ------------------- AUTH STATE STREAM -------------------
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // ------------------- GET USER DATA FROM FIRESTORE -------------------
  Future<Map<String, dynamic>> getUserData(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists) {
        return doc.data()!;
      }
      return {};
    } catch (e) {
      print('Error getting user data: $e');
      return {};
    }
  }

  // ------------------- UPDATE USER PROFILE -------------------
  Future<void> updateUserProfile({
    required String uid,
    String? name,
    String? bio,
    String? photoUrl,
  }) async {
    try {
      final Map<String, dynamic> updates = {
        'updatedAt': FieldValue.serverTimestamp(),
      };
      
      if (name != null) updates['name'] = name;
      if (bio != null) updates['bio'] = bio;
      if (photoUrl != null) updates['photoUrl'] = photoUrl;
      
      await _firestore.collection('users').doc(uid).update(updates);
      
      // Also update Firebase Auth display name
      if (name != null) {
        await _auth.currentUser?.updateDisplayName(name);
      }
      
    } catch (e) {
      print('Error updating profile: $e');
      rethrow;
    }
  }

  // ------------------- ERROR HANDLING -------------------
  String _handleFirebaseAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'No account found with this email. Please sign up.';
      case 'wrong-password':
        return 'Incorrect password. Please try again.';
      case 'invalid-email':
        return 'Invalid email address format.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'email-already-in-use':
        return 'An account already exists with this email.';
      case 'operation-not-allowed':
        return 'Email/password sign-in is not enabled.';
      case 'weak-password':
        return 'Password is too weak. Use at least 6 characters.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'network-request-failed':
        return 'Network error. Please check your connection.';
      case 'requires-recent-login':
        return 'Please sign out and sign in again to change your password.';
      case 'account-exists-with-different-credential':
        return 'An account already exists with the same email but different sign-in method.';
      case 'invalid-credential':
        return 'Invalid authentication credentials.';
      case 'user-mismatch':
        return 'The credential given does not correspond to the user.';
      case 'credential-already-in-use':
        return 'This credential is already associated with a different user account.';
      default:
        // Clean up Firebase error message
        String message = e.message ?? e.code;
        return message
            .replaceAll('[firebase_auth/', '')
            .replaceAll(']', '')
            .replaceAll('FirebaseError: ', '');
    }
  }
}
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AuthService extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? _currentUser;
  bool _isAdmin = false;
  bool _isLoading = true;

  User? get currentUser => _currentUser;
  bool get isAdmin => _isAdmin;
  bool get isLoading => _isLoading;

  AuthService() {
    _auth.authStateChanges().listen(_handleAuthStateChange);
  }

  Future<void> _handleAuthStateChange(User? user) async {
    _currentUser = user;
    _isLoading = true;
    notifyListeners();

    if (user != null) {
      try {
        final doc = await _firestore.collection('users').doc(user.uid).get();
        _isAdmin = doc.data()?['role'] == 'admin';
      } catch (_) {
        _isAdmin = false;
      }
    } else {
      _isAdmin = false;
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> signIn(String email, String password) async {
    await _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }
}
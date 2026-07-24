import 'package:supabase_flutter/supabase_flutter.dart';
import '../supabase/client.dart';

class AuthService {
  /// Send magic link to email
  Future<void> signInWithMagicLink(String email) async {
    await supabase.auth.signInWithOtp(
      email: email,
      shouldCreateUser: true,
    );
  }

  /// Sign in with email + password
  Future<AuthResponse> signInWithPassword(String email, String password) async {
    return supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  /// Sign up with email + password
  Future<AuthResponse> signUp(String email, String password) async {
    return supabase.auth.signUp(
      email: email,
      password: password,
    );
  }

  /// Sign out
  Future<void> signOut() async {
    await supabase.auth.signOut();
  }

  /// Check if user is logged in
  bool get isLoggedIn => supabase.auth.currentSession != null;

  /// Get current user
  User? get currentUser => supabase.auth.currentUser;
}

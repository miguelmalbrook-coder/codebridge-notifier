import 'package:supabase_flutter/supabase_flutter.dart';
import '../supabase/client.dart';

class AuthService {
  /// Sign in with email + password (admin creates users in Supabase panel)
  Future<AuthResponse> signInWithPassword(String email, String password) async {
    return supabase.auth.signInWithPassword(
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

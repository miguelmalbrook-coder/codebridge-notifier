import 'package:flutter/material.dart';
import '../auth/auth_service.dart';
import '../supabase/client.dart';
import 'camera_list_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _auth = AuthService();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  bool _useMagicLink = true;

  Future<void> _submit() async {
    setState(() => _loading = true);
    try {
      if (_useMagicLink) {
        await _auth.signInWithMagicLink(_emailCtrl.text.trim());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Magic link sent! Check your email.'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        await _auth.signInWithPassword(
          _emailCtrl.text.trim(),
          _passwordCtrl.text,
        );
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const CameraListScreen()),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.camera_alt_outlined, size: 80, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text('Codebridge Notifier', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Real-time camera alerts', style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 48),

              TextField(
                controller: _emailCtrl,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email_outlined),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              if (!_useMagicLink) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    prefixIcon: Icon(Icons.lock_outlined),
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                ),
              ],
              const SizedBox(height: 24),

              FilledButton.icon(
                onPressed: _loading ? null : _submit,
                icon: _loading
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.login),
                label: Text(_useMagicLink ? 'Send Magic Link' : 'Sign In'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                ),
              ),
              const SizedBox(height: 16),

              TextButton(
                onPressed: () => setState(() => _useMagicLink = !_useMagicLink),
                child: Text(_useMagicLink ? 'Use password instead' : 'Use magic link instead'),
              ),

              // Listen for auth state changes
              StreamBuilder(
                stream: supabase.auth.onAuthStateChange,
                builder: (context, snapshot) {
                  final session = snapshot.data?.session;
                  if (session != null) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (_) => const CameraListScreen()),
                        );
                      }
                    });
                  }
                  return const SizedBox.shrink();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

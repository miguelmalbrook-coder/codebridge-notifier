import 'package:supabase_flutter/supabase_flutter.dart';

/// Global Supabase client — initialized in main().
SupabaseClient supabase = SupabaseClient('', '');

/// Initialize Supabase with build-time env vars.
Future<void> initSupabase() async {
  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );

  supabase = Supabase.instance.client;
}

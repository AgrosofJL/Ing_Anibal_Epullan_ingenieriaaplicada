import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static const String supabaseUrl = 'https://whtvjzmdyjhjbiiuihbw.supabase.co';
  static const String supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndodHZqem1keWpoamJpaXVpaGJ3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODgyNjYyMzksImV4cCI6MjEwMzg0MjIzOX0.lyth5W_8Owkg4Hj8trpCNcrkBbDL97ZYKtvh7ktYSgA';

  static Future<void> inicializar() async {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );
  }

  static SupabaseClient get client => Supabase.instance.client;
}
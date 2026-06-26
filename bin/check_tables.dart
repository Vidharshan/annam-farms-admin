import 'dart:io';
import 'package:supabase/supabase.dart';
void main() async {
  final supabaseUrl = 'https://kptnngwdknzifnzduckd.supabase.co';
  final supabaseKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtwdG5uZ3dka256aWZuemR1Y2tkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjU5OTMyNTgsImV4cCI6MjA4MTU2OTI1OH0.T93Y32nVmrrNUPOY2Rv31doMlfBmwhtcVIqTCJyQip8';

  final client = SupabaseClient(supabaseUrl, supabaseKey);
  try {
    final res = await client.from('user_profiles').select().limit(1);
    print('user_profiles exists: $res');
  } catch (e) {
    print('user_profiles error: $e');
  }
  try {
    final res = await client.from('profiles').select().limit(1);
    print('profiles exists: $res');
  } catch (e) {
    print('profiles error: $e');
  }
}

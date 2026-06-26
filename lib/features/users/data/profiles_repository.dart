import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/domain/profile_model.dart';

class ProfilesRepository {
  final SupabaseClient _client;

  ProfilesRepository(this._client);

  Future<List<Profile>> getAllProfiles() async {
    final response = await _client
        .from('user_profiles')
        .select()
        .order('full_name');
    
    return (response as List)
        .map((json) => Profile.fromJson(json))
        .toList();
  }

  Future<void> updateProfile(String profileId, Map<String, dynamic> updates) async {
    await _client
        .from('user_profiles')
        .update(updates)
        .eq('id', profileId);
  }
}

final profilesRepositoryProvider = Provider<ProfilesRepository>((ref) {
  return ProfilesRepository(Supabase.instance.client);
});

final allProfilesProvider = FutureProvider<List<Profile>>((ref) async {
  return ref.watch(profilesRepositoryProvider).getAllProfiles();
});

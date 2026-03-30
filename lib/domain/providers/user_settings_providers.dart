import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:cashi_flow/domain/models/user_settings_model.dart';
import 'package:cashi_flow/data/repositories/hive_user_settings_repository.dart';

final userSettingsRepositoryProvider = Provider((ref) {
  final box = Hive.box<UserSettingsModel>('user_settings');
  return HiveUserSettingsRepository(box);
});

final userSettingsStreamProvider = StreamProvider<UserSettingsModel?>((ref) {
  final repo = ref.watch(userSettingsRepositoryProvider);
  return repo.watchSettings();
});

// A provider to easily fetch the user settings state rather than streaming it
final userSettingsFutureProvider = FutureProvider<UserSettingsModel?>((ref) {
  final repo = ref.watch(userSettingsRepositoryProvider);
  return repo.getSettings();
});

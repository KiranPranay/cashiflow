import 'package:hive_flutter/hive_flutter.dart';
import 'package:cashi_flow/domain/models/user_settings_model.dart';
import 'package:cashi_flow/domain/repositories/user_settings_repository.dart';

class HiveUserSettingsRepository implements UserSettingsRepository {
  final Box<UserSettingsModel> _box;

  HiveUserSettingsRepository(this._box);

  @override
  Stream<UserSettingsModel?> watchSettings() async* {
    yield _box.get('settings');
    yield* _box.watch(key: 'settings').map((event) => event.value as UserSettingsModel?);
  }

  @override
  Future<void> saveSettings(UserSettingsModel settings) async {
    await _box.put('settings', settings);
  }

  @override
  Future<UserSettingsModel?> getSettings() async {
    return _box.get('settings');
  }
}

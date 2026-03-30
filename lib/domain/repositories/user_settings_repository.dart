import 'package:cashi_flow/domain/models/user_settings_model.dart';

abstract class UserSettingsRepository {
  Stream<UserSettingsModel?> watchSettings();
  Future<void> saveSettings(UserSettingsModel settings);
  Future<UserSettingsModel?> getSettings();
}

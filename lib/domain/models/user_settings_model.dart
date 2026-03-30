import 'package:hive/hive.dart';

part 'user_settings_model.g.dart';

@HiveType(typeId: 3)
class UserSettingsModel extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final Map<String, double> expectedIncomes;

  @HiveField(2)
  final String? baseBankAccountId;

  @HiveField(3)
  final bool onboardingCompleted;

  @HiveField(4)
  final DateTime? lastNotificationCleanup;

  @HiveField(5)
  final String? geminiApiKey;

  UserSettingsModel({
    this.id = 'settings',
    this.expectedIncomes = const {'Salary': 0.0},
    this.baseBankAccountId,
    this.onboardingCompleted = false,
    this.lastNotificationCleanup,
    this.geminiApiKey,
  });

  UserSettingsModel copyWith({
    Map<String, double>? expectedIncomes,
    String? baseBankAccountId,
    bool? onboardingCompleted,
    DateTime? lastNotificationCleanup,
    String? geminiApiKey,
  }) {
    return UserSettingsModel(
      id: this.id,
      expectedIncomes: expectedIncomes ?? this.expectedIncomes,
      baseBankAccountId: baseBankAccountId ?? this.baseBankAccountId,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      lastNotificationCleanup: lastNotificationCleanup ?? this.lastNotificationCleanup,
      geminiApiKey: geminiApiKey ?? this.geminiApiKey,
    );
  }
}

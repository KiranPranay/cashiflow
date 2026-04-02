// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_settings_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class UserSettingsModelAdapter extends TypeAdapter<UserSettingsModel> {
  @override
  final int typeId = 3;

  @override
  UserSettingsModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return UserSettingsModel(
      id: fields[0] as String,
      expectedIncomes: (fields[1] as Map).cast<String, double>(),
      baseBankAccountId: fields[2] as String?,
      onboardingCompleted: fields[3] as bool,
      lastNotificationCleanup: fields[4] as DateTime?,
      geminiApiKey: fields[5] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, UserSettingsModel obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.expectedIncomes)
      ..writeByte(2)
      ..write(obj.baseBankAccountId)
      ..writeByte(3)
      ..write(obj.onboardingCompleted)
      ..writeByte(4)
      ..write(obj.lastNotificationCleanup)
      ..writeByte(5)
      ..write(obj.geminiApiKey);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserSettingsModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

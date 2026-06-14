// ignore_for_file: do_not_use_environment

/// Single source of truth for the embedded Gemini API key.
///
/// The key is swappable/revocable in one place:
///  - Local/dev builds use the [defaultValue] placeholder below (the app then
///    falls back to a user-supplied key from settings).
///  - Release/CI builds bake in the real key via:
///      flutter build ... --dart-define=GEMINI_API_KEY=xxxxxxxx
///
/// NOTE: a key baked into a published binary is extractable by end users.
/// Restrict it (API/app restrictions) and rotate it here if it leaks.
const String kEmbeddedGeminiApiKey = String.fromEnvironment(
  'GEMINI_API_KEY',
  defaultValue: 'PASTE_KEY_HERE',
);

/// True when a real key has been baked in (i.e. not the dev placeholder).
bool get isEmbeddedGeminiKeyConfigured =>
    kEmbeddedGeminiApiKey.isNotEmpty &&
    kEmbeddedGeminiApiKey != 'PASTE_KEY_HERE';

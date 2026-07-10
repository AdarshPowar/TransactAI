import 'package:shared_preferences/shared_preferences.dart';

/// Handles storing and verifying the app's 4-digit PIN.
/// PIN is stored as a plain string in SharedPreferences.
/// For production you'd want to hash it — fine for portfolio/MVP.
class PinService {
  static const _pinKey = 'transactai_app_pin';

  /// Returns true if a PIN has been set by the user.
  static Future<bool> hasPin() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_pinKey);
  }

  /// Saves a new PIN.
  static Future<void> savePin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pinKey, pin);
  }

  /// Returns true if the provided PIN matches the stored one.
  static Future<bool> verifyPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_pinKey);
    return stored == pin;
  }

  /// Clears the stored PIN (e.g. on logout).
  static Future<void> clearPin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pinKey);
  }
static const _bioKey = 'transactai_biometric_enabled';

static Future<bool> isBiometricEnabled() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_bioKey) ?? false;
}

static Future<void> setBiometricEnabled(bool value) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_bioKey, value);
}


}
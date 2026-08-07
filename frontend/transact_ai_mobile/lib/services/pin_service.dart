import 'package:shared_preferences/shared_preferences.dart';

/// Handles storing and verifying the app's 4-digit PIN,
/// biometric preference, login state, and classified SMS IDs.
class PinService {
  // ── PIN ───────────────────────────────────────────────────────────────────
  static const _pinKey = 'transactai_app_pin';

  static Future<bool> hasPin() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_pinKey);
  }

  static Future<void> savePin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pinKey, pin);
  }

  static Future<bool> verifyPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_pinKey);
    return stored == pin;
  }

  static Future<void> clearPin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pinKey);
  }

  // ── Biometric ─────────────────────────────────────────────────────────────
  static const _bioKey = 'transactai_biometric_enabled';

  static Future<bool> isBiometricEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_bioKey) ?? false;
  }

  static Future<void> setBiometricEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_bioKey, value);
  }

  // ── Login state fallback ──────────────────────────────────────────────────
  static const _loggedInKey = 'transactai_logged_in';

  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_loggedInKey) ?? false;
  }

  static Future<void> setLoggedIn(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_loggedInKey, value);
  }

  // ── Classified SMS IDs ────────────────────────────────────────────────────
  static const _classifiedKey = 'transactai_classified_ids';

  /// Returns set of SMS IDs already classified — persists across app restarts.
  static Future<Set<String>> getClassifiedIds() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_classifiedKey) ?? [];
    return list.toSet();
  }

  /// Marks an SMS ID as classified so it won't be reclassified on reopen.
  static Future<void> markClassified(String smsId) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_classifiedKey) ?? [];
    if (!list.contains(smsId)) {
      list.add(smsId);
      // Keep only last 500 IDs to avoid unbounded growth
      if (list.length > 500) list.removeRange(0, list.length - 500);
      await prefs.setStringList(_classifiedKey, list);
    }
  }

  /// Clears classified IDs on logout.
  static Future<void> clearClassifiedIds() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_classifiedKey);
  }
}
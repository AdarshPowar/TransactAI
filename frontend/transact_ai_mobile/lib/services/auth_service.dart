import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Wraps all Firebase Authentication flows used by TransactAI:
/// - Email / Password
/// - Phone number + OTP
/// - Google Sign-In
class AuthService {
  AuthService._internal();
  static final AuthService instance = AuthService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: ['email']);

  /// Currently signed-in Firebase user, if any.
  User? get currentUser => _auth.currentUser;

  /// Stream of auth state changes (signed in / signed out).
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // ── Email / Password ───────────────────────────────────────────────────

  /// Signs in an existing user with email + password.
  /// Throws [FirebaseAuthException] on failure (caller should catch and
  /// surface a friendly message).
  Future<User?> signInWithEmail(String email, String password) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    return credential.user;
  }

  /// Creates a new account with email + password.
  Future<User?> signUpWithEmail(String email, String password) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    return credential.user;
  }

  // ── Phone + OTP ─────────────────────────────────────────────────────────

  /// Starts the phone verification flow.
  ///
  /// [onCodeSent] is called once Firebase has sent (or simulated, for test
  /// numbers) the OTP — [verificationId] must be retained and passed to
  /// [verifyOtp] later.
  ///
  /// [onAutoVerified] fires only on Android when SMS auto-retrieval
  /// completes verification without the user typing the OTP.
  ///
  /// [onFailed] fires on invalid phone number, quota issues, etc.
  Future<void> sendOtp({
    required String phoneNumber, // full E.164 format e.g. +919876543210
    required void Function(String verificationId) onCodeSent,
    required void Function(User? user) onAutoVerified,
    required void Function(String message) onFailed,
  }) async {
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (PhoneAuthCredential credential) async {
        // Android auto-retrieval / instant verification (rare on test numbers)
        try {
          final result = await _auth.signInWithCredential(credential);
          onAutoVerified(result.user);
        } on FirebaseAuthException catch (e) {
          onFailed(_friendlyError(e));
        }
      },
      verificationFailed: (FirebaseAuthException e) {
        onFailed(_friendlyError(e));
      },
      codeSent: (String verificationId, int? resendToken) {
        onCodeSent(verificationId);
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        // No-op: user can still enter the OTP manually using this ID.
      },
    );
  }

  /// Verifies the OTP entered by the user and signs them in.
  Future<User?> verifyOtp({
    required String verificationId,
    required String smsCode,
  }) async {
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    final result = await _auth.signInWithCredential(credential);
    return result.user;
  }

  Future<void> sendPasswordResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: email.trim());
  }

  // ── Google Sign-In ──────────────────────────────────────────────────────

  /// Launches the Google sign-in flow. Returns null if the user cancels.
  Future<User?> signInWithGoogle() async {
    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) return null; // user cancelled

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final result = await _auth.signInWithCredential(credential);
    return result.user;
  }

  // ── Shared ──────────────────────────────────────────────────────────────

  Future<void> signOut() async {
    await Future.wait([
      _auth.signOut(),
      _googleSignIn.signOut(),
    ]);
  }

  /// Converts FirebaseAuthException codes into user-friendly messages.
  String _friendlyError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'That email address looks invalid.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'user-not-found':
        return 'No account found with that email.';
      case 'wrong-password':
        return 'Incorrect password. Please try again.';
      case 'email-already-in-use':
        return 'An account already exists with that email.';
      case 'weak-password':
        return 'Password is too weak. Use at least 6 characters.';
      case 'invalid-phone-number':
        return 'That phone number looks invalid.';
      case 'invalid-verification-code':
        return 'Incorrect OTP. Please check and try again.';
      case 'session-expired':
        return 'OTP expired. Please request a new one.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'network-request-failed':
        return 'Network error. Check your connection and try again.';
      default:
        return e.message ?? 'Something went wrong. Please try again.';
    }
  }
}
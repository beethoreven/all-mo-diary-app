/// Build-time settings. Neither is secret; both can be overridden for a test setup with
/// `--dart-define=AMD_API_BASE=...` / `--dart-define=AMD_WEB_CLIENT_ID=...`.
abstract final class Env {
  /// The all-mo-diary backend: router-backend's address plus `/all-mo-diary`, no trailing slash. Render added the
  /// `-3hl2` suffix because the name `router-backend` was already taken on onrender.com.
  static const apiBase = String.fromEnvironment(
    'AMD_API_BASE',
    defaultValue: 'https://router-backend-3hl2.onrender.com/all-mo-diary',
  );

  /// Google Cloud project all-mo-diary, OAuth client "all-mo-diary-web" (web application). The phone
  /// asks Google for ID tokens with this as the audience, and the backend checks it
  /// (ALL_MO_DIARY__GOOGLE_CLIENT_ID).
  static const webClientId = String.fromEnvironment(
    'AMD_WEB_CLIENT_ID',
    defaultValue: '759877918158-gp2co5qrmhataeu1rafvr3tl5odtkmc4.apps.googleusercontent.com',
  );

  static bool get backendConfigured => apiBase.isNotEmpty;

  static bool get googleConfigured => webClientId.isNotEmpty;
}

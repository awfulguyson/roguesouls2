class AppConfig {
  // Use compile-time constants set via --dart-define
  // For development: uses localhost
  // For production: set via --dart-define=API_BASE_URL=https://your-backend.com
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:3000',
  );

  static const String websocketUrl = String.fromEnvironment(
    'WEBSOCKET_URL',
    defaultValue: 'http://localhost:3000',
  );
}


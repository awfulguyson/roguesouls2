class AppConfig {
  // Use compile-time constants set via --dart-define
  // For development: set via --dart-define=API_BASE_URL=http://localhost:3000
  // For production: uses Render backend
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://roguesouls-backend.onrender.com',
  );

  static const String websocketUrl = String.fromEnvironment(
    'WEBSOCKET_URL',
    defaultValue: 'https://roguesouls-backend.onrender.com',
  );
}


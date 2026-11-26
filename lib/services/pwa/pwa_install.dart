import 'pwa_install_stub.dart' if (dart.library.js_interop) 'pwa_install_web.dart' as impl;

/// "Install the app" on the web (PWA). On Android and iOS builds this is a
/// no-op — the app is already installed.
class PwaInstall {
  const PwaInstall._();

  /// True on the web when not already running as an installed app.
  static bool get available => impl.pwaAvailable();

  /// True when the browser offered an install prompt we can show.
  static bool get canPrompt => impl.pwaCanPrompt();

  /// Shows the browser's install prompt; true when the player accepted.
  static Future<bool> prompt() => impl.pwaPrompt();
}

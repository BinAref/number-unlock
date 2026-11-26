import 'dart:js_interop';

// Defined in web/index.html (captures the browser's beforeinstallprompt).
@JS('unlockNumbersPwa.canPrompt')
external bool _canPrompt();

@JS('unlockNumbersPwa.isStandalone')
external bool _isStandalone();

@JS('unlockNumbersPwa.prompt')
external JSPromise<JSBoolean> _prompt();

bool pwaAvailable() {
  try {
    return !_isStandalone();
  } on Object {
    return false;
  }
}

bool pwaCanPrompt() {
  try {
    return _canPrompt();
  } on Object {
    return false;
  }
}

Future<bool> pwaPrompt() async {
  try {
    return (await _prompt().toDart).toDart;
  } on Object {
    return false;
  }
}

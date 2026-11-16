import 'package:flutter/foundation.dart' show kIsWeb;

/// Compile-time demo switch (#30):
///
///     flutter build web --release --wasm --dart-define=DEMO_MODE=true
///
/// The demo runs on a throwaway in-memory database seeded with sample
/// records, never opens the real ledger file, and shows a banner saying so.
const demoModeFlag = bool.fromEnvironment('DEMO_MODE');

/// The web build is always the demo: it has no persistent storage, so a
/// browser can never hold (or lose) a real ledger.
const isDemoMode = demoModeFlag || kIsWeb;

const demoBannerText =
    'Demo Mode: This is a temporary demonstration of My Little CRM. Any '
    'changes you make will be discarded when you refresh or close this page.';

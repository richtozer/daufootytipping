#!/usr/bin/env python3
"""Patches ONLY the startup wiring of a disposable copy of the released app, so it can run against the
local emulators with no production identity. All pages, view models and write paths stay as released.

  1. lib/firebase_options.dart : the web options name a demo project (the copy never names production)
  2. lib/main.dart             : App Check skipped (no reCAPTCHA / App Check traffic); the emulator
                                 hooks that the released app only enables in a debug build are enabled
                                 in this release build; the Auth emulator is configured (the released
                                 app has no Auth emulator hook)
Usage: patch_app.py <path to the disposable app copy>
"""
import sys

root = sys.argv[1]


def read(path):
    with open(f"{root}/{path}") as f:
        return f.read()


def write(path, text):
    with open(f"{root}/{path}", "w") as f:
        f.write(text)


def must_replace(text, old, new, label):
    if old not in text:
        raise SystemExit(f"patch failed ({label}): expected text not found")
    return text.replace(old, new)


# 1. demo-project web options
opts = read("lib/firebase_options.dart")
a = opts.index("  static const FirebaseOptions web = FirebaseOptions(")
b = opts.index("  );\n", a) + len("  );\n")
opts = (
    opts[:a]
    + """  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'demo-api-key',
    appId: '1:000000000000:web:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: 'demo-dau-rules',
    authDomain: 'demo-dau-rules.firebaseapp.com',
    databaseURL: 'https://demo-dau-rules-default-rtdb.firebaseio.com',
    storageBucket: 'demo-dau-rules.appspot.com',
  );
"""
    + opts[b:]
)
write("lib/firebase_options.dart", opts)

# 2. main.dart startup wiring
main = read("lib/main.dart")
a = main.index("  final bool useDebugAppCheck =")
b = main.index("  if (!kIsWeb && !(kDebugMode && useFirebaseEmulators)) {")
main = main[:a] + "  // SMOKE-TEST COPY: App Check is skipped (no reCAPTCHA or App Check traffic).\n  log('SMOKE: App Check skipped');\n\n" + main[b:]
main = main.replace("kDebugMode && useFirebaseEmulators", "useFirebaseEmulators")
main = must_replace(
    main,
    "  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);\n",
    "  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);\n"
    "  // SMOKE-TEST COPY: the released app has no Auth emulator hook.\n"
    "  await FirebaseAuth.instance.useAuthEmulator('localhost', 8099);\n",
    "auth emulator",
)
main = must_replace(
    main,
    "import 'package:firebase_core/firebase_core.dart';",
    "import 'package:firebase_auth/firebase_auth.dart';\nimport 'package:firebase_core/firebase_core.dart';",
    "auth import",
)
write("lib/main.dart", main)

# Safety: the web options of the patched copy must not name the production project.
check = read("lib/firebase_options.dart")
web = check[check.index("static const FirebaseOptions web"): check.index("static const FirebaseOptions android")]
if "demo-dau-rules" not in web:
    raise SystemExit("patched web options do not name the demo project")
print("patched:", root)

# Admin Authorization Strategy

This document outlines the recommended authorization strategy for Firebase Cloud Functions (Dart) that require admin-level privileges (e.g., triggering fixture downloads or forcing full rescores).

Since Cloud Functions execute on the server, security must be enforced server-side. Client-side state (such as checking `user.isAdmin` in the UI) is easily bypassed and must never be the sole gatekeeper for privileged operations.

---

## 1. Recommended First Implementation: RTDB Lookup

The simplest and most direct method is to look up the caller's tipper record in the Realtime Database during function execution.

### Flow
1. The client invokes the callable function.
2. The function extracts `context.auth.uid` from the invocation context.
3. The function queries the Realtime Database at `/AllTippers/{uid}`.
4. The function checks the `tipperRole` field.
5. If `tipperRole` is equal to `'admin'`, the execution continues. Otherwise, the function immediately terminates with an `HttpsError` (unauthenticated or permission-denied).

### Pseudo-code (Dart Cloud Function)

```dart
import 'package:firebase_functions_interop/firebase_functions_interop.dart';
import 'package:firebase_admin_interop/firebase_admin_interop.dart';

Future<void> adminFixtureDownload(CallRequest request, FunctionContext context) async {
  // 1. Check authentication
  final auth = context.auth;
  if (auth == null) {
    throw HttpsError(
      code: HttpsErrorCode.unauthenticated,
      message: 'The function must be called while authenticated.',
    );
  }

  final uid = auth.uid;

  // 2. Query RTDB to check admin role
  final app = FirebaseAdmin.instance.initializeApp();
  final database = app.database();
  final tipperRef = database.ref('/AllTippers/$uid');
  final snapshot = await tipperRef.once('value');

  if (!snapshot.exists) {
    throw HttpsError(
      code: HttpsErrorCode.permissionDenied,
      message: 'Tipper record not found.',
    );
  }

  final tipperData = snapshot.val() as Map;
  final role = tipperData['tipperRole'];

  // 3. Enforce the admin role
  if (role != 'admin') {
    throw HttpsError(
      code: HttpsErrorCode.permissionDenied,
      message: 'Only administrators can perform this action.',
    );
  }

  // Proceed with admin logic...
}
```

---

## 2. Advanced/Later Improvement: Firebase Auth Custom Claims

To avoid an extra RTDB read on every administrative function call, we can synchronize the tipper's role to Firebase Auth Custom Claims.

Custom Claims are metadata key-value pairs set on a user account by the Admin SDK. They are propagated inside the user's ID token and are available in the function context without requiring a database look-up.

### How it works:
1. An admin writes or modifies a tipper's role in the system.
2. A database trigger (`onWrite` for `/AllTippers/{uid}/tipperRole`) fires.
3. The trigger handler (running with admin privileges) calls the Firebase Auth Admin SDK to set the user's custom claim:
   ```javascript
   // Node/TypeScript trigger or equivalent Dart Function
   await admin.auth().setCustomUserClaims(uid, { role: 'admin' });
   ```
4. On subsequent requests, the client-side ID token carries the `role: 'admin'` claim.
5. In the callable function, checking the claim is instantaneous:

```dart
Future<void> adminFixtureDownload(CallRequest request, FunctionContext context) async {
  final auth = context.auth;
  if (auth == null) {
    throw HttpsError(code: HttpsErrorCode.unauthenticated);
  }

  // Custom claims are accessible in the auth token object
  final claims = auth.token.customClaims;
  if (claims['role'] != 'admin') {
    throw HttpsError(
      code: HttpsErrorCode.permissionDenied,
      message: 'Only administrators can perform this action.',
    );
  }

  // Proceed...
}
```

### Note on Token Latency
When custom claims are updated, the changes propagate to the client app the next time the ID token is refreshed (usually every hour), or when the client explicitly calls `user.getIdToken(true)` to force refresh.

/// What the identity callables take from the verified ID token of the caller.
/// The login address is read only from here, never from the request.
class CallerToken {
  const CallerToken({
    required this.uid,
    this.email,
    this.emailVerified = false,
    this.signInProvider,
    this.pictureUrl,
  });

  final String uid;
  final String? email;
  final bool emailVerified;

  /// `password`, `google.com`, `apple.com`, `anonymous` and so on.
  final String? signInProvider;
  final String? pictureUrl;

  bool get isAnonymous => signInProvider == 'anonymous';

  /// Reads the decoded claims of a callable's `request.auth.token`.
  factory CallerToken.fromClaims(String uid, Map<String, dynamic>? claims) {
    final firebase = claims?['firebase'];
    final provider = firebase is Map ? firebase['sign_in_provider'] : null;
    final email = claims?['email'];
    final picture = claims?['picture'];
    return CallerToken(
      uid: uid,
      email: email is String && email.trim().isNotEmpty ? email.trim() : null,
      emailVerified: claims?['email_verified'] == true,
      signInProvider: provider is String ? provider : null,
      pictureUrl: picture is String && picture.startsWith('https://')
          ? picture
          : null,
    );
  }
}

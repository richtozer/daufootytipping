import 'package:flutter/material.dart';

/// A route between screens that draw the same veiled backdrop, such as signing
/// out from the Profile page to the loader and sign-in screens.
///
/// It cross-fades the new page in over the old one, so the backdrop stays put
/// and only what sits on it changes. The platform transition instead fades both
/// pages over the theme's surface colour, which flashes the backdrop pale.
PageRouteBuilder<T> authFadeRoute<T>(WidgetBuilder builder) {
  return PageRouteBuilder<T>(
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionsBuilder: (context, animation, secondaryAnimation, child) =>
        FadeTransition(opacity: animation, child: child),
  );
}

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

Widget circleAvatarWithFallback({
  String? imageUrl,
  String? text,
  double radius = 35,
  Color? backgroundColor,
}) {
  String initials = '';
  text = text != null ? sanitizeString(text) : null;
  if (text != null && text.isNotEmpty) {
    List<String> nameParts = text.split(' ');

    if (nameParts.length > 1) {
      // If name is multiple words, use the first character of the first two words
      initials = nameParts
          .take(2)
          .map(
            (word) => word.characters.first,
          ) // Use characters.first for Unicode safety
          .join();
    } else {
      // If name is one word, use the first two grapheme clusters
      initials = text.characters
          .take(2)
          .toString(); // Take the first two grapheme clusters
    }
  }

  initials = initials.toUpperCase(); // Convert to uppercase
  return CircleAvatar(
    radius: radius,
    foregroundImage: (imageUrl == null || imageUrl.isEmpty)
        ? null
        : CachedNetworkImageProvider(imageUrl),
    backgroundColor: backgroundColor,
    child: Center(
      child: Text(
        initials,
        style: TextStyle(color: Colors.white, fontSize: radius == 40 ? 40 : 15),
      ),
    ),
  );
}

String sanitizeString(String input) {
  try {
    return String.fromCharCodes(input.codeUnits);
  } catch (e) {
    debugPrint('Invalid string detected: $input');
    return '??'; // Fallback initials
  }
}

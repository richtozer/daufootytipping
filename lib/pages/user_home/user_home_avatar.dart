import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

Widget circleAvatarWithFallback(
    {String? imageUrl,
    String? text,
    double radius = 35,
    Color? backgroundColor}) {
  String initials;
  List<String>? nameParts = text?.split(' ');

  if (nameParts != null && nameParts.isNotEmpty) {
    if (nameParts.length > 1) {
      // If name is multiple words, use first char from word 1 and first char from word 2
      initials = nameParts
          .take(2)
          .map((word) => word.isNotEmpty ? word[0] : '')
          .join();
    } else {
      // If name is one word, use first 2 chars
      initials = nameParts[0].substring(0, 2);
    }
  } else {
    initials = '';
  }

  initials = initials.toUpperCase();
  return CircleAvatar(
      radius: radius,
      foregroundImage: imageUrl == null || imageUrl == ''
          ? null
          : !kIsWeb
              ? CachedNetworkImageProvider(imageUrl)
              : Image.network(imageUrl)
                  .image, // TODO workaround for this bug: https://github.com/flutter/flutter/issues/160127
      backgroundColor: backgroundColor,
      child: Center(
        child: Text(initials,
            style: TextStyle(
              color: Colors.white,
              fontSize: radius == 30 ? 30 : 15,
            )),
      ));
}

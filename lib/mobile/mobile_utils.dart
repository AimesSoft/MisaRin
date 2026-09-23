import 'dart:io';

import 'package:flutter/widgets.dart';

bool isMobileOrPhone(BuildContext context) {
  if (Platform.isAndroid || Platform.isIOS) {
    final size = MediaQuery.sizeOf(context);
    // tablet is usually shortestSide >= 600
    if (size.shortestSide < 600) {
      return true;
    }
  }

  return false;
}

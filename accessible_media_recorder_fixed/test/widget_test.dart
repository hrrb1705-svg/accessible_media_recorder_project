import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:accessible_media_recorder/main.dart';

void main() {
  testWidgets('اجرا شدن ساده اپ', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.rtl,
        child: AccessibleMediaRecorderApp(),
      ),
    );
    expect(find.text('ضبط رسانه دسترس‌پذیر'), findsOneWidget);
  });
}

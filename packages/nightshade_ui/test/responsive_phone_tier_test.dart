import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

Future<
    ({
      bool isPhone,
      bool isCompactPhone,
      bool isMobile,
      bool isLandscape,
      bool isPhoneLandscape,
      bool isPhonePortrait,
    })> _probe(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  late bool isPhone;
  late bool isCompactPhone;
  late bool isMobile;
  late bool isLandscape;
  late bool isPhoneLandscape;
  late bool isPhonePortrait;

  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          isPhone = Responsive.isPhone(context);
          isCompactPhone = Responsive.isCompactPhone(context);
          isMobile = Responsive.isMobile(context);
          isLandscape = Responsive.isLandscape(context);
          isPhoneLandscape = Responsive.isPhoneLandscape(context);
          isPhonePortrait = Responsive.isPhonePortrait(context);
          return const SizedBox.shrink();
        },
      ),
    ),
  );

  return (
    isPhone: isPhone,
    isCompactPhone: isCompactPhone,
    isMobile: isMobile,
    isLandscape: isLandscape,
    isPhoneLandscape: isPhoneLandscape,
    isPhonePortrait: isPhonePortrait,
  );
}

void main() {
  testWidgets('360x640 is a compact phone in portrait', (tester) async {
    final r = await _probe(tester, const Size(360, 640));
    expect(r.isPhone, isTrue);
    expect(r.isCompactPhone, isTrue);
    expect(r.isMobile, isTrue);
    expect(r.isPhonePortrait, isTrue);
    expect(r.isPhoneLandscape, isFalse);
  });

  testWidgets('390x844 is a (compact) phone in portrait', (tester) async {
    final r = await _probe(tester, const Size(390, 844));
    expect(r.isPhone, isTrue);
    // 390 < 480 so it IS compact.
    expect(r.isCompactPhone, isTrue);
    expect(r.isPhonePortrait, isTrue);
  });

  testWidgets('540x900 is a phone but not compact', (tester) async {
    final r = await _probe(tester, const Size(540, 900));
    expect(r.isPhone, isTrue);
    expect(r.isCompactPhone, isFalse); // 540 >= 480
  });

  testWidgets('844x390 rotated is phone landscape', (tester) async {
    final r = await _probe(tester, const Size(844, 390));
    // 844 >= 600 so it is NOT a phone by width.
    expect(r.isPhone, isFalse);
    expect(r.isLandscape, isTrue);
  });

  testWidgets('520-wide landscape is a phone in landscape', (tester) async {
    final r = await _probe(tester, const Size(520, 360));
    expect(r.isPhone, isTrue);
    expect(r.isPhoneLandscape, isTrue);
    expect(r.isPhonePortrait, isFalse);
  });

  testWidgets('700-wide is not a phone (small tablet)', (tester) async {
    final r = await _probe(tester, const Size(700, 1000));
    expect(r.isPhone, isFalse);
    expect(r.isMobile, isTrue); // legacy bucket still < 768
  });

  test('phone/compact thresholds match BreakpointTokens', () {
    expect(Responsive.phoneMaxWidth, BreakpointTokens.breakpointPhone);
    expect(Responsive.compactPhoneMaxWidth, 480.0);
  });
}

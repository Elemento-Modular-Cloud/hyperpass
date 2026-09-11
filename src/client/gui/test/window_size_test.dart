import 'dart:ui';

import 'package:elp_gui/layout/compact_layout.dart';
import 'package:elp_gui/window_size.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:elp_gui/logger.dart' as log;

void main() {
  setUpAll(() {
    log.logger = Logger(
      printer: PrettyPrinter(methodCount: 0),
      output: ConsoleOutput(),
    );
  });

  test('minimum window size clamps to a small visible frame', () {
    final min = computeMinimumWindowSize(const Size(700, 480));
    expect(min.width, lessThanOrEqualTo(750));
    expect(min.height, lessThanOrEqualTo(450));
    expect(min.width, greaterThanOrEqualTo(CompactLayout.floorWidth));
    expect(min.height, greaterThanOrEqualTo(CompactLayout.floorHeight));
  });

  test('default size on a small screen does not exceed the preferred min', () {
    final size = computeDefaultWindowSize(const Size(1024, 576));
    expect(size.width, lessThanOrEqualTo(750));
    expect(size.height, lessThanOrEqualTo(450));
  });

  test('compact layout is detected below breakpoints', () {
    expect(CompactLayout.isCompactSize(const Size(1280, 800)), isFalse);
    expect(CompactLayout.isCompactSize(const Size(800, 700)), isTrue);
    expect(CompactLayout.isCompactSize(const Size(1100, 500)), isTrue);
  });
}

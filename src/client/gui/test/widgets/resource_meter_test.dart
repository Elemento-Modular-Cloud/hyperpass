import 'package:elp_gui/brand.dart';
import 'package:elp_gui/widgets/resource_meter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fillFor uses info below 70%, warning to 90%, critical above', () {
    expect(ResourceMeter.warningThreshold, 0.7);
    expect(ResourceMeter.criticalThreshold, 0.9);

    final healthy = ResourceMeter.fillFor(0.4);
    expect(healthy, Brand.info.withValues(alpha: 0.75));

    expect(ResourceMeter.fillFor(0.7), Brand.warning);
    expect(ResourceMeter.fillFor(0.89), Brand.warning);
    expect(ResourceMeter.fillFor(0.9), Brand.critical);
    expect(ResourceMeter.fillFor(1), Brand.critical);
  });

  test('workload AI allocation is not LaunchPad orange', () {
    expect(Brand.workloadAi, isNot(Brand.primary));
    expect(Brand.workloadAi, const Color(0xFFC792EA));
  });
}

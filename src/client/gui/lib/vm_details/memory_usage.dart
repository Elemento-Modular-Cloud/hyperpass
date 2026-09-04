import 'package:flutter/material.dart';

import '../widgets/resource_meter.dart';

class MemoryUsage extends StatelessWidget {
  final String used;
  final String total;

  const MemoryUsage({super.key, required this.used, required this.total});

  static Color get normalColor => ResourceMeter.fillFor(0);
  static Color get almostFullColor => ResourceMeter.fillFor(0.85);
  static const backgroundColor = Color(0x3dFFA600);

  @override
  Widget build(BuildContext context) {
    final usedValue = double.tryParse(used) ?? 0;
    final totalValue = double.tryParse(total) ?? 1;
    var progress = usedValue / totalValue;
    progress = progress.isFinite ? progress : 0.0;
    final valueText =
        progress != 0 ? '${formatResourceBytes(used)} / ${formatResourceBytes(total)}' : '-';

    return ResourceMeter(
      label: '',
      valueText: valueText,
      progress: progress,
      compact: true,
      showLabel: false,
    );
  }
}

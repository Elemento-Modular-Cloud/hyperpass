import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'brand.dart';

/// HSV colour wheel + value slider + hex field (desktop-friendly).
class HsvColourPicker extends StatefulWidget {
  const HsvColourPicker({
    required this.color,
    required this.onChanged,
    super.key,
  });

  final Color color;
  final ValueChanged<Color> onChanged;

  @override
  State<HsvColourPicker> createState() => _HsvColourPickerState();
}

class _HsvColourPickerState extends State<HsvColourPicker> {
  late HSVColor _hsv;
  late TextEditingController _hexController;
  bool _editingHex = false;

  static const _presets = <Color>[
    Color(0xFF1A1A2E),
    Color(0xFF1C1CBA),
    Color(0xFF0033FF),
    Color(0xFF120030),
    Color(0xFF000000),
    Color(0xFF343441),
    Color(0xFF1A1C20),
    Color(0xFFF5F5FA),
    Color(0xFFFFFFFF),
    Brand.accent,
    Color(0xFFFF0055),
    Color(0xFF00C853),
  ];

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.color);
    _hexController = TextEditingController(text: _hexOf(_hsv.toColor()));
  }

  @override
  void didUpdateWidget(covariant HsvColourPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.color != widget.color && !_editingHex) {
      _hsv = HSVColor.fromColor(widget.color);
      _hexController.text = _hexOf(_hsv.toColor());
    }
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  void _emit(HSVColor next) {
    setState(() => _hsv = next);
    final color = next.toColor();
    if (!_editingHex) {
      _hexController.value = TextEditingValue(
        text: _hexOf(color),
        selection: TextSelection.collapsed(offset: _hexOf(color).length),
      );
    }
    widget.onChanged(color);
  }

  static String _hexOf(Color color) {
    final rgb = color.toARGB32() & 0xFFFFFF;
    return rgb.toRadixString(16).padLeft(6, '0').toUpperCase();
  }

  void _applyHex(String raw) {
    var value = raw.trim().replaceFirst('#', '');
    if (value.length == 3) {
      value = value.split('').map((c) => '$c$c').join();
    }
    if (value.length != 6) return;
    final parsed = int.tryParse(value, radix: 16);
    if (parsed == null) return;
    _emit(HSVColor.fromColor(Color(0xFF000000 | parsed)));
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final color = _hsv.toColor();

    return SizedBox(
      width: 280,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: _HueSatWheel(
                    hsv: _hsv,
                    onChanged: _emit,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _ValueSlider(
                hsv: _hsv,
                onChanged: _emit,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(Brand.radius),
                  border: Border.all(color: onSurface.withValues(alpha: 0.25)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _hexController,
                  onTap: () => _editingHex = true,
                  onChanged: _applyHex,
                  onEditingComplete: () {
                    _editingHex = false;
                    _applyHex(_hexController.text);
                    FocusScope.of(context).unfocus();
                  },
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[#0-9a-fA-F]')),
                    LengthLimitingTextInputFormatter(7),
                  ],
                  decoration: InputDecoration(
                    prefixText: '#',
                    labelText: 'Hex',
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Brand.radius),
                    ),
                  ),
                  style: TextStyle(
                    fontFamily: Brand.fontFamily,
                    color: onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final preset in _presets)
                InkWell(
                  onTap: () => _emit(HSVColor.fromColor(preset)),
                  borderRadius: BorderRadius.circular(Brand.radius),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: preset,
                      borderRadius: BorderRadius.circular(Brand.radius),
                      border: Border.all(
                        color: _hexOf(preset) == _hexOf(color)
                            ? Brand.accent
                            : onSurface.withValues(alpha: 0.2),
                        width: _hexOf(preset) == _hexOf(color) ? 2 : 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HueSatWheel extends StatelessWidget {
  const _HueSatWheel({
    required this.hsv,
    required this.onChanged,
  });

  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  void _update(Offset local, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    final delta = local - center;
    final distance = delta.distance.clamp(0.0, radius);
    final angle = (math.atan2(delta.dy, delta.dx) + math.pi * 2) % (math.pi * 2);
    final hue = angle * 180 / math.pi;
    final saturation = (distance / radius).clamp(0.0, 1.0);
    onChanged(hsv.withHue(hue).withSaturation(saturation));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          onPanDown: (d) => _update(d.localPosition, size),
          onPanUpdate: (d) => _update(d.localPosition, size),
          child: CustomPaint(
            painter: _HueSatWheelPainter(hsv: hsv),
            size: size,
          ),
        );
      },
    );
  }
}

class _HueSatWheelPainter extends CustomPainter {
  _HueSatWheelPainter({required this.hsv});

  final HSVColor hsv;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;

    final huePaint = Paint()
      ..shader = SweepGradient(
        colors: [
          for (var i = 0; i <= 12; i++)
            HSVColor.fromAHSV(1, (i * 30) % 360, 1, 1).toColor(),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, huePaint);

    final satPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white,
          Colors.white.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, satPaint);

    // Dim by value so the wheel matches the selected brightness.
    if (hsv.value < 1) {
      canvas.drawCircle(
        center,
        radius,
        Paint()..color = Colors.black.withValues(alpha: 1 - hsv.value),
      );
    }

    final angle = hsv.hue * math.pi / 180;
    final marker = Offset(
      center.dx + math.cos(angle) * hsv.saturation * radius,
      center.dy + math.sin(angle) * hsv.saturation * radius,
    );
    canvas.drawCircle(
      marker,
      8,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    canvas.drawCircle(
      marker,
      8,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _HueSatWheelPainter oldDelegate) =>
      oldDelegate.hsv != hsv;
}

class _ValueSlider extends StatelessWidget {
  const _ValueSlider({
    required this.hsv,
    required this.onChanged,
  });

  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 220,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final height = constraints.maxHeight;
          return GestureDetector(
            onPanDown: (d) {
              final t = (1 - (d.localPosition.dy / height)).clamp(0.0, 1.0);
              onChanged(hsv.withValue(t));
            },
            onPanUpdate: (d) {
              final t = (1 - (d.localPosition.dy / height)).clamp(0.0, 1.0);
              onChanged(hsv.withValue(t));
            },
            child: CustomPaint(
              painter: _ValueSliderPainter(hsv: hsv),
              size: Size(constraints.maxWidth, height),
            ),
          );
        },
      ),
    );
  }
}

class _ValueSliderPainter extends CustomPainter {
  _ValueSliderPainter({required this.hsv});

  final HSVColor hsv;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(4, 0, size.width - 8, size.height),
      const Radius.circular(6),
    );
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          hsv.withValue(1).toColor(),
          hsv.withValue(0).toColor(),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRRect(rect, paint);

    final y = (1 - hsv.value) * size.height;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(size.width / 2, y), width: size.width, height: 6),
        const Radius.circular(3),
      ),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _ValueSliderPainter oldDelegate) =>
      oldDelegate.hsv != hsv;
}

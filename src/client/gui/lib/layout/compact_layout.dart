import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Layout helpers for smaller laptop displays.
abstract final class CompactLayout {
  static const widthBreakpoint = 900.0;
  static const heightBreakpoint = 600.0;
  static const compactTextScale = 0.9;

  static const preferredMinWidth = 750.0;
  static const preferredMinHeight = 450.0;
  static const floorWidth = 640.0;
  static const floorHeight = 400.0;

  static bool isCompactSize(Size size) =>
      size.width < widthBreakpoint || size.height < heightBreakpoint;

  static Size computeMinimumWindowSize(Size? screenSize) {
    const preferred = Size(preferredMinWidth, preferredMinHeight);
    if (screenSize == null) return preferred;
    final width = math.min(preferred.width, screenSize.width * 0.95);
    final height = math.min(preferred.height, screenSize.height * 0.9);
    return Size(
      math.max(floorWidth, width),
      math.max(floorHeight, height),
    );
  }

  static double dialogWidth(BuildContext context, double preferred) {
    final maxWidth = MediaQuery.sizeOf(context).width * 0.92;
    return math.min(preferred, maxWidth);
  }
}

class CompactScope extends InheritedWidget {
  const CompactScope({
    required this.isCompact,
    required super.child,
    super.key,
  });

  final bool isCompact;

  static bool of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<CompactScope>()?.isCompact ??
        false;
  }

  @override
  bool updateShouldNotify(CompactScope oldWidget) =>
      isCompact != oldWidget.isCompact;
}

class SidebarForceExpandedNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;

  void setExpanded(bool value) => state = value;
}

final sidebarForceExpandedProvider =
    NotifierProvider<SidebarForceExpandedNotifier, bool>(
  SidebarForceExpandedNotifier.new,
);

bool sidebarCollapsedOf(BuildContext context, WidgetRef ref) {
  final compact = CompactScope.of(context);
  final forceExpanded = ref.watch(sidebarForceExpandedProvider);
  return compact && !forceExpanded;
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'overview_feature_banners.dart';
import 'overview_hero.dart';
import 'overview_running_grid.dart';
import 'overview_system_rail.dart';

class OverviewScreen extends ConsumerWidget {
  static const sidebarKey = 'overview';

  const OverviewScreen({super.key});

  static const _railBreakpoint = 1180.0;
  static const _railWidth = 320.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final showRailBeside = constraints.maxWidth >= _railBreakpoint;

          final mainColumn = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const OverviewHero(),
              const SizedBox(height: 20),
              const OverviewRunningGrid(),
              const SizedBox(height: 20),
              const OverviewFeatureBanners(),
              if (!showRailBeside) ...[
                const SizedBox(height: 20),
                const OverviewSystemRail(),
              ],
            ],
          );

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
            child: showRailBeside
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: mainColumn),
                      const SizedBox(width: 20),
                      const SizedBox(
                        width: _railWidth,
                        child: OverviewSystemRail(),
                      ),
                    ],
                  )
                : mainColumn,
          );
        },
      ),
    );
  }
}

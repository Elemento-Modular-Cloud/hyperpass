import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'appearance_settings.dart';
import 'brand.dart';

/// Full-window backdrop (Electros `body` wallpaper + `atmosphere-background`).
class AppBackground extends ConsumerStatefulWidget {
  const AppBackground({super.key});

  @override
  ConsumerState<AppBackground> createState() => _AppBackgroundState();
}

class _AppBackgroundState extends ConsumerState<AppBackground>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _syncAnimation(AppearanceSettings settings) {
    final controller = _controller;
    if (controller == null) return;
    final shouldAnimate = settings.wallpaperType == WallpaperType.atmosphere &&
        settings.animate;
    if (shouldAnimate && !controller.isAnimating) {
      controller.repeat();
    } else if (!shouldAnimate && controller.isAnimating) {
      controller.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appearanceSettingsProvider);
    _syncAnimation(settings);

    return switch (settings.wallpaperType) {
      WallpaperType.colour => ColoredBox(
          color: settings.wallpaperColor ??
              themeBackgroundColor(settings.theme),
        ),
      WallpaperType.image || WallpaperType.provider =>
        _ImageWallpaper(settings: settings),
      WallpaperType.none =>
        ColoredBox(color: themeBackgroundColor(settings.theme)),
      WallpaperType.atmosphere => _AtmosphereBackground(
          settings: settings,
          animation: _controller!,
        ),
    };
  }
}

class _ImageWallpaper extends ConsumerWidget {
  const _ImageWallpaper({required this.settings});

  final AppearanceSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fallback = ColoredBox(color: themeBackgroundColor(settings.theme));

    final image = wallpaperImageProvider(settings);
    if (image != null) {
      return _WallpaperImage(source: image, settings: settings);
    }

    if (settings.wallpaperType == WallpaperType.provider) {
      final fileAsync = ref.watch(providerWallpaperFileProvider);
      return fileAsync.when(
        data: (file) {
          if (file == null) return fallback;
          return _WallpaperImage(source: FileImage(file), settings: settings);
        },
        loading: () => fallback,
        error: (_, __) => fallback,
      );
    }

    return fallback;
  }
}

class _WallpaperImage extends StatelessWidget {
  const _WallpaperImage({
    required this.source,
    required this.settings,
  });

  final ImageProvider source;
  final AppearanceSettings settings;

  @override
  Widget build(BuildContext context) {
    final brightness = settings.wallpaperBrightness / 100;
    final blur = settings.wallpaperBlur;

    Widget image = Image(
      image: source,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      gaplessPlayback: true,
    );

    if (blur > 0) {
      image = ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: image,
      );
    }

    if (brightness != 1) {
      image = ColorFiltered(
        colorFilter: ColorFilter.matrix(<double>[
          brightness, 0, 0, 0, 0,
          0, brightness, 0, 0, 0,
          0, 0, brightness, 0, 0,
          0, 0, 0, 1, 0,
        ]),
        child: image,
      );
    }

    return SizedBox.expand(child: image);
  }
}

class _AtmosphereBackground extends StatelessWidget {
  const _AtmosphereBackground({
    required this.settings,
    required this.animation,
  });

  final AppearanceSettings settings;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final base = themeBackgroundColor(settings.theme);
    if (settings.theme == AppearanceTheme.light) {
      return ColoredBox(
        color: base,
        child: const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFF5F5FA),
                Color(0xFFE8E8F2),
                Color(0xFFF0F0F8),
              ],
            ),
          ),
        ),
      );
    }

    if (!settings.animate) {
      return ColoredBox(
        color: base,
        child: const DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(-0.3, -0.5),
              radius: 1.4,
              colors: [
                Color(0xFF001A66),
                Color(0xFF120030),
                Color(0xFF000000),
              ],
              stops: [0, 0.55, 1],
            ),
          ),
        ),
      );
    }

    return ColoredBox(
      color: base,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          final t = animation.value;
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(
                  -0.3 + 0.2 * (t * 2 % 1),
                  -0.5 + 0.15 * ((t + 0.3) % 1),
                ),
                radius: 1.4,
                colors: const [
                  Color(0xFF001A66),
                  Color(0xFF120030),
                  Color(0xFF000000),
                ],
                stops: [0, 0.55, 1],
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Brand.accent.withValues(alpha: 0.18),
                        Colors.transparent,
                        const Color(0xFF0033FF).withValues(alpha: 0.22),
                      ],
                      stops: const [0, 0.45, 1],
                      transform: GradientRotation(t * 6.28),
                    ),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(0.8 - t * 0.4, 1.1),
                      radius: 0.9,
                      colors: [
                        const Color(0xFFFF0055).withValues(alpha: 0.12),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'features/common/ad_overlay.dart';
import 'features/home/home_screen.dart';
import 'services/app_services.dart';
import 'ui/world/world_backdrop.dart';

/// The app shell: language, direction, theme and the living world that
/// stays behind every page.
class UnlockNumbersApp extends StatefulWidget {
  const UnlockNumbersApp({super.key, required this.services, this.home});

  final AppServices services;

  /// The first page (tests may start elsewhere; the game starts at home).
  final Widget? home;

  /// Shared parallax camera (moved by the levels map).
  static final WorldCamera camera = WorldCamera();

  @override
  State<UnlockNumbersApp> createState() => _UnlockNumbersAppState();
}

class _UnlockNumbersAppState extends State<UnlockNumbersApp> with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> _navigator = GlobalKey<NavigatorState>();

  AppServices get s => widget.services;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    installMockAds(s, _navigator);
    s.theme.addListener(_themeChanged);
    s.audio.music(s.theme.activeId);
    s.levels.ensureAhead(s.player.progress.highestUnlocked);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    s.theme.removeListener(_themeChanged);
    super.dispose();
  }

  void _themeChanged() => s.audio.music(s.theme.activeId);

  @override
  void didChangePlatformBrightness() => s.theme.platformChanged(WidgetsBinding.instance.platformDispatcher.platformBrightness);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      s.audio.pause();
    } else if (state == AppLifecycleState.resumed) {
      s.audio.resume();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Services(
      services: s,
      child: ListenableBuilder(
        listenable: Listenable.merge([s.i18n, s.theme]),
        builder: (context, _) {
          final t = s.theme.tokens;
          return MaterialApp(
            navigatorKey: _navigator,
            debugShowCheckedModeBanner: false,
            onGenerateTitle: (_) => s.i18n.t('app.name'),
            locale: s.i18n.locale,
            supportedLocales: s.i18n.supportedLocales,
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: ThemeData(
              useMaterial3: true,
              brightness: t.brightness,
              fontFamily: s.i18n.current.font,
              scaffoldBackgroundColor: Colors.transparent,
              canvasColor: Colors.transparent,
              colorScheme: ColorScheme.fromSeed(seedColor: t.color('gold.base'), brightness: t.brightness),
              textSelectionTheme: TextSelectionThemeData(cursorColor: t.color('text.accent'), selectionColor: t.color('stone.purple')),
            ),
            builder: (context, child) => Stack(children: [
              Positioned.fill(child: WorldBackdrop(camera: UnlockNumbersApp.camera)),
              if (child != null) Positioned.fill(child: child),
            ]),
            home: widget.home ?? const HomeScreen(),
          );
        },
      ),
    );
  }
}

import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'player/media_session_handler.dart';
import 'player/music_player_controller.dart';
import 'screens/download_screen.dart';
import 'screens/now_playing_screen.dart';
import 'screens/playlist_screen.dart';
import 'screens/search_screen.dart';
import 'services/database_service.dart';
import 'services/resume_store.dart';
import 'services/update_service.dart';
import 'services/youtube_service.dart';
import 'theme/app_theme.dart';
import 'widgets/mini_player.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb && Platform.isAndroid) {
    try {
      await AudioService.init(
        builder: () => MediaSessionHandler.instance,
        config: const AudioServiceConfig(
          androidNotificationChannelId:
              'com.example.yt_local_music.channel.audio',
          androidNotificationChannelName: 'Playback',
          androidNotificationChannelDescription:
              'Media notification and playback controls',
          androidNotificationIcon: 'mipmap/launcher_icon',
          androidNotificationClickStartsActivity: true,
          fastForwardInterval: Duration(seconds: 10),
          rewindInterval: Duration(seconds: 10),
        ),
      );
    } catch (e) {
      debugPrint('[main] media session unavailable: $e');
    }
  }

  // The controller is app-scoped (created here, never by the widget layer) so
  // it, and the media session mirroring it, survive navigation and activity
  // teardown while playback lives in the foreground service.
  final youtubeService = YouTubeService();
  final controller = MusicPlayerController(
    streamUrlResolver: (songId) => youtubeService.getAudioStreamUrl(songId),
    resumeStore: DatabaseResumeStore(),
  );
  MediaSessionHandler.instance.attach(controller);

  // App-scoped update engine. FreeVibe is offline-first: no update check runs
  // at startup. The engine gates Internet-dependent actions via
  // `hasInternetConnection` and lazily checks for updates after an online
  // search (failures are silently ignored, search never waits on it).
  final updateService = UpdateService();

  runApp(
    MyApp(
      controller: controller,
      youtubeService: youtubeService,
      updateService: updateService,
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({
    super.key,
    this.controller,
    this.youtubeService,
    this.updateService,
  });

  /// Injectable for widget tests. When null, [HomeScreen] builds/owns its own
  /// controller backed by the real AudioService.
  final MusicPlayerController? controller;

  /// Injectable for widget tests. When null, [HomeScreen] builds/owns its own.
  final YouTubeService? youtubeService;

  /// Injectable for widget tests / app startup. When null the update flow is
  /// skipped entirely (tests stay plugin-free).
  final UpdateService? updateService;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'YT Local Music',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: HomeScreen(
        controller: controller,
        youtubeService: youtubeService,
        updateService: updateService,
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.controller,
    this.youtubeService,
    this.updateService,
  });

  final MusicPlayerController? controller;

  final YouTubeService? youtubeService;

  final UpdateService? updateService;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  late final MusicPlayerController _playerController;
  late final YouTubeService _youtubeService;
  ({bool shuffle, RepeatStyle repeat})? _lastSavedSettings;

  @override
  void initState() {
    super.initState();
    _youtubeService = widget.youtubeService ?? YouTubeService();
    _playerController =
        widget.controller ??
        MusicPlayerController(
          streamUrlResolver: (songId) =>
              _youtubeService.getAudioStreamUrl(songId),
          resumeStore: DatabaseResumeStore(),
        );
    _playerController.init();
    _playerController.addListener(_onPlayerChanged);
    _restoreSettings();
  }

  Future<void> _restoreSettings() async {
    try {
      final db = DatabaseService.instance;
      final shuffle = await db.getSetting('shuffle') == 'true';
      final repeatName = await db.getSetting('repeat');
      final repeat = RepeatStyle.values.firstWhere(
        (mode) => mode.name == repeatName,
        orElse: () => RepeatStyle.off,
      );
      _playerController.restoreSettings(shuffle: shuffle, repeat: repeat);
      // Warm the in-memory resume cache so "Continue · X:XX" hints are
      // available right away after a fresh app start.
      _playerController.warmResumePositions();
    } catch (e) {
      debugPrint('[HomeScreen] could not restore settings: $e');
    }
  }

  void _onPlayerChanged() {
    final settings = _playerController.exportSettings();
    if (settings == _lastSavedSettings) {
      return;
    }
    _lastSavedSettings = settings;
    _persistSettings(settings);
  }

  Future<void> _persistSettings(
    ({bool shuffle, RepeatStyle repeat}) settings,
  ) async {
    try {
      final db = DatabaseService.instance;
      await db.setSetting('shuffle', settings.shuffle.toString());
      await db.setSetting('repeat', settings.repeat.name);
    } catch (e) {
      debugPrint('[HomeScreen] could not persist settings: $e');
    }
  }

  @override
  void dispose() {
    _playerController.removeListener(_onPlayerChanged);
    // Only dispose what this widget created; app-scoped instances injected
    // from main() (which back the media session) live for the whole process.
    if (widget.controller == null) {
      _playerController.dispose();
    }
    if (widget.youtubeService == null) {
      _youtubeService.dispose();
    }
    super.dispose();
  }

  void _openNowPlaying() {
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 280),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (context, animation, secondaryAnimation) =>
            NowPlayingScreen(controller: _playerController),
        transitionsBuilder: (context, animation, secondary, child) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.08),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          );
        },
      ),
    );
  }

  void _openDownloadHistory() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const DownloadScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _HeaderNavigation(
              selectedIndex: _currentIndex,
              onSelected: (index) => setState(() => _currentIndex = index),
              onHistory: _openDownloadHistory,
            ),
            Expanded(
              child: IndexedStack(
                index: _currentIndex,
                children: [
                  PlaylistScreen(playerController: _playerController),
                  SearchScreen(
                    youtubeService: _youtubeService,
                    playerController: _playerController,
                    updateService: widget.updateService,
                  ),
                ],
              ),
            ),
            MiniPlayer(
              controller: _playerController,
              onOpenNowPlaying: _openNowPlaying,
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderNavigation extends StatelessWidget {
  const _HeaderNavigation({
    required this.selectedIndex,
    required this.onSelected,
    required this.onHistory,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 10, 8),
      child: Row(
        children: [
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    _HeaderDestination(
                      icon: Icons.library_music_rounded,
                      label: 'Library',
                      selected: selectedIndex == 0,
                      onTap: () => onSelected(0),
                    ),
                    _HeaderDestination(
                      icon: Icons.download_rounded,
                      label: 'Download',
                      selected: selectedIndex == 1,
                      onTap: () => onSelected(1),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Tooltip(
            message: 'History',
            child: IconButton(
              onPressed: onHistory,
              tooltip: 'Open History',
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: const Icon(Icons.history_rounded),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderDestination extends StatelessWidget {
  const _HeaderDestination({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.primary
              : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Semantics(
          button: true,
          selected: selected,
          label: label,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(24),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 11),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 19),
                  const SizedBox(width: 7),
                  Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

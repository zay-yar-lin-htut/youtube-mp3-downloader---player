import 'package:flutter/material.dart';
import 'player/music_player_controller.dart';
import 'services/youtube_service.dart';
import 'services/database_service.dart';
import 'screens/search_screen.dart';
import 'screens/playlist_screen.dart';
import 'screens/download_screen.dart';
import 'screens/now_playing_screen.dart';
import 'widgets/mini_player.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.controller});

  /// Injectable for widget tests. When null, [HomeScreen] builds its own
  /// controller backed by the real AudioService.
  final MusicPlayerController? controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'YT Local Music',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: HomeScreen(controller: controller),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.controller});

  final MusicPlayerController? controller;

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
    _youtubeService = YouTubeService();
    _playerController =
        widget.controller ?? MusicPlayerController(
              streamUrlResolver: (songId) =>
                  _youtubeService.getAudioStreamUrl(songId),
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
      ({bool shuffle, RepeatStyle repeat}) settings) async {
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
    _playerController.dispose();
    _youtubeService.dispose();
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
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOut,
            ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: IndexedStack(
                index: _currentIndex,
                children: [
                  SearchScreen(
                    youtubeService: _youtubeService,
                    playerController: _playerController,
                  ),
                  const DownloadScreen(),
                  PlaylistScreen(playerController: _playerController),
                ],
              ),
            ),
            MiniPlayer(
              controller: _playerController,
              onOpenNowPlaying: _openNowPlaying,
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: 4),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.search_rounded),
            selectedIcon: Icon(Icons.search_rounded),
            label: 'Search',
          ),
          NavigationDestination(
            icon: Icon(Icons.download_rounded),
            selectedIcon: Icon(Icons.download_rounded),
            label: 'Downloads',
          ),
          NavigationDestination(
            icon: Icon(Icons.library_music_rounded),
            selectedIcon: Icon(Icons.library_music_rounded),
            label: 'Playlist',
          ),
        ],
      ),
    );
  }
}
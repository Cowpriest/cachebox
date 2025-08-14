// lib/screens/video_player_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';

class VideoPlayerScreen extends StatefulWidget {
  final String videoUrl;
  final String? fileName;

  // Optional: provide the whole folder playlist (sorted alphanumerically).
  final List<String>? playlistUrls; // parallel to playlistNames
  final List<String>? playlistNames; // optional labels
  final int? initialIndex; // index within playlistUrls for videoUrl

  const VideoPlayerScreen({
    super.key,
    required this.videoUrl,
    this.fileName,
    this.playlistUrls,
    this.playlistNames,
    this.initialIndex,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

enum _LoopMode { none, one, all }

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late final Player _player;
  late final VideoController _controller;

  StreamSubscription<dynamic>? _errorSub;
  StreamSubscription<Tracks>? _tracksSub;
  StreamSubscription<PlaylistMode>? _modeSub;
  StreamSubscription<Playlist>? _playlistSub;
  bool _audioOnly = false;

  // Subtitles
  List<SubtitleTrack> _subtitleTracks = const [];
  SubtitleTrack? _currentSubtitle;
  // Persisted subtitle pref: 'off' | 'auto' | null (unset)
  static const _kSubtitlePrefKey = 'video_subtitle_pref';
  String? _savedSubtitlePref; // last saved value
  bool _savedPrefAppliedOnce = false; // apply once after tracks appear

  bool _isOff(SubtitleTrack t) => t.id == SubtitleTrack.no().id;
  bool _isAuto(SubtitleTrack t) => t.id == SubtitleTrack.auto().id;

  Future<void> _persistSubtitlePref(String pref) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSubtitlePrefKey, pref); // 'off' or 'auto'
    _savedSubtitlePref = pref;
  }

  Future<void> _restoreSubtitlePref() async {
    final prefs = await SharedPreferences.getInstance();
    _savedSubtitlePref = prefs.getString(_kSubtitlePrefKey);

    // Default to OFF if nothing saved yet
    final initial = _savedSubtitlePref ?? 'off';

    if (initial == 'off') {
      await _player.setSubtitleTrack(SubtitleTrack.no());
      _currentSubtitle = SubtitleTrack.no();
    } else {
      await _player.setSubtitleTrack(SubtitleTrack.auto());
      _currentSubtitle = SubtitleTrack.auto();
    }
    if (mounted) setState(() {});
  }

  // Looping & playlist
  _LoopMode _loopMode = _LoopMode.one;
  bool _hasUsablePlaylist = false;
  List<Media> _playlist = const [];
  int _currentIndex = 0;

  // Title (AppBar) + toast
  String? _currentTitle;
  OverlayEntry? _titleOverlay;
  Timer? _titleHideTimer;

  // Overlay controls (center Play/Pause)
  // bool _controlsVisible = false;
  // Timer? _controlsHideTimer;

  @override
  void initState() {
    super.initState();

    _player = Player();
    _controller = VideoController(_player);
    // Apply saved Off/Auto immediately (and set chip)
    _restoreSubtitlePref();

    _initPlaylistFromWidget();
    _applyLoopMode(_LoopMode.one, initializing: true);

    _modeSub = _player.stream.playlistMode.listen((mode) {
      final m = (mode == PlaylistMode.none)
          ? _LoopMode.none
          : (mode == PlaylistMode.single ? _LoopMode.one : _LoopMode.all);
      if (mounted) setState(() => _loopMode = m);
    });

    _playlistSub = _player.stream.playlist.listen((pl) {
      if (!mounted || pl == null) return;
      _updateTitleFromState(showToast: true); // toast is now deferred safely
    });

    _tracksSub = _player.stream.tracks.listen((tracks) async {
      final filtered = _filterSubtitleTracks(tracks.subtitle);
      final deduped = _dedupeById(filtered);
      if (!mounted) return;

      setState(() {
        _subtitleTracks = deduped; // (we removed the injected 'Off' earlier)
        _audioOnly = tracks.video.isEmpty; // <--- no video tracks => audio-only
        //debug:
        print('audioOnly = $_audioOnly; videoTracks = ${tracks.video.length}');
      });

      // Apply saved Off/Auto once, in case the demuxer auto-picked something
      if (!_savedPrefAppliedOnce) {
        _savedPrefAppliedOnce = true;
        final pref = _savedSubtitlePref ?? 'off';
        await _player.setSubtitleTrack(
          pref == 'off' ? SubtitleTrack.no() : SubtitleTrack.auto(),
        );
        if (mounted) {
          setState(() => _currentSubtitle =
              pref == 'off' ? SubtitleTrack.no() : SubtitleTrack.auto());
        }
      }
    });

    _errorSub = _player.stream.error.listen((e) async {
      // Only show a snackbar if we are truly failing to start.
      final s = _player.state;
      if (!s.playing && (s.duration == null || s.duration == Duration.zero)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Playback error: $e')),
        );
      }
    });

    if (_hasUsablePlaylist) {
      _player.open(Playlist(_playlist), play: true);
      _player.jump(_currentIndex);
      _updateTitleFromState(showToast: true); // deferred internally
    } else {
      _player.open(Media(widget.videoUrl), play: true);
      _currentTitle = widget.fileName ?? _basename(widget.videoUrl);
      _showTitleToastOverlayAfterBuild(_currentTitle!); // <-- defer toast
      setState(() {});
    }
  }

  @override
  void dispose() {
    _titleHideTimer?.cancel();
    //_controlsHideTimer?.cancel();
    _removeTitleOverlay();
    _errorSub?.cancel();
    _tracksSub?.cancel();
    _modeSub?.cancel();
    _playlistSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  // ---------- playlist & title ----------

  void _initPlaylistFromWidget() {
    final urls = widget.playlistUrls ?? const [];
    // final names = widget.playlistNames ?? const []; // names used later

    if (urls.isNotEmpty) {
      _hasUsablePlaylist = true;
      _playlist = urls.map((u) => Media(u)).toList(growable: false);
      _currentIndex = (widget.initialIndex ?? 0).clamp(0, _playlist.length - 1);
    } else {
      _hasUsablePlaylist = false;
      _playlist = const [];
      _currentIndex = 0;
    }
  }

  String _basename(String s) {
    final u = Uri.parse(s);
    final last = u.pathSegments.isNotEmpty ? u.pathSegments.last : s;
    return Uri.decodeComponent(last);
  }

  void _updateTitleFromState({bool showToast = false}) {
    final st = _player.state;
    final idx = st.playlist.index;
    String? title;

    if (st.playlist.medias.isNotEmpty && idx != null && idx >= 0) {
      final current = st.playlist.medias[idx];
      title =
          widget.playlistNames != null && idx < (widget.playlistNames!.length)
              ? widget.playlistNames![idx]
              : _basename(current.uri);
    } else {
      title = widget.fileName ?? _basename(widget.videoUrl);
    }
    _currentTitle = title;

    if (showToast && title != null) {
      _showTitleToastOverlayAfterBuild(title); // <-- always defer
    }
    if (mounted) setState(() {});
  }

  // Defer any overlay/mediaquery usage to after first frame.
  void _showTitleToastOverlayAfterBuild(String title) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showTitleToastOverlay(title);
    });
  }

  // ---------- loop mode ----------

  void _applyLoopMode(_LoopMode mode, {bool initializing = false}) {
    switch (mode) {
      case _LoopMode.none:
        _player.setPlaylistMode(PlaylistMode.none);
        break;
      case _LoopMode.one:
        _player.setPlaylistMode(PlaylistMode.single);
        break;
      case _LoopMode.all:
        _player.setPlaylistMode(PlaylistMode.loop);
        break;
    }
    if (!initializing && mounted) setState(() => _loopMode = mode);
  }

  void _toggleLoopMode() {
    final next = _loopMode == _LoopMode.none
        ? _LoopMode.one
        : (_loopMode == _LoopMode.one ? _LoopMode.all : _LoopMode.none);
    _applyLoopMode(next);
    if (mounted) setState(() => _loopMode = next); // fixed
  }

  // ---------- subtitles ----------

  List<SubtitleTrack> _filterSubtitleTracks(List<SubtitleTrack> list) {
    return list.where((t) {
      final id = (t.id ?? '').trim().toLowerCase();
      if (id == 'auto' || id == 'no' || id == '-1' || id == 'unknown')
        return false;
      return true;
    }).toList(growable: false);
  }

  List<SubtitleTrack> _dedupeById(List<SubtitleTrack> list) {
    final seen = <String>{};
    final out = <SubtitleTrack>[];
    for (final t in list) {
      final key = (t.id ?? '').trim();
      final altKey = key.isEmpty
          ? '${t.title?.trim() ?? ''}|${t.language?.trim() ?? ''}'
          : key;
      if (seen.add(altKey)) out.add(t);
    }
    return out;
  }

  String _fullSubtitleLabel(SubtitleTrack? track) {
    if (track == null) return 'Auto';
    if (track.id == SubtitleTrack.no().id) return 'Off';
    if (track.id == SubtitleTrack.auto().id) return 'Auto';
    final parts = <String>[];
    if ((track.title?.trim().isNotEmpty ?? false))
      parts.add(track.title!.trim());
    if ((track.language?.trim().isNotEmpty ?? false))
      parts.add(track.language!.trim());
    return parts.isEmpty ? 'Track' : parts.join(' ');
  }

  String _chipLabel(SubtitleTrack? track) {
    final full = _fullSubtitleLabel(track);
    if (full == 'Off' || full == 'Auto') return full;
    const maxLen = 5;
    if (full.length <= maxLen) return full;
    return '${full.substring(0, maxLen)}…';
  }

  Future<void> _showSubtitlePicker() async {
    if (!mounted) return;
    final chosen = await showModalBottomSheet<SubtitleTrack?>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.black87,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.subtitles_off, color: Colors.white70),
                title: const Text('Off', style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(ctx, SubtitleTrack.no()),
              ),
              ListTile(
                leading: const Icon(Icons.auto_fix_high, color: Colors.white70),
                title:
                    const Text('Auto', style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(ctx, SubtitleTrack.auto()),
              ),
              const Divider(color: Colors.white24, height: 1),
              if (_subtitleTracks.isEmpty)
                const ListTile(
                  enabled: false,
                  leading: Icon(Icons.info_outline, color: Colors.white30),
                  title: Text(
                    'No embedded tracks found',
                    style: TextStyle(color: Colors.white54),
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _subtitleTracks.length,
                    itemBuilder: (_, i) {
                      final t = _subtitleTracks[i];
                      final label = _fullSubtitleLabel(t);
                      return ListTile(
                        leading:
                            const Icon(Icons.subtitles, color: Colors.white70),
                        title: Text(label,
                            style: const TextStyle(color: Colors.white)),
                        onTap: () => Navigator.pop(ctx, t),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
    if (!mounted || chosen == null) return;

// prevent the one-time restore in _tracksSub from overriding the user's choice
    _savedPrefAppliedOnce = true;

// apply to player
    await _player.setSubtitleTrack(chosen);

// remember Off/Auto only (skip saving when a specific embedded track is chosen)
    if (_isOff(chosen)) {
      await _persistSubtitlePref('off');
    } else if (_isAuto(chosen)) {
      await _persistSubtitlePref('auto');
    }

// finally, reflect it in the UI
    setState(() => _currentSubtitle = chosen);
  }

  // ---------- title toast overlay ----------

  void _showTitleToastOverlay(String title) {
    _removeTitleOverlay();
    final topPad = MediaQuery.of(context).padding.top + kToolbarHeight + 8.0;
    _titleOverlay = OverlayEntry(
      builder: (_) => _TitleToast(text: title, topPadding: topPad),
    );
    Overlay.of(context).insert(_titleOverlay!);
    _titleHideTimer?.cancel();
    _titleHideTimer = Timer(const Duration(seconds: 4), _removeTitleOverlay);
  }

  void _removeTitleOverlay() {
    _titleHideTimer?.cancel();
    _titleOverlay?.remove();
    _titleOverlay = null;
  }

  // ---------- center overlay controls ----------

  // void _toggleControls() {
  //   final vis = !_controlsVisible;
  //   setState(() => _controlsVisible = vis);
  //   _restartControlsHideTimer();
  // }

  // void _hideControls() {
  //   if (_controlsVisible) {
  //     setState(() => _controlsVisible = false);
  //   }
  //   _controlsHideTimer?.cancel();
  // }

  // void _restartControlsHideTimer() {
  //   _controlsHideTimer?.cancel();
  //   if (!_controlsVisible) return;
  //   _controlsHideTimer = Timer(const Duration(seconds: 3), () {
  //     if (!mounted) return;
  //     setState(() => _controlsVisible = false);
  //   });
  // }

  // Future<void> _togglePlayPause() async {
  //   try {
  //     if (_player.state.playing) {
  //       await _player.pause();
  //     } else {
  //       await _player.play();
  //     }
  //     _restartControlsHideTimer();
  //   } catch (e) {
  //     if (!mounted) return;
  //     ScaffoldMessenger.of(context).showSnackBar(
  //       SnackBar(content: Text('Playback error: $e')),
  //     );
  //   }
  // }

  @override
  Widget build(BuildContext context) {
    final ccText = _fullSubtitleLabel(_currentSubtitle);

    return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text(
            _currentTitle ?? widget.fileName ?? 'Video',
            style: const TextStyle(color: Colors.white),
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _toggleLoopMode,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _loopMode == _LoopMode.none
                        ? Colors.white12
                        : (_loopMode == _LoopMode.one
                            ? Colors.white24
                            : Colors.white30),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.loop, size: 16, color: Colors.white),
                      //const SizedBox(width: 6),
                      Text(
                        _loopLabel(_loopMode),
                        style:
                            const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _showSubtitlePicker,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 36),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.subtitles,
                          size: 16, color: Colors.white),
                      const SizedBox(width: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 72),
                        child: Text(
                          ccText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          bottom: true,
          child: Container(
            color: Colors.black,
            alignment: Alignment.center,
            child: MaterialVideoControlsTheme(
              key: ValueKey('controls-theme-${_audioOnly ? "audio" : "video"}'),
              normal: MaterialVideoControlsThemeData(
                visibleOnMount: true,
                controlsHoverDuration: _audioOnly
                    ? const Duration(days: 365)
                    : const Duration(seconds: 3),
                seekBarMargin: const EdgeInsets.fromLTRB(48, 8, 48, 80),
              ),
              fullscreen: MaterialVideoControlsThemeData(
                visibleOnMount: true,
                controlsHoverDuration: _audioOnly
                    ? const Duration(days: 365)
                    : const Duration(seconds: 3),
                seekBarMargin: const EdgeInsets.fromLTRB(80, 8, 80, 50),
              ),
              child: Video(
                controller: _controller,
                // 👇 force Material controls so the Material theme actually applies
                controls: (state) => KeyedSubtree(
                  key: ValueKey('controls-${_audioOnly ? "audio" : "video"}'),
                  child: MaterialVideoControls(state),
                ),
              ),
            ),
          ),
        ));
  }

  String _loopLabel(_LoopMode mode) {
    switch (mode) {
      case _LoopMode.none:
        return '';
      case _LoopMode.one:
        return '';
      case _LoopMode.all:
        return 'All';
    }
  }
}

class _TitleToast extends StatefulWidget {
  final String text;
  final double topPadding;
  const _TitleToast({required this.text, required this.topPadding});

  @override
  State<_TitleToast> createState() => _TitleToastState();
}

class _TitleToastState extends State<_TitleToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac =
      AnimationController(vsync: this, duration: const Duration(seconds: 4))
        ..forward();

  // 0–2s: fully visible, 2–4s: fade to 0
  late final Animation<double> _opacity = TweenSequence<double>([
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 2),
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 2),
  ]).animate(_ac);

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(top: widget.topPadding),
          child: Align(
            alignment: Alignment.topCenter,
            child: AnimatedBuilder(
              animation: _opacity,
              builder: (_, __) => Opacity(
                opacity: _opacity.value,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    widget.text,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

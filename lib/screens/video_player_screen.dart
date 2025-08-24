// lib/screens/video_player_screen.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/resume_store.dart';

class VideoPlayerScreen extends StatefulWidget {
  final String videoUrl;
  final String? fileName;
  // final String? resumeKey;
  // final int? initialResumeMs;
  final bool resumeOnInitialOpen;

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
    this.resumeOnInitialOpen = true,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

enum _LoopMode { none, one, all }

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late final Player _player;
  late final VideoController _controller;
  Timer? _saveTimer;
  bool _resumeApplied = false;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub;
  String? _activeResumeKey; // updates when playlist item changes
  bool _resumeAllowedForThisItem = false;
  int? _lastPlaylistIndex;
  bool _sawFirstPlaylistEvent = false;
  bool _ignoreNextIndexChangeOnce = false;
  bool _forceStartFromZeroOnce = false;

  // Tracks
  List<AudioTrack> _audioTracks = const [];
  List<SubtitleTrack> _subtitleTracks = const [];
  AudioTrack? _currentAudio;
  SubtitleTrack? _currentSubtitle; // null means "Auto" for label purposes

  StreamSubscription<Tracks>? _tracksSub;
  StreamSubscription<dynamic>? _errorSub;
  StreamSubscription<PlaylistMode>? _modeSub;
  StreamSubscription<Playlist>? _playlistSub;

  bool _audioOnly = false;
  // Persisted subtitle pref: 'off' | 'auto' | null (unset)
  static const _kSubtitlePrefKey = 'video_subtitle_pref';
  String? _savedSubtitlePref; // last saved value
  bool _savedPrefAppliedOnce = false; // apply once after tracks appear
  StreamSubscription<bool>? _playingSub;

  bool _isOff(SubtitleTrack t) => t.id == SubtitleTrack.no().id;
  bool _isAuto(SubtitleTrack t) => t.id == SubtitleTrack.auto().id;

  Future<void> _seekResumeWhenReady() async {
    // If duration is already known, resume immediately.
    if ((_player.state.duration ?? Duration.zero) > Duration.zero) {
      await _maybeSeekResume();
      return;
    }
    // Otherwise wait once for duration > 0, then try.
    late final StreamSubscription<Duration> sub;
    final c = Completer<void>();
    sub = _player.stream.duration.listen((d) async {
      if (d > Duration.zero) {
        await _maybeSeekResume();
        await sub.cancel();
        if (!c.isCompleted) c.complete();
      }
    });
    await c.future;
  }

  void _forceStartAtZeroWhenPlaying() {
    // If we somehow already advanced, yank back to 0.
    if ((_player.state.position ?? Duration.zero) > Duration.zero) {
      unawaited(_player.seek(Duration.zero));
      return;
    }
    // Otherwise wait once for the first position tick & yank to 0.
    late final StreamSubscription<Duration> sub;
    sub = _player.stream.position.listen((p) {
      if (p > Duration.zero) {
        unawaited(_player.seek(Duration.zero));
        sub.cancel();
      }
    });
  }

  /// One place to apply the policy for the *current* item.
  Future<void> _applyResumePolicyForCurrent({required bool allowResume}) async {
    _resumeApplied = false;
    _resumeAllowedForThisItem = allowResume;
    _activeResumeKey = _keyForCurrent();
    if (allowResume) {
      await _seekResumeWhenReady();
    } else {
      _forceStartAtZeroWhenPlaying();
    }
  }

  String _keyForUrl(String uri) {
    // keep keys prefs-safe & shortish
    final b64 = base64Url.encode(utf8.encode(uri)).replaceAll('=', '');
    return 'resume:$b64';
  }

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

  List<AudioTrack> _filterAudioTracks(List<AudioTrack> list) {
    return list.where((t) {
      final id = (t.id ?? '').trim().toLowerCase();
      // Hide pseudo/control entries
      return id != 'auto' && id != 'no' && id != '-1' && id != 'unknown';
    }).toList(growable: false);
  }

  String _fullAudioLabel(AudioTrack t) {
    final parts = <String>[];

    // prefer language (uppercased), then title, then codec
    final lang = (t.language ?? '').trim();
    if (lang.isNotEmpty) parts.add(lang.toUpperCase());

    final title = (t.title ?? '').trim();
    if (title.isNotEmpty) parts.add(title);

    final codec = (t.codec ?? '').trim();
    if (codec.isNotEmpty) parts.add(codec);

    // fallback
    return parts.isEmpty ? 'Audio' : parts.join(' · ');
  }

  String _keyForCurrent() {
    // Prefer provided key; else fallback to URL-based key for current media.
    final st = _player.state;
    final idx = st.playlist.index;
    final uri = (st.playlist.medias.isNotEmpty && idx != null && idx >= 0)
        ? st.playlist.medias[idx].uri
        : widget.videoUrl;
    return _keyForUrl(uri);
  }

  Future<void> _maybeSeekResume() async {
    if (_forceStartFromZeroOnce) return;
    if (_resumeApplied || !_resumeAllowedForThisItem) {
      // debugPrint(
      //     'resume: skip (applied=$_resumeApplied, allowed=$_resumeAllowedForThisItem)');
      return;
    }
    final key = _keyForCurrent();
    final resumeMs = await ResumeStore.load(key);
    final dur = _player.state.duration ?? Duration.zero;
    //debugPrint('resume: loaded=$resumeMs, dur=${dur.inMilliseconds}');
    if (resumeMs != null &&
        resumeMs > 5000 &&
        dur > Duration.zero &&
        resumeMs < (dur.inMilliseconds - 5000)) {
      await _player.seek(Duration(milliseconds: resumeMs));
      _resumeApplied = true;
      //debugPrint('resume: SEEK to $resumeMs ms');
    }
    _activeResumeKey = key;
  }

  Future<void> _persistPosition() async {
    final key = _activeResumeKey ?? _keyForCurrent();
    final pos = _player.state.position?.inMilliseconds ?? 0;
    final dur = _player.state.duration?.inMilliseconds ?? 0;
    if (pos > 1000) {
      await ResumeStore.save(key: key, positionMs: pos, durationMs: dur);
    }
  }

  Future<void> _maybeClearNearEnd() async {
    final key = _activeResumeKey ?? _keyForCurrent();
    final pos = _player.state.position ?? Duration.zero;
    final dur = _player.state.duration ?? Duration.zero;
    if (dur > Duration.zero && (dur - pos).inSeconds <= 10) {
      await ResumeStore.clear(key);
    }
  }

  /// Build human labels for audio tracks & ensure they are unique.
  /// If two different streams both become "Audio", this will make them:
  /// "Audio · Track 1", "Audio · Track 2", etc.  If an id exists, we append a short id.
  List<String> _audioLabelsUnique(List<AudioTrack> tracks) {
    final base = tracks.map(_fullAudioLabel).toList(growable: false);

    // count occurrences
    final counts = <String, int>{};
    for (final b in base) {
      counts[b] = (counts[b] ?? 0) + 1;
    }

    // build unique labels
    final out = <String>[];
    final seenSoFar = <String, int>{};
    for (int i = 0; i < tracks.length; i++) {
      final b = base[i];
      if ((counts[b] ?? 0) <= 1) {
        out.add(b);
        continue;
      }
      // duplicate label: append index or short id
      final shortId = (tracks[i].id ?? '').trim();
      final n = (seenSoFar[b] ?? 0) + 1;
      seenSoFar[b] = n;

      if (shortId.isNotEmpty) {
        out.add('$b · ${shortId}');
      } else {
        out.add('$b · Track $n');
      }
    }
    return out;
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

    _resumeAllowedForThisItem = widget.resumeOnInitialOpen;

    // Apply saved Off/Auto immediately (and set chip)
    _restoreSubtitlePref();
    _initPlaylistFromWidget();
    _ignoreNextIndexChangeOnce = _hasUsablePlaylist;
    _applyLoopMode(_LoopMode.one, initializing: true);

    _modeSub = _player.stream.playlistMode.listen((mode) {
      final m = (mode == PlaylistMode.none)
          ? _LoopMode.none
          : (mode == PlaylistMode.single ? _LoopMode.one : _LoopMode.all);
      if (mounted) setState(() => _loopMode = m);
    });

    _playlistSub = _player.stream.playlist.listen((pl) async {
      if (!mounted || pl == null) return;
      _updateTitleFromState(showToast: true);

      final idx = _player.state.playlist.index ?? 0;

      // First playlist event after open.
      if (!_sawFirstPlaylistEvent) {
        _sawFirstPlaylistEvent = true;
        _lastPlaylistIndex = idx;
        _activeResumeKey = _keyForCurrent();

        // If we won't do a jump(), this *is* the initial user-open item.
        if (!_ignoreNextIndexChangeOnce) {
          await _applyResumePolicyForCurrent(
            allowResume: widget.resumeOnInitialOpen,
          );
        }
        return;
      }

      // Subsequent index changes.
      if (_lastPlaylistIndex != idx) {
        _lastPlaylistIndex = idx;
        _activeResumeKey = _keyForCurrent();

        if (_ignoreNextIndexChangeOnce) {
          // The jump() we triggered to land on initialIndex.
          _ignoreNextIndexChangeOnce = false;
          await _applyResumePolicyForCurrent(
            allowResume: widget.resumeOnInitialOpen,
          );
        } else {
          // Real autoplay/next (including Replay All loop): start from 0.
          await _applyResumePolicyForCurrent(allowResume: false);
        }
      }
    });

    _tracksSub = _player.stream.tracks.listen((tracks) async {
      // Subtitles: filter & dedupe like before
      final filteredSubs = _filterSubtitleTracks(tracks.subtitle);
      final dedupedSubs = _dedupeById(filteredSubs);

      if (!mounted) return;
      setState(() {
        _audioTracks = _filterAudioTracks(tracks.audio);
        _subtitleTracks = _dedupeById(_filterSubtitleTracks(tracks.subtitle));
        _audioOnly = tracks.video.isEmpty; // audio-only file if no video tracks
        if (_currentAudio == null && _audioTracks.length > 1) {
          final engIdx = _findPreferredEnglishAudioIndex(_audioTracks);
          if (engIdx >= 0) {
            final engTrack = _audioTracks[engIdx];
            // Apply once, guarded & fire-and-forget; ignore errors silently
            _player.setAudioTrack(engTrack).then((_) {
              if (mounted) setState(() => _currentAudio = engTrack);
            }).catchError((_) {});
          }
        }
      });

      // Apply saved Off/Auto once after tracks appear
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

    // Seek to resume once we know duration (> 0).
    _durSub = _player.stream.duration.listen((d) {
      if (d > Duration.zero) {
        if (_forceStartFromZeroOnce) {
          _forceStartFromZeroOnce = false;
          unawaited(_player.seek(Duration.zero)); // <-- fire and forget
          return;
        }
        // _maybeSeekResume();
      }
    });

    _playingSub = _player.stream.playing.listen((isPlaying) {
      if (isPlaying) {
        if (_forceStartFromZeroOnce) {
          _forceStartFromZeroOnce = false;
          unawaited(_player.seek(Duration.zero)); // <-- fire and forget
          return;
        }
        //_maybeSeekResume(); // try again once playback is on
      }
    });

// Periodically save position (and clear when near end).
    _posSub = _player.stream.position.listen((_) {
      _maybeClearNearEnd();
    });

    _resumeApplied = false;
    _resumeAllowedForThisItem = widget.resumeOnInitialOpen;

    if (_hasUsablePlaylist) {
      _ignoreNextIndexChangeOnce = true; // we’re about to jump
      _player.open(Playlist(_playlist), play: true);
      _player.jump(_currentIndex); // triggers one index change we ignore
      _updateTitleFromState(showToast: true);
    } else {
      _activeResumeKey = _keyForUrl(widget.videoUrl);
      _player.open(Media(widget.videoUrl), play: true);
      _currentTitle = widget.fileName ?? _basename(widget.videoUrl);
      _showTitleToastOverlayAfterBuild(_currentTitle!);
      setState(() {});
      // Single item: apply policy once.
      unawaited(_applyResumePolicyForCurrent(
        allowResume: widget.resumeOnInitialOpen,
      ));
    }

    _saveTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _persistPosition();
    });
  }

  @override
  void reassemble() {
    super.reassemble();
    // Hot reload safety: allow resume logic to re-run.
    _resumeApplied = false;
    _resumeAllowedForThisItem = widget.resumeOnInitialOpen;
  }

  @override
  void dispose() {
    _titleHideTimer?.cancel();
    _removeTitleOverlay();
    _errorSub?.cancel();
    _tracksSub?.cancel();
    _modeSub?.cancel();
    _playlistSub?.cancel();
    _playingSub?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _saveTimer?.cancel();
    _persistPosition(); // best-effort final save
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

  int _findPreferredEnglishAudioIndex(List<AudioTrack> tracks) {
    if (tracks.isEmpty) return -1;

    // 1) Perfect match: language code like "en", "eng"
    final idxLang = tracks.indexWhere((t) {
      final lang = (t.language ?? '').trim().toLowerCase();
      return lang == 'en' || lang == 'eng' || lang.startsWith('en-');
    });
    if (idxLang >= 0) return idxLang;

    // 2) Title mentions English (handles weird metadata)
    final idxTitle = tracks.indexWhere((t) {
      final title = (t.title ?? '').toLowerCase();
      return title.contains('english') || RegExp(r'\beng\b').hasMatch(title);
    });
    if (idxTitle >= 0) return idxTitle;

    // 3) Language contains "en" anywhere (very loose fallback)
    final idxLoose = tracks.indexWhere((t) {
      final lang = (t.language ?? '').toLowerCase();
      return lang.contains('en');
    });
    if (idxLoose >= 0) return idxLoose;

    return -1;
  }

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

  Future<void> _showTracksPicker() async {
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.black87,
      isScrollControlled: true,
      builder: (ctx) {
        // Local state inside the sheet for selected radio indices
        int selectedAudio = _currentAudio != null
            ? _audioTracks.indexWhere((t) => t.id == _currentAudio!.id)
            : -1;

// If only one real track, preselect it.
        if (selectedAudio < 0 && _audioTracks.length == 1) {
          selectedAudio = 0;
          if (_currentAudio == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _currentAudio = _audioTracks.first);
            });
          }
        }

// If multiple, prefer English if available.
        if (selectedAudio < 0 && _audioTracks.length > 1) {
          final engIdx = _findPreferredEnglishAudioIndex(_audioTracks);
          if (engIdx >= 0) {
            selectedAudio = engIdx;
            if (_currentAudio == null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted)
                  setState(() => _currentAudio = _audioTracks[engIdx]);
              });
            }
          }
        }

        // Subs: -1 = Off, -2 = Auto, >=0 = index in _subtitleTracks
        int selectedSub;
        if (_currentSubtitle == null || _isAuto(_currentSubtitle!)) {
          selectedSub = -2;
        } else if (_isOff(_currentSubtitle!)) {
          selectedSub = -1;
        } else {
          selectedSub = _subtitleTracks.indexWhere(
            (t) => t.id == _currentSubtitle!.id,
          );
        }

        return SafeArea(
          child: StatefulBuilder(
            builder: (ctx, setSheetState) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const ListTile(
                      title: Text('Audio / Subtitles',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          )),
                      subtitle: Text('Choose audio language/track and subtitle',
                          style: TextStyle(color: Colors.white70)),
                    ),
                    const Divider(color: Colors.white24, height: 1),

                    // ---------- AUDIO ----------
                    const ListTile(
                      title: Text('Audio',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          )),
                    ),
                    if (_audioTracks.isEmpty)
                      const Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text('No audio tracks reported',
                              style: TextStyle(color: Colors.white54)),
                        ),
                      )
                    else
                      ...List.generate(_audioTracks.length, (i) {
                        final audioLabels = _audioLabelsUnique(_audioTracks);
                        final t = _audioTracks[i];
                        final label = audioLabels[i];
                        return RadioListTile<int>(
                          value: i,
                          groupValue: selectedAudio,
                          onChanged: (v) async {
                            if (v == null) return;
                            final chosen = _audioTracks[v];
                            try {
                              await _player.setAudioTrack(chosen);
                              if (!mounted) return;
                              setState(() => _currentAudio = chosen);
                              setSheetState(() => selectedAudio = v);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Audio: $label')),
                              );
                            } catch (e) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text('Failed to set audio: $e')),
                              );
                            }
                          },
                          title: Text(label,
                              style: const TextStyle(color: Colors.white)),
                          activeColor: Colors.white,
                        );
                      }),

                    const Divider(color: Colors.white24, height: 1),

                    // ---------- SUBTITLES ----------
                    const ListTile(
                      title: Text('Subtitles',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          )),
                    ),
                    // Off
                    RadioListTile<int>(
                      value: -1,
                      groupValue: selectedSub,
                      onChanged: (v) async {
                        _savedPrefAppliedOnce = true; // don't override later
                        try {
                          await _player.setSubtitleTrack(SubtitleTrack.no());
                          if (!mounted) return;
                          await _persistSubtitlePref('off');
                          setState(() => _currentSubtitle = SubtitleTrack.no());
                          setSheetState(() => selectedSub = -1);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Subtitles: Off')),
                          );
                        } catch (e) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content:
                                    Text('Failed to disable subtitles: $e')),
                          );
                        }
                      },
                      title: const Text('Off',
                          style: TextStyle(color: Colors.white)),
                      activeColor: Colors.white,
                    ),
                    // Auto
                    RadioListTile<int>(
                      value: -2,
                      groupValue: selectedSub,
                      onChanged: (v) async {
                        _savedPrefAppliedOnce = true; // don't override later
                        try {
                          await _player.setSubtitleTrack(SubtitleTrack.auto());
                          if (!mounted) return;
                          await _persistSubtitlePref('auto');
                          setState(
                              () => _currentSubtitle = SubtitleTrack.auto());
                          setSheetState(() => selectedSub = -2);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Subtitles: Auto')),
                          );
                        } catch (e) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Failed to set Auto: $e')),
                          );
                        }
                      },
                      title: const Text('Auto',
                          style: TextStyle(color: Colors.white)),
                      activeColor: Colors.white,
                    ),

                    if (_subtitleTracks.isEmpty)
                      const Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text('No embedded tracks found',
                              style: TextStyle(color: Colors.white54)),
                        ),
                      )
                    else
                      ...List.generate(_subtitleTracks.length, (i) {
                        final t = _subtitleTracks[i];
                        final label = _fullSubtitleLabel(t);
                        return RadioListTile<int>(
                          value: i,
                          groupValue: selectedSub,
                          onChanged: (v) async {
                            if (v == null) return;
                            _savedPrefAppliedOnce = true; // lock user choice
                            final chosen = _subtitleTracks[v];
                            try {
                              await _player.setSubtitleTrack(chosen);
                              if (!mounted) return;
                              setState(() => _currentSubtitle = chosen);
                              setSheetState(() => selectedSub = v);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text(
                                        'Subtitles: ${_fullSubtitleLabel(chosen)}')),
                              );
                            } catch (e) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content:
                                        Text('Failed to set subtitles: $e')),
                              );
                            }
                          },
                          title: Text(label,
                              style: const TextStyle(color: Colors.white)),
                          activeColor: Colors.white,
                        );
                      }),
                    const SizedBox(height: 8),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
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
                onTap: _showTracksPicker,
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

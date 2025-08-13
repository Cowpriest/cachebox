// lib/screens/audio_player_screen.dart
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:rxdart/rxdart.dart';

class AudioPlayerScreen extends StatefulWidget {
  final String audioUrl;
  final String? title;
  const AudioPlayerScreen({required this.audioUrl, this.title, Key? key})
      : super(key: key);

  @override
  State<AudioPlayerScreen> createState() => _AudioPlayerScreenState();
}

class _AudioPlayerScreenState extends State<AudioPlayerScreen> {
  late final AudioPlayer _player;
  double _speed = 1.0;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _init();
  }

  Future<void> _init() async {
    final fallbackTitle = widget.title ?? widget.audioUrl.split('/').last;
    final src = AudioSource.uri(
      Uri.parse(widget.audioUrl),
      tag: MediaItem(
        id: widget.audioUrl,
        title: fallbackTitle.isEmpty ? 'Audio' : fallbackTitle,
        artist: 'CacheBox',
        // artUri: Uri.parse('https://example.com/cover.jpg'), // optional
      ),
    );
    try {
      await _player.setAudioSource(src);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load audio: $e')),
      );
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  // Combine position/buffer/duration into one stream for convenience.
  Stream<PositionData> get _positionDataStream =>
      Rx.combineLatest3<Duration, Duration, Duration?, PositionData>(
        _player.positionStream,
        _player.bufferedPositionStream,
        _player.durationStream,
        (position, bufferedPosition, duration) => PositionData(
          position,
          bufferedPosition,
          duration ?? Duration.zero,
        ),
      );

  String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return h > 0 ? "${two(h)}:${two(m)}:${two(s)}" : "${two(m)}:${two(s)}";
  }

  @override
  Widget build(BuildContext context) {
    final title =
        Uri.decodeComponent(widget.title ?? widget.audioUrl.split('/').last);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _Artwork(player: _player),
            const SizedBox(height: 16),
            // Transport controls
            StreamBuilder<PlayerState>(
              stream: _player.playerStateStream,
              builder: (context, snapshot) {
                final ps = snapshot.data;
                final playing = ps?.playing ?? false;
                final processingState = ps?.processingState;
                final isLoading = processingState == ProcessingState.loading ||
                    processingState == ProcessingState.buffering;
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      iconSize: 36,
                      onPressed: isLoading
                          ? null
                          : () async {
                              final newPos = _player.position -
                                  const Duration(seconds: 10);
                              await _player.seek(newPos < Duration.zero
                                  ? Duration.zero
                                  : newPos);
                            },
                      icon: const Icon(Icons.replay_10),
                      tooltip: 'Back 10s',
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: isLoading
                          ? null
                          : () async {
                              if (playing) {
                                await _player.pause();
                              } else {
                                await _player.play();
                              }
                            },
                      icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                      label: Text(playing ? 'Pause' : 'Play'),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      iconSize: 36,
                      onPressed: isLoading
                          ? null
                          : () async {
                              final newPos = _player.position +
                                  const Duration(seconds: 10);
                              await _player.seek(newPos);
                            },
                      icon: const Icon(Icons.forward_10),
                      tooltip: 'Forward 10s',
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            // Position + buffer
            StreamBuilder<PositionData>(
              stream: _positionDataStream,
              builder: (context, snapshot) {
                final data = snapshot.data;
                final position = data?.position ?? Duration.zero;
                final buffered = data?.bufferedPosition ?? Duration.zero;
                final total = data?.duration ?? Duration.zero;
                final totalMs =
                    total.inMilliseconds == 0 ? 1 : total.inMilliseconds;
                final posMs = position.inMilliseconds.clamp(0, totalMs);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Slider(
                      min: 0.0,
                      max: totalMs.toDouble(),
                      value: posMs.toDouble(),
                      onChanged: (v) {
                        final d = Duration(milliseconds: v.toInt());
                        final dur = _player.duration;
                        final safe = (dur != null && d >= dur)
                            ? dur - const Duration(milliseconds: 1)
                            : d;
                        _player
                            .seek(safe < Duration.zero ? Duration.zero : safe);
                      },
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_fmt(position)),
                        Text(_fmt(total)),
                      ],
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            // Volume + speed row
            Row(
              children: [
                const Icon(Icons.volume_up),
                const SizedBox(width: 8),
                Expanded(
                  child: StreamBuilder<double>(
                    stream: _player.volumeStream,
                    initialData: _player.volume,
                    builder: (context, snapshot) {
                      final vol = (snapshot.data ?? 1.0).clamp(0.0, 1.0);
                      return Slider(
                        min: 0.0,
                        max: 1.0,
                        value: vol,
                        onChanged: (v) async {
                          await _player.setVolume(v);
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                const Text('Speed'),
                const SizedBox(width: 8),
                DropdownButton<double>(
                  value: _speed,
                  items: const [
                    DropdownMenuItem(value: 0.75, child: Text('0.75x')),
                    DropdownMenuItem(value: 1.0, child: Text('1.0x')),
                    DropdownMenuItem(value: 1.25, child: Text('1.25x')),
                    DropdownMenuItem(value: 1.5, child: Text('1.5x')),
                    DropdownMenuItem(value: 2.0, child: Text('2.0x')),
                  ],
                  onChanged: (s) async {
                    if (s != null) {
                      setState(() => _speed = s);
                      await _player.setSpeed(s);
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// Top-level artwork widget with placeholder.
class _Artwork extends StatelessWidget {
  final AudioPlayer player;
  const _Artwork({required this.player});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SequenceState?>(
      stream: player.sequenceStateStream,
      builder: (context, snapshot) {
        MediaItem? item;
        try {
          final tag = snapshot.data?.currentSource?.tag;
          if (tag is MediaItem) item = tag;
        } catch (_) {}
        final artUri = item?.artUri;
        final title = Uri.decodeComponent(item?.title ?? 'Audio');
        return Column(
          children: [
            SizedBox(
              height: 160,
              width: 160,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: artUri != null
                    ? Image.network(
                        artUri.toString(),
                        fit: BoxFit.cover,
                        errorBuilder: (c, e, st) => _placeholder(),
                      )
                    : _placeholder(),
              ),
            ),
            const SizedBox(height: 8),
            Text(title, textAlign: TextAlign.center),
          ],
        );
      },
    );
  }

  Widget _placeholder() {
    return Container(
      color: Colors.black12,
      child: const Center(
        child: Icon(Icons.music_note, size: 64),
      ),
    );
  }
}

// Simple data class for combined position info.
class PositionData {
  final Duration position;
  final Duration bufferedPosition;
  final Duration duration;
  const PositionData(this.position, this.bufferedPosition, this.duration);
}

// lib/screens/audio_player_screen.dart

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

class AudioPlayerScreen extends StatefulWidget {
  final String audioUrl;
  const AudioPlayerScreen({required this.audioUrl, Key? key}) : super(key: key);

  @override
  State<AudioPlayerScreen> createState() => _AudioPlayerScreenState();
}

class _AudioPlayerScreenState extends State<AudioPlayerScreen> {
  late final AudioPlayer _player;
  double _speed = 1.0;
  double _volume = 1.0;

  @override
  void initState() {
    super.initState();
    _initPlayer(); // fire-and-forget our async setup
  }

  Future<void> _initPlayer() async {
    _player = AudioPlayer();
    final fileName = widget.audioUrl.split('/').last;

    await _player.setAudioSource(
      AudioSource.uri(
        Uri.parse(widget.audioUrl),
        tag: MediaItem(
          id: widget.audioUrl,
          //album: 'Album Name',
          title: fileName,
          artist: 'Cachebox',
          //artUri: Uri.parse('https://example.com/artwork.png'),
        ),
      ),
    );

    // now you can optionally auto-play, or leave it for your Play button
    // await _player.play();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  String _format(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final totalStream = _player.durationStream;
    final positionStream = _player.positionStream;

    return Scaffold(
      appBar: AppBar(title: Text(widget.audioUrl.split('/').last)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ─── artwork placeholder ─────────────────────────
            SizedBox(
              height: 200,
              child: Container(
                color: Colors.grey.shade200,
                child: const Center(child: Text('Artwork Here')),
              ),
            ),

            const SizedBox(height: 16),
            const Spacer(), // pushes controls to bottom
            // ─── skip/play/skip row ──────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.replay_10),
                  onPressed: () async {
                    final pos = await _player.position;
                    _player.seek(pos - const Duration(seconds: 10));
                  },
                ),
                StreamBuilder<PlayerState>(
                  stream: _player.playerStateStream,
                  builder: (ctx, snap) {
                    final playing = snap.data?.playing ?? false;
                    return IconButton(
                      iconSize: 64,
                      icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                      onPressed:
                          () => playing ? _player.pause() : _player.play(),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.forward_10),
                  onPressed: () async {
                    final pos = await _player.position;
                    _player.seek(pos + const Duration(seconds: 10));
                  },
                ),
              ],
            ),

            const SizedBox(height: 16),

            // ─── time display & seek slider ──────────────────
            StreamBuilder<Duration?>(
              stream: totalStream,
              builder: (ctx, totalSnap) {
                final total = totalSnap.data ?? Duration.zero;
                return StreamBuilder<Duration>(
                  stream: positionStream,
                  builder: (ctx, posSnap) {
                    final pos = posSnap.data ?? Duration.zero;
                    return Column(
                      children: [
                        Text(
                          '${_format(pos)} / ${_format(total)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Slider(
                          min: 0,
                          max: total.inMilliseconds.toDouble(),
                          value:
                              pos.inMilliseconds
                                  .clamp(0, total.inMilliseconds)
                                  .toDouble(),
                          onChanged:
                              (v) => _player.seek(
                                Duration(milliseconds: v.toInt()),
                              ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),

            const SizedBox(height: 8),

            // ─── volume slider ───────────────────────────────
            Row(
              children: [
                const Icon(Icons.volume_down),
                Expanded(
                  child: Slider(
                    min: 0,
                    max: 1,
                    value: _volume,
                    onChanged: (v) {
                      _player.setVolume(v);
                      setState(() => _volume = v);
                    },
                  ),
                ),
                const Icon(Icons.volume_up),
              ],
            ),

            const SizedBox(height: 8),

            // ─── speed selector ───────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Speed:'),
                const SizedBox(width: 8),
                DropdownButton<double>(
                  value: _speed,
                  items:
                      [0.5, 1.0, 1.5, 2.0]
                          .map(
                            (s) => DropdownMenuItem(
                              value: s,
                              child: Text('${s}×'),
                            ),
                          )
                          .toList(),
                  onChanged: (s) {
                    if (s != null) {
                      _player.setSpeed(s);
                      setState(() => _speed = s);
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

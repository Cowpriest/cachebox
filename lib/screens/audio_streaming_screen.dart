// lib/screens/audio_streaming_screen.dart
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

class AudioStreamingScreen extends StatefulWidget {
  final String audioUrl;
  const AudioStreamingScreen({Key? key, required this.audioUrl})
      : super(key: key);

  @override
  _AudioStreamingScreenState createState() => _AudioStreamingScreenState();
}

class _AudioStreamingScreenState extends State<AudioStreamingScreen> {
  final AudioPlayer _player = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _player.setUrl(widget.audioUrl);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Stream Audio")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            StreamBuilder<PlayerState>(
              stream: _player.playerStateStream,
              builder: (context, snapshot) {
                final playerState = snapshot.data;
                final processingState = playerState?.processingState;
                final playing = playerState?.playing;
                if (processingState == ProcessingState.loading ||
                    processingState == ProcessingState.buffering) {
                  return CircularProgressIndicator();
                } else if (playing != true) {
                  return IconButton(
                    icon: Icon(Icons.play_arrow),
                    iconSize: 64.0,
                    onPressed: _player.play,
                  );
                } else if (processingState != ProcessingState.completed) {
                  return IconButton(
                    icon: Icon(Icons.pause),
                    iconSize: 64.0,
                    onPressed: _player.pause,
                  );
                } else {
                  return IconButton(
                    icon: Icon(Icons.replay),
                    iconSize: 64.0,
                    onPressed: () => _player.seek(Duration.zero),
                  );
                }
              },
            ),
            SizedBox(height: 20),
            Text("Streaming Audio..."),
          ],
        ),
      ),
    );
  }
}

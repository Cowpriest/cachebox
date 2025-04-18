// lib/screens/video_streaming_screen.dart
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class VideoStreamingScreen extends StatefulWidget {
  final String videoUrl;
  const VideoStreamingScreen({Key? key, required this.videoUrl})
      : super(key: key);

  @override
  _VideoStreamingScreenState createState() => _VideoStreamingScreenState();
}

class _VideoStreamingScreenState extends State<VideoStreamingScreen> {
  late VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.network(widget.videoUrl)
      ..initialize().then((_) {
        // Once the video is initialized, start playing automatically.
        _controller.play();
        setState(() {}); // Refresh the UI after initialization.
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Stream Video")),
      body: Center(
        child: _controller.value.isInitialized
            ? GestureDetector(
                onTap: () {
                  setState(() {
                    // Toggle play/pause when the video is tapped.
                    _controller.value.isPlaying
                        ? _controller.pause()
                        : _controller.play();
                  });
                },
                child: AspectRatio(
                  aspectRatio: _controller.value.aspectRatio,
                  child: VideoPlayer(_controller),
                ),
              )
            : CircularProgressIndicator(),
      ),
    );
  }
}

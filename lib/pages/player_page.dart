import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'package:objective_app2/models/requests.dart';


/// Stateful widget to fetch and then display video content.
class PlayerPage extends StatefulWidget {
  final RequestFromServer request;
  const PlayerPage({Key? key, required this.request}) : super(key: key);

  @override
  _PlayerPageState createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    print('url!: ${widget.request.videoUrl}');
    _controller = VideoPlayerController.network(
        widget.request.videoUrl)
      ..initialize().then((_) {
        // Ensure the first frame is shown after the video is initialized, even before the play button has been pressed.
        setState(() {});
        _controller.play();
      });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: widget.request.requestId,
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: _controller.value.isInitialized
              ? AspectRatio(
                  aspectRatio: _controller.value.aspectRatio,
                  child: VideoPlayer(_controller),
                )
              : CircularProgressIndicator(color: Colors.white),
        ),
        floatingActionButton: FloatingActionButton(
          backgroundColor: Colors.white,
          onPressed: () {
            Navigator.pop(context);
          },
          child: Icon(
            Icons.close,
            color: Colors.black,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
    _controller.dispose();
  }
}
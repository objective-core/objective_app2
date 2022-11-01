import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

import 'package:async/async.dart';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:convert/convert.dart';
import 'package:objective_app2/utils/data.dart';


class RecorderPage extends StatefulWidget {
  const RecorderPage({Key? key}) : super(key: key);

  @override
  State<RecorderPage> createState() => _RecorderPageState();
}

class _RecorderPageState extends State<RecorderPage> with WidgetsBindingObserver {
  late CameraController controller;
  late List<CameraDescription> cameras; 
  late Data videoData;

  var isVideoRecording = false;
  var initialized = false;

  @override
  Widget build(BuildContext context) {
    videoData = ModalRoute.of(context)!.settings.arguments as Data;

    return FutureBuilder<bool>(
      future: initCamera(),
      builder: (context, AsyncSnapshot<bool> snapshot) {
        if (snapshot.hasData) {
          return Stack(
            children: [
              Positioned(
                child: CameraPreview(controller)
              ),
              Positioned(
                bottom: 20,
                left: 20,
                child: Row(
                  children: [
                    ElevatedButton(
                      onPressed: () => takePicture(),
                      child: const Text('Take Picture'),
                    ),
                    SizedBox(width: 20),
                    (isVideoRecording) ? ElevatedButton(
                      onPressed: () => stopVideoRecording(),
                      child: const Text('Stop Recording'),
                    ) : ElevatedButton(
                      onPressed: () => startVideoRecording(),
                      child: const Text('Start Recording'),
                    ),
                  ],
                )
              ),
              Positioned(
                child: Text(
                    videoData.videoHash,
                    textAlign: TextAlign.center,overflow: TextOverflow.visible,
                    style: const TextStyle(color: Colors.white, fontSize: 20, decoration: TextDecoration.none)
                ),
                bottom: 70,
              ),
            ],
          );
        } else {
          return Container(
            alignment: Alignment.center,
            child: const CircularProgressIndicator()
          );
        }
      }
    );
  }

  void takePicture() async {
    try {
      var file = await controller.takePicture();
      file.saveTo('/storage/emulated/0/DCIM/Camera/picture.jpg');
      print(file);
    } catch (e) {
      print(e);
    }
  }

  void startVideoRecording() async {
    try {
      controller.startVideoRecording();

      setState(() {
        isVideoRecording = true;
      });
    } catch (e) {
      print(e);
    }
  }

  void stopVideoRecording() async {
    try {
      var file = await controller.stopVideoRecording();
      var path = '/storage/emulated/0/DCIM/Camera/video.mp4';
      file.saveTo('/storage/emulated/0/DCIM/Camera/video.mp4');

      videoData.videoPath = path;
      videoData.videoHash = (await getFileSha256(path)).toString();
      
      print(videoData.videoHash);

      setState(() {
        isVideoRecording = false;
      });
    } catch (e) {
      print(e);
    }
  }

  Future<Digest> getFileSha256(String path) async {
    final reader = ChunkedStreamReader(File(path).openRead());
    const chunkSize = 4096;
    var output = AccumulatorSink<Digest>();
    var input = sha256.startChunkedConversion(output);

    try {
      while (true) {
        final chunk = await reader.readChunk(chunkSize);
        if (chunk.isEmpty) {
          // indicate end of file
          break;
        }
        input.add(chunk);
      }
    } finally {
      // We always cancel the ChunkedStreamReader,
      // this ensures the underlying stream is cancelled.
      reader.cancel();
    }

    input.close();

    return output.events.single;
  }

  Future<bool> initCamera() async {
    if(initialized) {
      return initialized;
    }

    cameras = await availableCameras();
    controller = CameraController(cameras[0], ResolutionPreset.medium);
    controller.initialize().then((_) {
      if (!mounted) {
        return false;
      }
      setState(() {});
    }).catchError((Object e) {
      if (e is CameraException) {
        switch (e.code) {
          case 'CameraAccessDenied':
            print('User denied camera access.');
            break;
          default:
            print('Handle other errors.');
            break;
        }
      }
    });
    initialized = true;
    return initialized;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    print('state changed');
    print(state);
    if (state == AppLifecycleState.inactive) {
      controller.dispose();
    }
  }
}

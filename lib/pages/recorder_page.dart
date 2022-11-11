import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:typed_data';
import 'package:async/async.dart';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:convert/convert.dart';
import 'package:objective_app2/utils/data.dart';
import 'package:objective_app2/utils/routes.dart';
import 'package:bs58/bs58.dart';
import 'package:fast_base58/fast_base58.dart' as fast_base58;
import 'package:dio/dio.dart';
import 'package:walletconnect_dart/walletconnect_dart.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/services.dart';

import 'package:objective_app2/models/location.dart';
import 'package:objective_app2/models/login.dart';
import 'package:objective_app2/models/requests.dart';


class RecorderPage extends StatefulWidget {
  const RecorderPage({Key? key}) : super(key: key);

  @override
  State<RecorderPage> createState() => _RecorderPageState();
}

class _RecorderPageState extends State<RecorderPage> with WidgetsBindingObserver {
  late CameraController controller;
  late List<CameraDescription> cameras; 
  late Data data;
  Video? video;
  Dio dio = Dio();

  LocationModel? location;
  LoginModel? login;
  RequestFromServer? videoRequest;

  var isVideoRecording = false;
  var uploading = false;
  var initialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  Widget build(BuildContext context) {
    List<dynamic> args = ModalRoute.of(context)!.settings.arguments as List;

    print(args);

    location = args[0];
    login = args[1];
    videoRequest = args[2];

    print('done');

    return FutureBuilder<bool>(
      future: initCamera(),
      builder: (context, AsyncSnapshot<bool> snapshot) {
        if (snapshot.hasData) {
          return Stack(
            children: [
              Positioned(
                top: 100,
                left: 0,
                width: MediaQuery.of(context).size.width,
                height: MediaQuery.of(context).size.height - 220,
                child: CameraPreview(controller)
              ),
              Positioned(
                bottom: 20,
                left: MediaQuery.of(context).size.width / 2 - 40,
                child: Container(
                  width: 80,
                  height: 80,
                  child: RawMaterialButton(
                    onPressed: () {
                      if (isVideoRecording) {
                        stopVideoRecording();
                      } else {
                        startVideoRecording();
                      }
                    },
                    elevation: 2.0,
                    fillColor: Colors.white,
                    padding: EdgeInsets.all(15.0),
                    shape: CircleBorder(),
                    child: Icon(
                      size: 35.0,
                      isVideoRecording ? Icons.stop: Icons.circle,
                      color: isVideoRecording ? Colors.black : Colors.red,
                    ),
                  ),
                )
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

  void startVideoRecording() async {
    try {
      video = Video(
        startTime: DateTime.now(),
        position: location!.currentLocation,
      );

      await controller.startVideoRecording();
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
      var path = '/storage/emulated/0/DCIM/Camera/${file.name}';
      file.saveTo(path);

      setState(() {
        isVideoRecording = false;
      });

      print('uploading...');

      video!.path = path;
      video!.hash = await getFileCIDHash(path);
      video!.endTime = DateTime.now();

      var messageToSign = 'video hash: ${video!.hash}';
      video!.signature = await login!.signMessageWithMetamask(messageToSign);

      print('signed ${video!.signature}');
      await uploadVideo();

      Navigator.pop(context, video);
      print('uploaded.');
    } catch (e) {
      print(e);
    }
  }

  Future<String> getFileCIDHash(String path) async {
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

    var hash = output.events.single.toString();

    // https://ethereum.stackexchange.com/questions/44506/ipfs-hash-algorithm
    var prefix = '1220';
    var combined = prefix + hash;

    var cidHash = base58.encode(Uint8List.fromList(hex.decode(combined)));
    var fastCidHash = fast_base58.Base58Encode(hex.decode(combined));
    var actualCID = uploadToIpfs(path);
    print('cidHash: $cidHash, fastCidHash: $fastCidHash actualCID: $actualCID');
    return actualCID;
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

  Future<String> uploadToIpfs(String path) async {
    var authorizationToken = base64Encode('App:chainlink2020'.codeUnits);

    var uploadFile = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        path,
      ),
    });

    Response dioResponse = await dio.post(
      'https://ipfs.objective.camera/api/v0/add',
      data: uploadFile,
      options: Options(
        headers: {
          "Authorization": "Basic $authorizationToken",
        },
      ),
      onSendProgress: (received, total) {
        if (total != -1) {
          print((received / total * 100).toStringAsFixed(0) + '%');
        }
      },
    );

    var expectedHash = dioResponse.data['Hash'];
    return expectedHash;
  }

  Future<bool> uploadVideo() async {
    // curl -v \
    // -F lat=12 \
    // -F long=12 \
    // -F start=123123 \
    // -F end=123140 \
    // -F median_direction=12 \
    // -F signature=test \
    // -F request_id=test-request-id-1 \
    // -F expected_hash=QmNT8axScpvoXJeKaoeZcD7E9ew9eSNp4EePXjwB62mrv4 \
    // -F file=@requirements.in \
    // https://api.objective.camera/upload/

    var url = Uri.https('api.objective.camera', 'upload/');
    var request = http.MultipartRequest("POST", url);

    print('loading file??');
    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        video!.path!,
      )
    );
    request.fields.addAll({
      'lat': video!.position.latitude.toString(),
      'long': video!.position.longitude.toString(),
      'start': video!.startTime.millisecondsSinceEpoch.toString(),
      'end': video!.endTime!.millisecondsSinceEpoch.toString(),
      'median_direction': video!.position.heading.truncate().toString(),
      'signature': video!.signature!,
      'request_id': videoRequest!.requestId,
      'expected_hash': video!.hash!,
    });

    print('prepared request: ${request.fields}');
    var response = await request.send();
    print(response.statusCode);
    print(await response.stream.bytesToString());

    return true;
  }
}

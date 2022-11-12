import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:typed_data';
import 'package:async/async.dart';
import 'dart:io';
import 'dart:math';
import 'dart:core';
import 'dart:collection';
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
import 'package:flutter_compass/flutter_compass.dart';

import 'package:objective_app2/models/location.dart';
import 'package:objective_app2/models/login.dart';
import 'package:objective_app2/models/requests.dart';
import 'package:objective_app2/pages/alert_dialog.dart';
import 'package:motion_sensors/motion_sensors.dart';


class RecorderPage extends StatefulWidget {
  const RecorderPage({Key? key}) : super(key: key);

  @override
  State<RecorderPage> createState() => _RecorderPageState();
}

class _RecorderPageState extends State<RecorderPage> with WidgetsBindingObserver {
  CameraController? controller;
  late List<CameraDescription> cameras; 
  late Data data;
  Video? video;
  Dio dio = Dio();

  final gravityHistory = ListQueue<double>();
  var gravitySum = 0.0;
  var averageGravity = 0.0;
  var verticalThreshold = 8.0;
  var heading = 0.0;

  // start to calculate on video start;
  var averageHeading = 0.0;
  var headingSum = 0.0;
  var headingCount = 0;

  LocationModel? location;
  LoginModel? login;
  RequestFromServer? videoRequest;

  var isVideoRecording = false;
  var uploading = false;
  var initialized = false;

  var magnetometerStream, accelerometerStream, compassStream;

  double get targetDiffernce => ((videoRequest!.direction) - (heading + 360) % 360) % 360;
  bool get verified => ((targetDiffernce < 20 || targetDiffernce > 340) && averageGravity >= 8.0);

  @override
  void initState() {
    motionSensors.magnetometerUpdateInterval = 20000;
    motionSensors.accelerometerUpdateInterval = 20000;
    magnetometerStream = motionSensors.magnetometer.listen((MagnetometerEvent event) {
      // print('direction: ${90 - 180.0 * atan2(event.y, event.x) / pi}');
    });
    accelerometerStream = motionSensors.accelerometer.listen((AccelerometerEvent event) {
      // print('accelerometer: ${event.x} ${event.y} ${event.z}');
      gravitySum += event.y;
      gravityHistory.addLast(event.y);

      if(gravityHistory.length > 300) {
        gravitySum -= gravityHistory.removeFirst();
      }

      var oldAverageGravity = averageGravity;
      var newAverageGravity = gravitySum / gravityHistory.length;

      averageGravity = newAverageGravity;

      if(oldAverageGravity < verticalThreshold && newAverageGravity > verticalThreshold) { 
        if (mounted) {
          setState(() {});
        }

      } else if (oldAverageGravity > verticalThreshold && newAverageGravity < verticalThreshold) {
        if (mounted) {
          setState(() {});
        }
      }

      // print(averageGravity);
    });

    compassStream = FlutterCompass.events?.listen((CompassEvent event) {
      heading = event.heading!;
      // print(heading);
      if(isVideoRecording) {
        headingSum += heading;
        headingCount++;
        averageHeading = headingSum / headingCount;
      }

       if (mounted) {
          setState(() {});
       }
    });

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
                child: !uploading && controller != null ? CameraPreview(controller!) : const Center(
                  child: Text(
                    'Processing & uploading video...',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.normal,
                      decoration: TextDecoration.none,
                    ),
                  ),
                )
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
                        if((controller != null && verified && !uploading)) {
                          startVideoRecording();
                        }
                      }
                    },
                    elevation: 2.0,
                    fillColor: Colors.white,
                    padding: EdgeInsets.all(15.0),
                    shape: CircleBorder(),
                    child: Icon(
                      size: 35.0,
                      isVideoRecording ? Icons.stop: Icons.circle,
                      color: isVideoRecording ? Colors.black : ((controller != null && verified && !uploading) ? Colors.red : Colors.grey),
                    ),
                  ),
                )
              ),
            ] + buildVerificatorWisgets(context),
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

  List<Positioned> buildVerificatorWisgets(BuildContext context) {
    List<Positioned> result = [];

    if(averageGravity < 8.0) {
      result.add(
        Positioned(
          top: 40,
          left: 0,
          width: MediaQuery.of(context).size.width,
          child: const Center(
            child: Text(
              'Hold your phone vertically',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.normal,
                decoration: TextDecoration.none,
              ),
            )
          )
        )
      );
    }

    var difference = targetDiffernce;

    if(verified) {
      result.add(
        const Positioned(
            bottom: 140,
            right: 20,
            child: Icon(Icons.gpp_good, size: 50, color: Colors.green),
          )
        );
    } else {
      result.add(
        const Positioned(
          bottom: 140,
          right: 20,
          child: Icon(Icons.gpp_good, size: 50, color: Colors.red),
        )
      );
    }

    // print('difference: $difference heading: $heading direction: ${videoRequest!.direction}');

    if(difference > 20 && difference < 340) {
      if(difference > 180) {
        var arrowsNum = 1 + (160.0 - (difference - 180)) ~/ 60;

        result += buildLeftArrows(arrowsNum);
      } else {
        var arrowsNum = 1 + difference ~/ 60;
        result += buildRightArrows(arrowsNum);
      }
    }

    return result;
  }

  List<Positioned> buildLeftArrows(int number) {
    List<Positioned> result = [];

    for(int i = 0; i < number; i++) {
      result.add(
        Positioned(
          bottom: 140,
          left: 70 + 10.0 * i,
          child: Icon(Icons.keyboard_arrow_left_rounded , size: 50, color: number > 1?Colors.red:Colors.yellow),
        )
      );
    }

    return result;
  }

  List<Positioned> buildRightArrows(int number) {
    List<Positioned> result = [];

    for(int i = 0; i < number; i++) {
      result.add(
        Positioned(
          bottom: 140,
          right: 70 + 10.0 * i,
          child: Icon(Icons.keyboard_arrow_right_rounded , size: 50, color: number > 1?Colors.red:Colors.yellow),
        )
      );
    }

    return result;
  }

  void startVideoRecording() async {
    try {
      video = Video(
        startTime: DateTime.now(),
        position: location!.currentLocation,
      );

      averageHeading = 0.0;
      headingCount = 0;
      headingSum = 0;

      await controller!.startVideoRecording();
      setState(() {
        isVideoRecording = true;
      });
    } catch (e) {
      print(e);
    }
  }

  void stopVideoRecording() async {
    try {
      uploading = true;
      var file = await controller!.stopVideoRecording();
      var path = '/storage/emulated/0/DCIM/Camera/${file.name}';
      file.saveTo(path);

      setState(() {
        isVideoRecording = false;
      });

      print('uploading...');

      video!.heading = (averageHeading + 360) % 360;
      video!.path = path;
      video!.hash = await getFileCIDHash(path);
      video!.endTime = DateTime.now();

      if(video!.hash == '') {
        showAlertDialog(context, 'Error', 'Error uploading video, try again.');
        return;
      }

      var messageToSign = 'video hash: ${video!.hash}';
      video!.signature = await login!.signMessageWithMetamask(messageToSign);

      print('signed ${video!.signature}');
      var result = await uploadVideo();
      if(result) {
        Navigator.pop(context, video);
        print('uploaded.');
      } else {
        showAlertDialog(context, 'Error', 'Error uploading video, try again.');
      }
      uploading = false;
    } catch (e) {
      uploading = false;
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
    var actualCID = await uploadToIpfs(path);
    print('cidHash: $cidHash, fastCidHash: $fastCidHash actualCID: $actualCID');
    return actualCID;
  }

  Future<bool> initCamera() async {
    if(initialized) {
      return initialized;
    }

    cameras = await availableCameras();
    print('initCamera $cameras');
    controller = CameraController(cameras[0], ResolutionPreset.veryHigh);
    controller!.initialize().then((_) {
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
  void dispose() async {
    WidgetsBinding.instance.removeObserver(this);

    compassStream?.cancel();
    magnetometerStream?.cancel();
    accelerometerStream?.cancel();

    initialized = false;

    if(controller != null) {
      await controller!.dispose();
    }
    controller = null;

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    print('state changed');
    print(state);
    if (state == AppLifecycleState.inactive) {
      await controller!.dispose();
      controller = null;
    }
  }

  Future<String> uploadToIpfs(String path) async {
    var authorizationToken = base64Encode('App:chainlink2020'.codeUnits);

    var uploadFile = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        path,
      ),
    });

    Response? dioResponse;

    try {
      dioResponse = await dio.post(
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
    } catch (e) {
      print('upload to ipfs failed $e');
      return '';
    }

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
      'median_direction': video!.heading.truncate().toString(),
      'signature': video!.signature!,
      'request_id': videoRequest!.requestId,
      'expected_hash': video!.hash!,
    });

     var response;
    print('prepared request: ${request.fields}');
    try {
      response = await request.send();
    } catch (e) {
      print(e);
      return false;
    }
    print(response.statusCode);
    print(await response.stream.bytesToString());

    return response.statusCode == 200 || response.statusCode == 201;
  }
}

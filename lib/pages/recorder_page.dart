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


// 1. Page shows camera steam preview
// 2. When stream is verified (direction / location / phone orientation) button record becomes available
// 3. When button record is pressed, camera stream is recorded until verification requuriements met.
// 3.1 Video should contain at least 10 seconds of requested direction.
// 3.2 Video should contain executed actions (turn to random direction)
// 3.3 Video should not be longer than 30 seconds.
// 4. If all requirements met, video is uploaded to server.
// 5. Once video uploaded to server, we sign it's hash with metamask and push signature to server.
// 6. If requirements not met, video is discarded, and user is asked to try again.
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

  var requestedDirectionCaptured = 0.0;
  var actionDirectionCaptured = 0.0;

  LocationModel? location;
  LoginModel? login;
  RequestFromServer? videoRequest;

  var isVideoRecording = false;
  var uploading = false;
  var initialized = false;
  double uploadingProgress = 0.0;

  var angleChangeTime;

  var magnetometerStream, accelerometerStream, compassStream;

  double get targetDiffernce => ((videoRequest!.direction) - (heading + 360) % 360) % 360;
  double get actionDiffernce => ((videoRequest!.action) - (heading + 360) % 360) % 360;
  bool get targetVerified => ((targetDiffernce < 20 || targetDiffernce > 340) && averageGravity >= 8.0);
  bool get actionVerified => ((actionDiffernce < 20 || actionDiffernce > 340) && averageGravity >= 8.0);
  int get timeLeft => max(30 - ((DateTime.now().millisecondsSinceEpoch - video!.startTime.millisecondsSinceEpoch) / 1000.0).truncate(), 0);

  bool get goodToStartRecording => controller != null && targetVerified && !uploading;

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
      var previouseAngleChangeTime = angleChangeTime == null ? DateTime.now() : angleChangeTime;
      angleChangeTime = DateTime.now();
      heading = event.heading!;
      print('heading $heading headingForCameraMode: ${event.headingForCameraMode} accuracy: ${event.accuracy}');
      // print('location heading ${location!.currentLocation.heading}');

      if(isVideoRecording) {
        headingSum += heading;
        headingCount++;
        averageHeading = headingSum / headingCount;
        if(targetVerified) {
          requestedDirectionCaptured += (angleChangeTime.millisecondsSinceEpoch - previouseAngleChangeTime.millisecondsSinceEpoch) / 1000;
          // print('requestedDirectionCaptured: $requestedDirectionCaptured seconds $angleChangeTime, $previouseAngleChangeTime');
        }

        if(actionVerified && requestedDirectionCaptured > 10) {
          actionDirectionCaptured += (angleChangeTime.millisecondsSinceEpoch - previouseAngleChangeTime.millisecondsSinceEpoch) / 1000;
          // print('actionDirectionCaptured: $actionDirectionCaptured seconds $angleChangeTime, $previouseAngleChangeTime');

          if(actionDirectionCaptured > 5) {
            // all good we captured enough.
            stopVideoRecording();
          }
        }

        if(timeLeft == 0) {
          // captured enough, stop recording.
          stopVideoRecording();
        }
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

    location = args[0];
    login = args[1];
    videoRequest = args[2];

    return WillPopScope(
      onWillPop: () async {
        if(isVideoRecording) {
          await cancelVideoRecording();
        }
        if(controller != null) {
          await controller!.dispose();
          controller = null;
        }
        return true;
      },
      child: FutureBuilder<bool>(
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
                  child: !uploading && controller != null ? CameraPreview(controller!) : Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'Processing & uploading video...',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.normal,
                            decoration: TextDecoration.none,
                          ),
                        ),
                        Text(
                          'Progress: ${uploadingProgress.truncate()}%',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.normal,
                            decoration: TextDecoration.none,
                          ),
                        ),
                        Text(
                          uploadingProgress == 100 ? 'Connecting to metamask...' : '',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.normal,
                            decoration: TextDecoration.none,
                          ),
                        ),
                        const SizedBox(height: 50,),
                        const CircularProgressIndicator(color: Colors.white)
                    ]),
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
                        print('isVideoRecording $isVideoRecording $goodToStartRecording');
                        if (isVideoRecording) {
                          cancelVideoRecording();
                        } else {
                          if(goodToStartRecording) {
                            startVideoRecording();
                          } else {
                            print('can start recording $goodToStartRecording, $targetVerified, $uploading, $controller');
                          }
                        }
                      },
                      elevation: 2.0,
                      fillColor: Colors.white,
                      padding: EdgeInsets.all(15.0),
                      shape: CircleBorder(),
                      child: Icon(
                        size: 35.0,
                        isVideoRecording ? Icons.cancel : Icons.circle,
                        color: isVideoRecording ? Colors.black : (goodToStartRecording ? Colors.red : Colors.grey),
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
      ),
    );
  }

  List<Positioned> buildVerificatorWisgets(BuildContext context) {
    List<Positioned> result = [];

    if(uploading) {
      return result;
    }

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

    Color arrowsColor = Colors.red;
    if(isVideoRecording && requestedDirectionCaptured > 10) {
      difference = actionDiffernce;
      arrowsColor = Colors.green;
    }

    // print('action: ${videoRequest!.action}, direction: ${videoRequest!.direction},  heading $heading difference: $difference');

    if(targetVerified || (isVideoRecording && requestedDirectionCaptured > 10)) {
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

    if(isVideoRecording) {
      result.add(
        Positioned(
          bottom: 35,
          left: 20,
          width: 50,
          child: Icon(Icons.image, size: 50, color: Color.fromARGB(min(((requestedDirectionCaptured / 10.0) * 255).truncate() + 30, 255), 76, 175, 80)),
        )
      );
      result.add(
        Positioned(
          bottom: 20,
          left: 20,
          width: 43,
          child: Text('${min(((requestedDirectionCaptured / 10.0) * 100).truncate(), 100)}%', style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.bold,
              decoration: TextDecoration.none,
            ),
            textAlign: TextAlign.right,
          ),
        )
      );

      result.add(
        Positioned(
          bottom: 35,
          left: 70,
          width: 50,
          child: Icon(Icons.run_circle , size: 50, color: Color.fromARGB(min(((actionDirectionCaptured / 5.0) * 255).truncate() + 30, 255), 76, 175, 80)),
        )
      );
      result.add(
        Positioned(
          bottom: 20,
          left: 70,
          width: 43,
          child: Text('${min(((actionDirectionCaptured / 5.0) * 100).truncate(), 100)}%', style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.bold,
              decoration: TextDecoration.none,
            ),
            textAlign: TextAlign.right,
          ),
        )
      );

      result.add(
        Positioned(
          bottom: 50,
          right: 20,
          child: Text('${timeLeft}s', style: TextStyle(
              color: timeLeft > 5 ? Colors.white : Colors.red,
              fontSize: 20,
              fontWeight: FontWeight.bold,
              decoration: TextDecoration.none,
            ),
            textAlign: TextAlign.right,
          ),
        )
      );
    }


    if(difference > 20 && difference < 340) {
      if(difference > 180) {
        var arrowsNum = 1 + (160.0 - (difference - 180)) ~/ 60;

        result += buildLeftArrows(arrowsNum, color: arrowsColor);
      } else {
        var arrowsNum = 1 + difference ~/ 60;
        result += buildRightArrows(arrowsNum,  color: arrowsColor);
      }
    }

    return result;
  }

  List<Positioned> buildLeftArrows(int number, {Color color = Colors.red}) {
    List<Positioned> result = [];

    for(int i = 0; i < number; i++) {
      if(i == 0) {
        result.add(
          Positioned(
            bottom: 155,
            left: 0,
            width: MediaQuery.of(context).size.width,
            child: const Center(child: Text(
              'move camera left',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.normal,
                decoration: TextDecoration.none,
              ),
            )),
          )
        );
      }
      result.add(
        Positioned(
          bottom: 140,
          left: 70 - 10.0 * i,
          child: Icon(Icons.keyboard_arrow_left_rounded , size: 50, color: color),
        )
      );
    }

    return result;
  }

  List<Positioned> buildRightArrows(int number, {Color color = Colors.red}) {
    List<Positioned> result = [];

    for(int i = 0; i < number; i++) {
      if(i == 0) {
        result.add(
          Positioned(
            bottom: 155,
            left: 0,
            width: MediaQuery.of(context).size.width,
            child: const Center(child: Text(
              'move camera right',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.normal,
                decoration: TextDecoration.none,
              ),
            )),
          )
        );
      }
      result.add(
        Positioned(
          bottom: 140,
          right: 70 - 10.0 * i,
          child: Icon(Icons.keyboard_arrow_right_rounded , size: 50, color: color),
        )
      );
    }

    return result;
  }

  Future<void> startVideoRecording() async {
    try {
      video = Video(
        startTime: DateTime.now(),
        position: location!.currentLocation,
      );

      averageHeading = 0.0;
      headingCount = 0;
      headingSum = 0;
      requestedDirectionCaptured = 0.0;
      actionDirectionCaptured = 0.0;
      uploadingProgress = 0.0;
      isVideoRecording = true;

      await controller!.startVideoRecording();
      setState(() {
      });
    } catch (e) {
      print(e);
    }
  }

  Future<void> cancelVideoRecording() async {
    await controller!.stopVideoRecording();
    setState(() {
      uploading = false;
      isVideoRecording = false;
    });
  }

  Future<void> stopVideoRecording() async {
    try {
      if(!isVideoRecording) {
        return;
      }

      uploading = true;
      isVideoRecording = false;
      var file = await controller!.stopVideoRecording();

      if(!(requestedDirectionCaptured > 10 && actionDirectionCaptured > 5 && timeLeft > 0)) {
        print('verification is not passed');
        uploading = false;
        isVideoRecording = false;
        return;
      }

      var path = '/storage/emulated/0/DCIM/Camera/${file.name}';
      file.saveTo(path);

      setState(() {
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
  void dispose() {
    print('fucking disposing!');
    try {
      WidgetsBinding.instance.removeObserver(this);

      compassStream?.cancel();
      magnetometerStream?.cancel();
      accelerometerStream?.cancel();

      initialized = false;

      if(controller != null) {
        controller!.dispose();
        controller = null;
      }

    } catch (e) {
      print(e);
    }

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    print('state changed');
    print(state);
    if (state == AppLifecycleState.inactive) {
      if(controller != null) {
        if(isVideoRecording) {
          await controller!.stopVideoRecording();
        }
        await controller!.dispose();
        controller = null;
      }
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
            uploadingProgress = received / total * 100;
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
    // var request = http.Request("POST", url);

    // request.files.add(
    //   await http.MultipartFile.fromPath(
    //     'file',
    //     video!.path!,
    //   )
    // );
    var fields = new Map<String, dynamic>();

    fields['lat'] = video!.position.latitude.toString();
    fields['long'] = video!.position.longitude.toString();
    fields['start'] = video!.startTime.millisecondsSinceEpoch.toString();
    fields['end'] = video!.endTime!.millisecondsSinceEpoch.toString();
    fields['median_direction'] = video!.heading.truncate().toString();
    fields['signature'] = video!.signature!;
    fields['request_id'] = videoRequest!.requestId;
    fields['expected_hash'] = video!.hash!;

    print('prepared request: ${fields}');

    // request.fields.addAll({
    //   'lat': video!.position.latitude.toString(),
    //   'long': video!.position.longitude.toString(),
    //   'start': video!.startTime.millisecondsSinceEpoch.toString(),
    //   'end': video!.endTime!.millisecondsSinceEpoch.toString(),
    //   'median_direction': video!.heading.truncate().toString(),
    //   'signature': video!.signature!,
    //   'request_id': videoRequest!.requestId,
    //   'expected_hash': video!.hash!,
    // });

    http.Response response;

    try {
      response = await http.post(
          url,
          body: fields,
      );
    } catch (e) {
      print(e);
      return false;
    }
    print(response.statusCode);
    print(response.body);

    return response.statusCode == 200 || response.statusCode == 201;
  }
}

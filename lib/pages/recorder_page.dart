import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
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
// 3.1 Video should contain at least 7 seconds of requested direction.
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

  var popping = false;

  // start to calculate on video start;
  var averageHeading = 0.0;
  var headingSum = 0.0;
  var headingCount = 0;

  var in_direction_requirement = 6.0;
  var in_action_requirement = 3.0;

  var requestedDirectionCaptured = 0.0;
  var actionDirectionCaptured = 0.0;

  LocationModel? location;
  LoginModel? login;
  RequestFromServer? videoRequest;

  var isVideoRecording = false;
  var uploading = false;
  bool? verified;
  var initializationInProgress = false;
  double uploadingProgress = 0.0;

  var angleChangeTime;

  var accelerometerStream, compassStream;

  double get targetDiffernce => ((videoRequest!.direction) - (heading + 360) % 360) % 360;
  double get actionDiffernce => ((videoRequest!.action) - (heading + 360) % 360) % 360;
  bool get targetVerified => ((targetDiffernce < 20 || targetDiffernce > 340) && averageGravity >= 8.0);
  bool get actionVerified => ((actionDiffernce < 20 || actionDiffernce > 340) && averageGravity >= 8.0);
  int get timeLeft => max(20 - ((DateTime.now().millisecondsSinceEpoch - video!.startTime.millisecondsSinceEpoch) / 1000.0).truncate(), 0);

  bool get goodToStartRecording => controller != null && targetVerified && !uploading;

  @override
  void initState() {
    motionSensors.accelerometerUpdateInterval = 20000;

    accelerometerStream = motionSensors.accelerometer.listen((AccelerometerEvent event) {
      gravitySum += event.y;
      gravityHistory.addLast(event.y);

      if(gravityHistory.length > 300) {
        gravitySum -= gravityHistory.removeFirst();
      }

      var oldAverageGravity = averageGravity;
      var newAverageGravity = gravitySum / gravityHistory.length;

      averageGravity = newAverageGravity;

      if(oldAverageGravity < verticalThreshold && newAverageGravity > verticalThreshold) { 
        if (mounted && !popping) {
          setState(() {});
        }

      } else if (oldAverageGravity > verticalThreshold && newAverageGravity < verticalThreshold) {
        if (mounted && !popping) {
          setState(() {});
        }
      }
    });

    compassStream = FlutterCompass.events?.listen((CompassEvent event) {
      var previouseAngleChangeTime = angleChangeTime == null ? DateTime.now() : angleChangeTime;
      angleChangeTime = DateTime.now();
      heading = event.heading!;

      if(isVideoRecording) {
        headingSum += heading;
        headingCount++;
        averageHeading = headingSum / headingCount;
        if(targetVerified) {
          requestedDirectionCaptured += (angleChangeTime.millisecondsSinceEpoch - previouseAngleChangeTime.millisecondsSinceEpoch) / 1000;
        }

        if(actionVerified && requestedDirectionCaptured > in_direction_requirement) {
          actionDirectionCaptured += (angleChangeTime.millisecondsSinceEpoch - previouseAngleChangeTime.millisecondsSinceEpoch) / 1000;

          if(actionDirectionCaptured > in_action_requirement) {
            // all good we captured enough.
            if (mounted && !popping) {
              stopVideoRecording();
            }
          }
        }

        if(timeLeft == 0) {
          // captured enough, stop recording.
          if (mounted && !popping) {
            stopVideoRecording();
          }
        }
      }

      if (mounted && !popping) {
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

        popping = true;
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
                        buildStatusText(),
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
                        if (isVideoRecording) {
                          cancelVideoRecording();
                        } else {
                          if(goodToStartRecording) {
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

  Text buildStatusText() {
    String message;
    if(uploadingProgress < 100) {
      message = '';
    } else {
      if(verified == null) {
        message = 'Verifying video...';
      } else {
        if(verified!) {
          message = 'Video verified, signing...';
        } else {
          message = 'Video not verified.';
        }
      }
    }

    return Text(
      message,
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.normal,
        decoration: TextDecoration.none,
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
    if(isVideoRecording && requestedDirectionCaptured > in_direction_requirement) {
      difference = actionDiffernce;
      arrowsColor = Colors.green;
    }

    if(targetVerified || (isVideoRecording && requestedDirectionCaptured > in_direction_requirement)) {
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
          child: Text('${min(((requestedDirectionCaptured / in_direction_requirement) * 100).truncate(), 100)}%', style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.normal,
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
          child: Text('${min(((actionDirectionCaptured / in_action_requirement) * 100).truncate(), 100)}%', style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.normal,
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
      verified = null;

      await controller!.startVideoRecording();
      if(!popping) {setState(() {});} else {return;}
    } catch (e) {
      print(e);
    }
  }

  Future<void> cancelVideoRecording() async {
    await controller!.stopVideoRecording();
    if(!popping) {
      setState(() {
      uploading = false;
      isVideoRecording = false;
    });
    } else {
      return;
    }
  }

  Future<void> stopVideoRecording() async {
    try {
      if(!isVideoRecording) {
        return;
      }

      uploading = true;
      isVideoRecording = false;
      var file = await controller!.stopVideoRecording();

      if(!(requestedDirectionCaptured > in_direction_requirement && actionDirectionCaptured > in_action_requirement && timeLeft > 0)) {
        showOKDialog(
          context,
          'You recorded wrong direction.',
          'Please follow to instructions during recording the video, to meet expectations on recorded direction.',
        );

        uploading = false;
        isVideoRecording = false;
        return;
      }

      if(!popping) {setState(() {});} else {return;}

      video!.heading = (averageHeading + 360) % 360;
      video!.path = file.path;
      video!.endTime = DateTime.now();

      video!.hash = await getFileCIDHash(file.path);

      if(!mounted) {return;}

      while(video!.hash == '') {
        bool retry = await showRetryDialog(context, 'Error', 'Error uploading video, try again.');
        if(!retry) {
          uploading = false;
          isVideoRecording = false;
          return;
        }

        // try to upload again
        video!.hash = await getFileCIDHash(file.path);
      }

      if(!mounted) {return;}

      var url = 'https://api.objective.camera/verify/${video!.hash}/${videoRequest!.direction.truncate()}/${videoRequest!.action.truncate()}';

      bool gotResponse = false;
      while(!gotResponse) {
        try {
          Response dioResponse = await dio.get(url);
          verified = dioResponse.data['is_verified'];
          gotResponse = true;
        }  catch (e) {
          print(e);

          bool retry = await showRetryDialog(context, 'Error', 'Could not verify video on server.');
          if(!retry) {
            verified = false;
            break;
          }
        }
      }

      // if not verified wait a bit and return. Camera should start again.
      if(!verified!) {
        showOKDialog(
          context,
          'Video is not verified.',
          'Server could not verify video. It could be caused by moving objects in the video or by bad lighting conditions. Please try again.',
        );

        uploading = false;
        verified = null;
        if(!popping) {setState(() {});} else {return;}
        return;
      }

      if(!mounted) {return;}
      if(!popping) {setState(() {});} else {return;}

      var messageToSign = 'video hash: ${video!.hash}';
      while(video!.signature == null || video!.signature == '') {
        video!.signature = await login!.signMessageWithMetamask(messageToSign);
        if(video!.signature == '') {
          bool retry = await showRetryDialog(context, 'Error', 'Could not get signature from Metamask.');
          if(!retry) {
            uploading = false;
            verified = null;
            if(!popping) {setState(() {});} else {return;}
            return;
          }
        }
      }

      if(!mounted) {return;}

      bool uploaded = false;
      while(!uploaded) {
        uploaded = await uploadVideo();
        if(!uploaded) {
          bool retry = await showRetryDialog(context, 'Error', 'Error uploading video, try again.');
          if(!retry) {
            uploading = false;
            return;
          }
        }
      }

      if(uploaded) {
        Navigator.pop(context, video);
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
    return actualCID;
  }

  Future<bool> initCamera() async {
    if(initializationInProgress) {
      return false;
    }

    if(controller != null && controller!.value.isInitialized) {
      return true;
    }

    initializationInProgress = true;

    try {
      cameras = await availableCameras();
      controller = CameraController(cameras[0], ResolutionPreset.veryHigh);
      await controller!.initialize();
    } catch(e) {
      if (e is CameraException) {
        switch (e.code) {
          case 'CameraAccessDenied':
            break;
          default:
            break;
        }
      } else {
        print(e);
      }
    }

    initializationInProgress = false;

    if (!mounted || popping) {
      return false;
    }
    setState(() {});
    return true;
  }

  @override
  void dispose() {
    try {
      WidgetsBinding.instance.removeObserver(this);

      compassStream?.cancel();
      accelerometerStream?.cancel();

      if(controller != null) {
        controller!.dispose();
        controller = null;
      }

      initializationInProgress = false;

    } catch (e) {
      print(e);
    }

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
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
          }
        },
      );
    } catch (e) {
      print(e);
      return '';
    }

    var expectedHash = dioResponse.data['Hash'];
    return expectedHash;
  }

  Future<bool> uploadVideo() async {
    var url = Uri.https('api.objective.camera', 'upload/');
    var fields = new Map<String, dynamic>();

    fields['lat'] = video!.position.latitude.toString();
    fields['long'] = video!.position.longitude.toString();
    fields['start'] = video!.startTime.millisecondsSinceEpoch.toString();
    fields['end'] = video!.endTime!.millisecondsSinceEpoch.toString();
    fields['median_direction'] = video!.heading.truncate().toString();
    fields['signature'] = video!.signature!;
    fields['request_id'] = videoRequest!.requestId;
    fields['expected_hash'] = video!.hash!;

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

    return response.statusCode == 200 || response.statusCode == 201;
  }
}

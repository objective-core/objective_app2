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
import 'package:web3dart/crypto.dart';
import 'package:objective_app2/utils/data.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';



class RecorderPage extends StatefulWidget {
  const RecorderPage({Key? key}) : super(key: key);

  @override
  State<RecorderPage> createState() => _RecorderPageState();
}

class _RecorderPageState extends State<RecorderPage> with WidgetsBindingObserver {
  late CameraController controller;
  late List<CameraDescription> cameras; 
  late Data data;
  Dio dio = Dio();

  var isVideoRecording = false;
  var uploading = false;
  var initialized = false;

  @override
  Widget build(BuildContext context) {
    data = ModalRoute.of(context)!.settings.arguments as Data;

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
              Positioned(
                bottom: 25,
                left: 15,
                width: 70,
                height: 70,
                child: Container(
                  width: 80,
                  height: 80,
                  child: RawMaterialButton(
                    onPressed: () {
                      // Go to map page.
                      Navigator.pushNamed(context, AppRoutes.locationPickerRoute, arguments: data);
                    },
                    elevation: 2.0,
                    fillColor: Colors.black,
                    padding: EdgeInsets.all(15.0),
                    shape: CircleBorder(),
                    child: const Icon(
                      size: 30,
                      Icons.add_shopping_cart ,
                      color: Colors.white,
                    ),
                  ),
                )
              ),
              Positioned(
                bottom: 25,
                right: 15,
                width: 70,
                height: 70,
                child: Container(
                  width: 80,
                  height: 80,
                  child: RawMaterialButton(
                    onPressed: () {
                      // Go to map page.
                    },
                    elevation: 2.0,
                    fillColor: Colors.black,
                    padding: const EdgeInsets.all(15.0),
                    shape: const CircleBorder(),
                    child: const Icon(
                      size: 35,
                      Icons.attach_money,
                      color: Colors.white,
                    ),
                  ),
                )
              )
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
      data.video = Video(
        startTime: DateTime.now(),
        position: data.currentPosition!,
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

      data.video!.path = path;
      data.video!.hash = await getFileCIDHash(path);
      data.video!.endTime = DateTime.now();

      var messageToSign = 'video hash: ${data.video!.hash}';
      data.video!.signature = await signMessageWithMetamask(messageToSign);

      await uploadVideo();

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

    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        data.video!.path!,
      )
    );
    request.fields.addAll({
      'lat': data.currentPosition!.latitude.toString(),
      'long': data.currentPosition!.longitude.toString(),
      'start': data.video!.startTime.millisecondsSinceEpoch.toString(),
      'end': data.video!.endTime!.millisecondsSinceEpoch.toString(),
      'median_direction': data.currentPosition!.heading.truncate().toString(),
      'signature': data.video!.signature!,
      'request_id': '1667993686',
      'expected_hash': data.video!.hash!,
    });

    var response = await request.send();
    print(response.statusCode);
    print(await response.stream.bytesToString());

    return true;
  }

  Future<String> signMessageWithMetamask(String message) async {
    if (data.connector!.connected) {
      print("Message received");
      print(message);

      EthereumWalletConnectProvider provider =
          EthereumWalletConnectProvider(data.connector!);

      launchUrlString(data.connectionUri!, mode: LaunchMode.externalApplication);

      return await provider.personalSign(
        message: message,
        address: data.connector!.session.accounts[0],
        password: '',
      );
    }
    return '';
  }

}

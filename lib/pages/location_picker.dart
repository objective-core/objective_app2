import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'dart:ui';
import 'package:intl/intl.dart';
import 'package:map_location_picker/map_location_picker.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:objective_app2/utils/data.dart';
import 'package:web3dart/web3dart.dart';

import 'package:walletconnect_dart/walletconnect_dart.dart';
import 'package:web3dart/web3dart.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:dio/dio.dart';
import 'package:label_marker/label_marker.dart';


class LocationPickerPage extends StatefulWidget {
  const LocationPickerPage({Key? key}) : super(key: key);

  @override
  State<LocationPickerPage> createState() => _LocationPickerPageState();
}

enum PickerModes{
  location, period, videoRequest
}

class _LocationPickerPageState extends State<LocationPickerPage> {
    Completer<GoogleMapController> _controller = Completer();
    late BitmapDescriptor cameraIcon;
    late BitmapDescriptor cameraIconPressed;
    late BitmapDescriptor cameraIconSelected;
    Dio dio = Dio();

    Set<Marker> _markers = {};
    Set<Marker> _videoRequetsMarkers = {};
    List<VideoRequestFromServer> _videoRequests = [];
    late Marker _marker;

    double _mapAngle = 0;
    bool scrolling = false;

    double directionShift = 0;
    double timeShift = 0;

    PickerModes currentMode = PickerModes.location;
    bool locationConfirmed = false;
    bool timeConfirmed = false;

    var currentLocation, markerPostion;
    late Data data;

    @override
    Widget build(BuildContext context) {
      data = ModalRoute.of(context)!.settings.arguments as Data;

      currentLocation = LatLng(
        data.currentPosition!.latitude,
        data.currentPosition!.longitude
      );

      final CameraPosition _kGooglePlex = CameraPosition(
        target: currentLocation,
        zoom: 14.4746, 
      );

      addMarker();

      return buildMainWidget(_kGooglePlex, context);
    }

    Scaffold buildMainWidget(CameraPosition _kGooglePlex, BuildContext context) {
      return Scaffold(
        body: Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              height: 100,
              child: Container(
                  height: 100,
                  width: MediaQuery.of(context).size.width,
                  decoration: const BoxDecoration(
                    color: Colors.black,
                  ),
              ),
            ),
            Positioned(
              top: 100,
              left: 0,
              height: MediaQuery.of(context).size.height - 100,
              width: MediaQuery.of(context).size.width,
              child: GoogleMap(
                  initialCameraPosition: _kGooglePlex,
                  mapType: MapType.hybrid,
                  markers: _markers,
                  zoomControlsEnabled: false,
                  myLocationButtonEnabled: false,
                  onMapCreated: (GoogleMapController controller) {
                    _controller.complete(controller);
                  },
                  onTap: (latlang){
                    print(latlang);
                  },
                  onCameraMove: (position) {
                    _mapAngle = position.bearing;
                    refreshCameraMarker(context);
                  },
                ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              height: 120,
              child: Container(
                  height: 120,
                  width: MediaQuery.of(context).size.width,
                  decoration: const BoxDecoration(
                    color: Colors.black,
                  ),
              ),
            ),
            Positioned(
              bottom: 50,
              left: 0,
              width: MediaQuery.of(context).size.width,
              height: 70,
              child: currentMode == PickerModes.location ? ScrollWithScale(
                legendWidget: CompassLettersCarousel(shift: directionShift, context: context),
                onStartCallback: () {
                  scrolling = true;
                  cameraIconSelected = cameraIconPressed;
                  locationConfirmed = false;
                  refreshCameraMarker(context);
                  _goToTheMarker();
                },
                onUpdateCallback: (shift) {
                  directionShift = shift;
                  refreshCameraMarker(context);
                },
                onStopCallback: () {
                  scrolling = false;
                  cameraIconSelected = cameraIcon;
                  refreshCameraMarker(context);
                },
                onAnimationCallback: (shift) {
                  directionShift = shift;
                  refreshCameraMarker(context);
                },
              ) : ScrollWithScale(
                numberOfBars: 16,
                onStartCallback: () {
                  setState(() {
                    timeConfirmed = false;
                  });
                },
                onUpdateCallback: (shift) {
                  setState(() {
                    timeShift = shift;
                    data.request!.startTimestamp = calculateSelectedTime(context).millisecondsSinceEpoch ~/ 1000;
                  });
                },
                onStopCallback: () {},
                onAnimationCallback: (shift) {
                  setState(() {
                    timeShift = shift;
                    data.request!.startTimestamp = calculateSelectedTime(context).millisecondsSinceEpoch ~/ 1000;
                  });
                },
                legendWidget: TimePickerCarousel(shift: timeShift, context: context),
              )
            ),
            Positioned(
              bottom: 0,
              left: 0,
              height: 50,
              width: MediaQuery.of(context).size.width,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [ // IconButton(iconSize: 72, icon: Icon(Icons.favorite), ...)
                  IconButton(
                    icon: Icon(Icons.compass_calibration_rounded, size: 30),
                    color: currentMode == PickerModes.location? Colors.yellow : Colors.white,
                    iconSize: 50,
                    onPressed: () {
                      setState(() {
                        currentMode = PickerModes.location;
                      });
                    }
                  ),
                  IconButton(
                    icon: Icon(Icons.date_range, size: 30,),
                    color: currentMode == PickerModes.period? Colors.yellow : Colors.white,
                    highlightColor: Colors.white,
                    iconSize: 50,
                    onPressed: () {
                      setState(() {
                        currentMode = PickerModes.period;
                      });
                    },
                  ),
                ],
              ) 
            ),
            locationConfirmed && timeConfirmed ? Positioned(
                top: 40,
                right: 10,
                height: 50,
                width: 100,
                child: TextButton(
                  child: Text('Submit', textAlign: TextAlign.right, style: TextStyle(color: Colors.white, fontSize: 20),),
                  onPressed: () {
                    print('Submitting');
                    sendTxViaMetamask(context);
                    setState(() {
                      locationConfirmed = true;
                      currentMode = PickerModes.period;
                    });
                  }
                ),
            ) : (
              !locationConfirmed ? Positioned(
                top: 40,
                right: 10,
                height: 50,
                width: 180,
                child: TextButton(
                  child: Text('Confirm Location', textAlign: TextAlign.right, style: TextStyle(color: Colors.white, fontSize: 20),),
                  onPressed: () {
                    print('pressed Confirm why>>');
                    setState(() {
                      locationConfirmed = true;
                      currentMode = PickerModes.period;
                    });
                  }
                ),
              ) : Positioned(
                top: 40,
                right: 10,
                height: 50,
                width: 200,
                child: TextButton(
                  child: Text('Confirm Time: ${DateFormat('HH:mm').format(calculateSelectedTime(context))}', textAlign: TextAlign.right, style: TextStyle(color: Colors.white, fontSize: 20),),
                  onPressed: () {
                    print('pressed Confirm');
                    setState(() {
                      timeConfirmed = true;
                      currentMode = PickerModes.period;
                    });
                  }
                ),
              )
            ),
          ],
        ),
      );
    }

  Future<void> _goToTheMarker() async {
    if(_markers.length > 0){
      final GoogleMapController controller = await _controller.future;
      double currentZoom = await controller.getZoomLevel();
      controller.animateCamera(CameraUpdate.newCameraPosition(CameraPosition(
        target: _marker.position,
        zoom: currentZoom,
        bearing: _mapAngle,),
      ));
    }
  }

  void refreshCameraMarker(BuildContext context) {
    if(_markers.isNotEmpty) {
      setState(() {
        data.request!.latitude = markerPostion.latitude;
        data.request!.longitude = markerPostion.longitude;
        data.request!.direction = -(directionShift / MediaQuery.of(context).size.width) * 360;

        _marker = _marker.copyWith(
          rotationParam: -(directionShift / MediaQuery.of(context).size.width) * 360,
          positionParam: markerPostion,
          iconParam: cameraIconSelected,
        );
        _markers = {_marker};
        _markers.addAll(_videoRequetsMarkers);
      });
    }
  }

  Duration calculateSelectedShift(BuildContext context) {
    return Duration(minutes: (-timeShift ~/ ((MediaQuery.of(context).size.width / 16)).round()) * 15);
  }

  DateTime calculateSelectedTime(BuildContext context) {
    DateTime now = DateTime.now();
    now = DateTime(now.year, now.month, now.day, now.hour);
    DateTime time = now.add(calculateSelectedShift(context));
    return time;
  }

  String selectedTimeString(BuildContext context) {
    DateTime time = calculateSelectedTime(context);

    String result =  DateFormat('yyyy/MM/dd HH:mm').format(time);
    print('selected time: $time, result: $result');
    return result;
  }

  Future<void> addMarker() async {
    if(_markers.isEmpty) {
        data.request = VideoRequestData(
          direction: 0.0, // sbould be median direction
          latitude: data.currentPosition!.latitude,
          longitude: data.currentPosition!.longitude,
          startTimestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          secondsDuration: 3600 * 2,
        );

        cameraIcon = await BitmapDescriptor.fromAssetImage(
          const ImageConfiguration(size: Size(48, 48)),
          'assets/images/camera@2x.png'
        );
        cameraIconPressed = await BitmapDescriptor.fromAssetImage(
          const ImageConfiguration(size: Size(48, 48)),
          'assets/images/camera-pressed@2x.png'
        );
        cameraIconSelected = cameraIcon;

        markerPostion = currentLocation;
        var angle = -(directionShift / MediaQuery.of(context).size.width) * 360;

        _marker = Marker(
          // This marker id can be anything that uniquely identifies each marker.
          markerId: MarkerId('video_location'),
          position: markerPostion,
          infoWindow: const InfoWindow(
            title: 'Choose video location',
          ),
          icon: cameraIconSelected,
          draggable: true,
          anchor: const Offset(0.5, 0.5),
          rotation: angle,
          onDragStart: (value) {
            markerPostion = value;
            cameraIconSelected = cameraIconPressed;
            refreshCameraMarker(context);
          },
          onDrag: (value) {
            markerPostion = value;
            cameraIconSelected = cameraIconPressed;
            refreshCameraMarker(context);
          },
          onDragEnd: ((value) {
            markerPostion = value;
            cameraIconSelected = cameraIcon;
            refreshCameraMarker(context);
          })
        );
        _markers.add(_marker);
        setState(() {});

        await refreshVideoRequests();
        buildVideoRequestsMarkers(context);

        _markers.addAll(_videoRequetsMarkers);
        setState(() {});
    }
  }

  Future<void> refreshVideoRequests() async {
    // lets request the rest of markers
    _videoRequests = await getRequests();
  }

  buildVideoRequestsMarkers(BuildContext context) {
    for(var i = 0; i < _videoRequests.length; i++) {
      VideoRequestFromServer request = _videoRequests[i];

      String price = 'Ξ${request.reward.toDouble() / 1000000000000000000.toDouble()}';

      Duration selectedTimeShift = calculateSelectedShift(context);
      DateTime now = DateTime.now().add(selectedTimeShift);

      Duration timeToStart = Duration(milliseconds: request.startTime.millisecondsSinceEpoch - now.millisecondsSinceEpoch);
      Duration timeLeft = Duration(milliseconds: request.endTime.millisecondsSinceEpoch - now.millisecondsSinceEpoch);
      bool timeWindowPassed = timeLeft.isNegative;
      bool started = timeToStart.isNegative;
      bool captured = request.thumbnail != '';

      var color = Colors.blue;
      var message = '$price in ${timeToStart.inMinutes} mins';
      if(timeToStart.inMinutes > 60) {
        message = '$price in ${timeToStart.inHours} hours';
      }

      if(timeToStart.inHours > 24) {
        message = '$price in ${timeToStart.inDays} days';
      }

      if(captured) {
        message = '$price (captured)';
        color = Colors.yellow;
      } else if(timeWindowPassed) {
        message = '$price (expired)';
        color = Colors.grey;
      } else if(started) {
        if(started) {
          message = '$price ${timeLeft.inMinutes} mins left';
          color = timeLeft.inMinutes > 10 ? Colors.green : Colors.red;
        }
      }

      var marker = LabelMarker(
        label: message,
        markerId: MarkerId('video_location_${request.requestId}'),
        position: LatLng(request.latitude, request.longitude),
        backgroundColor: color,
        icon: cameraIcon,
      );

      _videoRequetsMarkers.addLabelMarker(marker);
    }
  }

  Future<DeployedContract> getContract() async {
      print('trying to load contract');
      String abi = await rootBundle.loadString("assets/contracts/VideoRequester.json");
      print('contract loaded');
      String contractAddress = "0xe011eA99393AaB86E59fd57Ff4DbB48825E36290";
      String contractName = "VideoRequester";

      DeployedContract contract = DeployedContract(
        ContractAbi.fromJson(abi, contractName),
        EthereumAddress.fromHex(contractAddress),
      );

      print('deployed contract created');

      return contract;
    }

  sendTxViaMetamask(BuildContext context) async {
      if (data.connector!.connected) {
        try {
          print("Sending transaction");
          print(data.request!.getIntegerDirection());
          print(data.request!.getIntegerLatitude());
          print(data.request!.getIntegerLongitude());
          print(data.request!.startTimestamp);
          print(data.request!.getIntegerEndTimestamp());

          var function_address = 'd8484ca7';
          var requestId = 1;
          var contractAddress = '0xa8cbf99c7ea18a8e6a2ea34619609a0aa9e77211';

          DeployedContract contract = await getContract();
          ContractFunction function = contract.function("submitRequest");

          print('constracting data');
          var data_bytes = function.encodeCall([
              "1",
              BigInt.from(data.request!.getIntegerLatitude()),
              BigInt.from(data.request!.getIntegerLongitude()),
              BigInt.from(data.request!.startTimestamp),
              BigInt.from(data.request!.getIntegerEndTimestamp()),
              BigInt.from(data.request!.getIntegerDirection()),
          ]);
          print(data_bytes);

          EthereumWalletConnectProvider provider = EthereumWalletConnectProvider(data.connector!, chainId: 5);
          launchUrlString(data.connectionUri!, mode: LaunchMode.externalApplication);

          var tx = await provider.sendTransaction(
            from: data.connector!.session.accounts[0],
            to: contractAddress,
            value: EtherAmount.fromUnitAndValue(EtherUnit.finney, BigInt.from(1)).getInWei,
            gasPrice: EtherAmount.fromUnitAndValue(EtherUnit.gwei, BigInt.from(100)).getInWei, // get gas price estimation from somewhere.
            gas: 150000, // default: 90000
            data: data_bytes,
          );

          print(tx);
          data.request!.txHash = tx;
          Navigator.pop(context);
        } catch (exp) {
          print("Error while sending transaction");
          print(exp);
          print(exp.toString());
        }
      }
  }

  Future<List<VideoRequestFromServer>> getRequests() async {
    Response dioResponse = await dio.get(
      'https://api.objective.camera/requests',
    );

    var requests = dioResponse.data['requests'];
    List<VideoRequestFromServer> result = [];

    for(var i = 0; i < requests.length; i++) {
      var request = requests[i];
      result.add(VideoRequestFromServer(
        direction: (request['location']['direction']).toDouble(),
        latitude: request['location']['lat'],
        longitude: request['location']['long'],
        startTime: DateTime.parse(request['start_time'] + 'Z'),
        endTime: DateTime.parse(request['end_time'] + 'Z'),
        requestId: request['id'],
        reward: request['reward'],
        thumbnail: request['video'] == null ? '' : 'https://i.picsum.photos/id/182/200/100.jpg?hmac=nuni_xT1TfXyyqbAcn1bG1oAXfba-QH6lW1zNDDgKDs',
      ));
    }
    return result;
  }

}

typedef ScrollWithScaleOnStartCallback = void Function();
typedef ScrollWithScaleOnUpdateCallback = void Function(double shift);
typedef ScrollWithScaleOnStopCallback = void Function();
typedef ScrollWithScaleOnAnimationCallback = void Function(double shift);

class ScrollWithScale extends StatefulWidget {
  ScrollWithScale({
    Key? key,
    required this.onStartCallback,
    required this.onUpdateCallback,
    required this.onStopCallback,
    required this.onAnimationCallback,
    required this.legendWidget,
    this.numberOfBars = 16,
    this.duration = const Duration(milliseconds: 200),
  }) : super(key: key);

  final ScrollWithScaleOnStartCallback onStartCallback;
  final ScrollWithScaleOnUpdateCallback onUpdateCallback;
  final ScrollWithScaleOnStopCallback onStopCallback;
  final ScrollWithScaleOnAnimationCallback onAnimationCallback;
  final int numberOfBars;
  final Duration duration;
  final Widget legendWidget;

  @override
  State<ScrollWithScale> createState() => _ScrollWithScaleState();
}

class _ScrollWithScaleState extends State<ScrollWithScale> {

  bool scrolling = false;
  double directionShift = 0;

  void animateToRoundedShift(BuildContext context) {
    var barSpace = Scale.getSpaceBetween(context, widget.numberOfBars) + Scale.barWidth;
    var delta = directionShift % (barSpace);

    var roundedShift = directionShift - delta;
    if(delta > barSpace / 2) {
      roundedShift = directionShift + (barSpace - delta);
    }

    animateShift(roundedShift, 0);
  }

  void animateShift(double toShift, int stepsDone) async {
    var frequencyMs = 20;
    var stepsOkToDo = widget.duration.inMilliseconds ~/ frequencyMs;

    if(scrolling || stepsDone >= stepsOkToDo) {
      return;
    }

    setState(() {
      directionShift += (toShift - directionShift) / (stepsOkToDo - stepsDone);
    });

    widget.onAnimationCallback(directionShift);

    await Future.delayed(Duration(milliseconds: frequencyMs));
    animateShift(toShift, stepsDone + 1);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
        Positioned(
          bottom: 30,
          left: 0,
          width: MediaQuery.of(context).size.width,
          height: 30,
          child: widget.legendWidget,
        ),
        Positioned(
          height: 20,
          bottom: 10,
          left: 0,
          width: MediaQuery.of(context).size.width,
          child: Scale(shift: directionShift, numberOfBars: widget.numberOfBars, context: context),
        ),
        Positioned(
          bottom: 0,
          width: MediaQuery.of(context).size.width,
          height: 60,
          child: const ScrollPickerShadow(),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          width: MediaQuery.of(context).size.width,
          height: 70,
          child: GestureDetector(
            onHorizontalDragStart: (details) {
              setState(() {
                scrolling = true;
              });
              widget.onStartCallback();
            },
            onHorizontalDragUpdate: (details) {
              setState(() {
                directionShift += details.delta.dx;
              });
              widget.onUpdateCallback(directionShift);
            },
            onHorizontalDragEnd: (details) {
              setState(() {
                scrolling = false;
              });
              widget.onStopCallback();
              animateToRoundedShift(context);
            },
          ),
        ),
      ],
    );
  }
}

class ScrollPickerShadow extends StatelessWidget {
  const ScrollPickerShadow({
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Colors.black.withOpacity(1.0),
            Colors.black.withOpacity(0.0),
            Colors.black.withOpacity(1.0),
          ],
        ),
      )
    );
  }
}

class CompassLettersCarousel extends StatelessWidget {
  const CompassLettersCarousel({
    Key? key,
    required double shift,
    required this.context,
  }) : _shift = shift, super(key: key);

  final double _shift;
  final BuildContext context;

  @override
  Widget build(BuildContext context) {
      var letterWidth = 30;
      var letters = ['S', 'W', 'N', 'E'];
      var containerWidth = MediaQuery.of(context).size.width;
      var effectiveShift = _shift %  containerWidth;
      List<Widget> children = [];

      for(var i = 0; i < 4; i++) {
          var letter = letters[i];
          // we can do this cause letters are in order
          var defaultPosition = i * containerWidth / 4.0;
          // position of letter after applying shift
          var position = (defaultPosition + effectiveShift - letterWidth / 2.0) % containerWidth;
          if(position >= 0 && position <= containerWidth - letterWidth) {
            children.add(
              Positioned(
                left: position,
                top: 0,
                width: 30,
                height: 30,
                child: DirectionLetter(letter: letter),
              )
            );
          }
      }

      return Stack(children: children);
    }
}

class TimePickerCarousel extends StatelessWidget {
  const TimePickerCarousel({
    Key? key,
    required double shift,
    required this.context,
  }) : _shift = shift, super(key: key);

  final double _shift;
  final BuildContext context;

  @override
  Widget build(BuildContext context) {
      var currentTime = DateTime.now();
      var currentHour = currentTime.hour;

      var containerWidth = MediaQuery.of(context).size.width;
      var hoursShift = (-_shift) ~/ (containerWidth / 4);
      var effectiveShift = _shift % (containerWidth / 4);
      if(_shift < 0) {
        effectiveShift = -(_shift.abs() % (containerWidth / 4));
      }

      print('hoursShift: $hoursShift; shift: $_shift; effectiveShift: $effectiveShift');

      // position hours correctly.
      var times = [
        currentTime.subtract(const Duration(hours: 2)).add(Duration(hours: hoursShift)),
        currentTime.subtract(const Duration(hours: 1)).add(Duration(hours: hoursShift)),
        currentTime.add(Duration(hours: hoursShift)),
        currentTime.add(const Duration(hours: 1)).add(Duration(hours: hoursShift)),
        currentTime.add(const Duration(hours: 2)).add(Duration(hours: hoursShift)),
      ];
      print(times);

      var letterWidth = 60.0;
      List<Widget> children = [];

      for(var i = 0; i < 5; i++) {
          DateTime hourDT = times[i];
          int dayDelta = -(currentTime.day - hourDT.day);
          // print('adding hour $hourDT');
          // we can do this cause times are in order
          var defaultPosition = i * containerWidth / 4.0;
          // position of letter after applying shift
          var position = (defaultPosition + effectiveShift - letterWidth / 2.0);
          // print(position);
          if(position >= 0 && position <= containerWidth - letterWidth) {
            children.add(
              Positioned(
                left: position,
                top: 0,
                width: letterWidth,
                height: 30,
                child: Container(
                  alignment: Alignment.center,
                  child: Text(
                    '${DateFormat.H().format(hourDT)}:00',
                    style: TextStyle(color: Colors.white, fontSize: 14),)
                ),
              )
            );
            if(dayDelta > 0 && hourDT.hour == 0 || dayDelta < 0 && hourDT.hour == 23) {
              children.add(
                Positioned(
                  left: position,
                  top: 0,
                  width: letterWidth,
                  height: 30,
                  child: Container(
                    alignment: Alignment.topRight,
                    child: Text(
                      dayDelta > 0?'+$dayDelta':'$dayDelta',
                      style: TextStyle(color: Colors.white, fontSize: 10),
                    )
                  ),
                )
              );
            }
          }
      }

      return Stack(children: children);
    }
}

class DirectionLetter extends StatelessWidget {
  const DirectionLetter({
    Key? key,
    required this.letter,
  }) : super(key: key);

  final String letter;

  static const Map<String, Color> letterToColor = {
    'S': Colors.white,
    'W': Colors.white,
    'N': Colors.red,
    'E': Colors.white,
  };

  @override
  Widget build(BuildContext context) {
      var container = Container(
        height: 30,
        width: 30,
        alignment: Alignment.center,
        child: Text(
          letter,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 18,
            color: letterToColor[letter],
            // fontWeight: FontWeight.bold,
          )
        ),
      );
      return container;
    }
}

class Scale extends StatelessWidget {
  const Scale({
    Key? key,
    required double shift,
    required int numberOfBars,
    required this.context,
  }) : _shift = shift, _numberOfBars = numberOfBars, super(key: key);

  final double _shift;
  final int _numberOfBars;
  final BuildContext context;

  static const double barWidth = 1.0;
  static const double barHeight = 10.0;
  static const double numberOfBars = 32.0;

  @override
  Widget build(BuildContext context) {
      var containerWidth = MediaQuery.of(context).size.width;
      var middle = containerWidth / 2.0;
      var effectiveShift = _shift % containerWidth;
      var spaceBetween = getSpaceBetween(context, _numberOfBars);
      List<Widget> children = [];

      for(double offset = 0; offset < containerWidth - barWidth; offset += spaceBetween + barWidth) {
        children.add(
          Positioned(
            left: (offset + effectiveShift) % containerWidth,
            top: 0,
            width: barWidth,
            height: barHeight,
            child: Container(
              width: barWidth,
              color: Colors.white,
            )
          )
        );
      }

      children.add(
        Positioned(
          top: 0,
          left: middle,
          width: 2,
          height: 20,
          child: Container(
            width: 2,
            color: Colors.yellow,
          )
        )
      );

      return Stack(children: children);
    }

    static double getSpaceBetween(BuildContext context, int numberOfBars) {
      var containerWidth = MediaQuery.of(context).size.width;
      return containerWidth / (numberOfBars) - barWidth;
    }
}

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

import 'package:objective_app2/models/location.dart';
import 'package:objective_app2/models/login.dart';
import 'package:objective_app2/models/requests.dart';


typedef CameraMarkerOnStartUpdate = void Function(Marker marker);
typedef CameraMarkerUpdated = void Function(Marker marker);
typedef CameraMarkerOnStopUpdate = void Function(Marker marker);

typedef VideoRequestUpdated = void Function(VideoRequestData data);
typedef VideoRequestSent = void Function(VideoRequestData data);
typedef VideoRequestCancel = void Function();


enum PickerModes{
  location, period, videoRequest
}

class LocationPickerBuilder {
    late BitmapDescriptor cameraIcon;
    late BitmapDescriptor cameraIconPressed;
    late BitmapDescriptor cameraIconSelected;
    Dio dio = Dio();

    // Models
    LocationModel? location;
    LoginModel? login;
    late VideoRequestData videoRequest;

    // Callbacks
    CameraMarkerUpdated onCameraMarkerUpdated;
    VideoRequestUpdated onVideoRequestUpdated;
    VideoRequestSent onVideoRequestSent;
    VideoRequestCancel onVideoRequestCancel;
    CameraMarkerOnStartUpdate onCameraMarkerOnStartUpdate;
    CameraMarkerOnStopUpdate onCameraMarkerOnStopUpdate;

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

    var markerPostion;

    LocationPickerBuilder({
      Key? key,
      required this.onCameraMarkerUpdated,
      required this.location,
      required this.login,
      required this.onVideoRequestUpdated,
      required this.onCameraMarkerOnStartUpdate,
      required this.onCameraMarkerOnStopUpdate,
      required this.onVideoRequestSent,
      required this.onVideoRequestCancel,
    });

    List<Positioned> buildLocationPicker(BuildContext context) {
      return [
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
              // TODO: _goToTheMarker();
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
          ) : ScrollWithScale( // Time selector
            numberOfBars: 16,
            onStartCallback: () {
              timeConfirmed = false;
              onVideoRequestUpdated(videoRequest);
            },
            onUpdateCallback: (shift) {
              timeShift = shift;
              videoRequest.startTimestamp = calculateSelectedTime(context).millisecondsSinceEpoch ~/ 1000;
              onVideoRequestUpdated(videoRequest);
            },
            onStopCallback: () {},
            onAnimationCallback: (shift) {
              timeShift = shift;
              videoRequest.startTimestamp = calculateSelectedTime(context).millisecondsSinceEpoch ~/ 1000;
              onVideoRequestUpdated(videoRequest);
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
                  currentMode = PickerModes.location;
                  onVideoRequestUpdated(videoRequest);
                }
              ),
              IconButton(
                icon: Icon(Icons.date_range, size: 30,),
                color: currentMode == PickerModes.period? Colors.yellow : Colors.white,
                highlightColor: Colors.white,
                iconSize: 50,
                onPressed: () {
                  currentMode = PickerModes.period;
                  onVideoRequestUpdated(videoRequest);
                },
              ),
            ],
          ) 
        ),
        Positioned(
            top: 40,
            left: 10,
            height: 50,
            width: 100,
            child: TextButton(
              child: Text('Cancel', textAlign: TextAlign.left, style: TextStyle(color: Colors.white, fontSize: 20),),
              onPressed: () {
                print('pressed cancel, calling callback ${onVideoRequestCancel}');
                onVideoRequestCancel();
              }
            ),
        ),
        locationConfirmed && timeConfirmed ? Positioned(
            top: 40,
            right: 10,
            height: 50,
            width: 100,
            child: TextButton(
              child: Text('Submit', textAlign: TextAlign.right, style: TextStyle(color: Colors.white, fontSize: 20),),
              onPressed: () async {
                print('Submitting');
                bool sent = await login!.sendTxViaMetamask(videoRequest);
                print('Submitted: $sent');
                onVideoRequestSent(videoRequest);
              }
            ),
        ) : (
          !locationConfirmed ? Positioned(
            top: 40,
            right: 10,
            height: 50,
            width: 200,
            child: TextButton(
              child: Text('Confirm Location', textAlign: TextAlign.right, style: TextStyle(color: Colors.white, fontSize: 20),),
              onPressed: () {
                print('pressed Confirm why>>');
                locationConfirmed = true;
                currentMode = PickerModes.period;
                onVideoRequestUpdated(videoRequest);
              }
            ),
          ) : Positioned(
            top: 40,
            right: 10,
            height: 50,
            width: 220,
            child: TextButton(
              child: Text('Confirm Time: ${DateFormat('HH:mm').format(calculateSelectedTime(context))}', textAlign: TextAlign.right, style: TextStyle(color: Colors.white, fontSize: 20),),
              onPressed: () {
                print('pressed Confirm');
                timeConfirmed = true;
                currentMode = PickerModes.period;
                onVideoRequestUpdated(videoRequest);
              }
            ),
          )
        ),
      ];
    }

  // Future<void> _goToTheMarker() async {
  //   // move to parent
  //   if(_markers.length > 0){
  //     final GoogleMapController controller = await _controller.future;
  //     double currentZoom = await controller.getZoomLevel();
  //     controller.animateCamera(CameraUpdate.newCameraPosition(CameraPosition(
  //       target: _marker.position,
  //       zoom: currentZoom,
  //       bearing: _mapAngle,),
  //     ));
  //   }
  // }

  void refreshCameraMarker(BuildContext context) {
    // call callback
    videoRequest.latitude = markerPostion.latitude;
    videoRequest.longitude = markerPostion.longitude;
    videoRequest.direction = -(directionShift / MediaQuery.of(context).size.width) * 360;

    _marker = _marker.copyWith(
      rotationParam: -(directionShift / MediaQuery.of(context).size.width) * 360,
      positionParam: markerPostion,
      iconParam: cameraIconSelected,
    );

    onCameraMarkerUpdated(_marker);
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

  Future<Marker> buildMarker(BuildContext context, double latitude, double longitude) async {
    videoRequest = VideoRequestData(
      direction: 0.0, //
      latitude: latitude,
      longitude: longitude,
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

    markerPostion = LatLng(latitude, longitude);
    var angle = -(directionShift / MediaQuery.of(context).size.width) * 360;

    _marker = Marker(
      // This marker id can be anything that uniquely identifies each marker.
      markerId: MarkerId('camera_marker'),
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

    return _marker;
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

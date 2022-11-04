import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:ui';
import 'package:map_location_picker/map_location_picker.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:objective_app2/utils/data.dart';


class LocationPickerPage extends StatefulWidget {
  const LocationPickerPage({Key? key}) : super(key: key);

  @override
  State<LocationPickerPage> createState() => _LocationPickerPageState();
}

enum PickerModes{
  location, period
}

class _LocationPickerPageState extends State<LocationPickerPage> {
    Completer<GoogleMapController> _controller = Completer();
    late BitmapDescriptor cameraIcon;
    late BitmapDescriptor cameraIconPressed;
    late BitmapDescriptor cameraIconSelected;

    Set<Marker> _markers = {};
    late Marker _marker;
    double _mapAngle = 0;
    bool scrolling = false;

    double directionShift = 0;
    double timeShift = 0;

    PickerModes currentMode = PickerModes.location;

    var currentLocation, markerPostion;

    @override
    Widget build(BuildContext context) {
      Data videoData = ModalRoute.of(context)!.settings.arguments as Data;

      currentLocation = LatLng(
        videoData.currentPosition!.latitude,
        videoData.currentPosition!.longitude
      );

      final CameraPosition _kGooglePlex = CameraPosition(
        target: currentLocation,
        zoom: 14.4746, 
      );

      addMarker();

      return buildMainWidget(_kGooglePlex, context);
    }

    void calculateRoundedMarkerAngle(BuildContext context) {
      var barSpace = Scale.spaceBetween + Scale.barWidth;
      var delta = directionShift % (barSpace);

      var roundedShift = directionShift - delta;
      if(delta > barSpace / 2) {
        roundedShift = directionShift + (barSpace - delta);
      }

      animateShift(roundedShift, 0);
    }

    void animateShift(double toShift, int stepsDone) async {
      var stepsOkToDo = 10;

      if(scrolling) {
        return;
      }

      if(stepsDone >= stepsOkToDo) {
        directionShift = toShift;
        return;
      }

      setState(() {
        directionShift += (toShift - directionShift) / (stepsOkToDo - stepsDone);
      });

      await Future.delayed(const Duration(milliseconds: 20));
      animateShift(toShift, stepsDone + 1);
    }

    Scaffold buildMainWidget(CameraPosition _kGooglePlex, BuildContext context) {
      return Scaffold(
        body: Stack(
          children: [
            Positioned(
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
              bottom: 80,
              left: 0,
              width: MediaQuery.of(context).size.width,
              child: Container(
                child: CompassLettersCarousel(shift: directionShift, context: context),
                width: MediaQuery.of(context).size.width,
                height: 30,
              )
            ),
            Positioned(
              height: 10,
              bottom: 70,
              left: 0,
              width: MediaQuery.of(context).size.width,
              child: Scale(shift: directionShift, context: context),
            ),
            Positioned(
              bottom: 60,
              left: MediaQuery.of(context).size.width / 2 - 1,
              width: 2,
              height: 20,
              child: Container(
                width: 2,
                color: Colors.yellow,
              )
            ),
            const ScrollPickerShadow(),
            Positioned(
              bottom: 50,
              left: 0,
              width: MediaQuery.of(context).size.width,
              height: 70,
              child: GestureDetector(
                onHorizontalDragStart: (details) {
                  scrolling = true;
                  cameraIconSelected = cameraIconPressed;
                  refreshCameraMarker(context);
                  _goToTheMarker();
                },
                onHorizontalDragUpdate: (details) {
                  var angleDx = (details.delta.dx / MediaQuery.of(context).size.width) * 360;
                  directionShift += details.delta.dx;
                  cameraIconSelected = cameraIconPressed;
                  refreshCameraMarker(context);
                },
                onHorizontalDragEnd: (details) {
                  scrolling = false;
                  cameraIconSelected = cameraIcon;
                  refreshCameraMarker(context);
                  calculateRoundedMarkerAngle(context);
                },
              ),
            ),
            Positioned(
              bottom: 30,
              left: 0,
              height: 20,
              width: MediaQuery.of(context).size.width,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: Icon(Icons.compass_calibration_rounded),
                    color: Colors.yellow,
                    highlightColor: Colors.yellow,
                    onPressed: () {
                      print('pressed');
                    },
                  ),
                  IconButton(
                    icon: Icon(Icons.date_range),
                    color: Colors.white,
                    highlightColor: Colors.white,
                    onPressed: () {
                      print('pressed');
                    },
                  ),
                ],
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
        _marker = _marker.copyWith(
          rotationParam: -(directionShift / MediaQuery.of(context).size.width) * 360,
          positionParam: markerPostion,
          iconParam: cameraIconSelected,
        );
        _markers = {_marker};
      });
    }
  }

  Future<void> addMarker() async {
    if(_markers.isEmpty) {
        cameraIcon = await BitmapDescriptor.fromAssetImage(
          const ImageConfiguration(size: Size(48, 48)),
          'assets/images/camera.png'
        );
        cameraIconPressed = await BitmapDescriptor.fromAssetImage(
          const ImageConfiguration(size: Size(48, 48)),
          'assets/images/camera-pressed.png'
        );
        cameraIconSelected = cameraIcon;

        markerPostion = currentLocation;
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
          rotation: -(directionShift / MediaQuery.of(context).size.width) * 360,
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
    }
  }
}

class ScrollPickerShadow extends StatelessWidget {
  const ScrollPickerShadow({
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 60,
      width: MediaQuery.of(context).size.width,
      height: 60,
      child: Container(
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
            fontSize: 20,
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
    required this.context,
  }) : _shift = shift, super(key: key);

  final double _shift;
  final BuildContext context;

  static const double spaceBetween = 15.0;
  static const double barWidth = 1.0;
  static const double barHeight = 10.0;

  @override
  Widget build(BuildContext context) {
      var containerWidth = MediaQuery.of(context).size.width;
      var effectiveShift = _shift % containerWidth;
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

      return Stack(children: children);
    }
}

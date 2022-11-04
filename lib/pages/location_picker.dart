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
    double _currentMarkerAngle = 0;
    double _roundedMarkerAngle = 0;
    double _snapshotMarkerAngle = 0;
    double _mapAngle = 0;
    bool scrolling = false;

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
      var widthOfBarSpace = 16;
      var numberOfBars = (MediaQuery.of(context).size.width / widthOfBarSpace);
      var discretization = 360 / numberOfBars;
      var delta = _currentMarkerAngle % discretization;

      _roundedMarkerAngle = _currentMarkerAngle - delta;
      if(delta > discretization / 2) {
        _roundedMarkerAngle = _currentMarkerAngle + (discretization - delta);
      }
      _snapshotMarkerAngle = _currentMarkerAngle;

      animateAngle(_snapshotMarkerAngle, _roundedMarkerAngle, 0);
    }

    void animateAngle(double fromAngle, double toAngle, int stepsDone) async {
      var stepsOkToDo = 10;
      if(_currentMarkerAngle == toAngle) {
        return;
      }

      if(_snapshotMarkerAngle != fromAngle) {
        return;
      }

      if(scrolling) {
        return;
      }

      if(stepsDone >= stepsOkToDo) {
        _currentMarkerAngle = toAngle;
        return;
      }

      setState(() {
        if(_currentMarkerAngle < toAngle) {
          _currentMarkerAngle += (toAngle - _currentMarkerAngle) / (stepsOkToDo - stepsDone);
        } else {
          _currentMarkerAngle += (toAngle - _currentMarkerAngle) / (stepsOkToDo - stepsDone);
        }
      });
      await Future.delayed(Duration(milliseconds: 20));
      animateAngle(fromAngle, toAngle, stepsDone + 1);
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
                    print(position.bearing);
                    _mapAngle = position.bearing;
                    refreshCameraMarker();
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
                child: buildDirectionLetters(context),
                width: MediaQuery.of(context).size.width,
                height: 30,
              )
            ),
            Positioned(
              height: 10,
              bottom: 70,
              left: 0,
              width: MediaQuery.of(context).size.width,
              child: buildScale(context),
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
            Positioned(
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
            ),
            Positioned(
              bottom: 50,
              left: 0,
              width: MediaQuery.of(context).size.width,
              height: 70,
              child: GestureDetector(
                onHorizontalDragStart: (details) {
                  scrolling = true;
                  cameraIconSelected = cameraIconPressed;
                  refreshCameraMarker();
                  _goToTheMarker();
                },
                onHorizontalDragUpdate: (details) {
                  var angleDx = (details.delta.dx / MediaQuery.of(context).size.width) * 360;
                  _currentMarkerAngle = (_currentMarkerAngle + angleDx) % 360;
                  cameraIconSelected = cameraIconPressed;
                  refreshCameraMarker();
                },
                onHorizontalDragEnd: (details) {
                  scrolling = false;
                  cameraIconSelected = cameraIcon;
                  refreshCameraMarker();
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

    Widget buildDirectionLetters(BuildContext context) {
      var letterWidth = 30;
      var letters = ['S', 'W', 'N', 'E'];
      var containerWidth = MediaQuery.of(context).size.width;
      var shift = (_currentMarkerAngle / 360.0) * containerWidth;
      List<Widget> children = [];

      for(var i = 0; i < 4; i++) {
          var letter = letters[i];
          // we can do this cause letters are in order
          var defaultPosition = i * containerWidth / 4.0;
          // position of letter after applying shift
          var position = (defaultPosition + shift - letterWidth / 2.0) % containerWidth;
          if(position >= 0 && position <= containerWidth - letterWidth) {
            children.add(
              Positioned(
                left: position,
                top: 0,
                width: 30,
                height: 30,
                child: directionLetter(letter),
              )
            );
          }
      }

      return Stack(children: children);
    }

    Widget buildScale(BuildContext context) {
      var containerWidth = MediaQuery.of(context).size.width;
      var shift = (_currentMarkerAngle / 360.0) * containerWidth;
      List<Widget> children = [];
      var spaceBetween = 15.0;
      var barWidth = 1.0;
      var varHeight = 10.0;
      var maxOffset = containerWidth - barWidth - spaceBetween;

      for(double offset = 0; offset < containerWidth - barWidth; offset += spaceBetween + barWidth) {
        children.add(
          Positioned(
            left: (offset + shift) % containerWidth,
            top: 0,
            width: barWidth,
            height: varHeight,
            child: Container(
              width: barWidth,
              color: Colors.white,
            )
          )
        );
      }

      return Stack(children: children);
    }

    Container directionLetter(String letter) {
      var letterToColor = {
        'S': Colors.white,
        'W': Colors.white,
        'N': Colors.red,
        'E': Colors.white,
      };

      return Container(
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

  void refreshCameraMarker() {
    if(_markers.isNotEmpty) {
      setState(() {
        _marker = _marker.copyWith(
          rotationParam: -_currentMarkerAngle - _mapAngle,
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
          rotation: _currentMarkerAngle,
          onDragStart: (value) {
            markerPostion = value;
            cameraIconSelected = cameraIconPressed;
            refreshCameraMarker();
          },
          onDrag: (value) {
            markerPostion = value;
            cameraIconSelected = cameraIconPressed;
            refreshCameraMarker();
          },
          onDragEnd: ((value) {
            markerPostion = value;
            cameraIconSelected = cameraIcon;
            refreshCameraMarker();
          })
        );
        _markers.add(_marker);
        setState(() {});
    }
  }
}

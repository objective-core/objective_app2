import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'dart:ui';
import 'dart:math';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart';
import 'package:map_location_picker/map_location_picker.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:objective_app2/utils/data.dart';
import 'package:web3dart/web3dart.dart';
import 'dart:io' show Platform;


import 'package:walletconnect_dart/walletconnect_dart.dart';
import 'package:web3dart/web3dart.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:dio/dio.dart';
import 'package:label_marker/label_marker.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:objective_app2/utils/routes.dart';
import 'package:objective_app2/models/permissions.dart';
import 'package:objective_app2/models/location.dart';
import 'package:objective_app2/models/login.dart';
import 'package:objective_app2/models/requests.dart';
import 'package:objective_app2/pages/player_page.dart';
import 'package:objective_app2/pages/location_picker_builder.dart';

class RequestPickerPage extends StatefulWidget {
  const RequestPickerPage({Key? key}) : super(key: key);

  @override
  State<RequestPickerPage> createState() => _RequestPickerPageState();
}


class _RequestPickerPageState extends State<RequestPickerPage> {
  // do we need it? should be models
  // models 
  late LocationModel location;
  late LoginModel login;
  late VideoRequestsManager videoRequestsManager;
  late LocationPickerBuilder locationPickerBuilder;

  String? selectedRequestId;
  bool pickingLocation = false;

  BitmapDescriptor? cameraIcon;

  // Map related
  Completer<GoogleMapController> _controller = Completer();
  CameraPosition? lastMapPosition;
  var _mapAngle = 0.0;

  Set<Marker> _requestMarkers = {};

  @override
  void initState() {
    // init models
    videoRequestsManager = VideoRequestsManager(
      onNearbyRequestsUpdate: ((_) async {
        await rebuildRequestsMarkers();
        setState(() {});
      })
    );

    location = LocationModel(
      onLocationUpdated: (position) async {
        await videoRequestsManager.startRefreshLoop(
          position.latitude,
          position.longitude,
          lastMapPosition != null ? videoRequestsManager.radius(lastMapPosition!.zoom) : 5000,
        );
        setState(() {});
      },
      onLocationDenied: () => setState(() {}),
    );
    location.updateLocation();

    login = LoginModel(
      supportedNetworks: [5],
      onLogin: ((account) => setState(() {})),
      onLogout: (() => setState(() {})),
      onUpdate: ((account) => setState(() {})),
    );
    login.initConnector();

    locationPickerBuilder = LocationPickerBuilder(
      location: location,
      login: login,
      onCameraMarkerUpdated: ((marker) {
        setState(() {
          _requestMarkers = {marker};
        });
      }),
      onVideoRequestUpdated: ((data) => setState(() {})),
      onCameraMarkerOnStartUpdate: ((marker) {
      }),
      onCameraMarkerOnStopUpdate: ((marker) {
      }),
      onVideoRequestSent: ((data) async {
        pickingLocation = false;
        await rebuildRequestsMarkers();
        setState(() {});
      }),
      onVideoRequestCancel: () async {
        pickingLocation = false;
        await rebuildRequestsMarkers();
        setState(() {});
      },
    );

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children:
          buildCommonBackground(context) +
          buildMap(context) +
          buildMainPageWidgets(context),
      ),
    );
  }

  List<Positioned> buildCommonBackground(BuildContext context) {
    return [Positioned( // common background
      height: MediaQuery.of(context).size.height,
      width: MediaQuery.of(context).size.width,
      child: Column(
        children: [
          SizedBox(height: 100, child: Container(color: Colors.black)),
          SizedBox(height: MediaQuery.of(context).size.height - 220, child: Container(color: const Color.fromARGB(255, 128, 128, 128))),
          SizedBox(height: 120, child: Container(color: Colors.black)),
        ],
      ),
    )];
  }

  List<Positioned> buildMap(BuildContext context) {
    if(location.locationAvailable || location.unableToLocate) {
      return [Positioned(
        top: 100,
        left: 0,
        height: MediaQuery.of(context).size.height - 219,
        width: MediaQuery.of(context).size.width,
        child: GoogleMap(
          initialCameraPosition: CameraPosition(
            target: initialCameraLocation,
            zoom: 14.4746, 
          ),
          mapType: MapType.hybrid,
          markers: buildMarkers(),
          zoomControlsEnabled: false,
          myLocationButtonEnabled: true,
          myLocationEnabled: true,
          onMapCreated: (GoogleMapController controller) {
            _controller.complete(controller);
          },
          onCameraMove: (position) {
            _mapAngle = position.bearing;

            var prevMapPosition = lastMapPosition;
            lastMapPosition = position;

            if(prevMapPosition != null && (prevMapPosition.zoom > 4 && position.zoom <= 4)) {
              rebuildRequestsMarkers();
            }

            videoRequestsManager.updateTargetLocation(
              position.target.latitude,
              position.target.longitude,
              videoRequestsManager.radius(position.zoom),
            );
          },
        )
      )];
    }

    return [];
  }

  List<Positioned> buildMainPageWidgets(BuildContext context) {
    return buildPermissionButtons(context) +
      buildLoginSection(context) +
      buildToCameraDialog(context) +
      buildToLocationPickerButtons(context) +
      buildLocationPicker(context);
  }

  List<Positioned> buildLoginSection(BuildContext context) {
    if(!login.loggedIn) {
      return [
        Positioned(
          top: 40,
          right: 10,
          height: 50,
          // width: 100,
          child: TextButton(
            child: Text('Login', textAlign: TextAlign.right, style: TextStyle(color: Colors.white, fontSize: 20),),
            onPressed: () async {
              await login.login();
            }
          ),
        ),
      ];
    }

    String title = '${login.account.networkName} ${login.account.address.substring(0, 4)}...${login.account.address.substring(login.account.address.length - 4)}';
    if(!login.networkSupported) {
      title = 'Choose Goerli network in wallet';
    }

    return [
      Positioned(
        top: 10,
        left: 0,
        width: MediaQuery.of(context).size.width,
        height: 110,
        child: Center(
          widthFactor: 0.5,
          child: Text(
            title,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right, style: TextStyle(color: Colors.white, fontSize: 20),
          ),
        ),
      )
    ];
  }
  
  List<Positioned> buildPermissionButtons(BuildContext context) {
    if(!PermissionsModel.needToRequestPermissions && !PermissionsModel.needToOpenSettings) {
      return [];
    }

    IconButton effectiveButton;
    if (PermissionsModel.needToRequestPermissions) {
      effectiveButton = IconButton(
        color: Colors.white,
        iconSize: 30,
        icon: const Icon(Icons.admin_panel_settings_outlined),
        onPressed: () async {
          await location.updateLocation();
          setState(() {});
        },
      );
    } else {
      effectiveButton = IconButton(
        color: Colors.white,
        iconSize: 30,
        icon: const Icon(Icons.app_settings_alt),
        onPressed: () => openAppSettings()
      );
    }

    return [
      Positioned(
        bottom: 35,
        left: 20,
        height: 50,
        child: effectiveButton,
      ),
    ];
  }

  List<Positioned> buildToCameraDialog(BuildContext context) {
    bool active = PermissionsModel.allGranted && login.loggedIn && login.networkSupported;
    if(selectedRequestId == null || !PermissionsModel.allGranted) {
      return [];
    }

    RequestFromServer request = videoRequestsManager.requestById[selectedRequestId]!;
    if(!request.captured && (!request.active || request.distance(location.currentLocation.latitude, location.currentLocation.longitude) > (kReleaseMode ? 20 : 500))) {
      String message = 'You are too far, please come closer.';
      if(request.timeWindowPassed) {
        message = 'Too late ¯\\_(ツ)_/¯. Try another one.'; 
      } else if(!request.started) {
        message = 'Come in ${request.timeLeftString}';
      }
      return [Positioned(
          bottom: 0,
          left: MediaQuery.of(context).size.width / 2 - 100,
          height: 120,
          width: 200,
          child: Container(
            color: Colors.black,
            height: 120,
            width: 200,
            alignment: Alignment.center,
            child: Center(
              child: Text(
                message,
                softWrap: true,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 20),
              )
            ),
          ),
        ),
      ];
    }

    if(request.captured) {
      return [Positioned(
          bottom: 0,
          left: 0,
          height: 120,
          width: MediaQuery.of(context).size.width,
          child: Container(
            color: Colors.black.withOpacity(0.5),
            child: Center(
              child: Container(
                child: TextButton(
                  child: Text('Watch', textAlign: TextAlign.right, style: TextStyle(color: Colors.white, fontSize: 20),),
                  onPressed: () async {
                    RequestFromServer request = videoRequestsManager.requestById[selectedRequestId]!;
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (BuildContext context) => PlayerPage(request: request)),
                    );
                  }
                )
              ),
            ),
          ),
        ),
      ];
    }

    if(!active) return [];

    if(!login.loggedIn) {
      return [
        Positioned(
          bottom: 0,
          left: 0,
          height: 120,
          width: MediaQuery.of(context).size.width,
          child: Container(
            color: Colors.black.withOpacity(0.5),
            child: Center(
              child: Container(
                child: TextButton(
                  child: Text('Login', textAlign: TextAlign.right, style: TextStyle(color: Colors.white, fontSize: 20),),
                  onPressed: () async {
                    await login.login();
                  }
                )
              ),
            ),
          ),
        ),
      ];
    }

    return [
      Positioned(
        bottom: 0,
        left: 0,
        height: 120,
        width: MediaQuery.of(context).size.width,
        child: Container(
          color: Colors.black.withOpacity(0.5),
          child: Center(
            child: Container(
              child: TextButton(
                child: Text('Start Recording', textAlign: TextAlign.right, style: TextStyle(color: Colors.white, fontSize: 20),),
                onPressed: () async {
                  var video = await Navigator.pushNamed(
                    context, AppRoutes.recorderRoute,
                    arguments: [location, login, videoRequestsManager.requestById[selectedRequestId]],
                  );
                }
              )
            ),
          ),
        ),
      ),
    ];
  }

  LatLng get initialCameraLocation {
    if(location.locationAvailable) {
      return LatLng(location.currentLocation.latitude, location.currentLocation.longitude);
    } else {
      LatLng defaultMapPosition = const LatLng(41.70, 44.76);
      return defaultMapPosition;
    }
  }

  buildMarkers() {
    return _requestMarkers;
  }

  rebuildRequestsMarkers() async {
    if(pickingLocation) {
      return;
    }

    bool needToConsolidate = false;
    if(lastMapPosition != null && lastMapPosition!.zoom <= 4) {
      needToConsolidate = true;
    }

    Set<Marker> newRequestMarkers = {};

    Set<String> locations = {};

    for(var i = 0; i < videoRequestsManager.nearbyRequests.length; i++) {
      RequestFromServer request = videoRequestsManager.nearbyRequests[i];

      // show only limited number of requests per location
      if(needToConsolidate) {
        var location = '${request.latitude.truncate()} ${request.longitude.truncate()}';
        if(locations.contains(location)) {
          continue;
        }
        locations.add(location);
      }

      String price = 'Ξ${request.reward.toDouble() / 1000000000000000000.toDouble()}';

      Duration timeToStart = request.timeToStart;
      Duration timeLeft = request.timeLeft;
      bool timeWindowPassed = request.timeWindowPassed;
      bool started = request.started;
      bool captured = request.thumbnail != '';

      var color = Colors.blue;
      var textColor = Colors.white;
      var message = '$price in ${request.timeLeftString}';

      if(captured) {
        message = '$price (captured)';
        color = Colors.yellow;
        textColor = Colors.black;
      } else if(timeWindowPassed) {
        message = '$price (expired)';
        color = Colors.grey;
      } else if(started) {
        if(started) {
          message = '$price ${timeLeft.inMinutes} mins left';
          color = timeLeft.inMinutes > 10 ? Colors.green : Colors.red;
        }
      }

      if(captured) {
        BitmapDescriptor? thumbnail = (selectedRequestId == request.requestId)
          ? videoRequestsManager.activeThumbnailById[request.requestId]
          : videoRequestsManager.thumbnailById[request.requestId];

        if(thumbnail != null) {
          var marker = Marker(
            markerId: MarkerId('video_icon_${request.requestId}'),
            position: LatLng(request.latitude, request.longitude),
            icon: thumbnail,
            onTap: () async {
              zoomToCoordinates(LatLng(request.latitude, request.longitude));
              setState(() {
                selectedRequestId = request.requestId;
              });
              await location.updateLocation();
            },
          );
          newRequestMarkers.add(marker);
          continue;
        }
      }

      var marker = LabelMarker(
        label: message,
        markerId: MarkerId('video_label_${request.requestId}'),
        position: LatLng(request.latitude, request.longitude),
        backgroundColor: color,
        textStyle: TextStyle(color: textColor, fontSize: request.requestId == selectedRequestId ? 35 : 30),
        anchor: const Offset(0.5, 1.4),
        onTap: () async {
          zoomToCoordinates(LatLng(request.latitude, request.longitude));
          setState(() {
            selectedRequestId = request.requestId;
          });
          await location.updateLocation();
          setState(() {
            selectedRequestId = request.requestId;
          });
        },
      );

      await newRequestMarkers.addLabelMarker(marker);

      if(!captured) {
        cameraIcon ??= await BitmapDescriptor.fromAssetImage(
          const ImageConfiguration(size: Size(24, 24)),
          'assets/images/camera-small@2x.png'
        );

        var cameraMarker = Marker(
          // This marker id can be anything that uniquely identifies each marker.
          markerId: MarkerId('camera_marker_${request.requestId}'),
          position: LatLng(request.latitude, request.longitude),
          icon: cameraIcon!,
          draggable: false,
          anchor: const Offset(0.5, 0.5),
          rotation: request.direction,
          onTap: () async {
            zoomToCoordinates(LatLng(request.latitude, request.longitude));
            setState(() {
              selectedRequestId = request.requestId;
            });
            await location.updateLocation();
            setState(() {
              selectedRequestId = request.requestId;
            });
          }
        );

        newRequestMarkers.add(cameraMarker);
      }
    }

    _requestMarkers = newRequestMarkers;
  }

  Future<void> zoomToCoordinates(LatLng target) async {
    final GoogleMapController controller = await _controller.future;
    double currentZoom = await controller.getZoomLevel();
    controller.animateCamera(CameraUpdate.newCameraPosition(CameraPosition(
      target: target,
      zoom: max(14.4746, currentZoom),
      bearing: _mapAngle,),
    ));
  }


  List<Positioned> buildToLocationPickerButtons(BuildContext context) {
    Color color = const Color.fromARGB(255, 80, 80, 80);

    bool active = PermissionsModel.allGranted && login.loggedIn && login.networkSupported;

    if(active) {
      color = Colors.white;
    }

    return [
      Positioned(
        bottom: 35,
        right: 20,
        height: 50,
        child: IconButton(
          color: color,
          iconSize: 30,
          icon: const Icon(Icons.add_shopping_cart),
          onPressed: () async {
            if(active)  {
              pickingLocation = true;
              selectedRequestId = null;
              double lat = location.currentLocation.latitude;
              double long = location.currentLocation.longitude;
              if(lastMapPosition != null) {
                lat = lastMapPosition!.target.latitude;
                long = lastMapPosition!.target.longitude;
              }
              locationPickerBuilder.resetTimeShift(context);
              Marker marker = await locationPickerBuilder.buildMarker(
                context,
                lat,
                long,
              );
              setState(() {
                _requestMarkers = {marker};
              });
            } else {
              // TODO: show hint
            }
          }
        ),
      ),
    ];
  }

  List<Positioned> buildLocationPicker(BuildContext context) {
    if(!pickingLocation) {
      return [];
    }

    return locationPickerBuilder.buildLocationPicker(context);
  }
}

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';


class RequestFromServer {
  double latitude;
  double longitude;
  int reward;
  String requestId;
  double direction;
  DateTime startTime;
  DateTime endTime;
  String videoUrl;
  String thumbnail; // if null -> no video

  RequestFromServer({
    required this.latitude,
    required this.longitude,
    required this.reward,
    required this.requestId,
    required this.direction,
    required this.startTime,
    required this.endTime,
    this.videoUrl = '',
    this.thumbnail = '',
  });

  Duration get timeToStart => Duration(milliseconds: startTime.millisecondsSinceEpoch - DateTime.now().millisecondsSinceEpoch);
  Duration get timeLeft => Duration(milliseconds: endTime.millisecondsSinceEpoch - DateTime.now().millisecondsSinceEpoch);
  bool get timeWindowPassed => timeLeft.isNegative;
  bool get started => timeToStart.isNegative;
  bool get active => !timeWindowPassed && started;
  bool get captured => videoUrl != '';

  String get timeLeftString {
    var result = '${timeToStart.inMinutes} ${timeToStart.inMinutes == 1 ? 'min' : 'mins'}';

    if(timeToStart.inMinutes > 60) {
      result = '${timeToStart.inHours} ${timeToStart.inHours == 1 ? 'hour' : 'hours'}';
    }

    if(timeToStart.inHours > 24) {
      result = '${timeToStart.inDays} ${timeToStart.inDays == 1 ? 'day' : 'days'}';
    }

    return result;
  }

  double distance(double lat, double long) {
    var result = Geolocator.distanceBetween(latitude, longitude, lat, long);
    return result;
  }
}

typedef OnNearbyRequestsUpdate = void Function(List<RequestFromServer>);



class VideoRequestsManager {
  Dio dio = Dio(
    BaseOptions(connectTimeout: 5000, receiveTimeout: 5000),
  );

  List<RequestFromServer> nearbyRequests = [];
  Map<String, RequestFromServer> requestById = {};

  final OnNearbyRequestsUpdate onNearbyRequestsUpdate;

  double _lastLat = -1;
  double _lastLong = -1;

  bool _loopStarted = false;

  VideoRequestsManager({required this.onNearbyRequestsUpdate});

  Future<List<RequestFromServer>> refreshRequestsNearby(double lat, double long) async {
    nearbyRequests = await getRequests(lat: lat, long: long);
    onNearbyRequestsUpdate(nearbyRequests);
    return nearbyRequests;
  }

  Future<List<RequestFromServer>> startRefreshLoop(double lat, double long) async {
    nearbyRequests = await refreshRequestsNearby(lat, long);

    _lastLat = lat;
    _lastLong = long;
    if(!_loopStarted) {
      _loopStarted = true;
      loopRefreshNearby();
    }

    return nearbyRequests;
  }

  Future<void> loopRefreshNearby() async {
    while(true) {
      await Future.delayed(const Duration(seconds: 5));
      await refreshRequestsNearby(_lastLat, _lastLong);
    }
  }

  Future<List<RequestFromServer>> getRequests({double lat=-1, double long=-1, int radius=1000}) async {
    Map<String, String> parameters = {};

    if(lat != -1 && long != -1) {
      parameters['lat'] = lat.toString();
      parameters['long'] = long.toString();
      parameters['radius'] = radius.toString();
      parameters['hide_expired'] = 'true';
    }

    Response dioResponse;
    // TODO: handle errors
    try {
      dioResponse = await dio.get(
        'https://api.objective.camera/requests_by_location',
        queryParameters: parameters,
      );
    } catch(e) {
      print(e);
      return [];
    } 

    print(dioResponse.requestOptions.uri);

    var requests = dioResponse.data['requests'];
    List<RequestFromServer> result = [];

    for(var i = 0; i < requests.length; i++) {
      var request = requests[i];
      var requestFromServer =RequestFromServer(
        direction: (request['location']['direction']).toDouble(),
        latitude: request['location']['lat'],
        longitude: request['location']['long'],
        startTime: DateTime.parse(request['start_time'] + 'Z'),
        endTime: DateTime.parse(request['end_time'] + 'Z'),
        requestId: request['id'],
        reward: request['reward'],
        videoUrl: request['video'] == null ? '' : 'https://ipfs.objective.camera/${request['video']['file_hash']}',
        thumbnail: request['video'] == null ? '' : 'https://i.picsum.photos/id/182/200/100.jpg?hmac=nuni_xT1TfXyyqbAcn1bG1oAXfba-QH6lW1zNDDgKDs',
      );
      requestById[requestFromServer.requestId] = requestFromServer;
      result.add(requestFromServer);
    }
    return result;
  }
}

import 'package:geolocator/geolocator.dart';
import 'package:map_location_picker/map_location_picker.dart';
import 'package:walletconnect_dart/walletconnect_dart.dart';


class VideoRequestFromServer {
  double latitude;
  double longitude;
  int reward;
  String requestId;
  double direction;
  DateTime startTime;
  DateTime endTime;
  String thumbnail; // if null -> no video

  VideoRequestFromServer({
    required this.latitude,
    required this.longitude,
    required this.reward,
    required this.requestId,
    required this.direction,
    required this.startTime,
    required this.endTime,
    this.thumbnail = '',
  });
}


class VideoRequestData {
  double latitude;
  double longitude;
  int startTimestamp;
  int secondsDuration;
  double direction;
  String txHash;

  VideoRequestData(
    {
      this.latitude=0.0,
      this.longitude=0.0,
      this.startTimestamp=0,
      this.secondsDuration=3600 * 2,
      this.direction=0.0,
      this.txHash='',
    }
  );

  int getIntegerLatitude() {
    return ((latitude + 180) * 10000000).toInt();
  }

  int getIntegerLongitude() {
    return ((longitude + 180) * 10000000).toInt();
  }

  int getIntegerDirection() {
    return (direction.truncate() + 360) % 360;
  }

  int getIntegerEndTimestamp() {
    return startTimestamp + secondsDuration;
  }
}

class Video {
  String? path;
  String? hash; // IPFS hash (CID)
  Position position;
  String? signature;
  DateTime startTime;
  DateTime? endTime;
  double heading = 0.0;

  Video({
    required this.startTime,
    required this.position,
  });
}


class Data {
  Position? currentPosition;
  Video? video;
  WalletConnect? connector;
  String? connectionUri;
  VideoRequestData? request;

  Data({
    this.currentPosition,
    this.video,
    this.connector,
  });

  set setCurrentPosition(Position position) {
    currentPosition = position;
  }
}

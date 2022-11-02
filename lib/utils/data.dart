import 'package:geolocator/geolocator.dart';


class Data {
  // recorded video data
  String videoPath;
  String videoHash;
  String metamaskHash;
  Position? currentPosition;

  Data({required this.videoPath, required this.videoHash, required this.metamaskHash});

  set setCurrentPosition(Position position) {
    currentPosition = position;
  }
}


class VideoRequestData {
  late Position position;
  late int secondsDuration;
  late int startTimestamp;
}

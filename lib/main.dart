import 'package:flutter/material.dart';

import 'package:objective_app2/utils/routes.dart';
import 'package:objective_app2/pages/login_page.dart';
import 'package:objective_app2/pages/recorder_page.dart';
import 'package:objective_app2/pages/location_picker.dart';
import 'package:objective_app2/pages/request_picker.dart';

void main(List<String> args) async {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      initialRoute: AppRoutes.requestPickerRoute,
      routes: {
        AppRoutes.loginRoute: (context) => const LoginPage(),
        AppRoutes.recorderRoute: (context) => const RecorderPage(),
        AppRoutes.locationPickerRoute: (context) => const LocationPickerPage(),
        AppRoutes.requestPickerRoute: (context) => const RequestPickerPage(),
      },
    );
  }
}

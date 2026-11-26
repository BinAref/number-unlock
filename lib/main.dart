import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'services/app_services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(statusBarColor: Color(0x00000000)));
  final dispatcher = WidgetsBinding.instance.platformDispatcher;
  final services = await AppServices.bootstrap(deviceLocale: dispatcher.locale, platform: dispatcher.platformBrightness);
  runApp(UnlockNumbersApp(services: services));
}

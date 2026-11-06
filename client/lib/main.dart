import 'package:flutter/material.dart';
import 'package:sing_box/sing_box.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SingBox.instance.initialize(
    const SingBoxOptions(
      android: SingBoxAndroidOptions(
        notificationTitle: 'VPN13',
        showTrafficInNotification: true,
      ),
    ),
  );
  runApp(const Vpn13ClientApp());
}

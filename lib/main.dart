import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();

  try {
    await Firebase.initializeApp();
  } catch (_) {
    // Firebase may be configured later; app still runs with local seed data.
  }

  runApp(const ArchitectulaApp());
}

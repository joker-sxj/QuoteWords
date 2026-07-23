import 'package:flutter/material.dart';

import 'core/ble/quote_ble_client.dart';
import 'core/devices/paired_device_store.dart';
import 'features/editor/editor_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const QuoteImageApp());
}

class QuoteImageApp extends StatelessWidget {
  const QuoteImageApp({super.key, this.bleClient, this.deviceStore});

  final QuoteBleClient? bleClient;
  final DeviceStore? deviceStore;

  @override
  Widget build(BuildContext context) {
    const colors = ColorScheme.light(
      primary: Color(0xff176b4d),
      onPrimary: Colors.white,
      secondary: Color(0xffb7791f),
      onSecondary: Colors.white,
      surface: Color(0xfffbfcfa),
      onSurface: Color(0xff20231f),
      error: Color(0xffa33428),
      onError: Colors.white,
      outline: Color(0xff747b73),
    );
    return MaterialApp(
      title: 'QuoteImage',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: colors,
        scaffoldBackgroundColor: colors.surface,
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xfffbfcfa),
          foregroundColor: Color(0xff20231f),
          elevation: 0,
          scrolledUnderElevation: 1,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: Color(0xff20231f),
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
        cardTheme: const CardThemeData(
          margin: EdgeInsets.zero,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(6)),
            side: BorderSide(color: Color(0xffcbd0c9)),
          ),
        ),
        segmentedButtonTheme: SegmentedButtonThemeData(
          style: ButtonStyle(
            textStyle: WidgetStateProperty.all(
              const TextStyle(fontSize: 13, letterSpacing: 0),
            ),
            shape: WidgetStateProperty.all(
              const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(4)),
              ),
            ),
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(4)),
          ),
        ),
      ),
      home: EditorScreen(bleClient: bleClient, deviceStore: deviceStore),
    );
  }
}

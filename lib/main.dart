import 'package:aplicaciones_foliares/loguer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'menu_central.dart';
import 'servicios/conexion.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() async {
  await initializeDateFormatting('es', null);
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseService.inicializar();
  if (kIsWeb) {
    databaseFactory = databaseFactoryFfiWeb;
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aplicaciones Foliares',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Roboto',
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          surface: const Color(0xFFF4F5F7),
        ),
        scaffoldBackgroundColor: const Color(0xFFF4F5F7),
        useMaterial3: true,
      ),
      home: const LoguerScreen(),
    );
  }
}
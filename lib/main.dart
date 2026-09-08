import 'dart:io' show Platform;
import 'package:aplicaciones_foliares/loguer.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

import 'menu_central.dart';
import 'servicios/conexion.dart';

void main() async {
  // 1. OBLIGATORIO: Siempre en la primera línea
  WidgetsFlutterBinding.ensureInitialized();

  // 2. OBLIGATORIO: Inicialización multiplataforma de base de datos SQLite
  if (kIsWeb) {
    // Entorno Web / Safari / Chrome PWA
    databaseFactory = databaseFactoryFfiWeb;
  } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    // Entorno PC / Desktop
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // 3. Inicializar localización de fechas en español
  try {
    await initializeDateFormatting('es', null);
  } catch (e) {
    debugPrint("Aviso al inicializar formato de fechas: $e");
  }

  // 4. Inicializar Supabase protegido contra caídas de red
  try {
    await SupabaseService.inicializar();
  } catch (e) {
    debugPrint("Aviso al inicializar Supabase: $e");
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AgroSoft J&L',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Roboto',
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E6B4C),
          surface: const Color(0xFFF4F5F7),
        ),
        scaffoldBackgroundColor: const Color(0xFFF4F5F7),
        useMaterial3: true,
      ),
      home: const LoguerScreen(),
    );
  }
}
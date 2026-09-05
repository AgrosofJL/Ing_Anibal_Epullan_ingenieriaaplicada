import 'dart:io' show Platform;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'base/base.dart';
import 'constantes/tema.dart';
import 'menu_central.dart';
import 'servicios/servicio_auth.dart';
import 'widgets/soft_button.dart';

class LoguerScreen extends StatefulWidget {
  const LoguerScreen({super.key});

  @override
  State<LoguerScreen> createState() => _LoguerScreenState();
}

class _LoguerScreenState extends State<LoguerScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  String _deviceIdentifier = "Obteniendo...";

  @override
  void initState() {
    super.initState();
    _getDeviceIdentifier();
    _checkExistingSession();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _getDeviceIdentifier() async {
    // 💡 Si corre en Safari / Web, se omite la consulta de hardware nativo
    if (kIsWeb) {
      if (!mounted) return;
      setState(() {
        _deviceIdentifier = "Safari PWA / Web Client";
      });
      return;
    }

    final deviceInfo = DeviceInfoPlugin();
    String deviceId = "Unknown Device";

    try {
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        deviceId = androidInfo.id;
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        deviceId = iosInfo.identifierForVendor ?? "Unknown iOS";
      }
    } catch (_) {
      deviceId = "Dispositivo no reconocido";
    }

    if (!mounted) return;
    setState(() {
      _deviceIdentifier = deviceId;
    });
  }

  Future<void> _checkExistingSession() async {
    final prefs = await SharedPreferences.getInstance();
    final bool loggedIn =
        (prefs.getBool('isLoggedIn') ?? false) || (prefs.getBool('isLogged') ?? false);
    final bool licenciaActiva = prefs.getBool('licencia_activa') ?? true;

    if (loggedIn && licenciaActiva && mounted) {
      _navigateToMenu();
    }
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final String inputUser = _emailController.text.trim();
    final String inputPass = _passwordController.text.trim();
    final prefs = await SharedPreferences.getInstance();

    // 1. Verificación de licencia previa
    final bool licenciaActiva = prefs.getBool('licencia_activa') ?? true;
    if (!licenciaActiva) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showError('El sistema se encuentra BLOQUEADO por licencia inactiva.');
      }
      return;
    }

    try {
      final supabase = Supabase.instance.client;

      // 2. Consulta en Supabase por correo o por nombre de operario
      final response = await supabase
          .from('usuarios')
          .select()
          .or('correo.ilike.$inputUser,operario.ilike.$inputUser')
          .eq('pass', inputPass)
          .maybeSingle();

      if (response != null) {
        final String dbDevice = (response['device'] ?? '').toString().trim();
        final String dbEstado = (response['estado'] ?? '').toString().toUpperCase();

        if (dbEstado != 'ACTIVO') {
          if (mounted) setState(() => _isLoading = false);
          _showAdminDialog();
          return;
        }

        // 💡 OMITIR DEVICE SI ESTAMOS EN SAFARI / WEB
        // Solo valida Device ID si NO es Web y el usuario tiene un device fijado en la BD
        if (!kIsWeb && dbDevice.isNotEmpty && dbDevice != _deviceIdentifier) {
          if (mounted) setState(() => _isLoading = false);
          _showAdminDialog();
          return;
        }

        // Respaldo en SQLite local
        final db = await DatabaseHelper.instance.database;
        final Map<String, dynamic> usuarioLocalRow = {
          'id': int.tryParse(response['id'].toString()) ?? 1,
          'correo': response['correo'],
          'operario': response['operario'],
          'device': response['device'],
          'pass': response['pass'],
          'rol': response['rol'],
          'estado': response['estado'],
          'cod_productor': response['cod_productor'] != null
              ? int.tryParse(response['cod_productor'].toString())
              : null,
        };

        await db.insert(
          'usuarios',
          usuarioLocalRow,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        // Guardar estado de sesión en SharedPreferences
        await prefs.setBool('isLoggedIn', true);
        await prefs.setBool('isLogged', true);
        await prefs.setInt('userId', usuarioLocalRow['id'] as int);
        await prefs.setString('userEmail', response['correo'] ?? '');
        await prefs.setString(
            'userName', response['operario'] ?? response['correo'] ?? 'Usuario');
        await prefs.setString(
            'userRole', (response['rol'] ?? 'OPERARIO').toString().toUpperCase());
        await prefs.setInt(
          'userCodProductor',
          response['cod_productor'] != null
              ? int.tryParse(response['cod_productor'].toString()) ?? 0
              : 0,
        );

        if (mounted) {
          _navigateToMenu();
        }
        return;
      } else {
        if (mounted) {
          _showError('Usuario o contraseña incorrectos.');
        }
      }
    } catch (e) {
      debugPrint("Error remoto, probando respaldo offline: $e");

      // 3. Fallback Offline en SQLite si no hay conexión
      try {
        final userLocal = await ServicioAuth.iniciarSesion(
          usuarioOCorreo: inputUser,
          password: inputPass,
        );

        if (userLocal != null) {
          final String localDevice = (userLocal['device'] ?? '').toString().trim();

          // Omitir device también offline si es Web/Safari
          if (!kIsWeb && localDevice.isNotEmpty && localDevice != _deviceIdentifier) {
            if (mounted) setState(() => _isLoading = false);
            _showAdminDialog();
            return;
          }

          await prefs.setBool('isLoggedIn', true);
          if (mounted) {
            _navigateToMenu();
          }
          return;
        } else {
          if (mounted) _showError('Usuario o contraseña incorrectos.');
        }
      } catch (authError) {
        if (mounted) _showError(authError.toString().replaceAll('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showAdminDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AgroTheme.radiusLg)),
          backgroundColor: AgroTheme.colorSurface,
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: AgroTheme.colorDanger.withOpacity(0.1),
                      shape: BoxShape.circle),
                  child: const Icon(Icons.lock_person_outlined,
                      color: AgroTheme.colorDanger, size: 32),
                ),
                const SizedBox(height: 16),
                const Text(
                  "Acceso No Acreditado",
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AgroTheme.colorText),
                ),
                const SizedBox(height: 10),
                const Text(
                  "Tu dispositivo o usuario no se encuentra en estado ACTIVO. Copiá el identificador y envialo al administrador.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13,
                      color: AgroTheme.colorTextSecondary,
                      height: 1.4),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AgroTheme.colorBg,
                    borderRadius: BorderRadius.circular(AgroTheme.radiusMd),
                    border: Border.all(color: AgroTheme.colorBorder),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _deviceIdentifier,
                          style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AgroTheme.colorText),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy,
                            size: 18, color: AgroTheme.colorTextSecondary),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _deviceIdentifier));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Copiado al portapapeles')),
                          );
                        },
                      )
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SoftButton(
                  isSecondary: true,
                  onTap: () => Navigator.pop(context),
                  child: const Center(
                    child: Text("Entendido",
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AgroTheme.colorText)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AgroTheme.colorDanger,
        content: Text(message,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w500)),
      ),
    );
  }

  void _navigateToMenu() {
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => const MenuCentral()));
  }

  String _getFormattedDate() {
    final now = DateTime.now();
    return DateFormat("EEEE dd 'DE' MMMM 'DE' yyyy", 'es')
        .format(now)
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AgroTheme.colorBg,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: 16,
              left: 20,
              child: Row(
                children: const [
                  Icon(Icons.person_outline,
                      size: 18, color: AgroTheme.colorTextSecondary),
                  SizedBox(width: 6),
                  Text('',
                      style: TextStyle(
                          color: AgroTheme.colorTextSecondary, fontSize: 12)),
                ],
              ),
            ),
            Positioned(
              top: 16,
              right: 20,
              child: Text(
                _getFormattedDate(),
                style: const TextStyle(
                    color: AgroTheme.colorText,
                    fontSize: 11,
                    fontWeight: FontWeight.w700),
              ),
            ),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          color: AgroTheme.colorSurface,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: AgroTheme.colorBorder),
                          boxShadow: const [
                            BoxShadow(
                                color: Color(0x08141E18),
                                blurRadius: 20,
                                offset: Offset(0, 8))
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(22),
                          child: Image.asset(
                            'logo/logo.png',
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(Icons.agriculture_rounded,
                                    size: 44, color: AgroTheme.colorAccent),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        "GESTION DE CAMPO",
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AgroTheme.colorText,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const Text(
                        "AgroSoft · Soluciones Integrales",
                        style: TextStyle(
                            fontSize: 13,
                            color: AgroTheme.colorTextSecondary,
                            fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 6),
                      // En web / Safari muestra el modo navegador; en app nativa muestra el Device ID
                      Text(
                        kIsWeb
                            ? "Plataforma: Safari Web / PWA"
                            : "Device ID: $_deviceIdentifier",
                        style: const TextStyle(
                            fontSize: 11, color: AgroTheme.colorTextSecondary),
                      ),
                      const SizedBox(height: 32),
                      Container(
                        padding: const EdgeInsets.all(26),
                        decoration: BoxDecoration(
                          color: AgroTheme.colorSurface,
                          borderRadius:
                              BorderRadius.circular(AgroTheme.radiusLg),
                          border: Border.all(color: AgroTheme.colorBorder),
                          boxShadow: const [
                            BoxShadow(
                                color: Color(0x0A141E18),
                                blurRadius: 30,
                                offset: Offset(0, 10))
                          ],
                        ),
                        child: Column(
                          children: [
                            TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              style: const TextStyle(
                                  color: AgroTheme.colorText, fontSize: 14),
                              decoration: InputDecoration(
                                hintText: "Email u Usuario",
                                hintStyle: const TextStyle(
                                    color: AgroTheme.colorTextSecondary,
                                    fontSize: 14),
                                prefixIcon: const Icon(Icons.mail_outline,
                                    size: 20,
                                    color: AgroTheme.colorTextSecondary),
                                filled: true,
                                fillColor: AgroTheme.colorBg,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(
                                      AgroTheme.radiusMd),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              validator: (val) => val == null || val.trim().isEmpty
                                  ? "Ingresá tu correo u usuario"
                                  : null,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _passwordController,
                              obscureText: true,
                              style: const TextStyle(
                                  color: AgroTheme.colorText, fontSize: 14),
                              decoration: InputDecoration(
                                hintText: "Contraseña",
                                hintStyle: const TextStyle(
                                    color: AgroTheme.colorTextSecondary,
                                    fontSize: 14),
                                prefixIcon: const Icon(Icons.lock_outline,
                                    size: 20,
                                    color: AgroTheme.colorTextSecondary),
                                filled: true,
                                fillColor: AgroTheme.colorBg,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(
                                      AgroTheme.radiusMd),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              validator: (val) => val == null || val.trim().isEmpty
                                  ? "Ingresá tu contraseña"
                                  : null,
                            ),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: SoftButton(
                                onTap: _isLoading ? null : _login,
                                child: Center(
                                  child: _isLoading
                                      ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2.2),
                                        )
                                      : const Text(
                                          "Iniciar Sesión",
                                          style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700),
                                        ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
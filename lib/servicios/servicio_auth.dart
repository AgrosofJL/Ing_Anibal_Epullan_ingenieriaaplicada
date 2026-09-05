import 'package:shared_preferences/shared_preferences.dart';
import '../base/base.dart';

class ServicioAuth {
  static Future<Map<String, dynamic>?> iniciarSesion({
    required String usuarioOCorreo,
    required String password,
  }) async {
    final db = await DatabaseHelper.instance.database;

    final List<Map<String, dynamic>> res = await db.rawQuery('''
      SELECT * FROM usuarios 
      WHERE (LOWER(TRIM(correo)) = LOWER(?) OR LOWER(TRIM(operario)) = LOWER(?))
        AND pass = ?
      LIMIT 1
    ''', [usuarioOCorreo.trim(), usuarioOCorreo.trim(), password.trim()]);

    if (res.isEmpty) {
      return null;
    }

    final user = res.first;
    final String estado = (user['estado'] ?? 'INACTIVO').toString().toUpperCase();

    if (estado != 'ACTIVO') {
      throw Exception('El usuario se encuentra INACTIVO en el sistema.');
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLogged', true);
    await prefs.setInt(
      'userId',
      user['id'] is int ? user['id'] : int.parse(user['id'].toString()),
    );
    await prefs.setString(
      'userName',
      user['operario'] ?? user['correo'] ?? 'Usuario',
    );
    await prefs.setString(
      'userRole',
      (user['rol'] ?? 'OPERARIO').toString().toUpperCase(),
    );
    await prefs.setInt(
      'userCodProductor',
      user['cod_productor'] != null
          ? int.tryParse(user['cod_productor'].toString()) ?? 0
          : 0,
    );

    return user;
  }

  static Future<void> cerrarSesion() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLogged', false);
    await prefs.remove('userId');
    await prefs.remove('userName');
    await prefs.remove('userRole');
    await prefs.remove('userCodProductor');
  }
}
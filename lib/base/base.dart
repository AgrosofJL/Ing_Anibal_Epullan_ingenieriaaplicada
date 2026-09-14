import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  final supabase = Supabase.instance.client;

  // 💡 SQLite nativo para todas las plataformas (gracias a sqflite_common_ffi_web en Web)
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('aplicaciones_foliares.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    String path;
    if (kIsWeb) {
      path = filePath;
    } else {
      final dbPath = await getDatabasesPath();
      path = join(dbPath, filePath);
    }

    return await openDatabase(
      path,
      version: 9,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS _control_sync (
        tabla TEXT PRIMARY KEY,
        ultima_fecha TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS usuarios (
        id INTEGER PRIMARY KEY,
        correo TEXT,
        operario TEXT,
        device TEXT,
        pass TEXT,
        rol TEXT,
        estado TEXT,
        cod_productor INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS rubros_insumos (
        codigo INTEGER,
        cod_rubro INTEGER,
        nombre TEXT,
        macro_rubro TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS parametros_aplic (
        id INTEGER PRIMARY KEY,
        vel_viento TEXT,
        Temperatura TEXT,
        Tamano_gota TEXT,
        Vel_Aplicacion TEXT,
        Caudal_Ha TEXT,
        cod_receta INTEGER,
        cod_orden INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS recetas_aplicaciones (
        cod_receta INTEGER PRIMARY KEY,
        cod_orden INTEGER,
        cod_productor INTEGER,
        productor TEXT,
        orden_aplic INTEGER,
        ref INTEGER,
        fecha TEXT,
        chacra TEXT,
        cuadros TEXT,
        motivo_aplic TEXT,
        momento_aplic TEXT,
        vol_aplic_ha REAL,
        responsable TEXT,
        cod_producto INTEGER,
        producto TEXT,
        dosis_100 REAL,
        dosis_maq REAL,
        tc TEXT,
        ti TEXT,
        habilitado TEXT,
        sincronizado INTEGER DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS config_app_enlaces (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        plataforma TEXT,
        url_instalacion TEXT,
        version TEXT,
        instrucciones TEXT,
        sincronizado INTEGER DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS productores (
        cod_productor INTEGER PRIMARY KEY AUTOINCREMENT,
        productor TEXT,
        cuit TEXT,
        renspa TEXT,
        nro_control INTEGER,
        localidad TEXT,
        estado TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS motivos_aplicaciones (
        cod INTEGER PRIMARY KEY,
        motivo TEXT,
        tipo_aplic TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS inventario_plantacion (
        id INTEGER PRIMARY KEY,
        cod_productor INTEGER,
        productor TEXT,
        chacra TEXT,
        cod_cuadro INTEGER,
        cuadro TEXT,
        cultivo TEXT,
        variedad TEXT,
        ano_plantacion INTEGER,
        ha REAL,
        plantas INTEGER,
        marco_plantacion INTEGER,
        up TEXT,
        dist_arbol REAL,
        dist_fila REAL,
        orientacion TEXT,
        sitema_riego TEXT,
        sistema_def TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS cuadros (
        cod_cuadro INTEGER PRIMARY KEY,
        cod_productor INTEGER,
        productor TEXT,
        chacra TEXT,
        cuadro TEXT,
        sitema_riego TEXT,
        sistema_def TEXT,
        ubicacion TEXT,
        sup REAL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS catalogo_insumos (
        ID_Insumos INTEGER,
        rubro TEXT,
        Descripcion1 TEXT,
        Descripcion2 TEXT,
        T_C INTEGER,
        TRI INTEGER,
        Mostrar INTEGER,
        Numeracion TEXT,
        Concentracion TEXT,
        principio_activo TEXT,
        stock_real INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS aplicaciones_registros (
        registro TEXT PRIMARY KEY,
        cod_receta INTEGER,
        cod_orden INTEGER,
        cod_productor INTEGER,
        productor TEXT,
        orden_aplic INTEGER,
        ref INTEGER,
        fecha TEXT,
        chacra TEXT,
        cuadros TEXT,
        variedad TEXT,
        sup_aplic REAL,
        motivo_aplic TEXT,
        momento_aplic TEXT,
        vol_aplic_ha REAL,
        tractorista TEXT,
        pulverizadora TEXT,
        litros REAL,
        cod_producto INTEGER,
        producto TEXT,
        dosis_100 REAL,
        dosis_maq REAL,
        tc TEXT,
        ti TEXT,
        habilitado TEXT,
        consumo_prod REAL,
        mostrar TEXT,
        sincronizado INTEGER DEFAULT 1
      )
    ''');
await db.execute('''
      CREATE TABLE IF NOT EXISTS ordenes_aplicaciones (
        cod_orden TEXT PRIMARY KEY,
        cod_productor TEXT,
        productor TEXT,
        orden_aplic INTEGER,
        ref INTEGER,
        fecha TEXT,
        chacra TEXT,
        cuadros TEXT,
        motivo_aplic TEXT,
        momento_aplic TEXT,
        vol_aplic_ha REAL,
        responsable TEXT,
        estado TEXT,
        vol_100 REAL,
        sincronizado INTEGER DEFAULT 1
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS insumos_detalles (
        cod_mov TEXT PRIMARY KEY,
        reg_ingreso TEXT,
        reg_aplic TEXT,
        cod_productor INTEGER,
        productor TEXT,
        deposito TEXT,
        ID_Insumos INTEGER,
        producto TEXT,
        concetracion TEXT,
        movimiento TEXT,
        cantidad REAL,
        unidad TEXT,
        fec_vencimiento TEXT,
        fecha_ingreso TEXT,
        reg_consumo TEXT,
        sincronizado INTEGER DEFAULT 1
      )
    ''');

    await _crearTablasCampo(db);
  }

  Future<void> _crearTablasCampo(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS fenologia_parametros (
        id TEXT PRIMARY KEY,
        cultivo TEXT,
        metodo TEXT,
        estado_codigo TEXT,
        descripcion TEXT,
        temp_critica_min REAL,
        temp_critica_max REAL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS lecturas_fenologia (
        id INTEGER,
        id_reg TEXT,
        created_at TEXT,
        establecimiento TEXT,
        sector TEXT,
        cuadro TEXT,
        fila TEXT,
        variedad TEXT,
        planta_numero TEXT,
        cultivo TEXT,
        estado_codigo TEXT,
        descripcion_estado TEXT,
        temp_aire_api INTEGER,
        temp_critica_min REAL,
        temp_critica_max REAL,
        url_evidencia TEXT,
        latitud TEXT,
        longitud TEXT,
        usuario TEXT,
        fecha TEXT,
        valor_lectura INTEGER,
        cod_establecimiento INTEGER,
        sincronizado INTEGER DEFAULT 1,
        PRIMARY KEY (id, id_reg)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS lecturas_trampas (
        id TEXT,
        id_reg TEXT,
        created_at TEXT,
        establecimiento TEXT,
        sector TEXT,
        cuadro TEXT,
        cultivo TEXT,
        variedad TEXT,
        fila TEXT,
        ubicacion TEXT,
        tipo_trampa TEXT,
        cod_trampa TEXT,
        usuario TEXT,
        trampa_numero TEXT,
        semana TEXT,
        temporada TEXT,
        macho TEXT,
        hembra_virgen TEXT,
        hembra_gravida TEXT,
        url_evidencia TEXT,
        cod_establecimiento INTEGER,
        sincronizado INTEGER DEFAULT 1,
        PRIMARY KEY (id, id_reg)
      )
    ''');
  }


  Future<void> _onUpgrade(Database db, int oldV, int newV) async {
    if (oldV < 4) {
      await _crearTablasCampo(db);
    }
    if (oldV < 7) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS parametros_aplic (
          id INTEGER PRIMARY KEY,
          vel_viento TEXT,
          Temperatura TEXT,
          Tamano_gota TEXT,
          Vel_Aplicacion TEXT,
          Caudal_Ha TEXT,
          cod_receta INTEGER,
          cod_orden INTEGER
        )
      ''');
    }
    if (oldV < 8) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS config_app_enlaces (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          plataforma TEXT,
          url_instalacion TEXT,
          version TEXT,
          instrucciones TEXT,
          sincronizado INTEGER DEFAULT 1
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS insumos_detalles (
          cod_mov TEXT PRIMARY KEY,
          reg_ingreso TEXT,
          reg_aplic TEXT,
          cod_productor INTEGER,
          productor TEXT,
          deposito TEXT,
          ID_Insumos INTEGER,
          producto TEXT,
          concetracion TEXT,
          movimiento TEXT,
          cantidad REAL,
          unidad TEXT,
          fec_vencimiento TEXT,
          fecha_ingreso TEXT,
          reg_consumo TEXT,
          sincronizado INTEGER DEFAULT 1
        )
      ''');
    }
  }


  Future<int> obtenerSiguienteId(String tabla, String campoId) async {
    final db = await instance.database;
    final res = await db.rawQuery('SELECT MAX(CAST($campoId AS INTEGER)) as max_id FROM $tabla');
    int maxId = (res.first['max_id'] as int?) ?? 0;
    return maxId + 1;
  }
}
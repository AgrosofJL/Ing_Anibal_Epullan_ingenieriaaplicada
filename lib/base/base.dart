import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  final supabase = Supabase.instance.client;

  // ACA ES LO NUEVO: Retorna _WebDatabaseAdapter en Web o Database en móvil
  Future<dynamic> get database async {
    if (kIsWeb) {
      return _WebDatabaseAdapter(supabase);
    }
    if (_database != null) return _database!;
    _database = await _initDB('aplicaciones_foliares.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 7,
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
      CREATE TABLE usuarios (
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
      CREATE TABLE rubros_insumos (
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
      CREATE TABLE recetas_aplicaciones (
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
      CREATE TABLE config_app_enlaces (
      id integer INTEGER PRIMARY KEY AUTOINCREMENT,
      plataforma text null,
      url_instalacion text null,
      version text null,
      instrucciones text null,
      sincronizado INTEGER DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE productores (
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
      CREATE TABLE motivos_aplicaciones (
        cod INTEGER PRIMARY KEY,
        motivo TEXT,
        tipo_aplic TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE inventario_plantacion (
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
      CREATE TABLE cuadros (
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
      CREATE TABLE catalogo_insumos (
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
      CREATE TABLE aplicaciones_registros (
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
  }

  // ESTO LO MODIFIQUE: Cálculo incremental compatible con Web y Móvil
  Future<int> obtenerSiguienteId(String tabla, String campoId) async {
    if (kIsWeb) {
      try {
        final res = await supabase
            .from(tabla)
            .select(campoId)
            .order(campoId, ascending: false)
            .limit(1);

        if (res.isNotEmpty) {
          final valor = res.first[campoId];
          final int maxId = int.tryParse(valor.toString()) ?? 0;
          return maxId + 1;
        }
        return 1;
      } catch (e) {
        debugPrint("Error obteniendo siguiente ID en Web ($tabla): $e");
        return 1;
      }
    }

    final db = await instance.database;
    final res = await db.rawQuery('SELECT MAX(CAST($campoId AS INTEGER)) as max_id FROM $tabla');
    int maxId = (res.first['max_id'] as int?) ?? 0;
    return maxId + 1;
  }
}

// ============================================================================
// ACA ES LO NUEVO: Adaptador Web transparente que intercepta y redirige a Supabase
// ============================================================================
class _WebDatabaseAdapter {
  final SupabaseClient supabase;
  _WebDatabaseAdapter(this.supabase);

  Future<List<Map<String, dynamic>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    try {
      dynamic builder = supabase.from(table).select();

      if (where != null && whereArgs != null && whereArgs.isNotEmpty) {
        final columna = where.split('=').first.trim();
        builder = builder.eq(columna, whereArgs.first);
      }

      if (orderBy != null) {
        final partes = orderBy.split(' ');
        final columna = partes[0].trim();
        final ascendente = partes.length > 1 ? partes[1].toUpperCase() == 'ASC' : true;
        builder = builder.order(columna, ascending: ascendente);
      }

      if (limit != null) {
        builder = builder.limit(limit);
      }

      final res = await builder;
      return List<Map<String, dynamic>>.from(res);
    } catch (e) {
      debugPrint("Error query Web en $table: $e");
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> rawQuery(String sql, [List<Object?>? arguments]) async {
    try {
      // Conteo de registros para widgets o contadores
      if (sql.toUpperCase().contains('COUNT(*)')) {
        return [{'t': 0}];
      }

      // SELECT MAX incremental
      final sqlMayus = sql.toUpperCase();
      if (sqlMayus.contains('SELECT MAX(') && sqlMayus.contains('FROM')) {
        final partesFrom = sql.split(RegExp(r'FROM', caseSensitive: false));
        if (partesFrom.length > 1) {
          final tabla = partesFrom[1].trim().split(' ').first;
          final regexCampo = RegExp(r'MAX\(CAST\((.*?) AS', caseSensitive: false);
          final match = regexCampo.firstMatch(sql);

          if (match != null) {
            final campo = match.group(1)!.trim();
            final res = await supabase
                .from(tabla)
                .select(campo)
                .order(campo, ascending: false)
                .limit(1);

            if (res.isNotEmpty) {
              final valor = res.first[campo];
              return [{'max_id': int.tryParse(valor.toString()) ?? 0}];
            }
          }
        }
        return [{'max_id': 0}];
      }

      return [];
    } catch (e) {
      debugPrint("Error rawQuery Web: $e");
      return [];
    }
  }

  Future<int> insert(
    String table,
    Map<String, dynamic> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    try {
      final payload = Map<String, dynamic>.from(values);
      payload.remove('sincronizado');
      await supabase.from(table).upsert(payload);
      return 1;
    } catch (e) {
      debugPrint("Error insert Web en $table: $e");
      return 0;
    }
  }

  Future<int> update(
    String table,
    Map<String, dynamic> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    try {
      final payload = Map<String, dynamic>.from(values);
      payload.remove('sincronizado');

      dynamic builder = supabase.from(table).update(payload);
      if (where != null && whereArgs != null && whereArgs.isNotEmpty) {
        final columna = where.split('=').first.trim();
        builder = builder.eq(columna, whereArgs.first);
      }
      await builder;
      return 1;
    } catch (e) {
      debugPrint("Error update Web en $table: $e");
      return 0;
    }
  }

  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    try {
      dynamic builder = supabase.from(table).delete();
      if (where != null && whereArgs != null && whereArgs.isNotEmpty) {
        final columna = where.split('=').first.trim();
        builder = builder.eq(columna, whereArgs.first);
      }
      await builder;
      return 1;
    } catch (e) {
      debugPrint("Error delete Web en $table: $e");
      return 0;
    }
  }
}
import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/audit_columns.dart';

/// Columnas de `ServicioLineaComercialVigencia` compartidas entre la
/// forma anterior y la nueva (todo excepto
/// `sueldo_mensual_referencia_personal`/`bono_mensual_referencia_personal`,
/// que no existían antes) — se usan para copiar filas tal cual.
const _columnasVigenciaCompartidas = [
  'id', 'created_at', 'updated_at', 'ciclo_vida_registro',
  'linea_comercial_id', 'puesto_id', 'modalidad_turno_id', 'cantidad_elementos', 'precio_unitario',
  'tratamiento_iva', 'descripcion', 'fecha_inicio_vigencia', 'fecha_fin_vigencia', 'observaciones',
];

/// Migración de la Etapa 15 (rediseño "Condiciones de Personal",
/// `schemaVersion` 49 → 50).
///
/// **`ServicioLineaComercialVigencia`** gana
/// `sueldoMensualReferenciaPersonal`/`bonoMensualReferenciaPersonal` —
/// cada línea pasa a representar un perfil contratado completo, con sus
/// propias condiciones salariales de referencia (ya no un único
/// sueldo/bono global por Servicio). Ambas columnas llevan `CHECK`
/// (mismo criterio que `Servicio.sueldoMensualReferenciaPersonal`/
/// `bonoMensualReferenciaPersonal`, Etapa 6B) y `Migrator.addColumn`
/// nunca agrega restricciones de tabla — solo la definición de la
/// columna misma (mismo motivo estructural que `migrarServicioV24`,
/// que originalmente agregó estas 2 columnas a `Servicio`). Se recrea
/// la tabla completa: RENAME → `createTable` con la forma actual →
/// copiar filas → verificar conteo → DROP. `ServicioLineaComercialVigencia`
/// es tabla *referenciada* por `DocumentoPorEmitirLinea` (FK cruda) —
/// mismo riesgo ya documentado en `migrarServicioV24`/`migrarServicioV6`:
/// `ALTER TABLE ... RENAME TO` reescribiría esa FK hacia el nombre
/// temporal, así que se usa la misma corrección
/// (`PRAGMA legacy_alter_table = ON`).
///
/// **`AsignacionServicio`** gana `lineaComercialId` (nullable, sin
/// `CHECK`) — a qué perfil pertenece cada asignación; al no llevar
/// restricción de tabla, `Migrator.addColumn` es suficiente aquí, sin
/// necesidad de recrear la tabla.
///
/// Las columnas globales `Servicio.sueldoMensualReferenciaPersonal`/
/// `bonoMensualReferenciaPersonal` **no se eliminan** — se dejan de usar
/// para operación nueva (Resolución explícita de Marlon: "conservar las
/// columnas globales antiguas en BD temporalmente para compatibilidad;
/// dejar de usarlas para nuevas operaciones"), y `AsignacionServicio`
/// existentes conservan `lineaComercialId = NULL` sin ningún intento de
/// adivinarlo retroactivamente — dato legítimo ("asignación histórica
/// sin perfil asociado"), no un hueco a rellenar a la fuerza.
///
/// **Migración asistida, solo en el caso trivial y determinista**
/// (Resolución explícita de Marlon, caso real MORGAN ATLACOMULCO): un
/// Servicio con sueldo/bono global capturado y **exactamente una**
/// línea comercial cuya vigencia está vigente *hoy* (al momento de
/// correr esta migración) recibe esos valores copiados directamente a
/// esa vigencia — es la única interpretación sin ambigüedad de "a qué
/// perfil pertenecía ese sueldo". Con 2+ líneas, o sin ninguna vigencia
/// vigente hoy, no se copia nada: nunca se adivina.
Future<void> migrarCondicionesPersonalLineaComercialV50(AppDatabase db, Migrator m) async {
  await db.transaction(() async {
    final columnasVigencia = await db.customSelect("PRAGMA table_info('servicio_linea_comercial_vigencia')").get();
    if (!columnasVigencia.any((fila) => fila.data['name'] == 'sueldo_mensual_referencia_personal')) {
      final conteoAntes = await db
          .customSelect('SELECT COUNT(*) AS n FROM servicio_linea_comercial_vigencia')
          .map((r) => r.data['n'] as int)
          .getSingle();

      await db.customStatement('PRAGMA legacy_alter_table = ON');
      await db.customStatement('ALTER TABLE servicio_linea_comercial_vigencia RENAME TO servicio_linea_comercial_vigencia_old');

      // Forma *actual* de la clase Dart — ya es la forma final que
      // necesita schemaVersion 50, sin ningún paso posterior que vuelva
      // a tocar esta tabla en esta cadena de `onUpgrade`.
      await m.createTable(db.servicioLineaComercialVigencia);

      final columnas = _columnasVigenciaCompartidas.join(', ');
      await db.customStatement(
        'INSERT INTO servicio_linea_comercial_vigencia ($columnas) SELECT $columnas FROM servicio_linea_comercial_vigencia_old',
      );

      final conteoDespues = await db
          .customSelect('SELECT COUNT(*) AS n FROM servicio_linea_comercial_vigencia')
          .map((r) => r.data['n'] as int)
          .getSingle();
      if (conteoDespues != conteoAntes) {
        throw StateError(
          'Migración de ServicioLineaComercialVigencia a schemaVersion 50: se esperaban $conteoAntes '
          'filas copiadas, se encontraron $conteoDespues. Migración abortada.',
        );
      }

      await db.customStatement('DROP TABLE servicio_linea_comercial_vigencia_old');
      await db.customStatement('PRAGMA legacy_alter_table = OFF');
    }

    final columnasAsignacion = await db.customSelect("PRAGMA table_info('asignacion_servicio')").get();
    if (!columnasAsignacion.any((fila) => fila.data['name'] == 'linea_comercial_id')) {
      await m.addColumn(db.asignacionServicio, db.asignacionServicio.lineaComercialId);
    }

    final hoy = DateTime.now();
    final hoySinHora = DateTime(hoy.year, hoy.month, hoy.day);

    final serviciosConSueldoGlobal =
        await (db.select(db.servicio)..where((t) => t.sueldoMensualReferenciaPersonal.isNotNull())).get();

    for (final servicio in serviciosConSueldoGlobal) {
      final lineas =
          await (db.select(db.servicioLineaComercial)..where((t) => t.servicioId.equals(servicio.id))).get();
      // 2+ líneas (o ninguna): no hay forma determinista de saber a
      // cuál pertenecía el sueldo global — nunca se adivina.
      if (lineas.length != 1) continue;

      final vigenciasActivas = await (db.select(db.servicioLineaComercialVigencia)
            ..where(
              (t) =>
                  t.lineaComercialId.equals(lineas.single.id) &
                  t.cicloVidaRegistro.equals(CicloVidaRegistro.activo.name),
            ))
          .get();

      // Misma selección de "la vigente" que `clasificarVigencias`
      // (`linea_comercial_con_vigencia.dart`) — reescrita aquí en vez de
      // importar el helper de dominio, mismo criterio de las demás
      // migraciones de este proyecto (autocontenidas).
      ServicioLineaComercialVigenciaData? vigente;
      for (final v in vigenciasActivas) {
        final inicio = DateTime(v.fechaInicioVigencia.year, v.fechaInicioVigencia.month, v.fechaInicioVigencia.day);
        if (inicio.isAfter(hoySinHora)) continue;
        final fin = v.fechaFinVigencia;
        final finSinHora = fin == null ? null : DateTime(fin.year, fin.month, fin.day);
        if (finSinHora != null && finSinHora.isBefore(hoySinHora)) continue;
        if (vigente == null ||
            inicio.isAfter(DateTime(vigente.fechaInicioVigencia.year, vigente.fechaInicioVigencia.month, vigente.fechaInicioVigencia.day))) {
          vigente = v;
        }
      }
      if (vigente == null) continue;

      await (db.update(db.servicioLineaComercialVigencia)..where((t) => t.id.equals(vigente!.id))).write(
        ServicioLineaComercialVigenciaCompanion(
          sueldoMensualReferenciaPersonal: Value(servicio.sueldoMensualReferenciaPersonal),
          bonoMensualReferenciaPersonal: Value(servicio.bonoMensualReferenciaPersonal),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violacionesFk.isNotEmpty) {
      throw StateError(
        'Migración a schemaVersion 50: foreign_key_check reportó '
        '${violacionesFk.length} violación(es) tras la migración. Migración abortada.',
      );
    }

    final resultadoIntegridad = await db
        .customSelect('PRAGMA integrity_check')
        .map((r) => r.data['integrity_check'] as String)
        .get();
    final integridadOk = resultadoIntegridad.length == 1 && resultadoIntegridad.single == 'ok';
    if (!integridadOk) {
      throw StateError(
        'Migración a schemaVersion 50: integrity_check reportó '
        'problemas: $resultadoIntegridad. Migración abortada.',
      );
    }
  });
}

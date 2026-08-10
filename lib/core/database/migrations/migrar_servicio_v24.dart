import 'package:drift/drift.dart';

import '../app_database.dart';

/// Columnas de `Servicio` compartidas entre la forma anterior (Etapa
/// 4F.2, `schemaVersion` 7) y la forma nueva (todo excepto
/// `sueldo_mensual_referencia_personal`/`bono_mensual_referencia_personal`,
/// que no existían antes) — se usan para copiar filas tal cual.
const _columnasServicioCompartidas = [
  'id', 'created_at', 'updated_at', 'ciclo_vida_registro',
  'codigo', 'cliente_id', 'nombre', 'tipo_servicio_id',
  'sucursal_administrativa_id', 'estatus', 'fecha_inicio', 'fecha_termino',
  'elementos_autorizados', 'responsable_cliente_contacto_id', 'observaciones',
  'entidad_fiscal_id', 'responsable_interno', 'referencia_comercial', 'referencia_contractual',
];

/// Migración estructural de la Etapa 6B (`schemaVersion` 6 a 23 → 24):
/// agrega `sueldoMensualReferenciaPersonal`/`bonoMensualReferenciaPersonal`
/// a `Servicio` — sueldo/bono de referencia para el personal asignado,
/// precargados al crear una `AsignacionServicio` nueva.
///
/// Requiere recrear la tabla: ambas columnas llevan `CHECK`
/// (`sueldo > 0`, `bono >= 0`, mismo criterio que
/// `Empleado.sueldoMensualAdministrativo`/`bonoMensualAdministrativo` de
/// la Etapa 6A) y `ALTER TABLE ... ADD COLUMN` (`Migrator.addColumn`)
/// nunca agrega restricciones de tabla (`customConstraints`) — solo la
/// definición de la columna misma. Mismo motivo estructural que
/// `migrarEmpleadoV23`/`migrarServicioV6`.
///
/// `Servicio` es tabla *referenciada* por `Direccion`, `Ubicacion`,
/// `Horario`, `AsignacionServicio`, `ServicioLineaComercial`,
/// `ConfiguracionCobro`, `DocumentoPorEmitirServicio`, `Ingreso` y
/// `Egreso` (FK cruda) — mismo riesgo real ya documentado en
/// `migrarServicioV6`/`migrarEmpleadoV23`: `ALTER TABLE ... RENAME TO`
/// reescribiría esas FK hacia el nombre temporal. Se usa la misma
/// corrección (`PRAGMA legacy_alter_table = ON`).
///
/// Solo aplica a instalaciones que ya tenían `Servicio` físicamente
/// creado con la forma de la Etapa 4F.2 en adelante (`from` 6 a 23) —
/// ver el doc comment del paso que la invoca en `app_database.dart` para
/// el detalle completo del gotcha de rango (`from == 1` y `from` 2 a 5
/// ya obtienen la forma actual vía `_createEtapa4ATables`/
/// `migrarServicioV6`).
Future<void> migrarServicioV24(AppDatabase db, Migrator m) async {
  await db.transaction(() async {
    final conteoAntes =
        await db.customSelect('SELECT COUNT(*) AS n FROM servicio').map((r) => r.data['n'] as int).getSingle();

    await db.customStatement('PRAGMA legacy_alter_table = ON');
    await db.customStatement('ALTER TABLE servicio RENAME TO servicio_old');

    // Forma *actual* de la clase Dart — ya es la forma final que
    // necesita schemaVersion 24, sin ningún paso posterior que vuelva a
    // tocar `Servicio` en esta cadena de `onUpgrade`.
    await m.createTable(db.servicio);

    final columnas = _columnasServicioCompartidas.join(', ');
    await db.customStatement(
      'INSERT INTO servicio ($columnas) SELECT $columnas FROM servicio_old',
    );

    final conteoDespues =
        await db.customSelect('SELECT COUNT(*) AS n FROM servicio').map((r) => r.data['n'] as int).getSingle();
    if (conteoDespues != conteoAntes) {
      throw StateError(
        'Migración de Servicio a schemaVersion 24: se esperaban $conteoAntes filas '
        'copiadas, se encontraron $conteoDespues. Migración abortada.',
      );
    }

    await db.customStatement('DROP TABLE servicio_old');
    await db.customStatement('PRAGMA legacy_alter_table = OFF');

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violacionesFk.isNotEmpty) {
      throw StateError(
        'Migración de Servicio a schemaVersion 24: foreign_key_check reportó '
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
        'Migración de Servicio a schemaVersion 24: integrity_check reportó '
        'problemas: $resultadoIntegridad. Migración abortada.',
      );
    }
  });
}

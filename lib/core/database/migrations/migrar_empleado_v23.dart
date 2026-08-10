import 'package:drift/drift.dart';

import '../app_database.dart';

/// Columnas de `Empleado` compartidas entre la forma anterior y la
/// forma nueva (todo excepto `codigo_empleado`, que desaparece, y las
/// columnas nuevas `numero_empleado`/`banco_id`/`numero_cuenta_tarjeta`/
/// `clabe`/`sueldo_mensual_administrativo`/`bono_mensual_administrativo`,
/// que no existían antes) — se usan para copiar filas tal cual.
const _columnasEmpleadoCompartidas = [
  'id', 'created_at', 'updated_at', 'ciclo_vida_registro',
  'fotografia_attachment_id',
  'nombres', 'apellido_paterno', 'apellido_materno', 'sexo', 'fecha_nacimiento',
  'curp', 'rfc', 'codigo_postal_fiscal', 'nss', 'estado_civil', 'nacionalidad',
  'telefono', 'correo_electronico', 'contacto_emergencia_nombre',
  'telefono_emergencia', 'parentesco_emergencia',
  'fecha_ingreso', 'estatus', 'puesto_id', 'empresa_id', 'sucursal_id', 'observaciones',
  'fecha_baja', 'motivo_baja', 'observaciones_baja',
  'nivel_estudios', 'observaciones_escolaridad',
  'anios_experiencia_seguridad', 'meses_experiencia_adicionales', 'ultimo_puesto_desempenado',
  'resumen_experiencia', 'observaciones_experiencia',
  'fecha_evaluacion_psicologica', 'resumen_psicologico', 'observaciones_psicologico',
  'fecha_estudio_socioeconomico', 'resumen_estudio_socioeconomico', 'observaciones_estudio_socioeconomico',
  'fecha_antidoping', 'resultado_amp', 'resultado_bzd', 'resultado_coc', 'resultado_met',
  'resultado_opi', 'observaciones_antidoping',
];

/// Migración estructural de la Etapa 6A (`schemaVersion` 18 a 22 → 23):
/// reemplaza `codigoEmpleado` (texto, `EMP-000001`) por `numeroEmpleado`
/// (entero, consecutivo desde 1, sin prefijo ni relleno — Resolución
/// explícita de Marlon), y agrega los datos bancarios
/// (`bancoId`/`numeroCuentaTarjeta`/`clabe`) y la condición laboral
/// administrativa (`sueldoMensualAdministrativo`/
/// `bonoMensualAdministrativo`). Requiere recrear la tabla: no se puede
/// cambiar el tipo de una columna existente ni ampliar el `CHECK` de
/// tabla vía `ALTER TABLE ... ADD COLUMN` (mismo motivo estructural que
/// `migrarDireccionV18`/`migrarAttachmentV13`).
///
/// `numeroEmpleado` se asigna por orden de `created_at` (orden real de
/// alta en el sistema, no `fecha_ingreso` — un dato de negocio que
/// pudo capturarse fuera de secuencia) vía `ROW_NUMBER()`, nunca
/// `MAX(...) + 1` fila por fila.
///
/// `Empleado` es tabla *referenciada* por `AsignacionServicio`,
/// `EmpleadoEvento`, `EmpleadoPeriodoLaboral`, `EmpleadoAttachment`,
/// `FichaTecnicaEmpleado` y `Direccion` (FK cruda) — mismo riesgo real
/// ya documentado en `migrarAttachmentV13`/`migrarServicioV6`:
/// `ALTER TABLE ... RENAME TO` reescribiría esas FK hacia el nombre
/// temporal. Se usa la misma corrección (`PRAGMA legacy_alter_table =
/// ON`).
///
/// Requiere que `banco` ya exista (su FK la referencia) — por eso corre
/// después de crear esa tabla en `onUpgrade`. Solo aplica a
/// instalaciones que ya tenían `Empleado` físicamente creada con la
/// forma anterior (`from` 18 a 22) — un origen `from <= 17` ya la crea
/// con la forma *actual* (bloque `to >= 18` de `app_database.dart`, que
/// para cuando llega aquí ya lee la clase Dart de hoy, con
/// `numeroEmpleado` y las columnas nuevas incluidas).
Future<void> migrarEmpleadoV23(AppDatabase db, Migrator m) async {
  await db.transaction(() async {
    final conteoAntes =
        await db.customSelect('SELECT COUNT(*) AS n FROM empleado').map((r) => r.data['n'] as int).getSingle();

    await db.customStatement('PRAGMA legacy_alter_table = ON');
    await db.customStatement('ALTER TABLE empleado RENAME TO empleado_old');

    // Forma *actual* de la clase Dart — ya es la forma final que
    // necesita schemaVersion 23, sin ningún paso posterior que vuelva
    // a tocar `Empleado` en esta cadena de `onUpgrade`.
    await m.createTable(db.empleado);

    final columnas = _columnasEmpleadoCompartidas.join(', ');
    await db.customStatement('''
      INSERT INTO empleado (numero_empleado, $columnas)
      SELECT ROW_NUMBER() OVER (ORDER BY created_at ASC, id ASC), $columnas
      FROM empleado_old
    ''');

    final conteoDespues =
        await db.customSelect('SELECT COUNT(*) AS n FROM empleado').map((r) => r.data['n'] as int).getSingle();
    if (conteoDespues != conteoAntes) {
      throw StateError(
        'Migración de Empleado a schemaVersion 23: se esperaban $conteoAntes filas '
        'copiadas, se encontraron $conteoDespues. Migración abortada.',
      );
    }

    await db.customStatement('DROP TABLE empleado_old');
    await db.customStatement('PRAGMA legacy_alter_table = OFF');

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violacionesFk.isNotEmpty) {
      throw StateError(
        'Migración de Empleado a schemaVersion 23: foreign_key_check reportó '
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
        'Migración de Empleado a schemaVersion 23: integrity_check reportó '
        'problemas: $resultadoIntegridad. Migración abortada.',
      );
    }
  });
}

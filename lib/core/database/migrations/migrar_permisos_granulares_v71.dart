import 'package:drift/drift.dart';

import '../app_database.dart';

/// Migración de la Etapa "1 — Modelo de permisos granular y consistente":
///
/// Puramente de datos, sin cambio de esquema — `PermisoUsuario.codigo`
/// es texto libre (mismo criterio que `migrarCorreccionTiempoExtraV70`,
/// el precedente directo de esta migración). El catálogo dividió varios
/// códigos amplios (`finanzas.crear/modificar/archivar`,
/// `comercial.crear/modificar/archivar`, `nomina.pagar`,
/// `personal.gestionarDescuentos`, `inventario.modificar`) en
/// facultades más finas, y estrechó el alcance de otros tres
/// (`compras.crear`, `personal.modificar`, `vehiculos.crear`,
/// `telefonia.crear` conservan su código pero ya no cubren todo lo que
/// cubrían antes).
///
/// Regla de migración (conservadora, pedido explícito de Marlon: "si un
/// usuario antes tenía un permiso amplio, inicialmente debe recibir
/// todos los nuevos permisos equivalentes a las facultades que ese
/// código le daba"): por cada código viejo, todo usuario que ya lo
/// tenía recibe TODOS los códigos nuevos que reemplazan su alcance —
/// nunca se le quita nada, nunca se le otorga una eliminación física
/// (`exigirMaestro` nunca consulta `PermisoUsuario`, ningún código de
/// esta lista la sustituye). El código viejo se conserva tal cual en
/// `PermisoUsuario` (fila inerte si ya no aparece en el catálogo, o
/// simplemente sigue vigente si el código no cambió) — nunca se borra,
/// `codigo` es texto libre y no requiere limpieza. El Usuario Maestro
/// nunca tiene filas de `PermisoUsuario` (su acceso se recalcula en
/// vivo desde `todosLosCodigosDePermiso()`), así que esta migración no
/// lo toca ni necesita tocarlo.
///
/// Idempotente: cada inserción se verifica antes (`getSingleOrNull`),
/// correrla dos veces no duplica ninguna fila ni falla por violar la
/// llave primaria `(usuarioId, codigo)`.
const migracionPermisosGranularesV71 = <String, List<String>>{
  // Finanzas — el propio `finanzas.crear/modificar/archivar` se retira
  // del catálogo (`finanzas` ahora solo tiene `ver`); cada usuario que
  // los tenía recibe todos los códigos de los 7 subdominios nuevos.
  'finanzas.crear': [
    'ingresos.crear',
    'egresos.crear',
    'deudas.crear',
    'deudas.registrarPago',
    'pagos.registrar',
    'cuentasFinancieras.crear',
    'categoriasFinancieras.crear',
  ],
  'finanzas.modificar': [
    'ingresos.corregir',
    'egresos.corregir',
    'deudas.corregir',
    'pagos.corregir',
    'cuentasFinancieras.corregir',
    'cuentasFinancieras.cambiarEstatus',
    'categoriasFinancieras.corregir',
    'cuentaPorCobrar.corregirFecha',
    'cuentaPorCobrar.reprogramarCobro',
  ],
  'finanzas.archivar': [
    'ingresos.cancelar',
    'egresos.cancelar',
    'deudas.cancelar',
    'pagos.cancelar',
    'pagos.cancelarAplicacion',
    'categoriasFinancieras.archivar',
  ],
  // Comercial — mismo criterio, `comercial.crear/modificar/archivar` se
  // retira (`comercial` ahora solo tiene `ver`); Organización
  // (`organizacion.*`) es un módulo aparte, no participa aquí.
  'comercial.crear': ['clientes.crear', 'servicios.crear', 'configuracionCobro.crear', 'agendaComercial.crear'],
  'comercial.modificar': [
    'clientes.corregir',
    'servicios.corregir',
    'configuracionCobro.corregir',
    'agendaComercial.corregir',
  ],
  'comercial.archivar': ['clientes.archivar'],
  // Nómina — `nomina.pagar` se retira, reemplazado por 3 facultades.
  'nomina.pagar': ['nomina.registrarPago', 'nomina.corregirPago', 'nomina.cancelarPago'],
  // Descuentos — `personal.gestionarDescuentos` se retira, reemplazado
  // por el módulo dedicado `descuentos` (incluye `descuentos.ver`,
  // nuevo — antes Descuentos no tenía ningún guardia de lectura propio).
  'personal.gestionarDescuentos': ['descuentos.ver', 'descuentos.crear', 'descuentos.corregir', 'descuentos.cancelar'],
  // Inventario — `inventario.modificar` se retira, reemplazado por 2
  // facultades ("modificar metadatos ≠ ajustar existencia").
  'inventario.modificar': ['inventario.corregir', 'inventario.ajustarExistencia'],
  // Los siguientes 4 CONSERVAN su código (nunca se retiran del
  // catálogo) — la migración solo AGREGA el código nuevo que separó
  // una facultad que antes venía incluida.
  //
  // `personal.modificar` cubría también dar de baja/reingresar — ahora
  // exige `personal.archivar` (antes 100% muerto, reutilizado aquí:
  // "dar de baja NO es simplemente modificar sus datos", pedido
  // explícito de Marlon).
  'personal.modificar': ['personal.archivar'],
  // `compras.crear` cubría también corregir una Compra ya registrada.
  'compras.crear': ['compras.corregir'],
  // `compras.archivar` sí se retira (reemplazado por `compras.cancelar`,
  // mismo verbo que el resto del rediseño).
  'compras.archivar': ['compras.cancelar'],
  // `vehiculos.crear` cubría también documento/mantenimiento/asignación
  // de un vehículo YA existente.
  'vehiculos.crear': ['vehiculos.operar'],
  // `telefonia.crear` cubría también recargar una línea (dinero real).
  'telefonia.crear': ['telefonia.recargar'],
};

Future<void> migrarPermisosGranularesV71(AppDatabase db, Migrator m) async {
  await db.transaction(() async {
    for (final entrada in migracionPermisosGranularesV71.entries) {
      final codigoViejo = entrada.key;
      final codigosNuevos = entrada.value;

      final usuariosConCodigoViejo =
          await (db.select(db.permisoUsuario)..where((t) => t.codigo.equals(codigoViejo))).get();

      for (final fila in usuariosConCodigoViejo) {
        for (final codigoNuevo in codigosNuevos) {
          final yaExiste = await (db.select(db.permisoUsuario)
                ..where((t) => t.usuarioId.equals(fila.usuarioId) & t.codigo.equals(codigoNuevo)))
              .getSingleOrNull();
          if (yaExiste == null) {
            await db.into(db.permisoUsuario).insert(
                  PermisoUsuarioCompanion.insert(usuarioId: fila.usuarioId, codigo: codigoNuevo),
                );
          }
        }
      }
    }

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violacionesFk.isNotEmpty) {
      throw StateError(
        'Migración a schemaVersion 71: foreign_key_check reportó '
        '${violacionesFk.length} violación(es). Migración abortada.',
      );
    }

    final resultadoIntegridad = await db
        .customSelect('PRAGMA integrity_check')
        .map((r) => r.data['integrity_check'] as String)
        .get();
    final integridadOk = resultadoIntegridad.length == 1 && resultadoIntegridad.single == 'ok';
    if (!integridadOk) {
      throw StateError(
        'Migración a schemaVersion 71: integrity_check reportó '
        'problemas: $resultadoIntegridad. Migración abortada.',
      );
    }
  });
}

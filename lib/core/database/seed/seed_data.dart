import 'package:drift/drift.dart';

import '../app_database.dart';
import 'seed_ids.dart';

/// Siembra idempotente de catálogos base, contador de códigos y la
/// Empresa RSG-01.
///
/// Idempotencia real: cada fila usa `InsertMode.insertOrIgnore` sobre una
/// llave estable (la primaria — `entityType` en `CodigoSecuencia`, `id`
/// estable de `seed_ids.dart` en catálogos/Empresa) — nunca se decide en
/// base a "la tabla está vacía", así que una migración futura que agregue
/// más filas de catálogo puede llamar a esta misma función sin duplicar
/// nada ni dejar una tabla a medio sembrar. Nunca hace `UPDATE`: si el
/// usuario ya editó una fila sembrada, esa edición sobrevive a que esta
/// función se vuelva a ejecutar.
Future<void> runSeed(AppDatabase db) async {
  await _seedCodigoSecuencia(db);
  await _seedTipoSucursal(db);
  await _seedIndustria(db);
  await _seedTipoServicio(db);
  await _seedArea(db);
  await _seedEmpresa(db);
}

Future<void> _seedCodigoSecuencia(AppDatabase db) async {
  final config = <(String entityType, String prefijo, int digitos)>[
    ('empresa', 'RSG', 2),
    ('sucursal', 'SUC', 4),
    ('ubicacion', 'UBI', 6),
    ('puesto', 'PUE', 4),
    ('cliente', 'CLI', 6),
    ('servicio', 'SER', 6),
    ('area', 'ARE', 4),
  ];

  for (final (entityType, prefijo, digitos) in config) {
    // El contador de 'empresa' arranca en 1 (RSG-01 ya se emite en esta
    // misma siembra) y el de 'area' en 6 (las 6 Áreas base ya se siembran
    // con ARE-0001..ARE-0006) — si no se reflejaran aquí, el servicio y
    // los datos sembrados quedarían desincronizados.
    final contadorInicial = switch (entityType) {
      'empresa' => 1,
      'area' => 6,
      _ => 0,
    };

    await db.into(db.codigoSecuencia).insert(
          CodigoSecuenciaCompanion.insert(
            entityType: entityType,
            prefijo: prefijo,
            digitos: digitos,
            contadorActual: Value(contadorInicial),
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }
}

Future<void> _seedTipoSucursal(AppDatabase db) async {
  final filas = [
    (SeedIds.tipoSucursalOficinaAdministrativa, 'OFICINA_ADMIN', 'Oficina Administrativa'),
    (SeedIds.tipoSucursalBaseOperativa, 'BASE_OPERATIVA', 'Base Operativa'),
    (SeedIds.tipoSucursalBodega, 'BODEGA', 'Bodega'),
  ];

  for (final (id, codigo, nombre) in filas) {
    await db.into(db.tipoSucursal).insert(
          TipoSucursalCompanion.insert(id: id, codigo: codigo, nombre: nombre),
          mode: InsertMode.insertOrIgnore,
        );
  }
}

Future<void> _seedIndustria(AppDatabase db) async {
  final filas = [
    (SeedIds.industriaComercio, 'COMERCIO', 'Comercio'),
    (SeedIds.industriaIndustrial, 'INDUSTRIAL', 'Industrial'),
    (SeedIds.industriaRetail, 'RETAIL', 'Retail'),
    (SeedIds.industriaGobierno, 'GOBIERNO', 'Gobierno'),
    (SeedIds.industriaOtro, 'OTRO', 'Otro'),
  ];

  for (final (id, codigo, nombre) in filas) {
    await db.into(db.industria).insert(
          IndustriaCompanion.insert(id: id, codigo: codigo, nombre: nombre),
          mode: InsertMode.insertOrIgnore,
        );
  }
}

Future<void> _seedTipoServicio(AppDatabase db) async {
  final filas = [
    (SeedIds.tipoServicioVigilanciaFija, 'VIGILANCIA_FIJA', 'Vigilancia fija'),
    (SeedIds.tipoServicioRondin, 'RONDIN', 'Rondín'),
    (SeedIds.tipoServicioEscolta, 'ESCOLTA', 'Escolta'),
    (SeedIds.tipoServicioMonitoreo, 'MONITOREO', 'Monitoreo'),
  ];

  for (final (id, codigo, nombre) in filas) {
    await db.into(db.tipoServicio).insert(
          TipoServicioCompanion.insert(id: id, codigo: codigo, nombre: nombre),
          mode: InsertMode.insertOrIgnore,
        );
  }
}

Future<void> _seedArea(AppDatabase db) async {
  // Formato definitivo (`ARE-####`) desde la Etapa 4D — una instalación
  // nueva siembra directo con este formato; una instalación existente
  // que todavía tenga los códigos alfabéticos originales (`OPERACIONES`,
  // `RH`, ...) los recibe vía `migrarCodigosAreaV3` en el upgrade a
  // schemaVersion 3, nunca aquí (esta función nunca hace `UPDATE`).
  final filas = [
    (SeedIds.areaOperaciones, 'ARE-0001', 'Operaciones'),
    (SeedIds.areaRecursosHumanos, 'ARE-0002', 'Recursos Humanos'),
    (SeedIds.areaAdministracion, 'ARE-0003', 'Administración'),
    (SeedIds.areaDireccion, 'ARE-0004', 'Dirección'),
    (SeedIds.areaMonitoreo, 'ARE-0005', 'Monitoreo'),
    (SeedIds.areaReclutamiento, 'ARE-0006', 'Reclutamiento'),
  ];

  for (final (id, codigo, nombre) in filas) {
    await db.into(db.area).insert(
          AreaCompanion.insert(id: id, codigo: codigo, nombre: nombre),
          mode: InsertMode.insertOrIgnore,
        );
  }
}

Future<void> _seedEmpresa(AppDatabase db) async {
  // Sin datos legales inventados: razonSocial/rfc/representanteLegal/
  // eslogan quedan pendientes de captura real en la Etapa 4B.
  await db.into(db.empresa).insert(
        EmpresaCompanion.insert(
          id: const Value(SeedIds.empresaRiseg),
          codigo: 'RSG-01',
          nombreComercial: 'Seguridad Privada RISEG',
        ),
        mode: InsertMode.insertOrIgnore,
      );
}

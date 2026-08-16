import 'package:drift/drift.dart';

import '../../../features/organizacion/data/tables/cliente_portal_table.dart';
import '../../security/credential_cipher.dart';
import '../app_database.dart';

/// Migración de la Etapa 15 (portal único del Cliente, `schemaVersion`
/// 51 → 52).
///
/// Funda `ClientePortal` — única fuente de verdad nueva para portales
/// de acceso del Cliente, reemplazando la captura duplicada que antes
/// vivía repetida en cada `ConfiguracionCobroVigencia` (`portalNombre`/
/// `portalUrl`/`portalUsuario`/`portalContrasena`/`portalObservaciones`,
/// ahora legacy — ver el doc comment de esas columnas). Agrega
/// `clientePortalId` (referencia, nunca copia — mismo patrón que
/// `entidadFiscalId`) en `ConfiguracionCobroVigencia` y
/// `DocumentoPorEmitir`.
///
/// **Migración de datos**: por cada `ConfiguracionCobroVigencia` con un
/// portal legado capturado, crea o reutiliza (dentro del mismo Cliente,
/// deduplicando por URL+usuario) una fila en `ClientePortal`, cifrando
/// `portalContrasena` con [CredentialCipher] antes de escribir
/// `contrasenaCifrada` — nunca queda una contraseña nueva en texto
/// plano. Las 5 columnas legacy **no se tocan ni se borran** (decisión
/// explícita de Marlon: se conservan por compatibilidad histórica,
/// candidatas a eliminarse en una futura etapa de limpieza). Los
/// correos (`ConfiguracionCobroCorreo`) tampoco se tocan — instrucción
/// explícita de Marlon, fuera de alcance de esta migración.
/// `DocumentoPorEmitir.clientePortalId` nace vacío para documentos
/// históricos — no hay forma confiable de reconstruir retroactivamente
/// qué portal se usó al emitir cada uno, así que no se adivina.
///
/// `cipher` es inyectable para que las pruebas de migración usen un
/// [AlmacenClaveCifrado] en memoria — ver el parámetro
/// `almacenClaveCifrado` del constructor de `AppDatabase`.
///
/// La prueba de esta migración (`test/core/database/migration_test.dart`,
/// "migración 51 → 52 ...") parte de `SchemaVerifier.schemaAt(51)` +
/// filas reales insertadas a mano, **nunca** de un `.sqlite` de
/// `RISEGONE-dev` — esos archivos `.bak-*` no son fixtures confiables
/// (ver la nota al inicio de ese archivo de pruebas).
Future<void> migrarClientePortalV52(AppDatabase db, Migrator m, {required CredentialCipher cipher}) async {
  await db.transaction(() async {
    await m.createTable(db.clientePortal);

    // `configuracion_cobro_vigencia`/`documento_por_emitir` nacen, en
    // varios pasos anteriores de este mismo `onUpgrade` (p. ej. `to >=
    // 9`/`to >= 11`), vía `m.createTable`/recreación con la forma
    // *actual* de sus clases Dart — que ya incluye `clientePortalId`.
    // Un origen que pasó por esos pasos en esta misma corrida ya tiene
    // la columna; solo se agrega si de verdad falta (mismo criterio
    // que `migrarCondicionesPersonalLineaComercialV50`).
    final columnasVigencia = await db.customSelect("PRAGMA table_info('configuracion_cobro_vigencia')").get();
    if (!columnasVigencia.any((fila) => fila.data['name'] == 'cliente_portal_id')) {
      await m.addColumn(db.configuracionCobroVigencia, db.configuracionCobroVigencia.clientePortalId);
    }

    final columnasDocumento = await db.customSelect("PRAGMA table_info('documento_por_emitir')").get();
    if (!columnasDocumento.any((fila) => fila.data['name'] == 'cliente_portal_id')) {
      await m.addColumn(db.documentoPorEmitir, db.documentoPorEmitir.clientePortalId);
    }

    // clienteId|url|usuario -> id del ClientePortal ya creado en esta
    // migración, para no duplicar un portal cuando 2+ vigencias del
    // mismo Cliente comparten la misma URL+usuario.
    final cacheDedup = <String, String>{};

    final vigenciasConPortal = await (db.select(db.configuracionCobroVigencia)
          ..where((t) => t.portalNombre.isNotNull()))
        .get();

    for (final vigencia in vigenciasConPortal) {
      final configuracion = await (db.select(db.configuracionCobro)
            ..where((t) => t.id.equals(vigencia.configuracionCobroId)))
          .getSingleOrNull();
      if (configuracion == null) continue;

      final servicio =
          await (db.select(db.servicio)..where((t) => t.id.equals(configuracion.servicioId))).getSingleOrNull();
      if (servicio == null) continue;

      final claveDedup = '${servicio.clienteId}|${vigencia.portalUrl ?? ''}|${vigencia.portalUsuario ?? ''}';
      var clientePortalId = cacheDedup[claveDedup];

      if (clientePortalId == null) {
        String? contrasenaCifrada;
        final contrasenaPlano = vigencia.portalContrasena;
        if (contrasenaPlano != null && contrasenaPlano.isNotEmpty) {
          contrasenaCifrada = await cipher.cifrar(contrasenaPlano);
        }

        final nuevo = await db.into(db.clientePortal).insertReturning(
              ClientePortalCompanion.insert(
                clienteId: servicio.clienteId,
                nombre: vigencia.portalNombre ?? 'Portal',
                tipo: TipoPortalCliente.otro.name,
                url: Value(vigencia.portalUrl),
                usuario: Value(vigencia.portalUsuario),
                contrasenaCifrada: Value(contrasenaCifrada),
                observaciones: Value(vigencia.portalObservaciones),
              ),
            );
        clientePortalId = nuevo.id;
        cacheDedup[claveDedup] = clientePortalId;
      }

      await (db.update(db.configuracionCobroVigencia)..where((t) => t.id.equals(vigencia.id))).write(
        ConfiguracionCobroVigenciaCompanion(clientePortalId: Value(clientePortalId)),
      );
    }

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violacionesFk.isNotEmpty) {
      throw StateError(
        'Migración a schemaVersion 52: foreign_key_check reportó '
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
        'Migración a schemaVersion 52: integrity_check reportó '
        'problemas: $resultadoIntegridad. Migración abortada.',
      );
    }
  });
}

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../app_database.dart';

/// Migración estructural de la Etapa 15 (`schemaVersion` 48 → 49,
/// ampliación "flujo posterior a la emisión"): reemplaza
/// `ConfiguracionCobroReglaEvento` (catálogo fijo de 3 eventos,
/// `tipoEvento` como identidad de fila) por `ConfiguracionCobroEtapa`
/// (colección dinámica — etapas de sistema o personalizadas, `id`
/// propio) y agrega `DocumentoPorEmitirHito` (tabla enteramente nueva,
/// snapshot de hitos por documento generado).
///
/// **Cada fila real ya capturada se preserva** — nunca se pierde
/// información histórica: por cada fila de `configuracion_cobro_regla_evento`
/// se crea una fila equivalente en `configuracion_cobro_etapa` con
/// `tipoSistema = tipoEvento` (los 3 valores del enum viejo son un
/// subconjunto exacto del nuevo), `orden` fijo según el orden implícito
/// que ya tenían (Emisión 0, Procesamiento 1, Pago esperado 2) y
/// `etapaReferenciaId` resuelto contra el `id` nuevo de la etapa
/// referenciada de la misma vigencia (`evento_referencia` viejo era un
/// `TipoEventoCobro`, nunca un id — se resuelve aquí en dos pasadas:
/// primero se genera un id nuevo por cada fila vieja, después se
/// insertan ya con la referencia correcta). Como el modelo viejo nunca
/// permitía que Emisión dependiera de nada, ninguna fila migrada activa
/// `referenciaCierrePeriodo` — el origen virtual "Cierre de periodo" es
/// una capacidad nueva, disponible desde cero para vigencias futuras.
///
/// **Verificación explícita de conteo** (mismo criterio que
/// `migrar_documento_por_emitir_uuid_v47.dart`): si el número de filas
/// copiadas no coincide con el original, la migración se aborta —
/// nunca continúa silenciosamente con datos parciales. `PRAGMA
/// table_info` (no aritmética de `from`/`to`) decide si existe algo que
/// migrar, mismo criterio ya documentado en
/// `migrar_equipos_telefonicos_v41.dart`.
Future<void> migrarConfiguracionCobroEtapaV49(AppDatabase db, Migrator m) async {
  await db.transaction(() async {
    // Tabla enteramente nueva, aditiva.
    await m.createTable(db.documentoPorEmitirHito);

    await m.createTable(db.configuracionCobroEtapa);

    final columnasAnteriores = await db.customSelect("PRAGMA table_info('configuracion_cobro_regla_evento')").get();
    if (columnasAnteriores.isNotEmpty) {
      final filas = await db.customSelect('SELECT * FROM configuracion_cobro_regla_evento').get();

      const ordenPorTipo = {'emision': 0, 'procesamiento': 1, 'pagoEsperado': 2};

      // Primera pasada: un id nuevo (uuid) por fila vieja, indexado
      // también por (vigencia, tipoEvento) — necesario para resolver
      // `evento_referencia` hacia el id real de la etapa referenciada
      // antes de insertar ninguna fila.
      final idNuevoPorViejo = <int, String>{};
      final idPorVigenciaYTipo = <String, String>{};
      for (final fila in filas) {
        final idViejo = fila.data['id'] as int;
        final vigenciaId = fila.data['configuracion_cobro_vigencia_id'] as String;
        final tipoEvento = fila.data['tipo_evento'] as String;
        final idNuevo = const Uuid().v4();
        idNuevoPorViejo[idViejo] = idNuevo;
        idPorVigenciaYTipo['$vigenciaId|$tipoEvento'] = idNuevo;
      }

      for (final fila in filas) {
        final idViejo = fila.data['id'] as int;
        final vigenciaId = fila.data['configuracion_cobro_vigencia_id'] as String;
        final tipoEvento = fila.data['tipo_evento'] as String;
        final eventoReferencia = fila.data['evento_referencia'] as String?;
        final etapaReferenciaId = eventoReferencia == null ? null : idPorVigenciaYTipo['$vigenciaId|$eventoReferencia'];

        await db.into(db.configuracionCobroEtapa).insert(
              ConfiguracionCobroEtapaCompanion.insert(
                id: idNuevoPorViejo[idViejo]!,
                configuracionCobroVigenciaId: vigenciaId,
                tipoSistema: Value(tipoEvento),
                orden: ordenPorTipo[tipoEvento] ?? 0,
                tipoRegla: Value(fila.data['tipo_regla'] as String?),
                mesRelativo: Value(fila.data['mes_relativo'] as String?),
                diaDelMes: Value(fila.data['dia_del_mes'] as int?),
                ordinalSemana: Value(fila.data['ordinal_semana'] as String?),
                diaSemana: Value(fila.data['dia_semana'] as String?),
                offsetDias: Value(fila.data['offset_dias_habiles'] as int?),
                etapaReferenciaId: Value(etapaReferenciaId),
              ),
            );
      }

      final conteoDespues = await db
          .customSelect('SELECT COUNT(*) AS n FROM configuracion_cobro_etapa')
          .map((r) => r.data['n'] as int)
          .getSingle();
      if (conteoDespues != filas.length) {
        throw StateError(
          'Migración de ConfiguracionCobroReglaEvento a ConfiguracionCobroEtapa (schemaVersion 49): se '
          'esperaban ${filas.length} filas copiadas, se encontraron $conteoDespues. Migración abortada.',
        );
      }

      await m.deleteTable('configuracion_cobro_regla_evento');
    }

    final violacionesFk = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violacionesFk.isNotEmpty) {
      throw StateError(
        'Migración a schemaVersion 49: foreign_key_check reportó '
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
        'Migración a schemaVersion 49: integrity_check reportó '
        'problemas: $resultadoIntegridad. Migración abortada.',
      );
    }
  });
}

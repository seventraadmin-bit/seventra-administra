// Etapa "Auditoría central completa y estándar único de trazabilidad".
//
// GAP P0-2 QUE CIERRA: tres historiales REALES existían en su tabla y
// nunca llegaban a Configuración → Auditoría — `TiempoExtraEvento`,
// `ArticuloUnidadEvento` y `BovedaCredencialEvento`. Nadie podía ver
// desde el panel central quién corrigió un tiempo extra, quién cambió
// el número de serie de una unidad, ni quién reveló una credencial.
//
// La integración LEE las tablas existentes. No crea una tabla genérica,
// no copia eventos y no escribe nada: `AuditoriaRepositoryImpl` sigue
// siendo estrictamente de solo lectura.

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/features/usuarios/data/repositories/auditoria_repository_impl.dart';
import 'package:riseg_one/features/usuarios/domain/usecases/buscar_auditoria_usecase.dart';
import 'package:riseg_one/features/usuarios/domain/usecases/destino_auditoria.dart';
import 'package:riseg_one/features/tiempos_extra/data/tables/tiempo_extra_table.dart';

/// El secreto real de la prueba. Si esta cadena aparece en CUALQUIER
/// parte de lo que produce la Auditoría, la prueba falla.
const _secretoReal = 'SUPER-SECRETO-abc123-NO-DEBE-SALIR';

void main() {
  late AppDatabase db;
  late BuscarAuditoriaUseCase buscar;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    buscar = BuscarAuditoriaUseCase(AuditoriaRepositoryImpl(db));

    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(
            id: const Value('marlon'),
            nombre: 'Marlon',
            nombreUsuario: 'marlon',
            passwordHash: 'x',
            esMaestro: const Value(true),
          ),
        );
  });

  tearDown(() => db.close());

  // ---------------------------------------------------------------
  // §2 — Tiempo Extra
  // ---------------------------------------------------------------

  /// Fixture mínimo REAL: las FK de `TiempoExtra` son `restrict`, así
  /// que el evento exige un tiempo extra que exista de verdad. Se
  /// siembra con companions directos (el turno y el tipo de servicio ya
  /// vienen del seed de `onCreate`) en vez de montar toda la cadena de
  /// casos de uso: lo que se prueba aquí es la PROYECCIÓN, no el alta.
  Future<String> sembrarTiempoExtra() async {
    final cliente = await db.into(db.cliente).insertReturning(
          ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'Sportium'),
        );
    final servicio = await db.into(db.servicio).insertReturning(
          ServicioCompanion.insert(
            codigo: 'SRV-000001',
            clienteId: cliente.id,
            nombre: 'Vigilancia Sportium',
            tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
            fechaInicio: DateTime(2026, 1, 1),
          ),
        );
    final empleado = await db.into(db.empleado).insertReturning(
          EmpleadoCompanion.insert(
            numeroEmpleado: 1,
            nombres: 'Javier',
            apellidoPaterno: 'Ruiz',
            sexo: 'masculino',
            fechaNacimiento: DateTime(1990, 1, 1),
            curp: 'RUSJ900101HDFXXX01',
            rfc: 'RUSJ900101AB1',
            nss: '12345678901',
            estadoCivil: 'soltero',
            fechaIngreso: DateTime(2025, 1, 1),
            aniosExperienciaSeguridad: 3,
          ),
        );
    final turno = await db.select(db.tipoModalidadTurno).get();
    final tex = await db.into(db.tiempoExtra).insertReturning(
          TiempoExtraCompanion.insert(
            folio: 'TEX-000012',
            fecha: DateTime(2026, 8, 1),
            servicioId: servicio.id,
            origenCobertura: Value(OrigenCoberturaTiempoExtra.ausenciaEmpleado.name),
            empleadoAusenteId: Value(empleado.id),
            motivoAusencia: const Value('falta'),
            turnoId: turno.first.id,
            montoTiempoExtra: 162000,
            formaPago: 'nomina',
          ),
        );
    return tex.id;
  }

  Future<void> eventoTiempoExtra({
    required String tiempoExtraId,
    required String tipoEvento,
    required DateTime fechaHora,
    String? observacion,
    String? estadoAnterior,
    String? estadoNuevo,
  }) {
    return db.into(db.tiempoExtraEvento).insert(
          TiempoExtraEventoCompanion.insert(
            tiempoExtraId: tiempoExtraId,
            fechaHora: fechaHora,
            tipoEvento: tipoEvento,
            observacion: Value(observacion),
            actorUsuarioId: const Value('marlon'),
            estadoAnterior: Value(estadoAnterior),
            estadoNuevo: Value(estadoNuevo),
          ),
        );
  }

  group('§12.A — Tiempo Extra: registrar → corregir → cancelar', () {
    test('los tres eventos aparecen en Auditoría central, en orden correcto', () async {
      final texId = await sembrarTiempoExtra();
      // Tal como los escribe `TiempoExtraRepositoryImpl`: el alta guarda
      // un JSON de resumen en `observacion`, la corrección y la
      // cancelación guardan el motivo real.
      await eventoTiempoExtra(
        tiempoExtraId: texId,
        tipoEvento: 'registrado',
        fechaHora: DateTime(2026, 8, 1, 9),
        observacion: '{"montoTotal":162000,"costosAdicionales":0}',
      );
      await eventoTiempoExtra(
        tiempoExtraId: texId,
        tipoEvento: 'corregido',
        fechaHora: DateTime(2026, 8, 2, 10),
        observacion: 'El turno real fue de 9 horas',
        estadoAnterior: '{"montoTotal":162000,"origen":"cuenta:BBVA"}',
        estadoNuevo: '{"montoTotal":180000,"origen":"tarjeta:Konfio"}',
      );
      await eventoTiempoExtra(
        tiempoExtraId: texId,
        tipoEvento: 'cancelado',
        fechaHora: DateTime(2026, 8, 3, 11),
        observacion: 'El empleado no se presentó',
      );

      final eventos = (await buscar.ejecutar(const FiltroAuditoria()))
          .where((e) => e.modulo == 'tiempoExtra')
          .toList();

      expect(eventos, hasLength(3), reason: 'hasta esta etapa NINGUNO llegaba a Auditoría central');
      // Orden: más reciente primero, igual que el resto de la pantalla.
      expect(eventos.map((e) => e.accion), ['cancelado', 'corregido', 'registrado']);
      expect(eventos.every((e) => e.actorUsuarioId == 'marlon'), isTrue);
      expect(eventos.every((e) => e.entidadEtiqueta == 'TEX-000012'), isTrue, reason: 'folio resuelto en lote');
    });

    test('el cambio financiero se presenta como campo: antes → después', () async {
      final texId = await sembrarTiempoExtra();
      await eventoTiempoExtra(
        tiempoExtraId: texId,
        tipoEvento: 'corregido',
        fechaHora: DateTime(2026, 8, 2),
        observacion: 'Factura real del turno',
        estadoAnterior: '{"montoTotal":162000}',
        estadoNuevo: '{"montoTotal":180000}',
      );

      final evento = (await buscar.ejecutar(const FiltroAuditoria(modulo: 'tiempoExtra'))).single;

      expect(evento.cambios, hasLength(1));
      expect(evento.cambios.single.campo, 'montoTotal');
      expect(evento.cambios.single.antes, '162000');
      expect(evento.cambios.single.despues, '180000');
      expect(evento.motivo, 'Factura real del turno');
    });

    test('el JSON de resumen del alta NO se muestra como si fuera un motivo', () async {
      final texId = await sembrarTiempoExtra();
      await eventoTiempoExtra(
        tiempoExtraId: texId,
        tipoEvento: 'registrado',
        fechaHora: DateTime(2026, 8, 1),
        observacion: '{"montoTotal":162000,"costosAdicionales":2}',
      );

      final evento = (await buscar.ejecutar(const FiltroAuditoria(modulo: 'tiempoExtra'))).single;

      expect(evento.motivo, isNull, reason: 'un alta no tiene motivo — y JSON crudo no es texto de motivo');
      expect(evento.detalleJson, contains('montoTotal'), reason: 'pero el dato no se pierde: va al detalle');
      expect(evento.cambios, isEmpty);
    });
  });

  // ---------------------------------------------------------------
  // §3 — Inventario / ArticuloUnidadEvento
  // ---------------------------------------------------------------

  Future<({String articuloId, String unidadId})> sembrarUnidad() async {
    final categoria = await db.into(db.categoriaArticulo).insertReturning(
          CategoriaArticuloCompanion.insert(nombre: 'Cómputo'),
        );
    final articulo = await db.into(db.articulo).insertReturning(
          ArticuloCompanion.insert(
            folio: 'ART-000007',
            nombre: 'Laptop Dell Latitude 5440',
            categoriaId: categoria.id,
            manejaSerie: const Value(true),
          ),
        );
    final unidad = await db.into(db.articuloUnidad).insertReturning(
          ArticuloUnidadCompanion.insert(
            articuloId: articulo.id,
            codigo: 'ART-000007-001',
            numeroSerie: 'SN-CORREGIDO-02',
          ),
        );
    return (articuloId: articulo.id, unidadId: unidad.id);
  }

  group('§12.B — Inventario: la unidad conserva campo/valorAnterior/valorNuevo', () {
    test('el evento aparece con su cambio real, sin pasar por JSON', () async {
      final ids = await sembrarUnidad();
      await db.into(db.articuloUnidadEvento).insert(
            ArticuloUnidadEventoCompanion.insert(
              unidadId: ids.unidadId,
              fechaHora: DateTime(2026, 8, 5),
              tipoEvento: 'correccionIdentidad',
              campo: 'numeroSerie',
              valorAnterior: const Value('SN-MAL-01'),
              valorNuevo: const Value('SN-CORREGIDO-02'),
              motivo: 'La etiqueta física no coincidía con la captura',
              actorUsuarioId: const Value('marlon'),
            ),
          );

      final evento = (await buscar.ejecutar(const FiltroAuditoria(accion: 'correccionIdentidad'))).single;

      expect(evento.modulo, 'inventario');
      expect(evento.motivo, 'La etiqueta física no coincidía con la captura');
      expect(evento.cambios, hasLength(1));
      expect(evento.cambios.single.campo, 'numeroSerie');
      expect(evento.cambios.single.antes, 'SN-MAL-01');
      expect(evento.cambios.single.despues, 'SN-CORREGIDO-02');
      expect(evento.detalleJson, isNull, reason: 'esta tabla no tiene JSON, y no se le inventa uno');
    });

    test('navega al ARTÍCULO, resuelto por id real desde la unidad', () async {
      final ids = await sembrarUnidad();
      await db.into(db.articuloUnidadEvento).insert(
            ArticuloUnidadEventoCompanion.insert(
              unidadId: ids.unidadId,
              fechaHora: DateTime(2026, 8, 5),
              tipoEvento: 'correccionIdentidad',
              campo: 'marca',
              valorNuevo: const Value('Dell'),
              motivo: 'Marca faltante',
            ),
          );

      final evento = (await buscar.ejecutar(const FiltroAuditoria(modulo: 'inventario'))).single;

      expect(evento.registroId, ids.unidadId, reason: 'el evento sigue siendo de la unidad');
      expect(evento.destinoId, ids.articuloId, reason: 'pero la ruta del expediente es por artículo');
      expect(destinoDeEvento(evento)!.ruta, '/inventario/articulos/${ids.articuloId}');
      expect(evento.entidadEtiqueta, 'SN-CORREGIDO-02');
    });
  });

  // ---------------------------------------------------------------
  // §4 y §11 — Bóveda: metadatos sí, secreto JAMÁS
  // ---------------------------------------------------------------

  Future<String> sembrarCredencial() async {
    final credencial = await db.into(db.bovedaCredencial).insertReturning(
          BovedaCredencialCompanion.insert(
            nombre: 'Portal SAT',
            tipo: 'portal',
            usuarioAcceso: const Value('RISEG950101ABC'),
            correo: const Value('contacto@riseg.mx'),
            // El secreto SÍ vive en la credencial, cifrado. Lo que esta
            // prueba fija es que nunca sale por Auditoría.
            secretoCifrado: const Value('aesgcm\$1\$aXY=\$$_secretoReal'),
          ),
        );
    return credencial.id;
  }

  Future<void> eventoBoveda(String credencialId, String tipoEvento, DateTime fechaHora) {
    return db.into(db.bovedaCredencialEvento).insert(
          BovedaCredencialEventoCompanion.insert(
            credencialId: credencialId,
            fechaHora: fechaHora,
            tipoEvento: tipoEvento,
            actorUsuarioId: const Value('marlon'),
          ),
        );
  }

  group('§12.C — Bóveda: crear → revelar → editar → baja → reactivar', () {
    test('los cinco eventos aparecen con actor, fecha y acción', () async {
      final id = await sembrarCredencial();
      await eventoBoveda(id, 'creada', DateTime(2026, 8, 1, 8));
      await eventoBoveda(id, 'secretoRevelado', DateTime(2026, 8, 2, 9));
      await eventoBoveda(id, 'editada', DateTime(2026, 8, 3, 10));
      await eventoBoveda(id, 'dadaDeBaja', DateTime(2026, 8, 4, 11));
      await eventoBoveda(id, 'reactivada', DateTime(2026, 8, 5, 12));

      final eventos = await buscar.ejecutar(const FiltroAuditoria(modulo: 'boveda'));

      expect(eventos, hasLength(5));
      expect(
        eventos.map((e) => e.accion),
        ['reactivada', 'dadaDeBaja', 'editada', 'secretoRevelado', 'creada'],
      );
      expect(eventos.every((e) => e.actorUsuarioId == 'marlon'), isTrue);
      expect(
        eventos.every((e) => e.entidadEtiqueta == 'Portal SAT'),
        isTrue,
        reason: 'se puede saber QUÉ credencial fue, sin revelar nada de ella',
      );
    });

    test('una revelación no tiene motivo, y no se le inventa uno', () async {
      final id = await sembrarCredencial();
      await eventoBoveda(id, 'secretoRevelado', DateTime(2026, 8, 2));

      final evento = (await buscar.ejecutar(const FiltroAuditoria(modulo: 'boveda'))).single;

      expect(evento.motivo, isNull, reason: 'revelar no exige motivo — "Sin motivo" sería un dato falso');
      expect(evento.cambios, isEmpty);
    });
  });

  group('§11 — PRIVACIDAD: el secreto nunca sale por Auditoría', () {
    test('ningún campo del evento contiene el secreto ni su forma cifrada', () async {
      final id = await sembrarCredencial();
      await eventoBoveda(id, 'secretoRevelado', DateTime(2026, 8, 2));
      await eventoBoveda(id, 'secretoCambiado', DateTime(2026, 8, 3));
      await eventoBoveda(id, 'secretoCopiado', DateTime(2026, 8, 4));

      final eventos = await buscar.ejecutar(const FiltroAuditoria(modulo: 'boveda'));

      for (final evento in eventos) {
        final serializado = [
          evento.accion,
          evento.registroId,
          evento.motivo ?? '',
          evento.detalleJson ?? '',
          evento.entidadEtiqueta ?? '',
          for (final c in evento.cambios) '${c.campo}${c.antes}${c.despues}',
        ].join('|');

        expect(serializado, isNot(contains(_secretoReal)), reason: 'el secreto en claro nunca puede aparecer');
        expect(serializado, isNot(contains('aesgcm')), reason: 'ni siquiera su envoltura cifrada');
        expect(evento.detalleJson, isNull, reason: 'Bóveda no aporta ningún blob que pudiera arrastrarlo');
        expect(evento.cambios, isEmpty);
      }
    });

    test('tampoco salen usuarioAcceso ni correo de la credencial', () async {
      final id = await sembrarCredencial();
      await eventoBoveda(id, 'editada', DateTime(2026, 8, 3));

      final evento = (await buscar.ejecutar(const FiltroAuditoria(modulo: 'boveda'))).single;

      expect(evento.entidadEtiqueta, 'Portal SAT');
      expect(evento.entidadEtiqueta, isNot(contains('RISEG950101ABC')));
      expect(evento.entidadEtiqueta, isNot(contains('@riseg.mx')));
    });

    test('buscar/filtrar en Auditoría no indexa el secreto por ninguna vía', () async {
      final id = await sembrarCredencial();
      await eventoBoveda(id, 'secretoRevelado', DateTime(2026, 8, 2));

      // Recorre TODO el resultado sin filtro de módulo: ninguna fila,
      // de ningún origen, arrastra el secreto.
      final todos = await buscar.ejecutar(const FiltroAuditoria());
      final volcado = todos
          .map((e) => '${e.modulo}|${e.accion}|${e.registroId}|${e.motivo}|${e.detalleJson}|${e.entidadEtiqueta}')
          .join('\n');

      expect(volcado, isNot(contains(_secretoReal)));
      expect(volcado, isNot(contains('aesgcm')));
    });
  });

  // ---------------------------------------------------------------
  // §6 — Navegación
  // ---------------------------------------------------------------

  group('§6 — navegación por id real', () {
    test('Tiempo Extra lleva a su detalle por id, nunca por folio', () async {
      final texId = await sembrarTiempoExtra();
      await eventoTiempoExtra(tiempoExtraId: texId, tipoEvento: 'cancelado', fechaHora: DateTime(2026, 8, 3));

      final evento = (await buscar.ejecutar(const FiltroAuditoria(modulo: 'tiempoExtra'))).single;
      final destino = destinoDeEvento(evento)!;

      expect(destino.ruta, '/personal/tiempos-extra/$texId');
      expect(destino.ruta, isNot(contains('TEX-000012')), reason: 'el folio nunca resuelve una ruta');
      expect(destino.exigeMaestro, isFalse);
    });

    test('Bóveda lleva a su pantalla y queda marcada como Maestro-only', () async {
      final id = await sembrarCredencial();
      await eventoBoveda(id, 'creada', DateTime(2026, 8, 1));

      final evento = (await buscar.ejecutar(const FiltroAuditoria(modulo: 'boveda'))).single;
      final destino = destinoDeEvento(evento)!;

      expect(destino.ruta, '/configuracion/boveda');
      expect(destino.exigeMaestro, isTrue, reason: 'auditoria.ver no puede abrir la Bóveda');
    });

    test('una eliminación física no navega: la entidad ya no existe', () async {
      await db.into(db.eliminacionFisicaEvento).insert(
            EliminacionFisicaEventoCompanion.insert(
              tipoEntidad: 'vehiculo',
              entidadIdOriginal: 'veh-borrado',
              fechaHora: DateTime(2026, 8, 6),
              motivo: 'Duplicado',
              snapshotJson: '{"codigo":"VEH-000009"}',
              actorUsuarioId: const Value('marlon'),
            ),
          );

      final evento = (await buscar.ejecutar(const FiltroAuditoria())).single;

      expect(evento.accion, 'eliminacionFisica:vehiculo');
      expect(destinoDeEvento(evento), isNull);
      expect(evento.detalleJson, contains('VEH-000009'), reason: '§13: el snapshot se conserva tal cual');
    });
  });

  // ---------------------------------------------------------------
  // §10 — Filtros
  // ---------------------------------------------------------------

  group('§10 — los tres módulos nuevos se pueden filtrar', () {
    test('filtrar por módulo aísla cada origen', () async {
      final texId = await sembrarTiempoExtra();
      final ids = await sembrarUnidad();
      final credencialId = await sembrarCredencial();
      await eventoTiempoExtra(tiempoExtraId: texId, tipoEvento: 'registrado', fechaHora: DateTime(2026, 8, 1));
      await db.into(db.articuloUnidadEvento).insert(
            ArticuloUnidadEventoCompanion.insert(
              unidadId: ids.unidadId,
              fechaHora: DateTime(2026, 8, 2),
              tipoEvento: 'correccionIdentidad',
              campo: 'marca',
              valorNuevo: const Value('Dell'),
              motivo: 'x',
            ),
          );
      await eventoBoveda(credencialId, 'creada', DateTime(2026, 8, 3));

      expect(await buscar.ejecutar(const FiltroAuditoria(modulo: 'tiempoExtra')), hasLength(1));
      expect(await buscar.ejecutar(const FiltroAuditoria(modulo: 'inventario')), hasLength(1));
      expect(await buscar.ejecutar(const FiltroAuditoria(modulo: 'boveda')), hasLength(1));
      expect(await buscar.ejecutar(const FiltroAuditoria()), hasLength(3));
    });

    test('los códigos solo-auditoría existen aparte del catálogo de permisos', () {
      // Si algún día alguien los agregara a `modulosPermiso`, crearía
      // permisos `tiempoExtra.ver`/`boveda.ver` que hoy NO existen.
      expect(modulosSoloAuditoria, containsAll(['tiempoExtra', 'boveda']));
    });

    test('filtrar por usuario y por fecha sigue funcionando sobre los orígenes nuevos', () async {
      final credencialId = await sembrarCredencial();
      await eventoBoveda(credencialId, 'creada', DateTime(2026, 8, 1));
      await eventoBoveda(credencialId, 'secretoRevelado', DateTime(2026, 9, 1));

      expect(
        await buscar.ejecutar(FiltroAuditoria(desde: DateTime(2026, 8, 15))),
        hasLength(1),
      );
      expect(await buscar.ejecutar(const FiltroAuditoria(actorUsuarioId: 'marlon')), hasLength(2));
      expect(await buscar.ejecutar(const FiltroAuditoria(actorUsuarioId: 'otro')), isEmpty);
    });
  });

  // ---------------------------------------------------------------
  // §8 — actor legacy
  // ---------------------------------------------------------------

  test('§8 — el agregador usa actorUsuarioId, nunca la columna actor legacy', () async {
    final ids = await sembrarUnidad();
    // `MovimientoInventario` es una de las 12 tablas con la columna
    // legacy `actor`, nunca poblada desde la 11D. Se le escribe un
    // valor a propósito: la Auditoría debe seguir leyendo
    // `actorUsuarioId` y nada más.
    await db.into(db.movimientoInventario).insert(
          MovimientoInventarioCompanion.insert(
            articuloId: ids.articuloId,
            tipoMovimiento: 'entrada',
            cantidad: 1,
            fecha: DateTime(2026, 8, 7),
            actor: const Value('TEXTO-LEGACY-QUE-NO-DEBE-USARSE'),
            actorUsuarioId: const Value('marlon'),
          ),
        );

    final evento = (await buscar.ejecutar(const FiltroAuditoria(modulo: 'inventario'))).single;

    expect(evento.actorUsuarioId, 'marlon');
    expect(evento.motivo, isNot(contains('LEGACY')));
  });

  // ---------------------------------------------------------------
  // §14 — sin N+1
  // ---------------------------------------------------------------

  test('§14 — 60 eventos de los 3 orígenes no disparan una consulta por fila', () async {
    final texId = await sembrarTiempoExtra();
    final ids = await sembrarUnidad();
    final credencialId = await sembrarCredencial();
    for (var i = 0; i < 20; i++) {
      await eventoTiempoExtra(
        tiempoExtraId: texId,
        tipoEvento: 'corregido',
        fechaHora: DateTime(2026, 8, 1).add(Duration(minutes: i)),
        observacion: 'ajuste $i',
      );
      await db.into(db.articuloUnidadEvento).insert(
            ArticuloUnidadEventoCompanion.insert(
              unidadId: ids.unidadId,
              fechaHora: DateTime(2026, 8, 2).add(Duration(minutes: i)),
              tipoEvento: 'correccionIdentidad',
              campo: 'marca',
              valorNuevo: Value('Dell $i'),
              motivo: 'x',
            ),
          );
      await eventoBoveda(credencialId, 'secretoRevelado', DateTime(2026, 8, 3).add(Duration(minutes: i)));
    }

    final antes = DateTime.now();
    final eventos = await buscar.ejecutar(const FiltroAuditoria());
    final duracion = DateTime.now().difference(antes);

    expect(eventos, hasLength(60));
    // Las 60 filas comparten 3 entidades: los lookups en lote las
    // resuelven con 3 consultas, no con 60. Si alguien introdujera un
    // lookup por fila, esto se dispararía muy por encima del umbral.
    expect(eventos.every((e) => e.entidadEtiqueta != null), isTrue);
    expect(
      duracion.inSeconds,
      lessThan(3),
      reason: 'una consulta por fila sobre 60 eventos tarda órdenes de magnitud más',
    );
  });
}

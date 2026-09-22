import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:riseg_one/core/auditoria/diff_evento.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';
import 'package:riseg_one/core/database/tables/direccion_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/ubicacion_table.dart';
import 'package:riseg_one/features/personal/domain/repositories/asignacion_servicio_repository.dart';

import '../tables/comercial_evento_table.dart';
import 'comercial_evento_writer.dart';
import '../../domain/repositories/servicio_repository.dart';
import '../../domain/shared/direccion_input.dart';
import '../../domain/usecases/eliminar_servicio_fisicamente_usecase.dart';
import 'ubicacion_repository_impl.dart';

/// **Nota de arquitectura (Etapa 5D):** este repositorio, de
/// `organizacion`, depende de `AsignacionServicioRepository`, del
/// dominio `personal` — la única forma de garantizar que el cierre de
/// las asignaciones vigentes ocurra en la *misma transacción* que el
/// cambio de estatus a `terminado` (Resolución explícita de Marlon:
/// "quiero evitar que después aparezcan empleados asignados a un
/// Servicio terminado"). Mismo criterio de composición ya usado con
/// `CuentaPorCobrarRepository` en `DocumentoPorEmitirRepositoryImpl`
/// (Etapa 4J.1) — la interfaz `ServicioRepository` (capa de dominio) no
/// sabe nada de `personal`, solo esta implementación.
class ServicioRepositoryImpl implements ServicioRepository {
  ServicioRepositoryImpl(this._db, this._asignacionServicioRepository);

  final AppDatabase _db;
  final AsignacionServicioRepository _asignacionServicioRepository;

  @override
  Future<ServicioData> crear({
    required String codigoServicio,
    required String clienteId,
    required String nombre,
    required String tipoServicioId,
    required DateTime fechaInicio,
    required String codigoUbicacionRaiz,
    DateTime? fechaTermino,
    String? observaciones,
  }) {
    return _db.transaction(() async {
      final servicio = await _db.into(_db.servicio).insertReturning(
            ServicioCompanion.insert(
              codigo: codigoServicio,
              clienteId: clienteId,
              nombre: nombre,
              tipoServicioId: tipoServicioId,
              fechaInicio: fechaInicio,
              fechaTermino: Value(fechaTermino),
              observaciones: Value(observaciones),
            ),
          );

      // Ancla estructural del árbol de Ubicación — se crea siempre,
      // exista o no todavía una Dirección operativa (Etapa 4F.1, punto 8
      // de la aprobación: "la Ubicación raíz es el ancla estructural del
      // árbol, no la Dirección").
      await _db.into(_db.ubicacion).insert(
            UbicacionCompanion.insert(
              codigo: codigoUbicacionRaiz,
              nombre: nombre,
              tipoUbicacion: TipoUbicacion.servicio.name,
              servicioId: Value(servicio.id),
            ),
          );

      return servicio;
    });
  }

  @override
  Future<ServicioData?> obtenerPorId(String id) {
    return (_db.select(_db.servicio)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  @override
  Future<List<ServicioListItem>> listar() async {
    // `leftOuterJoin` a Direccion (Etapa 16, evolución visual) — un
    // Servicio puede no tener ninguna Dirección operativa capturada
    // todavía (0 o 1, real 1:1 vía el `.unique()` de `servicioId`), así
    // que nunca puede ser un `innerJoin`. Una sola consulta, sin N+1:
    // el municipio/estado ya viven en `Direccion`, nunca duplicados.
    final query = _db.select(_db.servicio).join([
      innerJoin(_db.cliente, _db.cliente.id.equalsExp(_db.servicio.clienteId)),
      innerJoin(_db.tipoServicio, _db.tipoServicio.id.equalsExp(_db.servicio.tipoServicioId)),
      leftOuterJoin(
        _db.direccion,
        _db.direccion.servicioId.equalsExp(_db.servicio.id) &
            _db.direccion.tipoDireccion.equals(TipoDireccion.operativa.name) &
            _db.direccion.cicloVidaRegistro.equals(CicloVidaRegistro.activo.name),
      ),
    ]);

    final filas = await query.get();
    return [
      for (final fila in filas)
        ServicioListItem(
          servicio: fila.readTable(_db.servicio),
          clienteNombre: fila.readTable(_db.cliente).nombreComercial,
          tipoServicioNombre: fila.readTable(_db.tipoServicio).nombre,
          clienteLogoAttachmentId: fila.readTable(_db.cliente).logoAttachmentId,
          municipioAlcaldia: fila.readTableOrNull(_db.direccion)?.municipioAlcaldia,
          estado: fila.readTableOrNull(_db.direccion)?.estado,
        ),
    ];
  }

  @override
  Future<ServicioData> actualizar({
    required String id,
    required ServicioCompanion cambios,
    String? motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final anterior = await (_db.select(_db.servicio)..where((t) => t.id.equals(id))).getSingle();
      await (_db.update(_db.servicio)..where((t) => t.id.equals(id))).write(
        cambios.copyWith(updatedAt: Value(DateTime.now())),
      );
      final actualizado = await (_db.select(_db.servicio)..where((t) => t.id.equals(id))).getSingle();

      // Sólo los datos del Servicio EN SÍ. Precio, elementos, turno e
      // IVA no viven aquí: viven en su vigencia comercial, y su cambio
      // se registra allá — nunca se duplica el mismo hecho en dos
      // bitácoras.
      final diff = DiffEvento()
        ..anotar('nombre', anterior.nombre, actualizado.nombre)
        ..anotar('clienteId', anterior.clienteId, actualizado.clienteId)
        ..anotar('tipoServicioId', anterior.tipoServicioId, actualizado.tipoServicioId)
        ..anotar('fechaInicio', anterior.fechaInicio, actualizado.fechaInicio)
        ..anotar('fechaTermino', anterior.fechaTermino, actualizado.fechaTermino)
        ..anotar('entidadFiscalId', anterior.entidadFiscalId, actualizado.entidadFiscalId)
        ..anotar('observaciones', anterior.observaciones, actualizado.observaciones);
      if (diff.hayCambios) {
        await registrarEventoServicio(
          _db,
          servicioId: id,
          tipoEvento: TipoEventoServicio.corregido,
          estadoAnterior: diff.estadoAnteriorJson,
          estadoNuevo: diff.estadoNuevoJson,
          observacion: motivo,
          actorUsuarioId: actorUsuarioId,
        );
      }
      return actualizado;
    });
  }

  @override
  Future<ServicioData> cambiarEstatus({
    required String id,
    required EstatusServicio nuevo,
    DateTime? fechaTermino,
    String? motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final anterior = await (_db.select(_db.servicio)..where((t) => t.id.equals(id))).getSingle();
      await (_db.update(_db.servicio)..where((t) => t.id.equals(id))).write(
        ServicioCompanion(
          estatus: Value(nuevo.name),
          fechaTermino: Value(fechaTermino),
          updatedAt: Value(DateTime.now()),
        ),
      );
      final actualizado = await (_db.select(_db.servicio)..where((t) => t.id.equals(id))).getSingle();

      // Suspender o terminar un Servicio afecta directamente a la
      // cobranza: queda registrado con autor y motivo.
      final diff = DiffEvento()
        ..anotar('estatus', anterior.estatus, actualizado.estatus)
        ..anotar('fechaTermino', anterior.fechaTermino, actualizado.fechaTermino);
      if (diff.hayCambios) {
        await registrarEventoServicio(
          _db,
          servicioId: id,
          tipoEvento: TipoEventoServicio.estatusCambiado,
          estadoAnterior: diff.estadoAnteriorJson,
          estadoNuevo: diff.estadoNuevoJson,
          observacion: motivo,
          actorUsuarioId: actorUsuarioId,
        );
      }

      // Un Servicio suspendido conserva sus asignaciones vigentes (una
      // suspensión puede ser temporal, Resolución explícita de Marlon)
      // — solo `terminado` las cierra, y solo entonces, en la misma
      // transacción, con la fecha efectiva de término.
      if (nuevo == EstatusServicio.terminado && fechaTermino != null) {
        await _asignacionServicioRepository.cerrarTodasPorServicioTerminado(
          servicioId: id,
          fecha: fechaTermino,
          actorUsuarioId: actorUsuarioId,
        );
      }

      return actualizado;
    });
  }

  @override
  Future<bool> tieneDireccionOperativaActiva(String servicioId) async {
    final fila = await (_db.select(_db.direccion)
          ..where(
            (t) =>
                t.servicioId.equals(servicioId) &
                t.tipoDireccion.equals(TipoDireccion.operativa.name) &
                t.cicloVidaRegistro.equals(CicloVidaRegistro.activo.name),
          ))
        .getSingleOrNull();
    return fila != null;
  }

  @override
  Future<DireccionData?> obtenerDireccionOperativa(String servicioId) {
    return (_db.select(_db.direccion)
          ..where(
            (t) =>
                t.servicioId.equals(servicioId) &
                t.cicloVidaRegistro.equals(CicloVidaRegistro.activo.name),
          ))
        .getSingleOrNull();
  }

  /// Busca la Dirección operativa de este Servicio sin importar
  /// `cicloVidaRegistro` — `servicio_id` tiene un `.unique()` real en
  /// `Direccion` (1:1), así que solo puede existir una fila por Servicio
  /// en toda su historia (mismo patrón que
  /// `_buscarDomicilioDeEntidadFiscal` en Entidad fiscal).
  Future<DireccionData?> _buscarDireccionDeServicio(String servicioId) {
    return (_db.select(_db.direccion)..where((t) => t.servicioId.equals(servicioId))).getSingleOrNull();
  }

  @override
  Future<DireccionData?> guardarDireccionOperativa(String servicioId, DireccionInput? input) async {
    final existente = await _buscarDireccionDeServicio(servicioId);

    if (input == null) {
      // Sección vacía: si había una Dirección activa, se archiva — nunca
      // se borra físicamente la fila.
      if (existente != null && existente.cicloVidaRegistro == CicloVidaRegistro.activo.name) {
        await (_db.update(_db.direccion)..where((t) => t.id.equals(existente.id))).write(
          DireccionCompanion(
            cicloVidaRegistro: Value(CicloVidaRegistro.archivado.name),
            updatedAt: Value(DateTime.now()),
          ),
        );
      }
      return null;
    }

    final cambios = DireccionCompanion(
      cicloVidaRegistro: Value(CicloVidaRegistro.activo.name),
      calle: Value(input.calle),
      numeroExterior: Value(input.numeroExterior),
      numeroInterior: Value(input.numeroInterior),
      colonia: Value(input.colonia),
      municipioAlcaldia: Value(input.municipioAlcaldia),
      ciudadLocalidad: Value(input.ciudadLocalidad),
      estado: Value(input.estado),
      codigoPostal: Value(input.codigoPostal),
      pais: Value(input.pais),
      referencias: Value(input.referencias),
      updatedAt: Value(DateTime.now()),
    );

    if (existente != null) {
      // Reactiva (si venía archivada) y actualiza — nunca un segundo
      // `INSERT`, que violaría el `UNIQUE` real de `servicio_id`.
      final actualizada = existente.copyWithCompanion(cambios);
      await _db.update(_db.direccion).replace(actualizada);
      return actualizada;
    }

    return _db.into(_db.direccion).insertReturning(
          DireccionCompanion.insert(
            servicioId: Value(servicioId),
            tipoDireccion: TipoDireccion.operativa.name,
            calle: input.calle,
            numeroExterior: input.numeroExterior,
            numeroInterior: Value(input.numeroInterior),
            colonia: input.colonia,
            municipioAlcaldia: input.municipioAlcaldia,
            ciudadLocalidad: Value(input.ciudadLocalidad),
            estado: input.estado,
            codigoPostal: input.codigoPostal,
            pais: Value(input.pais),
            referencias: Value(input.referencias),
          ),
        );
  }

  @override
  Future<ServicioData> asignarEntidadFiscal({
    required String servicioId,
    required String? entidadFiscalId,
    String? motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final antes = await (_db.select(_db.servicio)..where((t) => t.id.equals(servicioId))).getSingle();
      await (_db.update(_db.servicio)..where((t) => t.id.equals(servicioId))).write(
        ServicioCompanion(entidadFiscalId: Value(entidadFiscalId), updatedAt: Value(DateTime.now())),
      );
      final despues = await (_db.select(_db.servicio)..where((t) => t.id.equals(servicioId))).getSingle();

      final diff = DiffEvento()..anotar('entidadFiscalId', antes.entidadFiscalId, despues.entidadFiscalId);
      if (diff.hayCambios) {
        // Un solo evento: el mismo hecho de vinculación carga actor,
        // diff y —cuando la regla lo exige— el motivo. Nunca se emite
        // un segundo evento sólo para justificar el cambio.
        await registrarEventoServicio(
          _db,
          servicioId: servicioId,
          tipoEvento: TipoEventoServicio.entidadFiscalAsignada,
          estadoAnterior: diff.estadoAnteriorJson,
          estadoNuevo: diff.estadoNuevoJson,
          observacion: motivo,
          actorUsuarioId: actorUsuarioId,
        );
      }
      return despues;
    });
  }

  @override
  Future<ServicioData> asignarResponsableCliente({
    required String servicioId,
    required String? contactoId,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final antes = await (_db.select(_db.servicio)..where((t) => t.id.equals(servicioId))).getSingle();
      await (_db.update(_db.servicio)..where((t) => t.id.equals(servicioId))).write(
        ServicioCompanion(responsableClienteContactoId: Value(contactoId), updatedAt: Value(DateTime.now())),
      );
      final despues = await (_db.select(_db.servicio)..where((t) => t.id.equals(servicioId))).getSingle();

      final diff = DiffEvento()..anotar('responsableClienteContactoId', antes.responsableClienteContactoId, despues.responsableClienteContactoId);
      if (diff.hayCambios) {
        await registrarEventoServicio(
          _db,
          servicioId: servicioId,
          tipoEvento: TipoEventoServicio.responsableClienteAsignado,
          estadoAnterior: diff.estadoAnteriorJson,
          estadoNuevo: diff.estadoNuevoJson,
          actorUsuarioId: actorUsuarioId,
        );
      }
      return despues;
    });
  }

  @override
  Future<ServicioData> asignarSucursalAdministrativa({
    required String servicioId,
    required String? sucursalId,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final antes = await (_db.select(_db.servicio)..where((t) => t.id.equals(servicioId))).getSingle();
      await (_db.update(_db.servicio)..where((t) => t.id.equals(servicioId))).write(
        ServicioCompanion(sucursalAdministrativaId: Value(sucursalId), updatedAt: Value(DateTime.now())),
      );
      final despues = await (_db.select(_db.servicio)..where((t) => t.id.equals(servicioId))).getSingle();

      final diff = DiffEvento()..anotar('sucursalAdministrativaId', antes.sucursalAdministrativaId, despues.sucursalAdministrativaId);
      if (diff.hayCambios) {
        await registrarEventoServicio(
          _db,
          servicioId: servicioId,
          tipoEvento: TipoEventoServicio.sucursalAdministrativaAsignada,
          estadoAnterior: diff.estadoAnteriorJson,
          estadoNuevo: diff.estadoNuevoJson,
          actorUsuarioId: actorUsuarioId,
        );
      }
      return despues;
    });
  }

  @override
  Future<ServicioData> guardarResponsableInterno({
    required String servicioId,
    required String? texto,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final antes = await (_db.select(_db.servicio)..where((t) => t.id.equals(servicioId))).getSingle();
      await (_db.update(_db.servicio)..where((t) => t.id.equals(servicioId))).write(
        ServicioCompanion(responsableInterno: Value(texto), updatedAt: Value(DateTime.now())),
      );
      final despues = await (_db.select(_db.servicio)..where((t) => t.id.equals(servicioId))).getSingle();

      final diff = DiffEvento()..anotar('responsableInterno', antes.responsableInterno, despues.responsableInterno);
      if (diff.hayCambios) {
        await registrarEventoServicio(
          _db,
          servicioId: servicioId,
          tipoEvento: TipoEventoServicio.responsableInternoActualizado,
          estadoAnterior: diff.estadoAnteriorJson,
          estadoNuevo: diff.estadoNuevoJson,
          actorUsuarioId: actorUsuarioId,
        );
      }
      return despues;
    });
  }

  /// Eliminación física extraordinaria (Etapa 15, mismo patrón que la
  /// Etapa 11D) — 17 tablas dependen realmente de `Servicio` (Personal,
  /// Nómina, Comercial, Cobro, Telefonía, Vehículos, Inventario,
  /// Finanzas, Agenda), pero igual que `crear` inserta automáticamente
  /// un nodo raíz de `Ubicacion` (ancla del árbol) en la misma
  /// transacción, esa Ubicación por sí sola no cuenta como dependencia
  /// real — mismo criterio y misma verificación (por *forma* del
  /// árbol: raíz con a lo más un hijo sin hijos propios) ya aplicado en
  /// `SucursalRepositoryImpl.eliminarFisicamente`. Todo — validación,
  /// snapshot, registro de auditoría y `DELETE` — ocurre en una sola
  /// transacción; nunca `CASCADE`.
  @override
  Future<EliminarServicioFisicamenteResultado> eliminarFisicamente({
    required String servicioId,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final servicio = await (_db.select(_db.servicio)..where((t) => t.id.equals(servicioId))).getSingleOrNull();
      if (servicio == null) return EliminarServicioFisicamenteNoExiste();

      final asignacionesPersonal =
          await (_db.select(_db.asignacionServicio)..where((t) => t.servicioId.equals(servicioId))).get();
      if (asignacionesPersonal.isNotEmpty) {
        return EliminarServicioFisicamenteTieneDependencias(
          'Tiene ${asignacionesPersonal.length} asignación(es) de personal registrada(s).',
        );
      }

      final lineasComerciales =
          await (_db.select(_db.servicioLineaComercial)..where((t) => t.servicioId.equals(servicioId))).get();
      if (lineasComerciales.isNotEmpty) {
        return EliminarServicioFisicamenteTieneDependencias(
          'Tiene ${lineasComerciales.length} línea(s) de configuración comercial registrada(s).',
        );
      }

      final configuracionesCobro =
          await (_db.select(_db.configuracionCobro)..where((t) => t.servicioId.equals(servicioId))).get();
      if (configuracionesCobro.isNotEmpty) {
        return EliminarServicioFisicamenteTieneDependencias('Tiene configuración de cobro registrada.');
      }

      final fichasTecnicas =
          await (_db.select(_db.fichaTecnicaEmpleado)..where((t) => t.servicioId.equals(servicioId))).get();
      if (fichasTecnicas.isNotEmpty) {
        return EliminarServicioFisicamenteTieneDependencias(
          'Tiene ${fichasTecnicas.length} ficha(s) técnica(s) registrada(s).',
        );
      }

      final nominaEmpleado =
          await (_db.select(_db.nominaEmpleado)..where((t) => t.servicioId.equals(servicioId))).get();
      if (nominaEmpleado.isNotEmpty) {
        return EliminarServicioFisicamenteTieneDependencias(
          'Tiene ${nominaEmpleado.length} registro(s) de nómina registrado(s).',
        );
      }

      final nominaTramos =
          await (_db.select(_db.nominaEmpleadoTramo)..where((t) => t.servicioId.equals(servicioId))).get();
      if (nominaTramos.isNotEmpty) {
        return EliminarServicioFisicamenteTieneDependencias(
          'Tiene ${nominaTramos.length} tramo(s) de nómina registrado(s).',
        );
      }

      final lineasTelefonicas =
          await (_db.select(_db.asignacionLineaTelefonica)..where((t) => t.servicioId.equals(servicioId))).get();
      if (lineasTelefonicas.isNotEmpty) {
        return EliminarServicioFisicamenteTieneDependencias(
          'Tiene ${lineasTelefonicas.length} línea(s) telefónica(s) asignada(s).',
        );
      }

      final vehiculosAsignados =
          await (_db.select(_db.asignacionVehiculo)..where((t) => t.servicioId.equals(servicioId))).get();
      if (vehiculosAsignados.isNotEmpty) {
        return EliminarServicioFisicamenteTieneDependencias(
          'Tiene ${vehiculosAsignados.length} vehículo(s) asignado(s).',
        );
      }

      final inventarioAsignado =
          await (_db.select(_db.asignacion)..where((t) => t.servicioId.equals(servicioId))).get();
      if (inventarioAsignado.isNotEmpty) {
        return EliminarServicioFisicamenteTieneDependencias(
          'Tiene ${inventarioAsignado.length} artículo(s) de inventario asignado(s).',
        );
      }

      final ingresos = await (_db.select(_db.ingreso)..where((t) => t.servicioId.equals(servicioId))).get();
      if (ingresos.isNotEmpty) {
        return EliminarServicioFisicamenteTieneDependencias('Tiene ${ingresos.length} ingreso(s) registrado(s).');
      }

      final egresos = await (_db.select(_db.egreso)..where((t) => t.servicioId.equals(servicioId))).get();
      if (egresos.isNotEmpty) {
        return EliminarServicioFisicamenteTieneDependencias('Tiene ${egresos.length} egreso(s) registrado(s).');
      }

      final documentosServicio =
          await (_db.select(_db.documentoPorEmitirServicio)..where((t) => t.servicioId.equals(servicioId))).get();
      if (documentosServicio.isNotEmpty) {
        return EliminarServicioFisicamenteTieneDependencias(
          'Tiene ${documentosServicio.length} documento(s) por emitir registrado(s).',
        );
      }

      final documentosConfiguracion = await (_db.select(_db.documentoPorEmitirConfiguracion)
            ..where((t) => t.servicioId.equals(servicioId)))
          .get();
      if (documentosConfiguracion.isNotEmpty) {
        return EliminarServicioFisicamenteTieneDependencias(
          'Tiene ${documentosConfiguracion.length} configuración(es) de agenda registrada(s).',
        );
      }

      final documentosLinea =
          await (_db.select(_db.documentoPorEmitirLinea)..where((t) => t.servicioId.equals(servicioId))).get();
      if (documentosLinea.isNotEmpty) {
        return EliminarServicioFisicamenteTieneDependencias(
          'Tiene ${documentosLinea.length} línea(s) de documento por emitir registrada(s).',
        );
      }

      final direcciones = await (_db.select(_db.direccion)..where((t) => t.servicioId.equals(servicioId))).get();
      if (direcciones.isNotEmpty) {
        return EliminarServicioFisicamenteTieneDependencias(
          'Tiene ${direcciones.length} dirección(es) registrada(s).',
        );
      }

      final horarios = await (_db.select(_db.horario)..where((t) => t.servicioId.equals(servicioId))).get();
      if (horarios.isNotEmpty) {
        return EliminarServicioFisicamenteTieneDependencias('Tiene ${horarios.length} horario(s) registrado(s).');
      }

      // A diferencia de Sucursal (raíz + Almacén General), `crear` de
      // Servicio solo inserta la raíz — sin hijo automático. Si tiene
      // algún hijo, alguien lo agregó manualmente (real, no
      // estructural): bloquea, igual que cualquier otra dependencia.
      final ubicacionRepo = UbicacionRepositoryImpl(_db);
      final raizUbicacion = await ubicacionRepo.obtenerRaizDeServicio(servicioId);
      if (raizUbicacion != null) {
        final hijosDeRaiz = await ubicacionRepo.obtenerHijos(raizUbicacion.id);
        if (hijosDeRaiz.isNotEmpty) {
          return EliminarServicioFisicamenteTieneDependencias('El Servicio tiene ubicaciones adicionales registradas.');
        }
      }

      await _db.into(_db.eliminacionFisicaEvento).insert(
            EliminacionFisicaEventoCompanion.insert(
              tipoEntidad: 'servicio',
              entidadIdOriginal: servicioId,
              fechaHora: DateTime.now(),
              motivo: motivo,
              snapshotJson: jsonEncode({
                'servicio': servicio.toJson(),
                if (raizUbicacion != null) 'ubicacionesEliminadas': [raizUbicacion.toJson()],
              }),
              actorUsuarioId: Value(actorUsuarioId),
            ),
          );

      // Sin CASCADE: se borra explícitamente antes que el Servicio (FK
      // `restrict` de `servicioId`).
      if (raizUbicacion != null) {
        await (_db.delete(_db.ubicacion)..where((t) => t.id.equals(raizUbicacion.id))).go();
      }
      await (_db.delete(_db.servicio)..where((t) => t.id.equals(servicioId))).go();

      return EliminarServicioFisicamenteExitoso();
    });
  }
}

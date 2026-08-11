import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';
import 'package:riseg_one/core/database/tables/direccion_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/sucursal_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/ubicacion_table.dart';

import '../../domain/repositories/sucursal_repository.dart';
import '../../domain/shared/direccion_input.dart';
import '../../domain/shared/horario_input.dart';
import '../../domain/usecases/eliminar_sucursal_fisicamente_usecase.dart';

class SucursalRepositoryImpl implements SucursalRepository {
  SucursalRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Future<SucursalData> crear({
    required String codigoSucursal,
    required String nombre,
    required String tipoSucursalId,
    required String codigoUbicacionRaiz,
    required String codigoAlmacenGeneral,
  }) {
    return _db.transaction(() async {
      final sucursal = await _db.into(_db.sucursal).insertReturning(
            SucursalCompanion.insert(
              codigo: codigoSucursal,
              nombre: nombre,
              tipoSucursalId: tipoSucursalId,
            ),
          );

      final raiz = await _db.into(_db.ubicacion).insertReturning(
            UbicacionCompanion.insert(
              codigo: codigoUbicacionRaiz,
              nombre: nombre,
              tipoUbicacion: TipoUbicacion.sucursal.name,
              sucursalId: Value(sucursal.id),
            ),
          );

      await _db.into(_db.ubicacion).insert(
            UbicacionCompanion.insert(
              codigo: codigoAlmacenGeneral,
              nombre: 'Almacén General',
              tipoUbicacion: TipoUbicacion.almacen.name,
              parentId: Value(raiz.id),
            ),
          );

      return sucursal;
    });
  }

  @override
  Future<SucursalData?> obtenerPorId(String id) {
    return (_db.select(_db.sucursal)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  @override
  Future<List<SucursalData>> listarActivas() {
    return (_db.select(_db.sucursal)
          ..where((t) => t.cicloVidaRegistro.equals(CicloVidaRegistro.activo.name)))
        .get();
  }

  @override
  Future<SucursalData> cambiarEstadoOperativo({
    required String sucursalId,
    required EstadoOperativoSucursal nuevo,
  }) async {
    await (_db.update(_db.sucursal)..where((t) => t.id.equals(sucursalId))).write(
      SucursalCompanion(estadoOperativo: Value(nuevo.name), updatedAt: Value(DateTime.now())),
    );
    return (_db.select(_db.sucursal)..where((t) => t.id.equals(sucursalId))).getSingle();
  }

  @override
  Future<DireccionData?> obtenerDireccionPrincipal(String sucursalId) {
    return (_db.select(_db.direccion)
          ..where(
            (t) =>
                t.sucursalId.equals(sucursalId) &
                t.cicloVidaRegistro.equals(CicloVidaRegistro.activo.name),
          ))
        .getSingleOrNull();
  }

  Future<HorarioData?> _obtenerHorarioActivo(String sucursalId) {
    return (_db.select(_db.horario)
          ..where(
            (t) =>
                t.sucursalId.equals(sucursalId) &
                t.cicloVidaRegistro.equals(CicloVidaRegistro.activo.name),
          ))
        .getSingleOrNull();
  }

  @override
  Future<List<HorarioDetalleData>?> obtenerHorario(String sucursalId) async {
    final horario = await _obtenerHorarioActivo(sucursalId);
    if (horario == null) return null;

    return (_db.select(_db.horarioDetalle)
          ..where((t) => t.horarioId.equals(horario.id))
          ..orderBy([(t) => OrderingTerm.asc(t.diaSemana)]))
        .get();
  }

  @override
  Future<SucursalExpedienteRaw> guardarExpediente({
    required String sucursalId,
    required SucursalCompanion datosGenerales,
    required DireccionInput? direccionPrincipal,
    required HorarioSemanalInput? horario,
  }) {
    return _db.transaction(() async {
      await (_db.update(_db.sucursal)..where((t) => t.id.equals(sucursalId))).write(
        datosGenerales.copyWith(updatedAt: Value(DateTime.now())),
      );
      final sucursalActualizada =
          await (_db.select(_db.sucursal)..where((t) => t.id.equals(sucursalId))).getSingle();

      final direccionResultante = await _guardarDireccionPrincipal(sucursalId, direccionPrincipal);
      final horarioResultante = await _guardarHorario(sucursalId, horario);

      return SucursalExpedienteRaw(
        sucursal: sucursalActualizada,
        direccionPrincipal: direccionResultante,
        horario: horarioResultante,
      );
    });
  }

  /// Busca la fila de Dirección de esta Sucursal sin importar
  /// `cicloVidaRegistro` — `sucursalId` tiene un `.unique()` real en la
  /// tabla (no condicionado a estar activa), así que solo puede existir
  /// una fila por Sucursal en toda su historia. Sin esto, recapturar una
  /// dirección después de haberla archivado intentaría un `INSERT` que
  /// choca contra esa fila archivada (mismo bug real ya corregido en
  /// `EmpresaRepositoryImpl`).
  Future<DireccionData?> _buscarDireccionDeSucursal(String sucursalId) {
    return (_db.select(_db.direccion)..where((t) => t.sucursalId.equals(sucursalId))).getSingleOrNull();
  }

  Future<DireccionData?> _guardarDireccionPrincipal(String sucursalId, DireccionInput? input) async {
    final existente = await _buscarDireccionDeSucursal(sucursalId);

    if (input == null) {
      // Sección vacía: si había una dirección activa, se archiva — nunca
      // se borra físicamente la fila (mismo patrón que Empresa en 4B).
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
      // `INSERT`, que chocaría con el `.unique()` de `sucursalId`.
      final actualizada = existente.copyWithCompanion(cambios);
      await _db.update(_db.direccion).replace(actualizada);
      return actualizada;
    }

    return _db.into(_db.direccion).insertReturning(
          DireccionCompanion.insert(
            sucursalId: Value(sucursalId),
            tipoDireccion: TipoDireccion.administrativa.name,
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

  /// Busca el encabezado de Horario de esta Sucursal sin importar
  /// `cicloVidaRegistro` — `sucursalId` tiene un `.unique()` real en
  /// `Horario`, igual que en `Direccion` (ver `_buscarDireccionDeSucursal`).
  Future<HorarioData?> _buscarHorarioDeSucursal(String sucursalId) {
    return (_db.select(_db.horario)..where((t) => t.sucursalId.equals(sucursalId))).getSingleOrNull();
  }

  Future<List<HorarioDetalleData>?> _guardarHorario(String sucursalId, HorarioSemanalInput? input) async {
    final existente = await _buscarHorarioDeSucursal(sucursalId);

    if (input == null) {
      // Sin ningún día abierto: si había un Horario activo, se archiva —
      // nunca se borra físicamente el encabezado.
      if (existente != null && existente.cicloVidaRegistro == CicloVidaRegistro.activo.name) {
        await (_db.update(_db.horario)..where((t) => t.id.equals(existente.id))).write(
          HorarioCompanion(
            cicloVidaRegistro: Value(CicloVidaRegistro.archivado.name),
            updatedAt: Value(DateTime.now()),
          ),
        );
      }
      return null;
    }

    final HorarioData horarioHeader;
    if (existente != null) {
      // Reactiva (si venía archivado) y actualiza — nunca un segundo
      // `INSERT`, que chocaría con el `.unique()` de `sucursalId`.
      horarioHeader = existente;
      await (_db.update(_db.horario)..where((t) => t.id.equals(existente.id))).write(
        HorarioCompanion(
          cicloVidaRegistro: Value(CicloVidaRegistro.activo.name),
          updatedAt: Value(DateTime.now()),
        ),
      );
    } else {
      horarioHeader = await _db.into(_db.horario).insertReturning(
            HorarioCompanion.insert(sucursalId: Value(sucursalId)),
          );
    }

    // Los 7 renglones siempre se reemplazan completos — no tienen
    // identidad propia fuera de "el renglón del día X de este Horario",
    // así que no hace falta (ni tiene sentido) archivarlos uno a uno: se
    // borran y se vuelven a insertar dentro de la misma transacción.
    await (_db.delete(_db.horarioDetalle)..where((t) => t.horarioId.equals(horarioHeader.id))).go();

    final renglones = <HorarioDetalleData>[];
    for (final dia in input.dias) {
      final renglon = await _db.into(_db.horarioDetalle).insertReturning(
            HorarioDetalleCompanion.insert(
              horarioId: horarioHeader.id,
              diaSemana: dia.diaSemana,
              horaInicio: dia.horaInicioMinutos ?? 0,
              horaFin: dia.horaFinMinutos ?? 0,
              cruzaMedianoche: Value(dia.cruzaMedianoche),
              activo: Value(dia.abierto),
            ),
          );
      renglones.add(renglon);
    }
    renglones.sort((a, b) => a.diaSemana.compareTo(b.diaSemana));
    return renglones;
  }

  /// Eliminación física extraordinaria (Etapa 11D) — condiciones
  /// aprobadas: elegible solo si ninguna fila de `Servicio`
  /// (`sucursalAdministrativaId`), `Ubicacion` (`sucursalId`) ni
  /// `Empleado` (`sucursalId`) referencia esta Sucursal. **Chequeos
  /// adicionales descubiertos durante la verificación del grafo de FK
  /// real** (no en la lista aprobada original, agregados por
  /// integridad): `Ingreso.sucursalId`/`Egreso.sucursalId` (movimientos
  /// financieros) y `Direccion.sucursalId`/`Horario.sucursalId`/
  /// `MedioContacto.sucursalId` (las tres declaran su FK como SQL
  /// crudo con `ON DELETE RESTRICT` en vez de `.references()` tipado —
  /// ver el doc comment de `Direccion` — así que no aparecen en una
  /// búsqueda superficial de `references(Sucursal,` pero son
  /// restricciones reales a nivel de base de datos). Nota: toda
  /// Sucursal creada por el flujo normal (`crear`) ya tiene
  /// exactamente una fila raíz en `Ubicacion` con `sucursalId` propio
  /// (ver ese método) — en la práctica esto bloquea la eliminación
  /// física de cualquier Sucursal que haya pasado por el alta normal,
  /// consistente con la condición tal como fue aprobada. Todo —
  /// validación, snapshot, registro de auditoría y `DELETE` — ocurre en
  /// una sola transacción; nunca `CASCADE` sobre ninguna de esas
  /// tablas.
  @override
  Future<EliminarSucursalFisicamenteResultado> eliminarFisicamente({
    required String sucursalId,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final sucursal = await (_db.select(_db.sucursal)..where((t) => t.id.equals(sucursalId))).getSingleOrNull();
      if (sucursal == null) return EliminarSucursalFisicamenteNoExiste();

      final servicios =
          await (_db.select(_db.servicio)..where((t) => t.sucursalAdministrativaId.equals(sucursalId))).get();
      if (servicios.isNotEmpty) {
        return EliminarSucursalFisicamenteTieneDependencias(
          'Tiene ${servicios.length} servicio(s) registrado(s).',
        );
      }

      final ubicaciones = await (_db.select(_db.ubicacion)..where((t) => t.sucursalId.equals(sucursalId))).get();
      if (ubicaciones.isNotEmpty) {
        return EliminarSucursalFisicamenteTieneDependencias(
          'Tiene ${ubicaciones.length} ubicación(es) registrada(s).',
        );
      }

      final empleados = await (_db.select(_db.empleado)..where((t) => t.sucursalId.equals(sucursalId))).get();
      if (empleados.isNotEmpty) {
        return EliminarSucursalFisicamenteTieneDependencias(
          'Tiene ${empleados.length} empleado(s) registrado(s).',
        );
      }

      final ingresos = await (_db.select(_db.ingreso)..where((t) => t.sucursalId.equals(sucursalId))).get();
      if (ingresos.isNotEmpty) {
        return EliminarSucursalFisicamenteTieneDependencias('Tiene ${ingresos.length} ingreso(s) registrado(s).');
      }

      final egresos = await (_db.select(_db.egreso)..where((t) => t.sucursalId.equals(sucursalId))).get();
      if (egresos.isNotEmpty) {
        return EliminarSucursalFisicamenteTieneDependencias('Tiene ${egresos.length} egreso(s) registrado(s).');
      }

      final direcciones = await (_db.select(_db.direccion)..where((t) => t.sucursalId.equals(sucursalId))).get();
      if (direcciones.isNotEmpty) {
        return EliminarSucursalFisicamenteTieneDependencias(
          'Tiene ${direcciones.length} dirección(es) registrada(s).',
        );
      }

      final horarios = await (_db.select(_db.horario)..where((t) => t.sucursalId.equals(sucursalId))).get();
      if (horarios.isNotEmpty) {
        return EliminarSucursalFisicamenteTieneDependencias(
          'Tiene ${horarios.length} horario(s) registrado(s).',
        );
      }

      final mediosContacto =
          await (_db.select(_db.medioContacto)..where((t) => t.sucursalId.equals(sucursalId))).get();
      if (mediosContacto.isNotEmpty) {
        return EliminarSucursalFisicamenteTieneDependencias(
          'Tiene ${mediosContacto.length} medio(s) de contacto registrado(s).',
        );
      }

      await _db.into(_db.eliminacionFisicaEvento).insert(
            EliminacionFisicaEventoCompanion.insert(
              tipoEntidad: 'sucursal',
              entidadIdOriginal: sucursalId,
              fechaHora: DateTime.now(),
              motivo: motivo,
              snapshotJson: jsonEncode(sucursal.toJson()),
              actorUsuarioId: Value(actorUsuarioId),
            ),
          );
      await (_db.delete(_db.sucursal)..where((t) => t.id.equals(sucursalId))).go();

      return EliminarSucursalFisicamenteExitoso();
    });
  }
}

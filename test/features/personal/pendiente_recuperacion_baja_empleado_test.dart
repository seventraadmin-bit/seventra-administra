// Pendientes de recuperación tras una baja — lo que sigue siendo cierto
// después del ajuste de cierre de la conciliación.
//
// ESTE ARCHIVO CAMBIÓ DE SENTIDO. Cubría el comportamiento de la v82:
// dar de baja marcaba TODOS los bienes como pendientes automáticamente.
// Ese automatismo se retiró — era una puerta trasera al flujo de
// conciliación y dejaba los bienes en un limbo que nadie había
// decidido. La prueba de que ya no existe vive en
// `bypass_y_destinos_fisicos_test.dart`.
//
// Lo que sigue siendo cierto, y se prueba aquí, es qué ocurre DESPUÉS de
// una conciliación real: el pendiente no está disponible, se devuelve
// más tarde con su fecha propia, un reingreso no lo revive, y la
// trazabilidad no puede borrarse.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/descuentos_personal/data/repositories/descuento_programado_repository_impl.dart';
import 'package:riseg_one/features/descuentos_personal/domain/usecases/registrar_descuento_programado_usecase.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/asignacion_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/tables/articulo_unidad_table.dart';
import 'package:riseg_one/features/inventario/data/tables/asignacion_table.dart';
import 'package:riseg_one/features/inventario/data/tables/movimiento_inventario_table.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/conciliacion_baja_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';
import 'package:riseg_one/features/personal/data/tables/conciliacion_baja_table.dart';
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart';
import 'package:riseg_one/features/personal/domain/usecases/conciliar_baja_empleado_usecase.dart';
import 'package:riseg_one/features/personal/domain/usecases/eliminar_empleado_fisicamente_usecase.dart';
import 'package:riseg_one/features/personal/domain/usecases/empleado_validator.dart';
import 'package:riseg_one/features/personal/domain/usecases/registrar_baja_laboral_usecase.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/asignacion_vehiculo_repository_impl.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/vehiculo_kilometraje_repository_impl.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/vehiculo_repository_impl.dart';
import 'package:riseg_one/features/vehiculos/data/tables/asignacion_vehiculo_table.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/asignar_vehiculo_usecase.dart';

void main() {
  late AppDatabase db;
  late AsignacionRepositoryImpl inventarioRepo;
  late AsignacionVehiculoRepositoryImpl vehiculoAsignacionRepo;
  late VehiculoRepositoryImpl vehiculoRepo;
  late EmpleadoRepositoryImpl empleadoRepo;
  late ConciliarBajaEmpleadoUseCase conciliar;
  late String actorId;
  var consecutivo = 0;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    inventarioRepo = AsignacionRepositoryImpl(db);
    vehiculoAsignacionRepo = AsignacionVehiculoRepositoryImpl(db);
    vehiculoRepo = VehiculoRepositoryImpl(db, vehiculoAsignacionRepo);
    empleadoRepo = EmpleadoRepositoryImpl(db, AsignacionServicioRepositoryImpl(db));

    final codigoSecuencia = CodigoSecuenciaService(db);
    conciliar = ConciliarBajaEmpleadoUseCase(
      empleadoRepo,
      RegistrarBajaLaboralUseCase(
        empleadoRepo,
        const EmpleadoValidator(),
        inventarioRepo,
        vehiculoAsignacionRepo,
      ),
      inventarioRepo,
      vehiculoAsignacionRepo,
      ConciliacionBajaRepositoryImpl(db),
      RegistrarDescuentoProgramadoUseCase(
        DescuentoProgramadoRepositoryImpl(db, EgresoRepositoryImpl(db), codigoSecuencia),
        empleadoRepo,
        GenerarCodigoUseCase(codigoSecuencia),
      ),
    );

    final actor = await db.into(db.usuario).insertReturning(
          UsuarioCompanion.insert(
            nombre: 'MARLON',
            nombreUsuario: 'marlon',
            passwordHash: r'pbkdf2$1$c2FsdA==$aGFzaA==',
            esMaestro: const Value(true),
          ),
        );
    actorId = actor.id;
  });

  tearDown(() => db.close());

  Future<EmpleadoData> crearEmpleado({String nombres = 'Juan'}) async {
    final n = (++consecutivo).toString().padLeft(2, '0');
    return db.into(db.empleado).insertReturning(
          EmpleadoCompanion.insert(
            numeroEmpleado: consecutivo,
            nombres: nombres,
            apellidoPaterno: 'Pérez',
            sexo: 'masculino',
            fechaNacimiento: DateTime(1990, 1, 1),
            curp: 'PEXJ900101HDFXXX$n',
            rfc: 'PEXJ900101A$n',
            nss: '123456789$n',
            estadoCivil: 'soltero',
            fechaIngreso: DateTime(2024, 1, 1),
            aniosExperienciaSeguridad: 3,
          ),
        );
  }

  Future<({String articuloId, String unidadId})> crearUnidad(String nombre, String serie) async {
    final categoria = await db.into(db.categoriaArticulo).insertReturning(
          CategoriaArticuloCompanion.insert(nombre: 'Cat $serie'),
        );
    final articulo = await ArticuloRepositoryImpl(db).crear(
      folio: 'ART-$serie',
      categoriaId: categoria.id,
      nombre: nombre,
      manejaVariante: false,
      manejaSerie: true,
    );
    final unidad = await db.into(db.articuloUnidad).insertReturning(
          ArticuloUnidadCompanion.insert(articuloId: articulo.id, codigo: 'UNI-$serie', numeroSerie: serie),
        );
    await db.into(db.movimientoInventario).insert(
          MovimientoInventarioCompanion.insert(
            articuloId: articulo.id,
            unidadId: Value(unidad.id),
            tipoMovimiento: TipoMovimientoInventario.entrada.name,
            cantidad: 1,
            fecha: DateTime(2025, 1, 1),
          ),
        );
    return (articuloId: articulo.id, unidadId: unidad.id);
  }

  Future<AsignacionData> asignar(({String articuloId, String unidadId}) bien, String empleadoId) {
    return inventarioRepo.crear(
      articuloId: bien.articuloId,
      unidadId: bien.unidadId,
      cantidad: 1,
      empleadoId: empleadoId,
      fechaEntrega: DateTime(2025, 2, 1),
      actorUsuarioId: actorId,
    );
  }

  /// Una conciliación real que DECLARA el bien como no entregado: el
  /// empleado se lo llevó y RISEG espera recuperarlo.
  Future<void> bajaDejandoPendiente(
    String empleadoId,
    List<String> asignacionIds, {
    String? vehiculoAsignacionId,
  }) {
    return conciliar.ejecutar(
      empleadoId: empleadoId,
      fechaBaja: DateTime(2025, 9, 15),
      motivo: MotivoBajaEmpleado.renuncia,
      actorUsuarioId: actorId,
      resoluciones: [
        for (final id in asignacionIds)
          ResolucionResguardo(
            asignacionId: id,
            resolucion: ResolucionResguardoBaja.noEntregado,
            motivoNoEntrega: MotivoNoEntregaResguardo.entregaAcordadaPosteriormente,
            fechaCompromiso: DateTime(2025, 9, 30),
            generaDescuento: true,
            importeDescuento: 100000,
          ),
        if (vehiculoAsignacionId != null)
          ResolucionResguardo(
            asignacionVehiculoId: vehiculoAsignacionId,
            resolucion: ResolucionResguardoBaja.noEntregado,
            motivoNoEntrega: MotivoNoEntregaResguardo.entregaAcordadaPosteriormente,
            fechaCompromiso: DateTime(2025, 9, 20),
            generaDescuento: true,
            importeDescuento: 500000,
          ),
      ],
    );
  }

  group('un pendiente DECLARADO no está disponible', () {
    test('sigue con la persona, y no se inventa ninguna devolución', () async {
      final juan = await crearEmpleado();
      final radio = await crearUnidad('Radio', 'R-104');
      final asignacion = await asignar(radio, juan.id);
      final movimientosAntes = (await db.select(db.movimientoInventario).get()).length;

      await bajaDejandoPendiente(juan.id, [asignacion.id]);

      final pendientes = await inventarioRepo.listarPendientesRecuperacionPorEmpleado(juan.id);
      expect(pendientes, hasLength(1));
      expect(pendientes.single.pendienteRecuperacionDesde, DateTime(2025, 9, 15));
      expect(pendientes.single.estatus, EstatusAsignacion.activa.name, reason: 'el bien SIGUE con la persona');

      final unidad = await (db.select(db.articuloUnidad)..where((t) => t.id.equals(radio.unidadId))).getSingle();
      expect(unidad.estatus, EstatusArticuloUnidad.asignado.name);
      final movimientos = await db.select(db.movimientoInventario).get();
      expect(movimientos.length, movimientosAntes, reason: 'cero movimientos de devolución inventados');
      expect(movimientos.where((m) => m.tipoMovimiento == TipoMovimientoInventario.entradaDevolucion.name), isEmpty);
    });
  });

  group('la devolución posterior conserva su fecha real', () {
    test('cierra el pendiente sin mover la fecha de baja', () async {
      final juan = await crearEmpleado();
      final radio = await crearUnidad('Radio', 'R-104');
      final asignacion = await asignar(radio, juan.id);
      await bajaDejandoPendiente(juan.id, [asignacion.id]);

      await inventarioRepo.cerrar(
        asignacionId: asignacion.id,
        motivo: MotivoCierreAsignacion.bajaEmpleado.name,
        fechaCierre: DateTime(2025, 9, 18),
        actorUsuarioId: actorId,
      );

      final devuelta = await inventarioRepo.obtenerPorId(asignacion.id);
      expect(devuelta!.estatus, EstatusAsignacion.devuelta.name);
      expect(devuelta.fechaCierre, DateTime(2025, 9, 18), reason: 'la fecha REAL de devolución');
      expect(devuelta.pendienteRecuperacionDesde, isNull);
      expect(devuelta.empleadoId, juan.id, reason: 'el empleado histórico se conserva');
      expect((await empleadoRepo.obtenerPorId(juan.id))!.fechaBaja, DateTime(2025, 9, 15));
      expect(await inventarioRepo.listarPendientesRecuperacionPorEmpleado(juan.id), isEmpty);
    });
  });

  group('vehículo pendiente', () {
    Future<({VehiculoData vehiculo, String asignacionId})> vehiculoDe(String empleadoId) async {
      final vehiculo = await vehiculoRepo.crear(
        codigo: 'VEH-00000$consecutivo',
        marca: 'Nissan',
        modelo: 'NP300',
        tipoVehiculo: 'pickup',
      );
      final asignacion = await vehiculoAsignacionRepo.crear(
        vehiculoId: vehiculo.id,
        empleadoId: empleadoId,
        fechaInicio: DateTime(2025, 2, 1),
        actorUsuarioId: actorId,
      );
      return (vehiculo: (await vehiculoRepo.obtenerPorId(vehiculo.id))!, asignacionId: asignacion.id);
    }

    test('no queda disponible ni puede asignarse a otra persona', () async {
      final juan = await crearEmpleado();
      final ana = await crearEmpleado(nombres: 'Ana');
      final v = await vehiculoDe(juan.id);

      await bajaDejandoPendiente(juan.id, const [], vehiculoAsignacionId: v.asignacionId);

      expect((await vehiculoRepo.obtenerPorId(v.vehiculo.id))!.estatus, 'asignado');
      expect(await vehiculoAsignacionRepo.listarPendientesRecuperacionPorEmpleado(juan.id), hasLength(1));

      final intento = await AsignarVehiculoUseCase(
        vehiculoRepo,
        vehiculoAsignacionRepo,
        VehiculoKilometrajeRepositoryImpl(db),
      ).ejecutar(vehiculoId: v.vehiculo.id, empleadoId: ana.id, fechaInicio: DateTime(2025, 9, 20));
      expect(intento, isA<AsignarVehiculoNoDisponible>());
    });

    test('la entrega posterior lo libera con su fecha real', () async {
      final juan = await crearEmpleado();
      final v = await vehiculoDe(juan.id);
      await bajaDejandoPendiente(juan.id, const [], vehiculoAsignacionId: v.asignacionId);

      await vehiculoAsignacionRepo.cerrar(
        asignacionVehiculoId: v.asignacionId,
        fechaTermino: DateTime(2025, 9, 20),
        motivoTermino: MotivoTerminoAsignacionVehiculo.liberacion.name,
        actorUsuarioId: actorId,
      );

      expect((await vehiculoRepo.obtenerPorId(v.vehiculo.id))!.estatus, 'disponible');
      final cerrada = await vehiculoAsignacionRepo.obtenerPorId(v.asignacionId);
      expect(cerrada!.fechaTermino, DateTime(2025, 9, 20));
      expect(cerrada.pendienteRecuperacionDesde, isNull);
      expect((await empleadoRepo.obtenerPorId(juan.id))!.fechaBaja, DateTime(2025, 9, 15));
    });
  });

  group('reingreso y eliminación física', () {
    test('el reingreso no revive el pendiente del periodo anterior', () async {
      final juan = await crearEmpleado();
      final radio = await crearUnidad('Radio', 'R-104');
      final asignacion = await asignar(radio, juan.id);
      await bajaDejandoPendiente(juan.id, [asignacion.id]);

      await empleadoRepo.registrarReingreso(empleadoId: juan.id, fechaIngreso: DateTime(2026, 3, 1));

      expect((await empleadoRepo.obtenerPorId(juan.id))!.estatus, EstatusEmpleado.activo.name);
      final pendiente = await inventarioRepo.obtenerPorId(asignacion.id);
      expect(pendiente!.pendienteRecuperacionDesde, DateTime(2025, 9, 15));
      expect(await inventarioRepo.listarPendientesRecuperacionPorEmpleado(juan.id), hasLength(1));
    });

    test('un empleado con pendientes no puede eliminarse físicamente', () async {
      final juan = await crearEmpleado();
      final radio = await crearUnidad('Radio', 'R-104');
      final asignacion = await asignar(radio, juan.id);
      await bajaDejandoPendiente(juan.id, [asignacion.id]);

      final resultado = await empleadoRepo.eliminarFisicamente(
        empleadoId: juan.id,
        motivo: 'Intento de borrar a alguien con un radio pendiente',
        actorUsuarioId: actorId,
      );

      expect(resultado, isA<EliminarEmpleadoFisicamenteTieneDependencias>());
      expect(await empleadoRepo.obtenerPorId(juan.id), isNotNull);
    });
  });
}

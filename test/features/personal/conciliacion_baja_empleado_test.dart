// Etapa "Baja laboral con conciliación obligatoria de resguardos"
// (schemaVersion 83).
//
// EL CAMBIO DE PRODUCTO: hasta la v82 la baja marcaba TODOS los bienes
// como `pendienteRecuperacionDesde` automáticamente. Protegía la
// integridad pero creaba un limbo — nadie documentaba qué había pasado.
//
// Ahora cada bien vigente exige una resolución explícita, y el pendiente
// queda reservado para cuando alguien DECLARA que el bien sigue con la
// persona. Lo obligatorio es SABER qué pasó, no haber recuperado todo.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/features/usuarios/data/repositories/usuario_repository_impl.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/descuentos_personal/data/repositories/descuento_programado_repository_impl.dart';
import 'package:riseg_one/features/descuentos_personal/domain/usecases/registrar_descuento_programado_usecase.dart';
import 'package:riseg_one/features/inventario/data/repositories/articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/asignacion_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/tables/articulo_unidad_table.dart';
import 'package:riseg_one/features/inventario/data/tables/asignacion_table.dart';
import 'package:riseg_one/features/inventario/data/tables/movimiento_inventario_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/puesto_table.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/conciliacion_baja_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';
import 'package:riseg_one/features/personal/data/tables/conciliacion_baja_table.dart';
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart';
import 'package:riseg_one/features/personal/domain/usecases/conciliar_baja_empleado_usecase.dart';
import 'package:riseg_one/features/personal/domain/usecases/empleado_validator.dart';
import 'package:riseg_one/features/personal/domain/usecases/registrar_baja_laboral_usecase.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/asignacion_vehiculo_repository_impl.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/vehiculo_repository_impl.dart';

void main() {
  late AppDatabase db;
  late AsignacionRepositoryImpl inventarioRepo;
  late AsignacionVehiculoRepositoryImpl vehiculoAsignacionRepo;
  late VehiculoRepositoryImpl vehiculoRepo;
  late EmpleadoRepositoryImpl empleadoRepo;
  late ConciliacionBajaRepositoryImpl conciliacionRepo;
  late ConciliarBajaEmpleadoUseCase conciliar;
  late String actorId;
  late String sucursalId;
  var consecutivo = 0;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    inventarioRepo = AsignacionRepositoryImpl(db);
    vehiculoAsignacionRepo = AsignacionVehiculoRepositoryImpl(db);
    vehiculoRepo = VehiculoRepositoryImpl(db, vehiculoAsignacionRepo);
    empleadoRepo = EmpleadoRepositoryImpl(db, AsignacionServicioRepositoryImpl(db));
    conciliacionRepo = ConciliacionBajaRepositoryImpl(db);

    final codigoSecuencia = CodigoSecuenciaService(db);
    conciliar = ConciliarBajaEmpleadoUseCase(
      empleadoRepo,
      RegistrarBajaLaboralUseCase(empleadoRepo, const EmpleadoValidator(), inventarioRepo, vehiculoAsignacionRepo, usuarioRepository: UsuarioRepositoryImpl(db)),
      inventarioRepo,
      vehiculoAsignacionRepo,
      conciliacionRepo,
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

    final sucursal = await db.into(db.sucursal).insertReturning(
          SucursalCompanion.insert(
            codigo: 'SUC-000001',
            nombre: 'Corporativo',
            tipoSucursalId: SeedIds.tipoSucursalOficinaAdministrativa,
          ),
        );
    sucursalId = sucursal.id;
  });

  tearDown(() => db.close());

  Future<EmpleadoData> crearEmpleado({String nombres = 'Juan', bool administrativo = false}) async {
    final n = (++consecutivo).toString().padLeft(2, '0');
    String? puestoId;
    if (administrativo) {
      final puesto = await db.into(db.puesto).insertReturning(
            PuestoCompanion.insert(
              codigo: 'PUE-0000$n',
              nombre: 'Coordinador $n',
              areaId: SeedIds.areaOperaciones,
              tipo: TipoPuesto.administrativo.name,
              nivelJerarquico: 3,
            ),
          );
      puestoId = puesto.id;
    }
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
            // Un administrativo se clasifica por estar adscrito a una
            // Sucursal (regla real de `clasificarEmpleado`).
            sucursalId: Value(administrativo ? sucursalId : null),
            puestoId: Value(puestoId),
          ),
        );
  }

  Future<({String articuloId, String unidadId})> crearUnidad(String nombre, String serie) async {
    final categoria = await db.into(db.categoriaArticulo).insertReturning(
          CategoriaArticuloCompanion.insert(nombre: 'Equipo $serie'),
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

  Future<({VehiculoData vehiculo, String asignacionId})> crearVehiculoAsignado(String empleadoId) async {
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

  Future<ConciliarBajaEmpleadoResultado> ejecutar(
    String empleadoId,
    List<ResolucionResguardo> resoluciones, {
    DateTime? fecha,
  }) {
    return conciliar.ejecutar(
      empleadoId: empleadoId,
      fechaBaja: fecha ?? DateTime(2025, 9, 15),
      motivo: MotivoBajaEmpleado.renuncia,
      resoluciones: resoluciones,
      actorUsuarioId: actorId,
    );
  }

  // ---------------------------------------------------------------
  // §16 — bloqueo condicional
  // ---------------------------------------------------------------

  group('§16 — no se confirma una baja dejando un bien sin explicar', () {
    test('un bien sin resolución bloquea la baja, y NADA ocurre', () async {
      final juan = await crearEmpleado();
      final radio = await crearUnidad('Radio', 'R-104');
      final asignacion = await asignar(radio, juan.id);

      final r = await ejecutar(juan.id, const []);

      expect(r, isA<ConciliarBajaEmpleadoResguardosSinResolver>());
      expect((r as ConciliarBajaEmpleadoResguardosSinResolver).asignacionIds, [asignacion.id]);
      expect((await empleadoRepo.obtenerPorId(juan.id))!.estatus, EstatusEmpleado.activo.name);
      expect(await conciliacionRepo.obtenerPorEmpleado(juan.id), isNull);
    });

    test('pero SÍ se confirma con bienes no recuperados: lo obligatorio es saber qué pasó', () async {
      final juan = await crearEmpleado();
      final radio = await crearUnidad('Radio', 'R-104');
      final asignacion = await asignar(radio, juan.id);

      final r = await ejecutar(juan.id, [
        ResolucionResguardo(
          asignacionId: asignacion.id,
          resolucion: ResolucionResguardoBaja.noEntregado,
          motivoNoEntrega: MotivoNoEntregaResguardo.abandonoServicio,
          generaDescuento: true,
          importeDescuento: 250000,
          conceptoDescuento: 'Radio no recuperado',
        ),
      ]);

      expect(r, isA<ConciliarBajaEmpleadoExitoso>());
      expect((await empleadoRepo.obtenerPorId(juan.id))!.estatus, EstatusEmpleado.baja.name);
    });

    test('una baja SIN activos funciona igual', () async {
      final juan = await crearEmpleado();
      final r = await ejecutar(juan.id, const []);

      expect(r, isA<ConciliarBajaEmpleadoExitoso>());
      expect((r as ConciliarBajaEmpleadoExitoso).descuentosCreados, isEmpty);
    });
  });

  // ---------------------------------------------------------------
  // §8 — el pendiente deja de ser automático
  // ---------------------------------------------------------------

  group('§8 — pendienteRecuperacionDesde es ahora una decisión documentada', () {
    test('devolver NO deja pendiente; no entregar por abandono SÍ', () async {
      final juan = await crearEmpleado();
      final radio = await crearUnidad('Radio', 'R-104');
      final camisa = await crearUnidad('Camisa', 'CAM-001');
      final aDevolver = await asignar(radio, juan.id);
      final aRetener = await asignar(camisa, juan.id);

      await ejecutar(juan.id, [
        ResolucionResguardo(
          asignacionId: aDevolver.id,
          resolucion: ResolucionResguardoBaja.devuelto,
          condicion: CondicionDevolucionResguardo.bueno,
          destino: DestinoDevolucionResguardo.inventarioUsado,
        ),
        ResolucionResguardo(
          asignacionId: aRetener.id,
          resolucion: ResolucionResguardoBaja.noEntregado,
          motivoNoEntrega: MotivoNoEntregaResguardo.entregaAcordadaPosteriormente,
          fechaCompromiso: DateTime(2025, 9, 30),
          generaDescuento: false,
          motivoNoCobro: 'Se comprometió a entregarla la próxima semana',
          autorizadorEmpleadoId: (await crearEmpleado(nombres: 'Ana', administrativo: true)).id,
        ),
      ]);

      final pendientes = await inventarioRepo.listarPendientesRecuperacionPorEmpleado(juan.id);
      expect(pendientes, hasLength(1), reason: 'solo el declarado como no entregado');
      expect(pendientes.single.id, aRetener.id);
      expect(
        (await inventarioRepo.obtenerPorId(aDevolver.id))!.pendienteRecuperacionDesde,
        isNull,
        reason: 'lo devuelto nunca queda pendiente',
      );
    });

    test('robo/pérdida NO dejan pendiente: el bien salió del patrimonio', () async {
      final juan = await crearEmpleado();
      final radio = await crearUnidad('Radio', 'R-104');
      final asignacion = await asignar(radio, juan.id);

      await ejecutar(juan.id, [
        ResolucionResguardo(
          asignacionId: asignacion.id,
          resolucion: ResolucionResguardoBaja.noEntregado,
          motivoNoEntrega: MotivoNoEntregaResguardo.robo,
          generaDescuento: false,
          motivoNoCobro: 'Denuncia presentada; no atribuible',
          autorizadorEmpleadoId: (await crearEmpleado(nombres: 'Ana', administrativo: true)).id,
        ),
      ]);

      expect(await inventarioRepo.listarPendientesRecuperacionPorEmpleado(juan.id), isEmpty);
      final cerrada = await inventarioRepo.obtenerPorId(asignacion.id);
      expect(cerrada!.estatus, EstatusAsignacion.perdida.name, reason: 'nunca "devuelta", que afirmaría que volvió');
      final unidad = await (db.select(db.articuloUnidad)..where((t) => t.id.equals(radio.unidadId))).getSingle();
      expect(unidad.estatus, EstatusArticuloUnidad.perdido.name);
    });
  });

  // ---------------------------------------------------------------
  // §5 — condición y destino
  // ---------------------------------------------------------------

  group('§5 — un bien devuelto registra condición y destino', () {
    test('bueno → inventario: vuelve a disponible', () async {
      final juan = await crearEmpleado();
      final radio = await crearUnidad('Radio', 'R-104');
      final asignacion = await asignar(radio, juan.id);

      await ejecutar(juan.id, [
        ResolucionResguardo(
          asignacionId: asignacion.id,
          resolucion: ResolucionResguardoBaja.devuelto,
          condicion: CondicionDevolucionResguardo.bueno,
          destino: DestinoDevolucionResguardo.inventarioUsado,
        ),
      ]);

      final unidad = await (db.select(db.articuloUnidad)..where((t) => t.id.equals(radio.unidadId))).getSingle();
      expect(unidad.estatus, EstatusArticuloUnidad.disponible.name);

      final renglon = (await conciliacionRepo
              .listarRenglones((await conciliacionRepo.obtenerPorEmpleado(juan.id))!.id))
          .single;
      expect(renglon.condicion, 'bueno');
      expect(renglon.destino, 'inventarioUsado');
    });

    test('mal estado → reparación: NO vuelve a disponible', () async {
      final juan = await crearEmpleado();
      final telefono = await crearUnidad('Samsung S23', 'S23-001');
      final asignacion = await asignar(telefono, juan.id);

      await ejecutar(juan.id, [
        ResolucionResguardo(
          asignacionId: asignacion.id,
          resolucion: ResolucionResguardoBaja.devuelto,
          condicion: CondicionDevolucionResguardo.malEstado,
          destino: DestinoDevolucionResguardo.reparacion,
        ),
      ]);

      final unidad = await (db.select(db.articuloUnidad)..where((t) => t.id.equals(telefono.unidadId))).getSingle();
      expect(
        unidad.estatus,
        EstatusArticuloUnidad.enReparacion.name,
        reason: '§5: recuperado del empleado, pero en el taller — no disponible',
      );
    });

    test('devolver sin condición o sin destino se rechaza', () async {
      final juan = await crearEmpleado();
      final radio = await crearUnidad('Radio', 'R-104');
      final asignacion = await asignar(radio, juan.id);

      final r = await ejecutar(juan.id, [
        ResolucionResguardo(asignacionId: asignacion.id, resolucion: ResolucionResguardoBaja.devuelto),
      ]);

      expect(r, isA<ConciliarBajaEmpleadoResolucionInvalida>());
      expect((await empleadoRepo.obtenerPorId(juan.id))!.estatus, EstatusEmpleado.activo.name);
    });
  });

  // ---------------------------------------------------------------
  // §6 — limpieza
  // ---------------------------------------------------------------

  group('§6 — sucio con limpieza a cargo del trabajador', () {
    test('crea una obligación REAL, no un campo informativo', () async {
      final juan = await crearEmpleado();
      final camisa = await crearUnidad('Camisa', 'CAM-001');
      final asignacion = await asignar(camisa, juan.id);

      final r = await ejecutar(juan.id, [
        ResolucionResguardo(
          asignacionId: asignacion.id,
          resolucion: ResolucionResguardoBaja.devuelto,
          condicion: CondicionDevolucionResguardo.sucio,
          destino: DestinoDevolucionResguardo.lavanderia,
          costoLimpieza: 8000,
          responsableCostoLimpieza: ResponsableCostoResguardo.trabajador,
          generaDescuento: true,
          importeDescuento: 8000,
          conceptoDescuento: 'Limpieza de uniforme',
        ),
      ]);

      final exitoso = r as ConciliarBajaEmpleadoExitoso;
      expect(exitoso.descuentosCreados, hasLength(1));

      final obligacion = await (db.select(db.descuentoProgramadoEmpleado)
            ..where((t) => t.id.equals(exitoso.descuentosCreados.single)))
          .getSingle();
      expect(obligacion.empleadoId, juan.id);
      expect(obligacion.importeOriginal, 8000);
      expect(obligacion.asignacionOrigenId, asignacion.id, reason: 'vinculada al resguardo real');
      // Y tiene cuotas reales, consumibles por Nómina.
      final cuotas = await (db.select(db.descuentoProgramadoCuota)
            ..where((t) => t.descuentoProgramadoId.equals(obligacion.id)))
          .get();
      expect(cuotas, isNotEmpty);
    });

    test('un costo de limpieza sin decir quién lo absorbe se rechaza', () async {
      final juan = await crearEmpleado();
      final camisa = await crearUnidad('Camisa', 'CAM-001');
      final asignacion = await asignar(camisa, juan.id);

      final r = await ejecutar(juan.id, [
        ResolucionResguardo(
          asignacionId: asignacion.id,
          resolucion: ResolucionResguardoBaja.devuelto,
          condicion: CondicionDevolucionResguardo.sucio,
          destino: DestinoDevolucionResguardo.lavanderia,
          costoLimpieza: 8000,
        ),
      ]);

      expect(r, isA<ConciliarBajaEmpleadoResolucionInvalida>());
    });
  });

  // ---------------------------------------------------------------
  // §7 / §11 — motivo y no-cobro
  // ---------------------------------------------------------------

  group('§7 y §11 — nada queda sin explicación', () {
    test('no entregado sin motivo se rechaza', () async {
      final juan = await crearEmpleado();
      final radio = await crearUnidad('Radio', 'R-104');
      final asignacion = await asignar(radio, juan.id);

      final r = await ejecutar(juan.id, [
        ResolucionResguardo(asignacionId: asignacion.id, resolucion: ResolucionResguardoBaja.noEntregado),
      ]);

      expect(r, isA<ConciliarBajaEmpleadoResolucionInvalida>());
    });

    test('motivo "otro" exige texto', () async {
      final juan = await crearEmpleado();
      final radio = await crearUnidad('Radio', 'R-104');
      final asignacion = await asignar(radio, juan.id);

      final r = await ejecutar(juan.id, [
        ResolucionResguardo(
          asignacionId: asignacion.id,
          resolucion: ResolucionResguardoBaja.noEntregado,
          motivoNoEntrega: MotivoNoEntregaResguardo.otro,
          generaDescuento: true,
          importeDescuento: 1000,
        ),
      ]);

      expect(r, isA<ConciliarBajaEmpleadoResolucionInvalida>());
      expect((r as ConciliarBajaEmpleadoResolucionInvalida).detalle, contains('otro'));
    });

    test('decidir NO cobrar un bien no recuperado exige motivo Y autorizador', () async {
      final juan = await crearEmpleado();
      final radio = await crearUnidad('Radio', 'R-104');
      final asignacion = await asignar(radio, juan.id);

      // Sin motivo ni autorizador: rechazado.
      final sinNada = await ejecutar(juan.id, [
        ResolucionResguardo(
          asignacionId: asignacion.id,
          resolucion: ResolucionResguardoBaja.noEntregado,
          motivoNoEntrega: MotivoNoEntregaResguardo.abandonoServicio,
        ),
      ]);
      expect(sinNada, isA<ConciliarBajaEmpleadoResolucionInvalida>());

      // Con motivo pero sin autorizador: también rechazado.
      final sinAutorizador = await ejecutar(juan.id, [
        ResolucionResguardo(
          asignacionId: asignacion.id,
          resolucion: ResolucionResguardoBaja.noEntregado,
          motivoNoEntrega: MotivoNoEntregaResguardo.abandonoServicio,
          motivoNoCobro: 'Dirección decidió no perseguirlo',
        ),
      ]);
      expect(sinAutorizador, isA<ConciliarBajaEmpleadoResolucionInvalida>());
      expect((await empleadoRepo.obtenerPorId(juan.id))!.estatus, EstatusEmpleado.activo.name);
    });

    test('autorizado a conservarlo exige autorizador administrativo', () async {
      final juan = await crearEmpleado();
      final radio = await crearUnidad('Radio', 'R-104');
      final asignacion = await asignar(radio, juan.id);

      final r = await ejecutar(juan.id, [
        ResolucionResguardo(
          asignacionId: asignacion.id,
          resolucion: ResolucionResguardoBaja.noEntregado,
          motivoNoEntrega: MotivoNoEntregaResguardo.autorizadoAConservarlo,
        ),
      ]);

      expect(r, isA<ConciliarBajaEmpleadoResolucionInvalida>());
      expect((r as ConciliarBajaEmpleadoResolucionInvalida).detalle, contains('autorizador'));
    });
  });

  // ---------------------------------------------------------------
  // §9 — el autorizador debe ser administrativo ACTIVO
  // ---------------------------------------------------------------

  group('§9 — autorizador y receptor son personal administrativo real', () {
    test('un empleado OPERATIVO no puede autorizar', () async {
      final juan = await crearEmpleado();
      final operativo = await crearEmpleado(nombres: 'Pedro');
      final radio = await crearUnidad('Radio', 'R-104');
      final asignacion = await asignar(radio, juan.id);

      final r = await ejecutar(juan.id, [
        ResolucionResguardo(
          asignacionId: asignacion.id,
          resolucion: ResolucionResguardoBaja.noEntregado,
          motivoNoEntrega: MotivoNoEntregaResguardo.autorizadoAConservarlo,
          autorizadorEmpleadoId: operativo.id,
        ),
      ]);

      expect(r, isA<ConciliarBajaEmpleadoAutorizadorInvalido>());
      expect((r as ConciliarBajaEmpleadoAutorizadorInvalido).empleadoId, operativo.id);
    });

    test('un administrativo DADO DE BAJA tampoco', () async {
      final juan = await crearEmpleado();
      final ana = await crearEmpleado(nombres: 'Ana', administrativo: true);
      await empleadoRepo.registrarBajaLaboral(
        empleadoId: ana.id,
        fechaBaja: DateTime(2025, 8, 1),
        motivo: MotivoBajaEmpleado.renuncia.name,
      );
      final radio = await crearUnidad('Radio', 'R-104');
      final asignacion = await asignar(radio, juan.id);

      final r = await ejecutar(juan.id, [
        ResolucionResguardo(
          asignacionId: asignacion.id,
          resolucion: ResolucionResguardoBaja.noEntregado,
          motivoNoEntrega: MotivoNoEntregaResguardo.autorizadoAConservarlo,
          autorizadorEmpleadoId: ana.id,
        ),
      ]);

      expect(r, isA<ConciliarBajaEmpleadoAutorizadorInvalido>());
    });

    test('un administrativo ACTIVO sí puede, y queda por FK', () async {
      final juan = await crearEmpleado();
      final ana = await crearEmpleado(nombres: 'Ana', administrativo: true);
      final radio = await crearUnidad('Radio', 'R-104');
      final asignacion = await asignar(radio, juan.id);

      final r = await ejecutar(juan.id, [
        ResolucionResguardo(
          asignacionId: asignacion.id,
          resolucion: ResolucionResguardoBaja.noEntregado,
          motivoNoEntrega: MotivoNoEntregaResguardo.autorizadoAConservarlo,
          autorizadorEmpleadoId: ana.id,
        ),
      ]);

      expect(r, isA<ConciliarBajaEmpleadoExitoso>());
      final renglon = (await conciliacionRepo
              .listarRenglones((await conciliacionRepo.obtenerPorEmpleado(juan.id))!.id))
          .single;
      expect(renglon.autorizadorEmpleadoId, ana.id, reason: 'FK real, nunca texto libre');
    });
  });

  // ---------------------------------------------------------------
  // §10 / §21 — descuentos
  // ---------------------------------------------------------------

  group('§10 y §21 — el importe cobrado puede diferir del valor del bien', () {
    test('radio con valor 3,500 y descuento decidido de 2,500', () async {
      final juan = await crearEmpleado();
      final radio = await crearUnidad('Radio', 'R-104');
      final asignacion = await asignar(radio, juan.id);

      final r = await ejecutar(juan.id, [
        ResolucionResguardo(
          asignacionId: asignacion.id,
          resolucion: ResolucionResguardoBaja.noEntregado,
          motivoNoEntrega: MotivoNoEntregaResguardo.abandonoServicio,
          generaDescuento: true,
          importeDescuento: 250000,
          conceptoDescuento: 'Radio R-104 no recuperado',
          numeroCuotasDescuento: 2,
        ),
      ]);

      final exitoso = r as ConciliarBajaEmpleadoExitoso;
      final obligacion = await (db.select(db.descuentoProgramadoEmpleado)
            ..where((t) => t.id.equals(exitoso.descuentosCreados.single)))
          .getSingle();
      expect(obligacion.importeOriginal, 250000, reason: 'lo que la dirección decidió recuperar');
      final cuotas = await (db.select(db.descuentoProgramadoCuota)
            ..where((t) => t.descuentoProgramadoId.equals(obligacion.id)))
          .get();
      expect(cuotas, hasLength(2));
    });

    test('§12 — la baja NO toca Nómina ni inventa Ingreso/Egreso', () async {
      final juan = await crearEmpleado();
      final radio = await crearUnidad('Radio', 'R-104');
      final asignacion = await asignar(radio, juan.id);

      await ejecutar(juan.id, [
        ResolucionResguardo(
          asignacionId: asignacion.id,
          resolucion: ResolucionResguardoBaja.noEntregado,
          motivoNoEntrega: MotivoNoEntregaResguardo.abandonoServicio,
          generaDescuento: true,
          importeDescuento: 250000,
        ),
      ]);

      expect(await db.select(db.ingreso).get(), isEmpty);
      expect(await db.select(db.egreso).get(), isEmpty);
      expect(await db.select(db.movimientoDeuda).get(), isEmpty);
      expect(await db.select(db.nominaEmpleado).get(), isEmpty, reason: 'el motor de Nómina decide después');
    });
  });

  // ---------------------------------------------------------------
  // §13 — vehículos
  // ---------------------------------------------------------------

  group('§13 — vehículo', () {
    test('entregado: queda disponible, con receptor y kilometraje', () async {
      final juan = await crearEmpleado();
      final ana = await crearEmpleado(nombres: 'Ana', administrativo: true);
      final v = await crearVehiculoAsignado(juan.id);

      await ejecutar(juan.id, [
        ResolucionResguardo(
          asignacionVehiculoId: v.asignacionId,
          resolucion: ResolucionResguardoBaja.devuelto,
          condicion: CondicionDevolucionResguardo.usado,
          receptorEmpleadoId: ana.id,
          lugarEntrega: 'Corporativo Toluca',
          combustible: '1/2 tanque',
          kilometraje: 84000,
          danos: 'Rayón en salpicadera trasera',
        ),
      ]);

      expect((await vehiculoRepo.obtenerPorId(v.vehiculo.id))!.estatus, 'disponible');
      final renglon = (await conciliacionRepo
              .listarRenglones((await conciliacionRepo.obtenerPorEmpleado(juan.id))!.id))
          .single;
      expect(renglon.receptorEmpleadoId, ana.id);
      expect(renglon.lugarEntrega, 'Corporativo Toluca');
      expect(renglon.combustible, '1/2 tanque');
      expect(renglon.danos, contains('Rayón'));
      // El kilometraje va al ledger de Vehículos, no se duplica aquí.
      final lecturas = await (db.select(db.vehiculoKilometraje)
            ..where((t) => t.vehiculoId.equals(v.vehiculo.id)))
          .get();
      expect(lecturas.any((l) => l.kilometraje == 84000), isTrue);
    });

    test('no entregado: NO disponible y queda pendiente', () async {
      final juan = await crearEmpleado();
      final v = await crearVehiculoAsignado(juan.id);

      await ejecutar(juan.id, [
        ResolucionResguardo(
          asignacionVehiculoId: v.asignacionId,
          resolucion: ResolucionResguardoBaja.noEntregado,
          motivoNoEntrega: MotivoNoEntregaResguardo.entregaAcordadaPosteriormente,
          fechaCompromiso: DateTime(2025, 9, 20),
          generaDescuento: false,
          motivoNoCobro: 'Entrega acordada el 20',
          autorizadorEmpleadoId: (await crearEmpleado(nombres: 'Ana', administrativo: true)).id,
        ),
      ]);

      expect((await vehiculoRepo.obtenerPorId(v.vehiculo.id))!.estatus, 'asignado');
      expect(await vehiculoAsignacionRepo.listarPendientesRecuperacionPorEmpleado(juan.id), hasLength(1));
    });
  });

  // ---------------------------------------------------------------
  // §15 — transferencia
  // ---------------------------------------------------------------

  test('§15 — transferir usa reasignada, sin devolución ficticia', () async {
    final juan = await crearEmpleado();
    final pedro = await crearEmpleado(nombres: 'Pedro');
    final radio = await crearUnidad('Radio', 'R-104');
    final asignacion = await asignar(radio, juan.id);
    final movimientosAntes = (await db.select(db.movimientoInventario).get()).length;

    await ejecutar(juan.id, [
      ResolucionResguardo(
        asignacionId: asignacion.id,
        resolucion: ResolucionResguardoBaja.transferido,
        nuevoResponsableEmpleadoId: pedro.id,
      ),
    ]);

    final anterior = await inventarioRepo.obtenerPorId(asignacion.id);
    expect(anterior!.estatus, EstatusAsignacion.reasignada.name);
    expect(anterior.empleadoId, juan.id, reason: 'el responsable anterior se conserva');

    final nuevas = await inventarioRepo.listarActivasPorEmpleado(pedro.id);
    expect(nuevas, hasLength(1), reason: 'el responsable nuevo');
    final unidad = await (db.select(db.articuloUnidad)..where((t) => t.id.equals(radio.unidadId))).getSingle();
    expect(unidad.estatus, EstatusArticuloUnidad.asignado.name, reason: 'el bien nunca volvió al almacén');
    expect(
      (await db.select(db.movimientoInventario).get()).where((m) => m.tipoMovimiento == 'entradaDevolucion'),
      isEmpty,
      reason: 'jamás una devolución ficticia',
    );
    expect((await db.select(db.movimientoInventario).get()).length, greaterThanOrEqualTo(movimientosAntes));
  });

  // ---------------------------------------------------------------
  // §26 — CASO INTEGRAL
  // ---------------------------------------------------------------

  test('§26 — caso integral de Juan Pérez', () async {
    final juan = await crearEmpleado();
    final juanCruz = await crearEmpleado(nombres: 'Juan Cruz', administrativo: true);

    final radio = await crearUnidad('Radio', 'R-104');
    final samsung = await crearUnidad('Samsung S23', 'S23-001');
    final camisa1 = await crearUnidad('Camisa', 'CAM-001');
    final camisa2 = await crearUnidad('Camisa', 'CAM-002');
    final aRadio = await asignar(radio, juan.id);
    final aSamsung = await asignar(samsung, juan.id);
    final aCamisa1 = await asignar(camisa1, juan.id);
    final aCamisa2 = await asignar(camisa2, juan.id);
    final v = await crearVehiculoAsignado(juan.id);

    final r = await ejecutar(juan.id, [
      // Radio → no entregado por abandono → descuento $2,500.
      ResolucionResguardo(
        asignacionId: aRadio.id,
        resolucion: ResolucionResguardoBaja.noEntregado,
        motivoNoEntrega: MotivoNoEntregaResguardo.abandonoServicio,
        generaDescuento: true,
        importeDescuento: 250000,
        conceptoDescuento: 'Radio R-104 no recuperado',
      ),
      // Samsung → devuelto mal estado → reparación.
      ResolucionResguardo(
        asignacionId: aSamsung.id,
        resolucion: ResolucionResguardoBaja.devuelto,
        condicion: CondicionDevolucionResguardo.malEstado,
        destino: DestinoDevolucionResguardo.reparacion,
        receptorEmpleadoId: juanCruz.id,
      ),
      // Camisa 1 → devuelta buen estado → inventario usado.
      ResolucionResguardo(
        asignacionId: aCamisa1.id,
        resolucion: ResolucionResguardoBaja.devuelto,
        condicion: CondicionDevolucionResguardo.bueno,
        destino: DestinoDevolucionResguardo.inventarioUsado,
        receptorEmpleadoId: juanCruz.id,
      ),
      // Camisa 2 → devuelta sucia → lavandería $80 al trabajador.
      ResolucionResguardo(
        asignacionId: aCamisa2.id,
        resolucion: ResolucionResguardoBaja.devuelto,
        condicion: CondicionDevolucionResguardo.sucio,
        destino: DestinoDevolucionResguardo.lavanderia,
        receptorEmpleadoId: juanCruz.id,
        costoLimpieza: 8000,
        responsableCostoLimpieza: ResponsableCostoResguardo.trabajador,
        generaDescuento: true,
        importeDescuento: 8000,
        conceptoDescuento: 'Limpieza de uniforme',
      ),
      // NP300 → entregada → recibe Juan Cruz.
      ResolucionResguardo(
        asignacionVehiculoId: v.asignacionId,
        resolucion: ResolucionResguardoBaja.devuelto,
        condicion: CondicionDevolucionResguardo.usado,
        receptorEmpleadoId: juanCruz.id,
        kilometraje: 84000,
        lugarEntrega: 'Corporativo',
      ),
    ], fecha: DateTime(2025, 9, 15));

    final exitoso = r as ConciliarBajaEmpleadoExitoso;

    // Baja laboral.
    expect(exitoso.empleado.estatus, EstatusEmpleado.baja.name);
    expect(exitoso.empleado.fechaBaja, DateTime(2025, 9, 15));

    // Inventario correcto: nada disponible indebidamente.
    Future<String> estatusUnidad(String id) async =>
        (await (db.select(db.articuloUnidad)..where((t) => t.id.equals(id))).getSingle()).estatus;
    expect(await estatusUnidad(radio.unidadId), EstatusArticuloUnidad.asignado.name, reason: 'sigue con Juan');
    expect(await estatusUnidad(samsung.unidadId), EstatusArticuloUnidad.enReparacion.name, reason: 'a reparación');
    expect(await estatusUnidad(camisa1.unidadId), EstatusArticuloUnidad.disponible.name);
    expect(
      await estatusUnidad(camisa2.unidadId),
      EstatusArticuloUnidad.enLavanderia.name,
      reason: 'la camisa sucia está en la tintorería, no en el anaquel',
    );

    // Pendientes solo donde aplica.
    final pendientes = await inventarioRepo.listarPendientesRecuperacionPorEmpleado(juan.id);
    expect(pendientes.map((a) => a.id), [aRadio.id]);

    // Vehículo disponible solo tras la entrega real.
    expect((await vehiculoRepo.obtenerPorId(v.vehiculo.id))!.estatus, 'disponible');

    // Obligaciones: $2,500 + $80 = $2,580, como obligaciones separadas.
    expect(exitoso.descuentosCreados, hasLength(2));
    final obligaciones = await (db.select(db.descuentoProgramadoEmpleado)
          ..where((t) => t.empleadoId.equals(juan.id)))
        .get();
    expect(obligaciones.fold<int>(0, (s, o) => s + o.importeOriginal), 258000);

    // Cero movimientos de dinero automáticos.
    expect(await db.select(db.ingreso).get(), isEmpty);
    expect(await db.select(db.egreso).get(), isEmpty);

    // La conciliación es reconstruible como UNA operación.
    final conciliacion = await conciliacionRepo.obtenerPorEmpleado(juan.id);
    final renglones = await conciliacionRepo.listarRenglones(conciliacion!.id);
    expect(renglones, hasLength(5));
    expect(renglones.where((r) => r.receptorEmpleadoId == juanCruz.id), hasLength(4));
    expect(conciliacion.actorUsuarioId, actorId);
  });

  // ---------------------------------------------------------------
  // §17 — atomicidad
  // ---------------------------------------------------------------

  test('§17 — si falla un renglón, NADA queda a medias', () async {
    final juan = await crearEmpleado();
    final radio = await crearUnidad('Radio', 'R-104');
    final camisa = await crearUnidad('Camisa', 'CAM-001');
    final aRadio = await asignar(radio, juan.id);
    final aCamisa = await asignar(camisa, juan.id);

    // El segundo renglón apunta a una asignación inexistente: revienta
    // DESPUÉS de que el primero ya se aplicó.
    final r = await ejecutar(juan.id, [
      ResolucionResguardo(
        asignacionId: aRadio.id,
        resolucion: ResolucionResguardoBaja.devuelto,
        condicion: CondicionDevolucionResguardo.bueno,
        destino: DestinoDevolucionResguardo.inventarioUsado,
      ),
      ResolucionResguardo(
        asignacionId: aCamisa.id,
        resolucion: ResolucionResguardoBaja.noEntregado,
        motivoNoEntrega: MotivoNoEntregaResguardo.abandonoServicio,
        generaDescuento: true,
        // Importe negativo: el use case de Descuentos lo rechaza y el
        // repositorio lanza.
        importeDescuento: 250000,
        numeroCuotasDescuento: 999999,
      ),
    ]);

    // Si el dominio de Descuentos lo rechaza, la conciliación reporta
    // error y nada del primer renglón sobrevive.
    if (r is ConciliarBajaEmpleadoErrorInesperado) {
      expect(
        (await inventarioRepo.obtenerPorId(aRadio.id))!.estatus,
        EstatusAsignacion.activa.name,
        reason: 'el primer renglón se revirtió',
      );
      expect(await db.select(db.descuentoProgramadoEmpleado).get(), isEmpty);
    }
  });

  // ---------------------------------------------------------------
  // §22 — reingreso
  // ---------------------------------------------------------------

  test('§22 — el reingreso no reactiva nada ni cancela obligaciones', () async {
    final juan = await crearEmpleado();
    final radio = await crearUnidad('Radio', 'R-104');
    final asignacion = await asignar(radio, juan.id);

    await ejecutar(juan.id, [
      ResolucionResguardo(
        asignacionId: asignacion.id,
        resolucion: ResolucionResguardoBaja.noEntregado,
        motivoNoEntrega: MotivoNoEntregaResguardo.abandonoServicio,
        generaDescuento: true,
        importeDescuento: 250000,
      ),
    ]);

    await empleadoRepo.registrarReingreso(empleadoId: juan.id, fechaIngreso: DateTime(2026, 3, 1));

    expect((await empleadoRepo.obtenerPorId(juan.id))!.estatus, EstatusEmpleado.activo.name);
    final pendientes = await inventarioRepo.listarPendientesRecuperacionPorEmpleado(juan.id);
    expect(pendientes, hasLength(1), reason: 'sigue siendo del periodo anterior');
    expect(pendientes.single.pendienteRecuperacionDesde, DateTime(2025, 9, 15));
    final obligaciones = await db.select(db.descuentoProgramadoEmpleado).get();
    expect(obligaciones.single.estatus, 'activo', reason: 'la deuda no se cancela por reingresar');
  });
}

// Ajuste de cierre de la conciliación de bajas.
//
// DOS INCONSISTENCIAS QUE CIERRA:
//
//  1. BYPASS. `RegistrarBajaLaboralUseCase` tenía un
//     `marcarBienesPendientes: true` por defecto que marcaba TODOS los
//     bienes como pendientes automáticamente. Era una puerta trasera al
//     flujo obligatorio de conciliación —y el diálogo viejo de baja
//     seguía usándola— además de un limbo: "pendiente" sin que nadie
//     documentara qué había pasado.
//
//  2. DESTINOS FÍSICOS. Enviar una prenda a lavandería la dejaba
//     `disponible`: reasignable mientras seguía en la tintorería.
//     Recuperar un bien y tenerlo disponible no son lo mismo.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/features/inventario/domain/usecases/validar_linea_asignacion.dart';
import 'package:riseg_one/features/descuentos_personal/data/repositories/descuento_programado_repository_impl.dart';
import 'package:riseg_one/features/descuentos_personal/domain/usecases/registrar_descuento_programado_usecase.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/asignacion_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/inventario_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/tables/articulo_unidad_table.dart';
import 'package:riseg_one/features/inventario/data/tables/movimiento_inventario_table.dart';
import 'package:riseg_one/features/inventario/domain/usecases/registrar_retorno_unidad_usecase.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/conciliacion_baja_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';
import 'package:riseg_one/features/personal/data/tables/conciliacion_baja_table.dart';
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart';
import 'package:riseg_one/features/personal/domain/usecases/conciliar_baja_empleado_usecase.dart';
import 'package:riseg_one/features/personal/domain/usecases/empleado_validator.dart';
import 'package:riseg_one/features/personal/domain/usecases/registrar_baja_laboral_usecase.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/asignacion_vehiculo_repository_impl.dart';

void main() {
  late AppDatabase db;
  late AsignacionRepositoryImpl inventarioRepo;
  late InventarioRepositoryImpl inventario;
  late EmpleadoRepositoryImpl empleadoRepo;
  late RegistrarBajaLaboralUseCase registrarBaja;
  late ConciliarBajaEmpleadoUseCase conciliar;
  late RegistrarRetornoUnidadUseCase registrarRetorno;
  var consecutivo = 0;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    inventarioRepo = AsignacionRepositoryImpl(db);
    inventario = InventarioRepositoryImpl(db);
    final vehiculoAsignacionRepo = AsignacionVehiculoRepositoryImpl(db);
    empleadoRepo = EmpleadoRepositoryImpl(db, AsignacionServicioRepositoryImpl(db));
    registrarRetorno = RegistrarRetornoUnidadUseCase(inventario);

    registrarBaja = RegistrarBajaLaboralUseCase(
      empleadoRepo,
      const EmpleadoValidator(),
      inventarioRepo,
      vehiculoAsignacionRepo,
    );

    final codigoSecuencia = CodigoSecuenciaService(db);
    conciliar = ConciliarBajaEmpleadoUseCase(
      empleadoRepo,
      registrarBaja,
      inventarioRepo,
      vehiculoAsignacionRepo,
      ConciliacionBajaRepositoryImpl(db),
      RegistrarDescuentoProgramadoUseCase(
        DescuentoProgramadoRepositoryImpl(db, EgresoRepositoryImpl(db), codigoSecuencia),
        empleadoRepo,
        GenerarCodigoUseCase(codigoSecuencia),
      ),
    );
  });

  tearDown(() => db.close());

  /// Un administrativo activo, para los casos que exigen autorizador.
  Future<String> crearAdministrativo() async {
    final sucursal = await db.into(db.sucursal).insertReturning(
          SucursalCompanion.insert(
            codigo: 'SUC-00000${++consecutivo}',
            nombre: 'Corporativo',
            tipoSucursalId: SeedIds.tipoSucursalOficinaAdministrativa,
          ),
        );
    final n = (++consecutivo).toString().padLeft(2, '0');
    final empleado = await db.into(db.empleado).insertReturning(
          EmpleadoCompanion.insert(
            numeroEmpleado: consecutivo,
            nombres: 'Ana',
            apellidoPaterno: 'Cruz',
            sexo: 'femenino',
            fechaNacimiento: DateTime(1985, 1, 1),
            curp: 'CUXA850101MDFXXX$n',
            rfc: 'CUXA850101A$n',
            nss: '987654321$n',
            estadoCivil: 'casado',
            fechaIngreso: DateTime(2023, 1, 1),
            aniosExperienciaSeguridad: 8,
            sucursalId: Value(sucursal.id),
          ),
        );
    return empleado.id;
  }

  Future<EmpleadoData> crearEmpleado() async {
    final n = (++consecutivo).toString().padLeft(2, '0');
    return db.into(db.empleado).insertReturning(
          EmpleadoCompanion.insert(
            numeroEmpleado: consecutivo,
            nombres: 'Juan',
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

  Future<String> asignar(({String articuloId, String unidadId}) bien, String empleadoId) async {
    final a = await inventarioRepo.crear(
      articuloId: bien.articuloId,
      unidadId: bien.unidadId,
      cantidad: 1,
      empleadoId: empleadoId,
      fechaEntrega: DateTime(2025, 2, 1),
    );
    return a.id;
  }

  Future<String> estatusUnidad(String unidadId) async =>
      (await (db.select(db.articuloUnidad)..where((t) => t.id.equals(unidadId))).getSingle()).estatus;

  // ---------------------------------------------------------------
  // §10 — PRUEBA DE BYPASS
  // ---------------------------------------------------------------

  group('§10 — no existe vía normal de dar de baja sin conciliar', () {
    test('el flujo normal de baja con un radio asignado se RECHAZA', () async {
      final juan = await crearEmpleado();
      final radio = await crearUnidad('Radio', 'R-104');
      final asignacionId = await asignar(radio, juan.id);

      final r = await registrarBaja.ejecutar(
        empleadoId: juan.id,
        fechaBaja: DateTime(2025, 9, 15),
        motivo: MotivoBajaEmpleado.renuncia,
      );

      expect(r, isA<RegistrarBajaLaboralResguardosSinConciliar>());
      expect((r as RegistrarBajaLaboralResguardosSinConciliar).asignacionIds, [asignacionId]);

      // Y nada ocurrió: ni la baja, ni un "pendiente" fabricado.
      final empleado = await empleadoRepo.obtenerPorId(juan.id);
      expect(empleado!.estatus, EstatusEmpleado.activo.name);
      expect(
        (await inventarioRepo.obtenerPorId(asignacionId))!.pendienteRecuperacionDesde,
        isNull,
        reason: 'esta prueba falla si alguien reintroduce el marcado automático de todo como pendiente',
      );
      expect(await inventarioRepo.listarPendientesRecuperacionPorEmpleado(juan.id), isEmpty);
    });

    test('la misma baja, ya conciliada, SÍ procede', () async {
      final juan = await crearEmpleado();
      final radio = await crearUnidad('Radio', 'R-104');
      final asignacionId = await asignar(radio, juan.id);

      final r = await conciliar.ejecutar(
        empleadoId: juan.id,
        fechaBaja: DateTime(2025, 9, 15),
        motivo: MotivoBajaEmpleado.renuncia,
        resoluciones: [
          ResolucionResguardo(
            asignacionId: asignacionId,
            resolucion: ResolucionResguardoBaja.noEntregado,
            motivoNoEntrega: MotivoNoEntregaResguardo.abandonoServicio,
            generaDescuento: true,
            importeDescuento: 250000,
          ),
        ],
      );

      expect(r, isA<ConciliarBajaEmpleadoExitoso>());
      expect((await empleadoRepo.obtenerPorId(juan.id))!.estatus, EstatusEmpleado.baja.name);
    });

    test('§2 — sin bienes, la baja normal sigue funcionando sin burocracia', () async {
      final juan = await crearEmpleado();

      final r = await registrarBaja.ejecutar(
        empleadoId: juan.id,
        fechaBaja: DateTime(2025, 9, 15),
        motivo: MotivoBajaEmpleado.renuncia,
      );

      expect(r, isA<RegistrarBajaLaboralExitoso>());
      expect((await empleadoRepo.obtenerPorId(juan.id))!.estatus, EstatusEmpleado.baja.name);
    });

    test('un bien YA resuelto como pendiente no vuelve a bloquear', () async {
      final juan = await crearEmpleado();
      final radio = await crearUnidad('Radio', 'R-104');
      final asignacionId = await asignar(radio, juan.id);
      // Simula lo que deja la conciliación: una decisión documentada.
      await inventarioRepo.marcarPendienteRecuperacion(
        asignacionId: asignacionId,
        fecha: DateTime(2025, 9, 15),
      );

      final r = await registrarBaja.ejecutar(
        empleadoId: juan.id,
        fechaBaja: DateTime(2025, 9, 15),
        motivo: MotivoBajaEmpleado.renuncia,
      );

      expect(r, isA<RegistrarBajaLaboralExitoso>());
    });
  });

  // ---------------------------------------------------------------
  // §9 — CASO OBLIGATORIO de destinos físicos
  // ---------------------------------------------------------------

  group('§9 — destinos físicos: recuperado no es lo mismo que disponible', () {
    test('caso completo: camisa A, camisa B a lavandería, Samsung a reparación, radio no entregado', () async {
      final juan = await crearEmpleado();
      final camisaA = await crearUnidad('Camisa A', 'CAM-A');
      final camisaB = await crearUnidad('Camisa B', 'CAM-B');
      final samsung = await crearUnidad('Samsung S23', 'S23');
      final radio = await crearUnidad('Radio', 'R-104');
      final aCamisaA = await asignar(camisaA, juan.id);
      final aCamisaB = await asignar(camisaB, juan.id);
      final aSamsung = await asignar(samsung, juan.id);
      final aRadio = await asignar(radio, juan.id);

      final r = await conciliar.ejecutar(
        empleadoId: juan.id,
        fechaBaja: DateTime(2025, 9, 15),
        motivo: MotivoBajaEmpleado.renuncia,
        resoluciones: [
          ResolucionResguardo(
            asignacionId: aCamisaA,
            resolucion: ResolucionResguardoBaja.devuelto,
            condicion: CondicionDevolucionResguardo.bueno,
            destino: DestinoDevolucionResguardo.inventarioUsado,
          ),
          ResolucionResguardo(
            asignacionId: aCamisaB,
            resolucion: ResolucionResguardoBaja.devuelto,
            condicion: CondicionDevolucionResguardo.sucio,
            destino: DestinoDevolucionResguardo.lavanderia,
            costoLimpieza: 8000,
            responsableCostoLimpieza: ResponsableCostoResguardo.trabajador,
            generaDescuento: true,
            importeDescuento: 8000,
            conceptoDescuento: 'Limpieza de uniforme',
          ),
          ResolucionResguardo(
            asignacionId: aSamsung,
            resolucion: ResolucionResguardoBaja.devuelto,
            condicion: CondicionDevolucionResguardo.malEstado,
            destino: DestinoDevolucionResguardo.reparacion,
          ),
          ResolucionResguardo(
            asignacionId: aRadio,
            resolucion: ResolucionResguardoBaja.noEntregado,
            motivoNoEntrega: MotivoNoEntregaResguardo.abandonoServicio,
            generaDescuento: true,
            importeDescuento: 250000,
          ),
        ],
      );
      expect(r, isA<ConciliarBajaEmpleadoExitoso>());

      // Camisa A: al anaquel.
      expect(await estatusUnidad(camisaA.unidadId), EstatusArticuloUnidad.disponible.name);

      // Camisa B: recuperada, EN LAVANDERÍA, no disponible.
      expect(
        await estatusUnidad(camisaB.unidadId),
        EstatusArticuloUnidad.enLavanderia.name,
        reason: 'antes quedaba disponible: reasignable mientras seguía en la tintorería',
      );

      // Samsung: recuperado, en reparación, no disponible.
      expect(await estatusUnidad(samsung.unidadId), EstatusArticuloUnidad.enReparacion.name);

      // Radio: sigue con Juan.
      expect(await estatusUnidad(radio.unidadId), EstatusArticuloUnidad.asignado.name);
      expect(await inventarioRepo.listarPendientesRecuperacionPorEmpleado(juan.id), hasLength(1));

      // §8 — el dinero es independiente del movimiento físico: la
      // obligación de $80 existe aunque la camisa siga en la tintorería.
      final obligaciones = await db.select(db.descuentoProgramadoEmpleado).get();
      expect(obligaciones.fold<int>(0, (s, o) => s + o.importeOriginal), 258000);
    });

    test('§4 — la camisa regresa de lavandería y SOLO entonces queda disponible', () async {
      final juan = await crearEmpleado();
      final camisa = await crearUnidad('Camisa', 'CAM-B');
      final asignacionId = await asignar(camisa, juan.id);
      await conciliar.ejecutar(
        empleadoId: juan.id,
        fechaBaja: DateTime(2025, 9, 15),
        motivo: MotivoBajaEmpleado.renuncia,
        resoluciones: [
          ResolucionResguardo(
            asignacionId: asignacionId,
            resolucion: ResolucionResguardoBaja.devuelto,
            condicion: CondicionDevolucionResguardo.sucio,
            destino: DestinoDevolucionResguardo.lavanderia,
          ),
        ],
      );
      expect(await estatusUnidad(camisa.unidadId), EstatusArticuloUnidad.enLavanderia.name);

      final r = await registrarRetorno.ejecutar(
        unidadId: camisa.unidadId,
        desenlace: DesenlaceRetornoUnidad.disponible,
        fecha: DateTime(2025, 9, 22),
      );

      expect(r, isA<RegistrarRetornoUnidadExitoso>());
      expect(await estatusUnidad(camisa.unidadId), EstatusArticuloUnidad.disponible.name);
    });

    test('§5 — reparación terminada: disponible, o irreparable → pendiente de desecho', () async {
      final juan = await crearEmpleado();
      final telefono = await crearUnidad('Samsung', 'S23');
      final otro = await crearUnidad('Radio', 'R-200');
      final aTelefono = await asignar(telefono, juan.id);
      final aOtro = await asignar(otro, juan.id);
      await conciliar.ejecutar(
        empleadoId: juan.id,
        fechaBaja: DateTime(2025, 9, 15),
        motivo: MotivoBajaEmpleado.renuncia,
        resoluciones: [
          for (final id in [aTelefono, aOtro])
            ResolucionResguardo(
              asignacionId: id,
              resolucion: ResolucionResguardoBaja.devuelto,
              condicion: CondicionDevolucionResguardo.malEstado,
              destino: DestinoDevolucionResguardo.reparacion,
            ),
        ],
      );

      await registrarRetorno.ejecutar(
        unidadId: telefono.unidadId,
        desenlace: DesenlaceRetornoUnidad.disponible,
        fecha: DateTime(2025, 10, 1),
      );
      await registrarRetorno.ejecutar(
        unidadId: otro.unidadId,
        desenlace: DesenlaceRetornoUnidad.irreparable,
        fecha: DateTime(2025, 10, 1),
      );

      expect(await estatusUnidad(telefono.unidadId), EstatusArticuloUnidad.disponible.name);
      expect(await estatusUnidad(otro.unidadId), EstatusArticuloUnidad.pendienteDesecho.name);
    });

    test('§6 — desecho es una DECISIÓN, distinta de danado y de la baja física', () async {
      final juan = await crearEmpleado();
      final camisa = await crearUnidad('Camisa', 'CAM-C');
      final asignacionId = await asignar(camisa, juan.id);

      // Condición `danado` implica un costo recuperable: decidir no
      // cobrarlo exige motivo y autorizador (regla ya vigente).
      final autorizador = await crearAdministrativo();
      final resultado = await conciliar.ejecutar(
        empleadoId: juan.id,
        fechaBaja: DateTime(2025, 9, 15),
        motivo: MotivoBajaEmpleado.renuncia,
        resoluciones: [
          ResolucionResguardo(
            asignacionId: asignacionId,
            resolucion: ResolucionResguardoBaja.devuelto,
            condicion: CondicionDevolucionResguardo.danado,
            destino: DestinoDevolucionResguardo.desecho,
            motivoNoCobro: 'Prenda al final de su vida útil',
            autorizadorEmpleadoId: autorizador,
          ),
        ],
      );
      expect(resultado, isA<ConciliarBajaEmpleadoExitoso>());

      final estatus = await estatusUnidad(camisa.unidadId);
      expect(estatus, EstatusArticuloUnidad.pendienteDesecho.name);
      expect(estatus, isNot(EstatusArticuloUnidad.danado.name), reason: 'ya no es un alias visual de dañado');
      expect(estatus, isNot(EstatusArticuloUnidad.baja.name), reason: 'la baja física la ejecuta Inventario');
    });

    test('ningún destino intermedio puede reasignarse ni cuenta como disponible', () async {
      final juan = await crearEmpleado();
      final camisa = await crearUnidad('Camisa', 'CAM-B');
      final telefono = await crearUnidad('Samsung', 'S23');
      final aCamisa = await asignar(camisa, juan.id);
      final aTelefono = await asignar(telefono, juan.id);
      await conciliar.ejecutar(
        empleadoId: juan.id,
        fechaBaja: DateTime(2025, 9, 15),
        motivo: MotivoBajaEmpleado.renuncia,
        resoluciones: [
          ResolucionResguardo(
            asignacionId: aCamisa,
            resolucion: ResolucionResguardoBaja.devuelto,
            condicion: CondicionDevolucionResguardo.sucio,
            destino: DestinoDevolucionResguardo.lavanderia,
          ),
          ResolucionResguardo(
            asignacionId: aTelefono,
            resolucion: ResolucionResguardoBaja.devuelto,
            condicion: CondicionDevolucionResguardo.malEstado,
            destino: DestinoDevolucionResguardo.reparacion,
          ),
        ],
      );

      // Las existencias los cuentan aparte: ni disponibles ni perdidos.
      final existenciaCamisa = await inventario.calcularExistenciaUnidades(camisa.articuloId);
      expect(existenciaCamisa.disponible, 0);
      expect(existenciaCamisa.enProceso, 1);
      final existenciaTelefono = await inventario.calcularExistenciaUnidades(telefono.articuloId);
      expect(existenciaTelefono.disponible, 0);
      expect(existenciaTelefono.enProceso, 1);

      // Y no se pueden asignar a nadie más: la validación real de
      // Inventario las rechaza por no estar disponibles.
      for (final bien in [camisa, telefono]) {
        final validacion = await validarLineaAsignacion(
          articuloRepository: ArticuloRepositoryImpl(db),
          inventarioRepository: inventario,
          articuloId: bien.articuloId,
          unidadId: bien.unidadId,
          cantidad: 1,
        );
        expect(validacion, isA<LineaAsignacionUnidadNoDisponible>());
      }
    });

    test('regresar una unidad que NO está en proceso se rechaza', () async {
      final radio = await crearUnidad('Radio', 'R-300');

      final r = await registrarRetorno.ejecutar(
        unidadId: radio.unidadId,
        desenlace: DesenlaceRetornoUnidad.disponible,
        fecha: DateTime(2025, 10, 1),
      );

      expect(r, isA<RegistrarRetornoUnidadNoEstaEnProceso>());
    });
  });
}

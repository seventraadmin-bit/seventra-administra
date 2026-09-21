import 'package:riseg_one/features/finanzas/domain/politica_saldo_cuenta.dart';
import 'package:riseg_one/features/finanzas/data/repositories/cuenta_financiera_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/domain/origen_financiero_gasto.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/attachments/attachment_repository.dart';
import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/asignacion_vehiculo_repository_impl.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/vehiculo_kilometraje_repository_impl.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/vehiculo_mantenimiento_repository_impl.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/vehiculo_repository_impl.dart';
import 'package:riseg_one/features/vehiculos/data/tables/vehiculo_kilometraje_table.dart';
import 'package:riseg_one/features/vehiculos/data/tables/vehiculo_mantenimiento_table.dart';
import 'package:riseg_one/features/vehiculos/data/tables/vehiculo_table.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/adjuntar_comprobante_mantenimiento_vehiculo_usecase.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/asignar_vehiculo_usecase.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/calcular_costos_vehiculo.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/calcular_proximo_mantenimiento.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/cambiar_estatus_vehiculo_usecase.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/crear_vehiculo_usecase.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/dar_de_baja_vehiculo_usecase.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/finalizar_mantenimiento_vehiculo_usecase.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/registrar_mantenimiento_vehiculo_usecase.dart';

/// Cubre Mantenimiento, incidencias y costos de Vehículos (Etapa 8D) —
/// las 15 pruebas explícitamente pedidas por Marlon. El caso "vehículo
/// dado de baja no genera nuevas alertas operativas" se cubre en
/// `test/smoke_test.dart` (requiere pumpear la pantalla real de
/// Alertas), no aquí.
void main() {
  late AppDatabase db;
  late VehiculoRepositoryImpl vehiculoRepo;
  late VehiculoKilometrajeRepositoryImpl kilometrajeRepo;
  late VehiculoMantenimientoRepositoryImpl mantenimientoRepo;
  late AsignacionVehiculoRepositoryImpl asignacionRepo;
  late AttachmentRepository attachmentRepo;
  late CrearVehiculoUseCase crearVehiculo;
  late CambiarEstatusVehiculoUseCase cambiarEstatus;
  late DarDeBajaVehiculoUseCase darDeBaja;
  late AsignarVehiculoUseCase asignarVehiculo;
  late RegistrarMantenimientoVehiculoUseCase registrarMantenimiento;
  late AdjuntarComprobanteMantenimientoVehiculoUseCase adjuntarComprobante;
  late FinalizarMantenimientoVehiculoUseCase finalizarMantenimiento;
  late Directory tempDir;
  late CuentaFinancieraRepositoryImpl cuentaRepo;
  // Desde la schemaVersion 80, TODO gasto con costo debe decir de dónde
  // salió el dinero — estas pruebas de la Etapa 8D usan esta cuenta.
  late String cuentaId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    asignacionRepo = AsignacionVehiculoRepositoryImpl(db);
    vehiculoRepo = VehiculoRepositoryImpl(db, asignacionRepo);
    kilometrajeRepo = VehiculoKilometrajeRepositoryImpl(db);
    mantenimientoRepo = VehiculoMantenimientoRepositoryImpl(db);
    attachmentRepo = AttachmentRepository(db);
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));

    crearVehiculo = CrearVehiculoUseCase(vehiculoRepo, generarCodigo);
    cambiarEstatus = CambiarEstatusVehiculoUseCase(vehiculoRepo);
    darDeBaja = DarDeBajaVehiculoUseCase(vehiculoRepo);
    asignarVehiculo = AsignarVehiculoUseCase(vehiculoRepo, asignacionRepo, kilometrajeRepo);
    registrarMantenimiento = RegistrarMantenimientoVehiculoUseCase(mantenimientoRepo, vehiculoRepo, kilometrajeRepo, DeudaRepositoryImpl(db, EgresoRepositoryImpl(db)));
    finalizarMantenimiento = FinalizarMantenimientoVehiculoUseCase(vehiculoRepo, asignacionRepo);

    cuentaRepo = CuentaFinancieraRepositoryImpl(db);
    cuentaId = (await cuentaRepo.crear(
      codigo: 'CTA-0001',
      nombre: 'BBVA Empresarial',
      tipo: 'banco',
      saldoInicial: 100000000,
      fechaSaldoInicial: DateTime(2026, 1, 1),
    ))
        .id;

    tempDir = Directory.systemTemp.createTempSync('riseg_mantenimiento_vehiculo_test_');
    adjuntarComprobante = AdjuntarComprobanteMantenimientoVehiculoUseCase(mantenimientoRepo, AttachmentStorage(tempDir.path));
  });

  tearDown(() {
    db.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<VehiculoData> crearVehiculoDePrueba() async {
    final resultado = await crearVehiculo.ejecutar(marca: 'BMW', modelo: '320i', tipoVehiculo: 'sedan');
    return (resultado as CrearVehiculoExitoso).vehiculo;
  }

  Future<EmpleadoData> crearEmpleadoDePrueba() {
    return db.into(db.empleado).insertReturning(
          EmpleadoCompanion.insert(
            numeroEmpleado: 1,
            nombres: 'Juan',
            apellidoPaterno: 'Pérez',
            sexo: 'masculino',
            fechaNacimiento: DateTime(1990, 1, 1),
            curp: 'PEXJ900101HDFXXX01',
            rfc: 'PEXJ900101AB1',
            nss: '12345678901',
            estadoCivil: 'soltero',
            fechaIngreso: DateTime(2026, 1, 1),
            aniosExperienciaSeguridad: 3,
          ),
        );
  }

  group('RegistrarMantenimientoVehiculoUseCase', () {
    test('alta de mantenimiento', () async {
      final vehiculo = await crearVehiculoDePrueba();
      final resultado = await registrarMantenimiento.ejecutar(
        vehiculoId: vehiculo.id,
        fecha: DateTime(2026, 1, 10),
        tipo: 'preventivo',
        descripcion: 'Cambio de aceite y filtros',
      );
      expect(resultado, isA<RegistrarMantenimientoVehiculoExitoso>());
      final registro = (resultado as RegistrarMantenimientoVehiculoExitoso).registro;
      expect(registro.tipo, 'preventivo');
    });

    test('rechaza descripción vacía', () async {
      final vehiculo = await crearVehiculoDePrueba();
      final resultado = await registrarMantenimiento.ejecutar(
        vehiculoId: vehiculo.id,
        fecha: DateTime(2026, 1, 10),
        tipo: 'preventivo',
        descripcion: '   ',
      );
      expect(resultado, isA<RegistrarMantenimientoVehiculoDescripcionRequerida>());
    });

    test('mantenimiento con kilometraje se integra al ledger VehiculoKilometraje (punto 4)', () async {
      final vehiculo = await crearVehiculoDePrueba();
      await registrarMantenimiento.ejecutar(
        vehiculoId: vehiculo.id,
        fecha: DateTime(2026, 1, 10),
        kilometraje: 15000,
        tipo: 'servicioGeneral',
        descripcion: 'Servicio de 15,000 km',
      );

      final actual = await kilometrajeRepo.obtenerActual(vehiculo.id);
      expect(actual, isNotNull);
      expect(actual!.kilometraje, 15000);
      expect(actual.origen, OrigenKilometrajeVehiculo.mantenimiento.name, reason: 'nunca una fuente paralela de kilometraje');
    });

    test('mantenimiento sin kilometraje sigue siendo válido y no toca el ledger', () async {
      final vehiculo = await crearVehiculoDePrueba();
      final resultado = await registrarMantenimiento.ejecutar(
        vehiculoId: vehiculo.id,
        fecha: DateTime(2026, 1, 10),
        tipo: 'llantas',
        descripcion: 'Rotación de llantas',
      );
      expect(resultado, isA<RegistrarMantenimientoVehiculoExitoso>());
      expect(await kilometrajeRepo.obtenerActual(vehiculo.id), isNull);
    });

    test('rechaza kilometraje menor al último conocido', () async {
      final vehiculo = await crearVehiculoDePrueba();
      await registrarMantenimiento.ejecutar(
        vehiculoId: vehiculo.id,
        fecha: DateTime(2026, 1, 1),
        kilometraje: 20000,
        tipo: 'preventivo',
        descripcion: 'Servicio',
      );

      final resultado = await registrarMantenimiento.ejecutar(
        vehiculoId: vehiculo.id,
        fecha: DateTime(2026, 2, 1),
        kilometraje: 18000,
        tipo: 'preventivo',
        descripcion: 'Otro servicio',
      );
      expect(resultado, isA<RegistrarMantenimientoVehiculoKilometrajeMenorAlActual>());
      expect((resultado as RegistrarMantenimientoVehiculoKilometrajeMenorAlActual).actual, 20000);
    });

    test('incidencia con costo', () async {
      final vehiculo = await crearVehiculoDePrueba();
      final resultado = await registrarMantenimiento.ejecutar(
        vehiculoId: vehiculo.id,
        fecha: DateTime(2026, 1, 10),
        tipo: 'golpe',
        descripcion: 'Golpe en la puerta trasera derecha',
        costo: 250000,
        origen: OrigenFinancieroCuenta(cuentaId),
      );
      final registro = (resultado as RegistrarMantenimientoVehiculoExitoso).registro;
      expect(registro.costo, 250000);
      expect(TipoMantenimientoVehiculo.values.byName(registro.tipo).esIncidencia, isTrue);
    });

    test('incidencia sin costo', () async {
      final vehiculo = await crearVehiculoDePrueba();
      final resultado = await registrarMantenimiento.ejecutar(
        vehiculoId: vehiculo.id,
        fecha: DateTime(2026, 1, 10),
        tipo: 'averia',
        descripcion: 'Falla eléctrica menor, resuelta en sitio',
      );
      final registro = (resultado as RegistrarMantenimientoVehiculoExitoso).registro;
      expect(registro.costo, isNull);
    });

    test('comprobante adjunto', () async {
      final vehiculo = await crearVehiculoDePrueba();
      final registro = ((await registrarMantenimiento.ejecutar(
        vehiculoId: vehiculo.id,
        fecha: DateTime(2026, 1, 10),
        tipo: 'frenos',
        descripcion: 'Cambio de balatas delanteras',
      )) as RegistrarMantenimientoVehiculoExitoso)
          .registro;

      final archivo = '${tempDir.path}/comprobante.pdf';
      File(archivo).writeAsStringSync('contenido de prueba');
      final resultado = await adjuntarComprobante.ejecutar(
        vehiculoMantenimientoId: registro.id,
        sourceFilePath: archivo,
        originalFileName: 'comprobante.pdf',
        mimeType: 'application/pdf',
      );
      expect(resultado, isA<AdjuntarComprobanteMantenimientoVehiculoExitoso>());

      final adjuntos = await attachmentRepo.listarActivosPorVehiculoMantenimiento(registro.id);
      expect(adjuntos, hasLength(1));
      expect(File(adjuntos.single.path).existsSync(), isTrue);
    });

    test('vehículo dado de baja conserva el histórico de mantenimiento', () async {
      final vehiculo = await crearVehiculoDePrueba();
      await registrarMantenimiento.ejecutar(
        vehiculoId: vehiculo.id,
        fecha: DateTime(2026, 1, 10),
        tipo: 'preventivo',
        descripcion: 'Servicio previo a la baja',
      );
      await darDeBaja.ejecutar(vehiculoId: vehiculo.id, fechaBaja: DateTime(2026, 3, 1), motivoBaja: MotivoBajaVehiculo.venta);

      final historial = await mantenimientoRepo.listarPorVehiculo(vehiculo.id);
      expect(historial, hasLength(1), reason: 'la baja no borra ni oculta el histórico de mantenimiento');
    });
  });

  group('calcularProximoMantenimiento', () {
    test('próximo por fecha (dentro del umbral)', () {
      final registro = _mantenimientoDePrueba(proximoFecha: DateTime(2026, 1, 20));
      final resultado = calcularProximoMantenimiento([registro], null, hoy: DateTime(2026, 1, 10));
      expect(resultado!.estado, EstadoProximoMantenimiento.proximo);
    });

    test('próximo por kilometraje (dentro del umbral)', () {
      final registro = _mantenimientoDePrueba(proximoKilometraje: 20500);
      final resultado = calcularProximoMantenimiento([registro], 20000, hoy: DateTime(2026, 1, 10));
      expect(resultado!.estado, EstadoProximoMantenimiento.proximo);
    });

    test('vencido (fecha ya pasada)', () {
      final registro = _mantenimientoDePrueba(proximoFecha: DateTime(2026, 1, 1));
      final resultado = calcularProximoMantenimiento([registro], null, hoy: DateTime(2026, 1, 10));
      expect(resultado!.estado, EstadoProximoMantenimiento.vencido);
    });

    test('vencido (kilometraje ya alcanzado)', () {
      final registro = _mantenimientoDePrueba(proximoKilometraje: 19000);
      final resultado = calcularProximoMantenimiento([registro], 20000, hoy: DateTime(2026, 1, 10));
      expect(resultado!.estado, EstadoProximoMantenimiento.vencido);
    });

    test('sin programar → null', () {
      final registro = _mantenimientoDePrueba();
      expect(calcularProximoMantenimiento([registro], null), isNull);
    });
  });

  group('Estatus operativo (Etapa 8D, punto 3)', () {
    test('cambio de estatus a enMantenimiento', () async {
      final vehiculo = await crearVehiculoDePrueba();
      final resultado = await cambiarEstatus.ejecutar(vehiculoId: vehiculo.id, estatus: 'enMantenimiento');
      expect(resultado, isA<CambiarEstatusVehiculoExitoso>());
      expect((resultado as CambiarEstatusVehiculoExitoso).vehiculo.estatus, 'enMantenimiento');
    });

    test('al finalizar mantenimiento, retorna a asignado si hay asignación vigente', () async {
      final vehiculo = await crearVehiculoDePrueba();
      final empleado = await crearEmpleadoDePrueba();
      await asignarVehiculo.ejecutar(vehiculoId: vehiculo.id, empleadoId: empleado.id, fechaInicio: DateTime(2026, 1, 1));
      // Se envía a mantenimiento saltando el bloqueo de UI (mismo
      // escenario ya documentado en la Etapa 8B: el estatus puede
      // divergir manualmente de la asignación vigente).
      await cambiarEstatus.ejecutar(vehiculoId: vehiculo.id, estatus: 'enMantenimiento');

      final resultado = await finalizarMantenimiento.ejecutar(vehiculoId: vehiculo.id);
      expect(resultado, isA<FinalizarMantenimientoVehiculoExitoso>());
      expect((resultado as FinalizarMantenimientoVehiculoExitoso).vehiculo.estatus, 'asignado');
    });

    test('al finalizar mantenimiento, retorna a disponible si no hay asignación vigente', () async {
      final vehiculo = await crearVehiculoDePrueba();
      await cambiarEstatus.ejecutar(vehiculoId: vehiculo.id, estatus: 'enMantenimiento');

      final resultado = await finalizarMantenimiento.ejecutar(vehiculoId: vehiculo.id);
      expect(resultado, isA<FinalizarMantenimientoVehiculoExitoso>());
      expect((resultado as FinalizarMantenimientoVehiculoExitoso).vehiculo.estatus, 'disponible');
    });

    test('rechaza finalizar mantenimiento si el Vehículo no está enMantenimiento', () async {
      final vehiculo = await crearVehiculoDePrueba();
      final resultado = await finalizarMantenimiento.ejecutar(vehiculoId: vehiculo.id);
      expect(resultado, isA<FinalizarMantenimientoVehiculoNoEstaEnMantenimiento>());
    });
  });

  group('calcularCostosVehiculo (punto 6)', () {
    test('costos acumulados separan mantenimiento de incidencias, sin depreciación', () async {
      final creado = await crearVehiculo.ejecutar(
        marca: 'BMW',
        modelo: '320i',
        tipoVehiculo: 'sedan',
        costoAdquisicion: 30000000,
      );
      final vehiculo = (creado as CrearVehiculoExitoso).vehiculo;

      await registrarMantenimiento.ejecutar(
        vehiculoId: vehiculo.id,
        fecha: DateTime(2026, 1, 1),
        tipo: 'preventivo',
        descripcion: 'Servicio',
        costo: 150000,
        origen: OrigenFinancieroCuenta(cuentaId),
      );
      await registrarMantenimiento.ejecutar(
        vehiculoId: vehiculo.id,
        fecha: DateTime(2026, 2, 1),
        tipo: 'golpe',
        descripcion: 'Golpe lateral',
        costo: 500000,
        origen: OrigenFinancieroCuenta(cuentaId),
      );
      await registrarMantenimiento.ejecutar(
        vehiculoId: vehiculo.id,
        fecha: DateTime(2026, 3, 1),
        tipo: 'llantas',
        descripcion: 'Sin costo capturado',
      );

      final historial = await mantenimientoRepo.listarPorVehiculo(vehiculo.id);
      final costos = calcularCostosVehiculo(vehiculo, historial);

      expect(costos.costoAdquisicion, 30000000);
      expect(costos.totalMantenimientos, 150000);
      expect(costos.totalIncidencias, 500000);
      expect(costos.costoOperativoAcumulado, 30000000 + 150000 + 500000);
    });
  });

  group('Política de saldo (v91) — Vehículos', () {
    Future<CuentaFinancieraData> cuentaCon(int saldo) {
      return db.into(db.cuentaFinanciera).insertReturning(
        CuentaFinancieraCompanion.insert(
          codigo: 'CTA-VEH-$saldo',
          nombre: 'Cuenta vehículos',
          tipo: 'banco',
          saldoInicial: saldo,
          fechaSaldoInicial: DateTime(2026, 1, 1),
        ),
      );
    }

    test('A) con saldo suficiente: el mantenimiento se registra', () async {
      final vehiculo = await crearVehiculoDePrueba();
      final cuenta = await cuentaCon(300000);
      final resultado = await registrarMantenimiento.ejecutar(
        vehiculoId: vehiculo.id,
        fecha: DateTime(2026, 1, 10),
        tipo: 'preventivo',
        descripcion: 'Cambio de aceite',
        costo: 300000,
        origen: OrigenFinancieroCuenta(cuenta.id),
      );
      expect(resultado, isA<RegistrarMantenimientoVehiculoExitoso>());
    });

    test('B y C) sin saldo: rechaza y NO deja persistencia parcial', () async {
      final vehiculo = await crearVehiculoDePrueba();
      final cuenta = await cuentaCon(299999);

      await expectLater(
        registrarMantenimiento.ejecutar(
          vehiculoId: vehiculo.id,
          fecha: DateTime(2026, 1, 10),
          tipo: 'preventivo',
          descripcion: 'Cambio de aceite',
          costo: 300000,
          origen: OrigenFinancieroCuenta(cuenta.id),
        ),
        throwsA(isA<SaldoInsuficienteException>()),
      );

      expect(await db.select(db.vehiculoMantenimiento).get(), isEmpty, reason: 'ni el mantenimiento');
      expect(await db.select(db.egreso).get(), isEmpty, reason: 'ni el Egreso');
      expect(await db.select(db.egresoFuente).get(), isEmpty, reason: 'ni su fuente');
    });
  });
}

VehiculoMantenimientoData _mantenimientoDePrueba({DateTime? proximoFecha, int? proximoKilometraje}) {
  final ahora = DateTime(2026, 1, 1);
  return VehiculoMantenimientoData(
    id: 'mantenimiento-prueba',
    vehiculoId: 'vehiculo-prueba',
    fecha: ahora,
    kilometraje: null,
    tipo: 'preventivo',
    descripcion: 'Servicio de prueba',
    tallerProveedor: null,
    costo: null,
    proximoMantenimientoFecha: proximoFecha,
    proximoMantenimientoKilometraje: proximoKilometraje,
    observaciones: null,
    createdAt: ahora,
    updatedAt: ahora,
    cicloVidaRegistro: 'activo',
    estatus: 'registrado',
  );
}

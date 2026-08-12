// Etapa 14B (Centro de notificaciones) — pruebas de los use cases
// nuevos: filtrado de Vehículos por tipo (reutiliza
// ObtenerAlertasVehiculosUseCase sin tocarlo), DocumentoPorEmitir
// "requiere acción" (función extraída, ya no duplicada con la
// Agenda), CxC próxima/vencida (mutuamente excluyentes), Pagos de
// hoy, y la guardia real de permiso en ObtenerNotificacionesUseCase.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/attachments/attachment_repository.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/repositories/cuenta_por_cobrar_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/pago_repository_impl.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/cuenta_por_cobrar_repository.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/pago_repository.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cuenta_por_cobrar_antiguedad.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/documento_por_emitir_repository_impl.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/cliente_repository.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/documento_por_emitir_repository.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/documento_por_emitir_requiere_accion.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/asignacion_vehiculo_repository_impl.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/vehiculo_documento_repository_impl.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/vehiculo_kilometraje_repository_impl.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/vehiculo_mantenimiento_repository_impl.dart';
import 'package:riseg_one/features/vehiculos/data/repositories/vehiculo_repository_impl.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/obtener_alertas_vehiculos_usecase.dart';

import 'package:riseg_one/features/notificaciones/domain/usecases/obtener_notificaciones_cxc_usecase.dart';
import 'package:riseg_one/features/notificaciones/domain/usecases/obtener_notificaciones_documentos_por_emitir_usecase.dart';
import 'package:riseg_one/features/notificaciones/domain/usecases/obtener_notificaciones_pagos_usecase.dart';
import 'package:riseg_one/features/notificaciones/domain/usecases/obtener_notificaciones_usecase.dart';
import 'package:riseg_one/features/notificaciones/domain/usecases/obtener_notificaciones_vehiculos_usecase.dart';

class _DocumentoRepoVacio implements DocumentoPorEmitirRepository {
  var llamado = false;
  @override
  Future<List<DocumentoPorEmitirData>> listar({
    DateTime? rangoInicio,
    DateTime? rangoFin,
    String? clienteId,
    String? servicioId,
    String? tipoDocumento,
    String? estatus,
  }) async {
    llamado = true;
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _CuentaRepoVacio implements CuentaPorCobrarRepository {
  var llamado = false;
  @override
  Future<List<CuentaPorCobrarData>> listar({
    String? clienteId,
    String? servicioId,
    String? entidadFiscalId,
    String? tipoDocumento,
    String? estatus,
    String? documentoPorEmitirId,
  }) async {
    llamado = true;
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _PagoRepoVacio implements PagoRepository {
  var llamado = false;
  @override
  Future<List<PagoData>> listar({String? clienteId, String? estatus, String? formaPago, DateTime? rangoInicio, DateTime? rangoFin}) async {
    llamado = true;
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  group('documentoPorEmitirRequiereAccion (función extraída)', () {
    DocumentoPorEmitirData documentoDePrueba({required String estatus, DateTime? fechaEmisionProgramada}) {
      final ahora = DateTime(2026, 1, 1);
      return DocumentoPorEmitirData(
        id: 'doc-1',
        createdAt: ahora,
        updatedAt: ahora,
        cicloVidaRegistro: 'activo',
        codigo: 'DOC-001',
        clienteId: 'cliente-1',
        tipoDocumento: 'cfdi',
        agrupacion: 'porServicio',
        metodo: 'pue',
        requiereComplemento: false,
        periodoInicio: ahora,
        periodoFin: ahora,
        fechaEmisionProgramada: fechaEmisionProgramada,
        generationKey: 'key-1',
        importeBaseEsperado: 10000,
        importeFinalEsperado: 10000,
        estatus: estatus,
      );
    }

    test('pendiente con fecha pasada requiere acción', () {
      final documento = documentoDePrueba(estatus: 'pendiente', fechaEmisionProgramada: DateTime(2026, 1, 1));
      expect(documentoPorEmitirRequiereAccion(documento, DateTime(2026, 1, 10)), isTrue);
    });

    test('emitido con la misma fecha pasada NO requiere acción', () {
      final documento = documentoDePrueba(estatus: 'emitido', fechaEmisionProgramada: DateTime(2026, 1, 1));
      expect(documentoPorEmitirRequiereAccion(documento, DateTime(2026, 1, 10)), isFalse);
    });

    test('enPreparacion con fecha futura NO requiere acción', () {
      final documento = documentoDePrueba(estatus: 'enPreparacion', fechaEmisionProgramada: DateTime(2026, 2, 1));
      expect(documentoPorEmitirRequiereAccion(documento, DateTime(2026, 1, 10)), isFalse);
    });

    test('sin fecha de emisión programada NO requiere acción', () {
      final documento = documentoDePrueba(estatus: 'pendiente', fechaEmisionProgramada: null);
      expect(documentoPorEmitirRequiereAccion(documento, DateTime(2026, 1, 10)), isFalse);
    });
  });

  group('diasParaVencerCxc', () {
    CuentaPorCobrarData cuentaDePrueba({required String estatus, DateTime? fechaVencimiento}) {
      final ahora = DateTime(2026, 1, 1);
      return CuentaPorCobrarData(
        id: 'cxc-1',
        createdAt: ahora,
        updatedAt: ahora,
        cicloVidaRegistro: 'activo',
        documentoPorEmitirId: 'doc-1',
        clienteId: 'cliente-1',
        tipoDocumento: 'cfdi',
        metodo: 'pue',
        requiereComplemento: false,
        fechaEmisionReal: ahora,
        importeEmitido: 50000,
        saldoOriginal: 50000,
        saldoPendiente: 50000,
        moneda: 'MXN',
        estatus: estatus,
        fechaVencimiento: fechaVencimiento,
      );
    }

    test('cuenta pendiente con vencimiento en 5 días retorna 5', () {
      final cuenta = cuentaDePrueba(estatus: 'pendiente', fechaVencimiento: DateTime(2026, 1, 15));
      expect(diasParaVencerCxc(cuenta, DateTime(2026, 1, 10)), 5);
    });

    test('cuenta pagada retorna null aunque tenga fecha de vencimiento', () {
      final cuenta = cuentaDePrueba(estatus: 'pagada', fechaVencimiento: DateTime(2026, 1, 15));
      expect(diasParaVencerCxc(cuenta, DateTime(2026, 1, 10)), isNull);
    });

    test('sin fecha de vencimiento retorna null', () {
      final cuenta = cuentaDePrueba(estatus: 'pendiente', fechaVencimiento: null);
      expect(diasParaVencerCxc(cuenta, DateTime(2026, 1, 10)), isNull);
    });
  });

  group('ObtenerNotificacionesVehiculosUseCase', () {
    late AppDatabase db;
    late ObtenerNotificacionesVehiculosUseCase obtenerNotificaciones;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      final asignacionRepo = AsignacionVehiculoRepositoryImpl(db);
      final vehiculoRepo = VehiculoRepositoryImpl(db, asignacionRepo);
      final documentoRepo = VehiculoDocumentoRepositoryImpl(db);
      final mantenimientoRepo = VehiculoMantenimientoRepositoryImpl(db);
      final kilometrajeRepo = VehiculoKilometrajeRepositoryImpl(db);
      final obtenerAlertas = ObtenerAlertasVehiculosUseCase(vehiculoRepo, documentoRepo, mantenimientoRepo, kilometrajeRepo);
      obtenerNotificaciones = ObtenerNotificacionesVehiculosUseCase(obtenerAlertas);
      addTearDown(db.close);
    });

    Future<String> crearVehiculo({String estatus = 'disponible'}) async {
      final vehiculo = await db.into(db.vehiculo).insertReturning(
            VehiculoCompanion.insert(
              codigo: 'VH-001',
              marca: 'Nissan',
              modelo: 'NP300',
              tipoVehiculo: 'pickup',
              estatus: Value(estatus),
              fechaBaja: estatus == 'baja' ? Value(DateTime(2025, 1, 1)) : const Value.absent(),
              motivoBaja: estatus == 'baja' ? const Value('venta') : const Value.absent(),
            ),
          );
      return vehiculo.id;
    }

    Future<void> crearDocumento(String vehiculoId, {required String tipo, required DateTime fechaVencimiento}) {
      return db.into(db.vehiculoDocumento).insert(
            VehiculoDocumentoCompanion.insert(vehiculoId: vehiculoId, tipo: tipo, fechaVencimiento: Value(fechaVencimiento)),
          );
    }

    test('verificación vencida aparece en el grupo correcto', () async {
      final vehiculoId = await crearVehiculo();
      await crearDocumento(vehiculoId, tipo: 'verificacion', fechaVencimiento: DateTime(2020, 1, 1));

      final resultado = await obtenerNotificaciones.ejecutar(hoy: DateTime(2026, 1, 1));

      expect(resultado.verificacion, hasLength(1));
      expect(resultado.verificacion.single.urgente, isTrue);
      expect(resultado.tenenciaRefrendo, isEmpty);
      expect(resultado.verificacion.single.ruta, '/vehiculos/flotilla/$vehiculoId');
    });

    test('tenencia/refrendo vigente (vencimiento lejano) NO aparece', () async {
      final vehiculoId = await crearVehiculo();
      await crearDocumento(vehiculoId, tipo: 'tenenciaRefrendo', fechaVencimiento: DateTime(2030, 1, 1));

      final resultado = await obtenerNotificaciones.ejecutar(hoy: DateTime(2026, 1, 1));

      expect(resultado.tenenciaRefrendo, isEmpty);
    });

    test('vehículo en baja con documento vencido NO aparece (regresión del use case reutilizado)', () async {
      final vehiculoId = await crearVehiculo(estatus: 'baja');
      await crearDocumento(vehiculoId, tipo: 'verificacion', fechaVencimiento: DateTime(2020, 1, 1));

      final resultado = await obtenerNotificaciones.ejecutar(hoy: DateTime(2026, 1, 1));

      expect(resultado.verificacion, isEmpty);
    });

    test('mantenimiento (otro tipo de alerta del use case reutilizado) nunca se filtra hacia acá', () async {
      final vehiculoId = await crearVehiculo();
      await crearDocumento(vehiculoId, tipo: 'seguro', fechaVencimiento: DateTime(2020, 1, 1));

      final resultado = await obtenerNotificaciones.ejecutar(hoy: DateTime(2026, 1, 1));

      expect(resultado.verificacion, isEmpty);
      expect(resultado.tenenciaRefrendo, isEmpty);
    });
  });

  group('ObtenerNotificacionesDocumentosPorEmitirUseCase', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
    });

    Future<String> crearCliente() async {
      final cliente = await db.into(db.cliente).insertReturning(
            ClienteCompanion.insert(codigo: 'CLI-001', nombreComercial: 'Residencial Alfa'),
          );
      return cliente.id;
    }

    Future<void> crearDocumento(String clienteId, {required String estatus, DateTime? fechaEmisionProgramada}) {
      final ahora = DateTime(2026, 1, 1);
      return db.into(db.documentoPorEmitir).insert(
            DocumentoPorEmitirCompanion.insert(
              codigo: 'DOC-${DateTime.now().microsecondsSinceEpoch}',
              clienteId: clienteId,
              tipoDocumento: 'cfdi',
              agrupacion: 'porServicio',
              metodo: 'pue',
              periodoInicio: ahora,
              periodoFin: ahora,
              fechaEmisionProgramada: Value(fechaEmisionProgramada),
              generationKey: 'key-${DateTime.now().microsecondsSinceEpoch}',
              importeBaseEsperado: 10000,
              importeFinalEsperado: 10000,
              estatus: Value(estatus),
            ),
          );
    }

    test('pendiente con fecha pasada aparece con el nombre del Cliente resuelto', () async {
      final clienteId = await crearCliente();
      await crearDocumento(clienteId, estatus: 'pendiente', fechaEmisionProgramada: DateTime(2025, 12, 1));

      final useCase = ObtenerNotificacionesDocumentosPorEmitirUseCase(
        DocumentoPorEmitirRepositoryImpl(db, AttachmentRepository(db), CuentaPorCobrarRepositoryImpl(db)),
        ClienteRepositoryImpl(db),
      );

      final resultado = await useCase.ejecutar(hoy: DateTime(2026, 1, 10));

      expect(resultado, hasLength(1));
      expect(resultado.single.titulo, 'Residencial Alfa');
      expect(resultado.single.ruta, '/comercial/agenda');
    });
  });

  group('ObtenerNotificacionesCxcUseCase — próxima y vencida son mutuamente excluyentes', () {
    late AppDatabase db;
    late CuentaPorCobrarRepository cuentaRepo;
    late ClienteRepository clienteRepo;
    late ObtenerNotificacionesCxcUseCase obtenerNotificaciones;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      cuentaRepo = CuentaPorCobrarRepositoryImpl(db);
      clienteRepo = ClienteRepositoryImpl(db);
      obtenerNotificaciones = ObtenerNotificacionesCxcUseCase(cuentaRepo, clienteRepo);
      addTearDown(db.close);
    });

    Future<String> crearClienteYDocumento() async {
      final cliente = await db.into(db.cliente).insertReturning(
            ClienteCompanion.insert(codigo: 'CLI-001', nombreComercial: 'Residencial Beta'),
          );
      final ahora = DateTime(2026, 1, 1);
      final documento = await db.into(db.documentoPorEmitir).insertReturning(
            DocumentoPorEmitirCompanion.insert(
              codigo: 'DOC-1',
              clienteId: cliente.id,
              tipoDocumento: 'cfdi',
              agrupacion: 'porServicio',
              metodo: 'pue',
              periodoInicio: ahora,
              periodoFin: ahora,
              generationKey: 'key-1',
              importeBaseEsperado: 50000,
              importeFinalEsperado: 50000,
            ),
          );
      return documento.id;
    }

    Future<void> crearCuenta(String documentoId, {required DateTime? fechaVencimiento, String estatus = 'pendiente'}) async {
      final cliente = (await db.select(db.documentoPorEmitir).get()).first;
      await db.into(db.cuentaPorCobrar).insert(
            CuentaPorCobrarCompanion.insert(
              documentoPorEmitirId: documentoId,
              clienteId: cliente.clienteId,
              tipoDocumento: 'cfdi',
              metodo: 'pue',
              fechaEmisionReal: DateTime(2026, 1, 1),
              importeEmitido: 50000,
              saldoOriginal: 50000,
              saldoPendiente: 50000,
              fechaVencimiento: Value(fechaVencimiento),
              estatus: Value(estatus),
            ),
          );
    }

    test('cuenta con vencimiento en 5 días aparece en próxima, no en vencida', () async {
      final documentoId = await crearClienteYDocumento();
      await crearCuenta(documentoId, fechaVencimiento: DateTime(2026, 1, 15));

      final resultado = await obtenerNotificaciones.ejecutar(hoy: DateTime(2026, 1, 10));

      expect(resultado.proximasAVencer, hasLength(1));
      expect(resultado.vencidas, isEmpty);
    });

    test('cuenta vencida hace 10 días aparece en vencida, no en próxima', () async {
      final documentoId = await crearClienteYDocumento();
      await crearCuenta(documentoId, fechaVencimiento: DateTime(2025, 12, 31));

      final resultado = await obtenerNotificaciones.ejecutar(hoy: DateTime(2026, 1, 10));

      expect(resultado.vencidas, hasLength(1));
      expect(resultado.vencidas.single.urgente, isTrue);
      expect(resultado.proximasAVencer, isEmpty);
    });

    test('cuenta pagada no aparece en ninguno de los dos grupos', () async {
      final documentoId = await crearClienteYDocumento();
      await crearCuenta(documentoId, fechaVencimiento: DateTime(2025, 12, 31), estatus: 'pagada');

      final resultado = await obtenerNotificaciones.ejecutar(hoy: DateTime(2026, 1, 10));

      expect(resultado.vencidas, isEmpty);
      expect(resultado.proximasAVencer, isEmpty);
    });
  });

  group('ObtenerNotificacionesPagosUseCase', () {
    late AppDatabase db;
    late ObtenerNotificacionesPagosUseCase obtenerNotificaciones;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      obtenerNotificaciones = ObtenerNotificacionesPagosUseCase(PagoRepositoryImpl(db), ClienteRepositoryImpl(db));
      addTearDown(db.close);
    });

    Future<String> crearClienteYPago(DateTime fechaPago) async {
      final cliente = await db.into(db.cliente).insertReturning(
            ClienteCompanion.insert(codigo: 'CLI-001', nombreComercial: 'Residencial Gama'),
          );
      await db.into(db.pago).insert(
            PagoCompanion.insert(folioPago: 'PAG-001', clienteId: cliente.id, montoTotal: 100000, fechaPago: fechaPago, formaPago: 'transferencia'),
          );
      return cliente.id;
    }

    test('pago de hoy aparece', () async {
      await crearClienteYPago(DateTime(2026, 1, 10));

      final resultado = await obtenerNotificaciones.ejecutar(hoy: DateTime(2026, 1, 10));

      expect(resultado, hasLength(1));
      expect(resultado.single.titulo, 'Residencial Gama');
    });

    test('pago de ayer NO aparece (ventana de un solo día)', () async {
      await crearClienteYPago(DateTime(2026, 1, 9));

      final resultado = await obtenerNotificaciones.ejecutar(hoy: DateTime(2026, 1, 10));

      expect(resultado, isEmpty);
    });
  });

  group('ObtenerNotificacionesUseCase — guardia real de permiso', () {
    test('cada incluirXxx en false nunca invoca su repositorio', () async {
      final documentoRepo = _DocumentoRepoVacio();
      final cuentaRepo = _CuentaRepoVacio();
      final pagoRepo = _PagoRepoVacio();

      final db = AppDatabase(NativeDatabase.memory());
      final asignacionRepo = AsignacionVehiculoRepositoryImpl(db);
      final vehiculoRepo = VehiculoRepositoryImpl(db, asignacionRepo);
      final vehiculoDocumentoRepo = VehiculoDocumentoRepositoryImpl(db);
      final mantenimientoRepo = VehiculoMantenimientoRepositoryImpl(db);
      final kilometrajeRepo = VehiculoKilometrajeRepositoryImpl(db);
      final obtenerAlertas = ObtenerAlertasVehiculosUseCase(vehiculoRepo, vehiculoDocumentoRepo, mantenimientoRepo, kilometrajeRepo);
      final clienteRepo = ClienteRepositoryImpl(db);

      final useCase = ObtenerNotificacionesUseCase(
        ObtenerNotificacionesVehiculosUseCase(obtenerAlertas),
        ObtenerNotificacionesDocumentosPorEmitirUseCase(documentoRepo, clienteRepo),
        ObtenerNotificacionesCxcUseCase(cuentaRepo, clienteRepo),
        ObtenerNotificacionesPagosUseCase(pagoRepo, clienteRepo),
      );

      final resultado = await useCase.ejecutar(incluirVehiculos: false, incluirComercial: false, incluirFinanzas: false);

      expect(resultado.total, 0);
      expect(documentoRepo.llamado, isFalse);
      expect(cuentaRepo.llamado, isFalse);
      expect(pagoRepo.llamado, isFalse);

      await db.close();
    });
  });
}

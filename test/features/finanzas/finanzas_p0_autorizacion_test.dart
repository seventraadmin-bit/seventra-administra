// Etapa 0 (auditoría de consistencia transversal — corrección de un
// hueco real de autorización): cinco operaciones de Finanzas leían su
// `Provider<UseCase>` crudo directo desde la pantalla, sin pasar por
// ningún `autorizarUseCase`/fachada `...AutorizadoProvider` — Registrar
// Egreso manual, Registrar Ingreso manual, alta/edición/archivado de
// Categoría financiera, Cancelar aplicación de Pago desde CxC y
// Reprogramar cobro desde Planeación. Ya corregidas; esta prueba solo
// demuestra que la corrección enforza el permiso real.
//
// Mismo patrón que `test/features/usuarios/authorization_service_test.dart`
// (`_SesionFija`/`_container`, llamada directa al Controller o a la
// fachada autorizada, sin montar ningún widget) combinado con las
// aserciones antes/después contra el repositorio real de
// `corregir_tiempo_extra_autorizacion_test.dart`: un usuario sin el
// permiso exacto nunca debe dejar rastro en la base de datos, y ningún
// Egreso/Ingreso/Pago/CuentaPorCobrar de más aparece por el intento
// rechazado.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/actualizar_categoria_financiera_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/archivar_categoria_financiera_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cancelar_aplicacion_pago_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/crear_categoria_financiera_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_egreso_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_ingreso_manual_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/reprogramar_cobro_cuenta_por_cobrar_usecase.dart';
import 'package:riseg_one/features/finanzas/finanzas_providers.dart';
import 'package:riseg_one/features/finanzas/presentation/egresos/egresos_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/ingresos/ingresos_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/pagos/pagos_controller.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import '../../support/sesion_en_base.dart';

/// Mismo mensaje que produce `autorizarUseCase` (`core/permissions/
/// authorization_service.dart`) — reutilizado tal cual en
/// `authorization_service_test.dart`.
const _mensajePermiso = 'No tiene permiso para realizar esta acción.';

/// Sesión de prueba fija (mismo patrón que `_SesionFija` en
/// `authorization_service_test.dart`) — un solo `usuarioId` real para
/// todos los perfiles; solo cambia el conjunto de permisos bajo prueba
/// en cada test.
class _SesionFija extends SesionController {
  _SesionFija(this._sesion);
  final SesionUsuario? _sesion;

  @override
  SesionUsuario? build() => _sesion;
}

SesionUsuario _sesionCon(Set<String> permisos) => SesionUsuario(
      usuarioId: 'usuario-prueba',
      nombre: 'Usuario de prueba',
      nombreUsuario: 'prueba',
      esMaestro: false,
      permisos: permisos,
    );

Future<ProviderContainer> _container(AppDatabase db, SesionUsuario sesion) async {
  // Etapa 3B: la autorización se revalida contra la base, así que
  // el escenario de ESTA prueba se persiste aquí — no en el `setUp`,
  // porque cada prueba declara su propio conjunto de permisos y
  // sembrar uno solo volvería positivas las pruebas negativas.
  await sembrarSesionEnBase(db, sesion);
  final container = ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      sesionControllerProvider.overrideWith(() => _SesionFija(sesion)),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// FK real hacia `Usuario` (Etapa 11D): cualquier evento que escriban
/// estos casos de uso (`actorUsuarioId`) exige que la fila exista.
Future<void> _sembrarUsuarioDePrueba(AppDatabase db) async {
  await db.into(db.usuario).insert(
        UsuarioCompanion.insert(
          id: const Value('usuario-prueba'),
          nombre: 'Usuario de prueba',
          nombreUsuario: 'usuario-prueba',
          passwordHash: 'x',
        ),
      );
}

/// Cliente + `DocumentoPorEmitir` ya `procesadoAceptado` + su Cuenta
/// por cobrar — mismo atajo de inserción directa que
/// `pago_cancelar_cxc_provider_test.dart` (aquí solo hace falta que la
/// Cuenta exista, no recorrer todo el flujo real de Configuración de
/// cobro/Línea comercial que la genera en producción).
Future<({String clienteId, String cuentaId})> _crearCuentaPorCobrarDePrueba(
  AppDatabase db, {
  int importeEmitido = 100000,
}) async {
  final sufijo = DateTime.now().microsecondsSinceEpoch;
  final cliente = await db.into(db.cliente).insertReturning(
        ClienteCompanion.insert(codigo: 'CLI-P0-$sufijo', nombreComercial: 'Cliente P0'),
      );
  final documento = await db.into(db.documentoPorEmitir).insertReturning(
        DocumentoPorEmitirCompanion.insert(
          codigo: 'DOC-P0-$sufijo',
          clienteId: cliente.id,
          tipoDocumento: 'reciboDePago',
          agrupacion: 'porServicio',
          metodo: 'noAplica',
          periodoInicio: DateTime(2026, 1, 1),
          periodoFin: DateTime(2026, 1, 31),
          generationKey: 'GK-P0-$sufijo',
          importeBaseEsperado: importeEmitido,
          importeFinalEsperado: importeEmitido,
          estatus: const Value('procesadoAceptado'),
        ),
      );
  final cuenta = await db.into(db.cuentaPorCobrar).insertReturning(
        CuentaPorCobrarCompanion.insert(
          documentoPorEmitirId: Value(documento.id),
          clienteId: Value(cliente.id),
          tipoDocumento: 'reciboDePago',
          metodo: 'noAplica',
          fechaEmisionReal: DateTime(2026, 1, 5),
          importeEmitido: importeEmitido,
          saldoOriginal: importeEmitido,
          saldoPendiente: importeEmitido,
        ),
      );
  return (clienteId: cliente.id, cuentaId: cuenta.id);
}

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await _sembrarUsuarioDePrueba(db);
  });

  tearDown(() => db.close());

  group('Registrar Egreso manual (egresos.crear) — EgresosController.registrar', () {
    test('sin egresos.crear no se registra ningún Egreso', () async {
      final container = await _container(db, _sesionCon({'finanzas.ver'}));

      final resultado = await container.read(egresosControllerProvider.notifier).registrar(
            monto: 150000,
            fecha: DateTime(2026, 9, 1),
            formaPago: 'efectivo',
            concepto: 'Papelería de oficina',
          );

      expect(resultado, isA<RegistrarEgresoErrorInesperado>());
      expect((resultado as RegistrarEgresoErrorInesperado).mensaje, _mensajePermiso);
      expect(
        await container.read(egresoRepositoryProvider).listar(),
        isEmpty,
        reason: 'nunca se crea el Egreso sin el permiso',
      );
    });

    test('con egresos.crear sí se registra el Egreso', () async {
      final container = await _container(db, _sesionCon({'finanzas.ver', 'egresos.crear'}));

      final resultado = await container.read(egresosControllerProvider.notifier).registrar(
            monto: 150000,
            fecha: DateTime(2026, 9, 1),
            formaPago: 'efectivo',
            concepto: 'Papelería de oficina',
          );

      expect(resultado, isA<RegistrarEgresoExitoso>());
      final egresos = await container.read(egresoRepositoryProvider).listar();
      expect(egresos, hasLength(1));
      expect(egresos.single.monto, 150000);
    });
  });

  group('Registrar Ingreso manual (ingresos.crear) — IngresosController.registrarManual', () {
    test('sin ingresos.crear no se registra ningún Ingreso', () async {
      final container = await _container(db, _sesionCon({'finanzas.ver'}));

      final resultado = await container.read(ingresosControllerProvider.notifier).registrarManual(
            monto: 80000,
            fecha: DateTime(2026, 9, 1),
            formaPago: 'efectivo',
            concepto: 'Ingreso de prueba',
          );

      expect(resultado, isA<RegistrarIngresoManualErrorInesperado>());
      expect((resultado as RegistrarIngresoManualErrorInesperado).mensaje, _mensajePermiso);
      expect(
        await container.read(ingresoRepositoryProvider).listar(),
        isEmpty,
        reason: 'nunca se crea el Ingreso sin el permiso',
      );
    });

    test('con ingresos.crear sí se registra el Ingreso', () async {
      final container = await _container(db, _sesionCon({'finanzas.ver', 'ingresos.crear'}));

      final resultado = await container.read(ingresosControllerProvider.notifier).registrarManual(
            monto: 80000,
            fecha: DateTime(2026, 9, 1),
            formaPago: 'efectivo',
            concepto: 'Ingreso de prueba',
          );

      expect(resultado, isA<RegistrarIngresoManualExitoso>());
      final ingresos = await container.read(ingresoRepositoryProvider).listar();
      expect(ingresos, hasLength(1));
      expect(ingresos.single.monto, 80000);
    });
  });

  group('Categoría financiera — crear/actualizar/archivar, tres permisos distintos', () {
    test('sin categoriasFinancieras.crear no se crea ninguna categoría', () async {
      final container = await _container(db, _sesionCon({'finanzas.ver'}));

      final resultado = await container.read(crearCategoriaFinancieraAutorizadoProvider)(
        codigo: 'CAT-P0-001',
        nombre: 'Papelería',
        tipo: 'egreso',
        tipoMovimiento: 'operativo',
      );

      expect(resultado, isA<CrearCategoriaFinancieraErrorInesperado>());
      expect((resultado as CrearCategoriaFinancieraErrorInesperado).mensaje, _mensajePermiso);
      expect(await container.read(categoriaFinancieraRepositoryProvider).listar(), isEmpty);
    });

    test('con categoriasFinancieras.crear sí se crea la categoría', () async {
      final container = await _container(db, _sesionCon({'finanzas.ver', 'categoriasFinancieras.crear'}));

      final resultado = await container.read(crearCategoriaFinancieraAutorizadoProvider)(
        codigo: 'CAT-P0-001',
        nombre: 'Papelería',
        tipo: 'egreso',
        tipoMovimiento: 'operativo',
      );

      expect(resultado, isA<CrearCategoriaFinancieraExitoso>());
      expect(await container.read(categoriaFinancieraRepositoryProvider).listar(), hasLength(1));
    });

    test('con categoriasFinancieras.crear (pero sin categoriasFinancieras.corregir) no se puede actualizar la categoría',
        () async {
      final containerCrear = await _container(db, _sesionCon({'categoriasFinancieras.crear'}));
      final creada = await containerCrear.read(crearCategoriaFinancieraAutorizadoProvider)(
        codigo: 'CAT-P0-002',
        nombre: 'Viáticos',
        tipo: 'egreso',
        tipoMovimiento: 'operativo',
      );
      final categoriaId = (creada as CrearCategoriaFinancieraExitoso).categoria.id;

      final resultado = await containerCrear.read(actualizarCategoriaFinancieraAutorizadoProvider)(
        id: categoriaId,
        codigo: 'CAT-P0-002',
        nombre: 'Viáticos corregido',
        tipo: 'egreso',
        tipoMovimiento: 'operativo',
      );

      expect(resultado, isA<ActualizarCategoriaFinancieraErrorInesperado>());
      expect((resultado as ActualizarCategoriaFinancieraErrorInesperado).mensaje, _mensajePermiso);
      final actual = await containerCrear.read(categoriaFinancieraRepositoryProvider).obtenerPorId(categoriaId);
      expect(actual!.nombre, 'Viáticos', reason: 'nunca se corrige sin categoriasFinancieras.corregir');
    });

    test('con categoriasFinancieras.corregir sí se puede actualizar la categoría', () async {
      final containerCrear = await _container(db, _sesionCon({'categoriasFinancieras.crear'}));
      final creada = await containerCrear.read(crearCategoriaFinancieraAutorizadoProvider)(
        codigo: 'CAT-P0-003',
        nombre: 'Viáticos',
        tipo: 'egreso',
        tipoMovimiento: 'operativo',
      );
      final categoriaId = (creada as CrearCategoriaFinancieraExitoso).categoria.id;

      final containerModificar = await _container(db, _sesionCon({'categoriasFinancieras.corregir'}));
      final resultado = await containerModificar.read(actualizarCategoriaFinancieraAutorizadoProvider)(
        id: categoriaId,
        codigo: 'CAT-P0-003',
        nombre: 'Viáticos corregido',
        tipo: 'egreso',
        tipoMovimiento: 'operativo',
      );

      expect(resultado, isA<ActualizarCategoriaFinancieraExitoso>());
      final actual = await containerModificar.read(categoriaFinancieraRepositoryProvider).obtenerPorId(categoriaId);
      expect(actual!.nombre, 'Viáticos corregido');
    });

    test('con categoriasFinancieras.crear (pero sin categoriasFinancieras.archivar) no se puede archivar la categoría',
        () async {
      final containerCrear = await _container(db, _sesionCon({'categoriasFinancieras.crear'}));
      final creada = await containerCrear.read(crearCategoriaFinancieraAutorizadoProvider)(
        codigo: 'CAT-P0-004',
        nombre: 'Ajustes varios',
        tipo: 'ambos',
        tipoMovimiento: 'financiero',
      );
      final categoriaId = (creada as CrearCategoriaFinancieraExitoso).categoria.id;

      final resultado = await containerCrear.read(archivarCategoriaFinancieraAutorizadoProvider)(categoriaId);

      expect(resultado, isA<ArchivarCategoriaFinancieraErrorInesperado>());
      expect((resultado as ArchivarCategoriaFinancieraErrorInesperado).mensaje, _mensajePermiso);
      final actual = await containerCrear.read(categoriaFinancieraRepositoryProvider).obtenerPorId(categoriaId);
      expect(actual!.cicloVidaRegistro, 'activo', reason: 'nunca se archiva sin categoriasFinancieras.archivar');
    });

    test('con categoriasFinancieras.archivar sí se puede archivar la categoría', () async {
      final containerCrear = await _container(db, _sesionCon({'categoriasFinancieras.crear'}));
      final creada = await containerCrear.read(crearCategoriaFinancieraAutorizadoProvider)(
        codigo: 'CAT-P0-005',
        nombre: 'Ajustes varios',
        tipo: 'ambos',
        tipoMovimiento: 'financiero',
      );
      final categoriaId = (creada as CrearCategoriaFinancieraExitoso).categoria.id;

      final containerArchivar = await _container(db, _sesionCon({'categoriasFinancieras.archivar'}));
      final resultado = await containerArchivar.read(archivarCategoriaFinancieraAutorizadoProvider)(categoriaId);

      expect(resultado, isA<ArchivarCategoriaFinancieraExitoso>());
      final actual = await containerArchivar.read(categoriaFinancieraRepositoryProvider).obtenerPorId(categoriaId);
      expect(actual!.cicloVidaRegistro, 'archivado');
    });
  });

  group('Cancelar aplicación de Pago desde CxC (pagos.cancelarAplicacion) — PagosController.cancelarAplicacion', () {
    test('sin pagos.cancelarAplicacion no se cancela la aplicación ni se revierte el saldo', () async {
      final base = await _crearCuentaPorCobrarDePrueba(db, importeEmitido: 100000);
      final container = await _container(db, _sesionCon({'finanzas.ver'}));
      final pagoRepo = container.read(pagoRepositoryProvider);
      final pago = await pagoRepo.crear(
        folioPago: 'PAG-P0-001',
        clienteId: base.clienteId,
        montoTotal: 100000,
        fechaPago: DateTime(2026, 1, 20),
        formaPago: 'efectivo',
      );
      final aplicacion = await pagoRepo.aplicar(pagoId: pago.id, cuentaPorCobrarId: base.cuentaId, monto: 100000);

      final resultado = await container.read(pagosControllerProvider.notifier).cancelarAplicacion(
            aplicacionPagoId: aplicacion.id,
            motivo: 'Intento sin permiso',
          );

      expect(resultado, isA<CancelarAplicacionPagoErrorInesperado>());
      expect((resultado as CancelarAplicacionPagoErrorInesperado).mensaje, _mensajePermiso);
      final aplicacionActual = await pagoRepo.obtenerAplicacionPorId(aplicacion.id);
      expect(aplicacionActual!.estatus, 'aplicada', reason: 'nunca se cancela sin el permiso');
      final cuentaActual = await container.read(cuentaPorCobrarRepositoryProvider).obtenerPorId(base.cuentaId);
      expect(cuentaActual!.saldoPendiente, 0, reason: 'el saldo no debe revertirse sin el permiso');
      expect(cuentaActual.estatus, 'pagada');
    });

    test('con pagos.cancelarAplicacion sí se cancela la aplicación y se revierte el saldo', () async {
      final base = await _crearCuentaPorCobrarDePrueba(db, importeEmitido: 100000);
      final container = await _container(db, _sesionCon({'pagos.cancelarAplicacion'}));
      final pagoRepo = container.read(pagoRepositoryProvider);
      final pago = await pagoRepo.crear(
        folioPago: 'PAG-P0-002',
        clienteId: base.clienteId,
        montoTotal: 100000,
        fechaPago: DateTime(2026, 1, 20),
        formaPago: 'efectivo',
      );
      final aplicacion = await pagoRepo.aplicar(pagoId: pago.id, cuentaPorCobrarId: base.cuentaId, monto: 100000);

      final resultado = await container.read(pagosControllerProvider.notifier).cancelarAplicacion(
            aplicacionPagoId: aplicacion.id,
            motivo: 'Aplicación duplicada por error',
          );

      expect(resultado, isA<CancelarAplicacionPagoExitoso>());
      final aplicacionActual = await pagoRepo.obtenerAplicacionPorId(aplicacion.id);
      expect(aplicacionActual!.estatus, 'cancelada');
      final cuentaActual = await container.read(cuentaPorCobrarRepositoryProvider).obtenerPorId(base.cuentaId);
      expect(cuentaActual!.saldoPendiente, 100000);
      expect(cuentaActual.estatus, 'pendiente');
    });
  });

  group(
      'Reprogramar cobro desde Planeación (cuentaPorCobrar.reprogramarCobro) — reprogramarCobroCuentaPorCobrarAutorizadoProvider',
      () {
    test('sin cuentaPorCobrar.reprogramarCobro no se reprograma el cobro', () async {
      final base = await _crearCuentaPorCobrarDePrueba(db);
      final container = await _container(db, _sesionCon({'finanzas.ver'}));

      final resultado = await container.read(reprogramarCobroCuentaPorCobrarAutorizadoProvider)(
        cuentaPorCobrarId: base.cuentaId,
        fechaCobroReprogramada: DateTime(2026, 10, 1),
        motivo: 'Cliente pidió más tiempo',
      );

      expect(resultado, isA<ReprogramarCobroCuentaPorCobrarErrorInesperado>());
      expect((resultado as ReprogramarCobroCuentaPorCobrarErrorInesperado).mensaje, _mensajePermiso);
      final actual = await container.read(cuentaPorCobrarRepositoryProvider).obtenerPorId(base.cuentaId);
      expect(actual!.fechaCobroReprogramada, isNull, reason: 'nunca se reprograma sin el permiso');
    });

    test('con cuentaPorCobrar.reprogramarCobro sí se reprograma el cobro', () async {
      final base = await _crearCuentaPorCobrarDePrueba(db);
      final container = await _container(db, _sesionCon({'cuentaPorCobrar.reprogramarCobro'}));

      final resultado = await container.read(reprogramarCobroCuentaPorCobrarAutorizadoProvider)(
        cuentaPorCobrarId: base.cuentaId,
        fechaCobroReprogramada: DateTime(2026, 10, 1),
        motivo: 'Cliente pidió más tiempo',
      );

      expect(resultado, isA<ReprogramarCobroCuentaPorCobrarExitoso>());
      final actual = await container.read(cuentaPorCobrarRepositoryProvider).obtenerPorId(base.cuentaId);
      expect(actual!.fechaCobroReprogramada, DateTime(2026, 10, 1));
    });
  });
}

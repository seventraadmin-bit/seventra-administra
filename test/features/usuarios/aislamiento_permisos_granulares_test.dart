// Etapa 1 — rediseño granular de permisos: el catálogo
// (`core/permissions/modulos_permiso.dart`) fue reescrito para que "un
// usuario reciba exactamente las facultades que necesita" (pedido
// explícito de Marlon), dividiendo códigos que antes colapsaban varias
// acciones distintas bajo un solo permiso (ej. `finanzas.crear` cubría
// Ingresos/Egresos/Deudas/Pagos/Cuentas financieras a la vez;
// `compras.crear` también cubría corregir; `personal.modificar` también
// cubría dar de baja).
//
// Esta suite no repite las pruebas de "el código correcto se exige"
// (ya cubiertas por `finanzas_p0_autorizacion_test.dart`,
// `personal_expediente_p0_autorizacion_test.dart`,
// `authorization_service_test.dart`, etc.) — su único propósito es
// demostrar la propiedad de AISLAMIENTO que motivó el rediseño: otorgar
// la facultad para una acción de un módulo NUNCA debe conceder
// implícitamente una acción hermana (ni dentro del mismo módulo, ej.
// `egresos.crear` no debe bastar para `egresos.corregir`, ni entre
// subdominios antes fusionados, ej. las facultades de Egresos no deben
// bastar para tocar Deudas ni Cuentas financieras, y viceversa).
//
// Mismo patrón que `authorization_service_test.dart`/
// `finanzas_p0_autorizacion_test.dart` (`_SesionFija`/`_sesionCon`,
// `ProviderContainer` con `appDatabaseProvider`/`sesionControllerProvider`
// sobrescritos, sin montar ningún widget) combinado con las
// aserciones antes/después contra el repositorio real de
// `corregir_tiempo_extra_autorizacion_test.dart`: un usuario sin el
// permiso exacto nunca debe dejar rastro en la base de datos.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cancelar_egreso_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/corregir_egreso_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_cuenta_financiera_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_deuda_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_egreso_usecase.dart';
import 'package:riseg_one/features/finanzas/finanzas_providers.dart';
import 'package:riseg_one/features/finanzas/presentation/egresos/egresos_controller.dart';
import 'package:riseg_one/features/nomina/data/tables/nomina_table.dart';
import 'package:riseg_one/features/nomina/domain/usecases/cancelar_pago_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/generar_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/registrar_pago_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/nomina_providers.dart';
import 'package:riseg_one/features/nomina/presentation/nominas/nominas_controller.dart';
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart';
import 'package:riseg_one/features/personal/domain/usecases/crear_empleado_usecase.dart';
import 'package:riseg_one/features/personal/domain/usecases/registrar_baja_laboral_usecase.dart';
import 'package:riseg_one/features/personal/personal_providers.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

/// Mismo mensaje que produce `autorizarUseCase` (`core/permissions/
/// authorization_service.dart`) — reutilizado tal cual en
/// `authorization_service_test.dart`/`finanzas_p0_autorizacion_test.dart`.
const _mensajePermiso = 'No tiene permiso para realizar esta acción.';

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

ProviderContainer _container(AppDatabase db, SesionUsuario sesion) {
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

/// Siembra un Egreso real llamando al caso de uso crudo (sin pasar por
/// ningún gate de permiso — mismo atajo que
/// `personal_expediente_p0_autorizacion_test.dart` usa con
/// `crearEmpleadoUseCaseProvider`) — el propósito de esta suite es
/// probar el aislamiento entre acciones YA existentes, no repetir la
/// prueba de "crear exige `egresos.crear`".
Future<String> _sembrarEgreso(AppDatabase db, {int monto = 150000}) async {
  final container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
  final resultado = await container.read(registrarEgresoUseCaseProvider).ejecutar(
        monto: monto,
        fecha: DateTime(2026, 9, 1),
        formaPago: 'efectivo',
        concepto: 'Papelería de oficina',
        actorUsuarioId: 'usuario-prueba',
      );
  container.dispose();
  return (resultado as RegistrarEgresoExitoso).egreso.id;
}

/// Empleado activo mínimo (mismo idioma que
/// `personal_expediente_p0_autorizacion_test.dart`), con sueldo
/// administrativo para que además pueda generar un renglón real de
/// Nómina cuando la escena lo requiera.
Future<String> _sembrarEmpleado(AppDatabase db, {int sueldoMensualAdministrativo = 1500000}) async {
  final container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
  final resultado = await container.read(crearEmpleadoUseCaseProvider).ejecutar(
        nombres: 'Juan',
        apellidoPaterno: 'Pérez',
        sexo: SexoEmpleado.masculino,
        fechaNacimiento: DateTime(1990, 1, 1),
        curp: 'PEXJ900101HDFXXX01',
        rfc: 'PEXJ900101AB1',
        nss: '12345678901',
        estadoCivil: EstadoCivilEmpleado.soltero,
        fechaIngreso: DateTime(2025, 1, 1),
        aniosExperienciaSeguridad: 3,
        sueldoMensualAdministrativo: sueldoMensualAdministrativo,
      );
  container.dispose();
  return (resultado as CrearEmpleadoExitoso).empleado.id;
}

/// Nómina cerrada + un PagoNomina ya registrado sobre el Empleado
/// sembrado — todo vía casos de uso crudos (sin gate de permiso), mismo
/// criterio que `_sembrarEgreso`: esta suite prueba aislamiento entre
/// acciones existentes, no la generación/cierre de Nómina en sí (ya
/// cubiertas en `test/features/nomina/`).
Future<String> _sembrarPagoNomina(AppDatabase db, String empleadoId) async {
  final container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
  final generado = await container.read(generarNominaUseCaseProvider).ejecutar(
        anio: 2026,
        mes: 1,
        tipo: TipoPeriodoNomina.primera,
      );
  final nominaId = (generado as GenerarNominaExitoso).nomina.id;
  await container.read(cerrarNominaUseCaseProvider).ejecutar(nominaId: nominaId);
  final renglon = (await container.read(nominaRepositoryProvider).listarEmpleados(nominaId)).single;

  final resultado = await container.read(registrarPagoNominaUseCaseProvider).ejecutar(
        nominaId: nominaId,
        fechaPago: DateTime(2026, 1, 20),
        formaPago: 'transferencia',
        cuentaFinancieraId: await _cuentaDePrueba(db),
        aplicaciones: [(nominaEmpleadoId: renglon.id, monto: renglon.totalAPagar)],
        actorUsuarioId: 'usuario-prueba',
      );
  container.dispose();
  return (resultado as RegistrarPagoNominaExitoso).pagoNomina.id;
}

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await _sembrarUsuarioDePrueba(db);
  });

  tearDown(() => db.close());

  group('1) Egresos — puede crear pero no corregir', () {
    test('con solo egresos.crear (+finanzas.ver), corregir un Egreso se rechaza y no cambia nada', () async {
      final egresoId = await _sembrarEgreso(db);
      final container = _container(db, _sesionCon({'finanzas.ver', 'egresos.crear'}));

      final resultado = await container.read(egresosControllerProvider.notifier).corregir(
            egresoId: egresoId,
            concepto: 'Intento sin permiso',
            motivo: 'Corrección no autorizada',
          );

      expect(resultado, isA<CorregirEgresoErrorInesperado>());
      expect((resultado as CorregirEgresoErrorInesperado).mensaje, _mensajePermiso);
      final actual = await container.read(egresoRepositoryProvider).obtenerPorId(egresoId);
      expect(actual!.concepto, 'Papelería de oficina', reason: 'egresos.crear no debe otorgar egresos.corregir');
    });

    test('con egresos.corregir además, sí puede corregir', () async {
      final egresoId = await _sembrarEgreso(db);
      final container = _container(db, _sesionCon({'finanzas.ver', 'egresos.crear', 'egresos.corregir'}));

      final resultado = await container.read(egresosControllerProvider.notifier).corregir(
            egresoId: egresoId,
            concepto: 'Concepto corregido',
            motivo: 'Corrección autorizada',
          );

      expect(resultado, isA<CorregirEgresoExitoso>());
      final actual = await container.read(egresoRepositoryProvider).obtenerPorId(egresoId);
      expect(actual!.concepto, 'Concepto corregido');
    });
  });

  group('2) Egresos — puede corregir pero no cancelar', () {
    test('con egresos.crear+corregir (sin egresos.cancelar), cancelar se rechaza y el estatus no cambia', () async {
      final egresoId = await _sembrarEgreso(db);
      final container = _container(db, _sesionCon({'finanzas.ver', 'egresos.crear', 'egresos.corregir'}));

      final resultado = await container.read(egresosControllerProvider.notifier).cancelar(
            egresoId: egresoId,
            motivo: 'Cancelación no autorizada',
          );

      expect(resultado, isA<CancelarEgresoErrorInesperado>());
      expect((resultado as CancelarEgresoErrorInesperado).mensaje, _mensajePermiso);
      final actual = await container.read(egresoRepositoryProvider).obtenerPorId(egresoId);
      expect(actual!.estatus, 'registrado', reason: 'egresos.corregir no debe otorgar egresos.cancelar');
    });

    test('con egresos.cancelar además, sí puede cancelar', () async {
      final egresoId = await _sembrarEgreso(db);
      final container = _container(db, _sesionCon({'finanzas.ver', 'egresos.crear', 'egresos.corregir', 'egresos.cancelar'}));

      final resultado = await container.read(egresosControllerProvider.notifier).cancelar(
            egresoId: egresoId,
            motivo: 'Cancelación autorizada',
          );

      expect(resultado, isA<CancelarEgresoExitoso>());
      final actual = await container.read(egresoRepositoryProvider).obtenerPorId(egresoId);
      expect(actual!.estatus, 'cancelado');
    });
  });

  group('3) Nómina — puede registrar pago pero no cancelarlo', () {
    test('con nomina.ver+registrarPago (sin nomina.cancelarPago), cancelar se rechaza y el estatus no cambia', () async {
      final empleadoId = await _sembrarEmpleado(db);
      final pagoNominaId = await _sembrarPagoNomina(db, empleadoId);
      final container = _container(db, _sesionCon({'nomina.ver', 'nomina.registrarPago'}));

      final resultado = await container.read(nominasControllerProvider.notifier).cancelarPago(
            pagoNominaId: pagoNominaId,
            motivo: 'Cancelación no autorizada',
          );

      expect(resultado, isA<CancelarPagoNominaErrorInesperado>());
      expect((resultado as CancelarPagoNominaErrorInesperado).mensaje, _mensajePermiso);
      final actual = await container.read(pagoNominaRepositoryProvider).obtenerPorId(pagoNominaId);
      expect(actual!.estatus, 'registrado', reason: 'nomina.registrarPago no debe otorgar nomina.cancelarPago');
    });

    test('con nomina.cancelarPago además, sí puede cancelar el pago', () async {
      final empleadoId = await _sembrarEmpleado(db);
      final pagoNominaId = await _sembrarPagoNomina(db, empleadoId);
      final container = _container(db, _sesionCon({'nomina.ver', 'nomina.registrarPago', 'nomina.cancelarPago'}));

      final resultado = await container.read(nominasControllerProvider.notifier).cancelarPago(
            pagoNominaId: pagoNominaId,
            motivo: 'Cancelación autorizada',
          );

      expect(resultado, isA<CancelarPagoNominaExitoso>());
      final actual = await container.read(pagoNominaRepositoryProvider).obtenerPorId(pagoNominaId);
      expect(actual!.estatus, 'cancelado');
    });
  });

  group('4) Personal — puede modificar pero no dar de baja', () {
    test('con personal.ver+modificar (sin personal.archivar), la Baja se rechaza y el Empleado sigue activo', () async {
      final empleadoId = await _sembrarEmpleado(db);
      final container = _container(db, _sesionCon({'personal.ver', 'personal.modificar'}));

      final resultado = await container.read(registrarBajaLaboralAutorizadoProvider)(
        empleadoId: empleadoId,
        fechaBaja: DateTime(2026, 6, 1),
        motivo: MotivoBajaEmpleado.renuncia,
      );

      expect(resultado, isA<RegistrarBajaLaboralErrorInesperado>());
      expect((resultado as RegistrarBajaLaboralErrorInesperado).mensaje, _mensajePermiso);
      final actual = await container.read(empleadoRepositoryProvider).obtenerPorId(empleadoId);
      expect(actual!.estatus, 'activo', reason: 'personal.modificar no debe otorgar personal.archivar');
      expect(actual.fechaBaja, isNull);
    });

    test('con personal.archivar además, sí puede dar de baja', () async {
      final empleadoId = await _sembrarEmpleado(db);
      final container = _container(db, _sesionCon({'personal.ver', 'personal.modificar', 'personal.archivar'}));

      final resultado = await container.read(registrarBajaLaboralAutorizadoProvider)(
        empleadoId: empleadoId,
        fechaBaja: DateTime(2026, 6, 1),
        motivo: MotivoBajaEmpleado.renuncia,
      );

      expect(resultado, isA<RegistrarBajaLaboralExitoso>());
      final actual = await container.read(empleadoRepositoryProvider).obtenerPorId(empleadoId);
      expect(actual!.estatus, 'baja');
    });
  });

  group('5) Finanzas — trabajar con Egresos no habilita registrar Deudas', () {
    test('con egresos.crear+corregir+cancelar (sin ningún deudas.*), registrar Deuda se rechaza y no crea nada', () async {
      final container = _container(db, _sesionCon({'egresos.crear', 'egresos.corregir', 'egresos.cancelar'}));

      final resultado = await container.read(registrarDeudaAutorizadoProvider)(
        nombre: 'Préstamo de prueba',
        tipo: 'prestamo',
        fechaOrigen: DateTime(2026, 1, 1),
        importeOriginal: 500000,
        saldoInicial: 500000,
      );

      expect(resultado, isA<RegistrarDeudaErrorInesperado>());
      expect((resultado as RegistrarDeudaErrorInesperado).mensaje, _mensajePermiso);
      expect(
        await container.read(deudaRepositoryProvider).listar(),
        isEmpty,
        reason: 'ninguna facultad de Egresos debe otorgar deudas.crear',
      );
    });

    test('con deudas.crear sí puede registrar la Deuda', () async {
      final container = _container(db, _sesionCon({'deudas.crear'}));

      final resultado = await container.read(registrarDeudaAutorizadoProvider)(
        nombre: 'Préstamo de prueba',
        tipo: 'prestamo',
        fechaOrigen: DateTime(2026, 1, 1),
        importeOriginal: 500000,
        saldoInicial: 500000,
      );

      expect(resultado, isA<RegistrarDeudaExitoso>());
      expect(await container.read(deudaRepositoryProvider).listar(), hasLength(1));
    });
  });

  group('6) Finanzas — gestionar Cuentas financieras no habilita Egresos (y viceversa)', () {
    test('con cuentasFinancieras.* (sin ningún egresos./ingresos./pagos./deudas.*), registrar Egreso se rechaza', () async {
      final container = _container(
        db,
        _sesionCon({'cuentasFinancieras.crear', 'cuentasFinancieras.corregir', 'cuentasFinancieras.cambiarEstatus'}),
      );

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
        reason: 'ninguna facultad de Cuentas financieras debe otorgar egresos.crear',
      );
    });

    test('con egresos.crear además, sí puede registrar el Egreso', () async {
      final container = _container(
        db,
        _sesionCon({'cuentasFinancieras.crear', 'cuentasFinancieras.corregir', 'cuentasFinancieras.cambiarEstatus', 'egresos.crear'}),
      );

      final resultado = await container.read(egresosControllerProvider.notifier).registrar(
            monto: 150000,
            fecha: DateTime(2026, 9, 1),
            formaPago: 'efectivo',
            concepto: 'Papelería de oficina',
          );

      expect(resultado, isA<RegistrarEgresoExitoso>());
      expect(await container.read(egresoRepositoryProvider).listar(), hasLength(1));
    });

    test('en dirección inversa: con solo egresos.crear, registrar Cuenta financiera se rechaza', () async {
      final container = _container(db, _sesionCon({'egresos.crear'}));

      final resultado = await container.read(registrarCuentaFinancieraAutorizadoProvider)(
        nombre: 'Cuenta de prueba',
        tipo: 'efectivo',
        saldoInicial: 100000,
        fechaSaldoInicial: DateTime(2026, 1, 1),
      );

      expect(resultado, isA<RegistrarCuentaFinancieraErrorInesperado>());
      expect((resultado as RegistrarCuentaFinancieraErrorInesperado).mensaje, _mensajePermiso);
      expect(
        await container.read(cuentaFinancieraRepositoryProvider).listar(),
        isEmpty,
        reason: 'ninguna facultad de Egresos debe otorgar cuentasFinancieras.crear',
      );
    });

    test('con cuentasFinancieras.crear sí puede registrar la Cuenta financiera', () async {
      final container = _container(db, _sesionCon({'cuentasFinancieras.crear'}));

      final resultado = await container.read(registrarCuentaFinancieraAutorizadoProvider)(
        nombre: 'Cuenta de prueba',
        tipo: 'efectivo',
        saldoInicial: 100000,
        fechaSaldoInicial: DateTime(2026, 1, 1),
      );

      expect(resultado, isA<RegistrarCuentaFinancieraExitoso>());
      expect(await container.read(cuentaFinancieraRepositoryProvider).listar(), hasLength(1));
    });
  });
}

/// La cuenta de origen de los pagos de Nómina en esta prueba.
///
/// Reutiliza la primera que el archivo ya haya creado; sólo inventa una
/// si no hay ninguna. Desde la Etapa de integridad financiera, un pago
/// de Nómina con monto > 0 exige cuenta: sin ella el Egreso nacería sin
/// origen y ningún saldo bajaría.
Future<String> _cuentaDePrueba(AppDatabase db) async {
  final existentes = await db.select(db.cuentaFinanciera).get();
  if (existentes.isNotEmpty) return existentes.first.id;
  final cuenta = await db.into(db.cuentaFinanciera).insertReturning(
        CuentaFinancieraCompanion.insert(
          codigo: 'CF-NOMINA-PRUEBA',
          nombre: 'Cuenta de prueba',
          tipo: 'banco',
          saldoInicial: 100000000, // fondeada: la v91 rechaza salidas sin saldo
          fechaSaldoInicial: DateTime(2020, 1, 1),
        ),
      );
  return cuenta.id;
}

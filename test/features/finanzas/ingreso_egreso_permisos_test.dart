// Etapa "Ingresos y Egresos: corrección, cancelación, origen automático
// y trazabilidad integral", Sección 17: `ingresos.crear`/`ingresos.
// corregir`/`ingresos.cancelar` y `egresos.crear`/`egresos.corregir`/
// `egresos.cancelar` son códigos INDEPENDIENTES — un usuario con
// exactamente uno puede realizar solo esa acción, nunca las otras. El
// Maestro tiene acceso completo sin necesitar ninguna fila de
// `PermisoUsuario`. Mismo patrón que `cuenta_por_cobrar_permisos_test.dart`:
// `_SesionFija`/`_container`, llamada directa al Controller, sin montar
// ningún widget.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cancelar_egreso_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cancelar_ingreso_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/corregir_egreso_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/corregir_ingreso_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_egreso_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_ingreso_manual_usecase.dart';
import 'package:riseg_one/features/finanzas/presentation/egresos/egresos_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/ingresos/ingresos_controller.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

const _mensajePermiso = 'No tiene permiso para realizar esta acción.';

class _SesionFija extends SesionController {
  _SesionFija(this._sesion);
  final SesionUsuario? _sesion;

  @override
  SesionUsuario? build() => _sesion;
}

SesionUsuario _sesionCon(Set<String> permisos, {bool esMaestro = false}) => SesionUsuario(
      usuarioId: 'usuario-prueba',
      nombre: 'Usuario de prueba',
      nombreUsuario: 'prueba',
      esMaestro: esMaestro,
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

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await _sembrarUsuarioDePrueba(db);
  });

  tearDown(() => db.close());

  group('Ingresos', () {
    test('ingresos.crear sin corregir/cancelar: SÍ registra, NO corrige, NO cancela', () async {
      final container = _container(db, _sesionCon({'ingresos.crear'}));
      final controller = container.read(ingresosControllerProvider.notifier);

      final registrado = await controller.registrarManual(monto: 100000, fecha: DateTime(2026, 1, 1), formaPago: 'efectivo', concepto: 'Concepto');
      expect(registrado, isA<RegistrarIngresoManualExitoso>());
      final ingresoId = (registrado as RegistrarIngresoManualExitoso).ingreso.id;

      final corregido = await controller.corregir(ingresoId: ingresoId, monto: 200000, motivo: 'Intento sin permiso');
      expect(corregido, isA<CorregirIngresoErrorInesperado>());
      expect((corregido as CorregirIngresoErrorInesperado).mensaje, _mensajePermiso);

      final cancelado = await controller.cancelar(ingresoId: ingresoId, motivo: 'Intento sin permiso');
      expect(cancelado, isA<CancelarIngresoErrorInesperado>());
      expect((cancelado as CancelarIngresoErrorInesperado).mensaje, _mensajePermiso);
    });

    test('ingresos.corregir sin crear/cancelar: SÍ corrige un Ingreso ya existente, NO registra, NO cancela', () async {
      final registrarSetup = _container(db, _sesionCon({'ingresos.crear'}));
      final registrado = await registrarSetup
          .read(ingresosControllerProvider.notifier)
          .registrarManual(monto: 100000, fecha: DateTime(2026, 1, 1), formaPago: 'efectivo', concepto: 'Concepto');
      final ingresoId = (registrado as RegistrarIngresoManualExitoso).ingreso.id;

      final container = _container(db, _sesionCon({'ingresos.corregir'}));
      final controller = container.read(ingresosControllerProvider.notifier);

      final registradoSinPermiso = await controller.registrarManual(monto: 100000, fecha: DateTime(2026, 1, 1), formaPago: 'efectivo', concepto: 'Concepto 2');
      expect(registradoSinPermiso, isA<RegistrarIngresoManualErrorInesperado>());
      expect((registradoSinPermiso as RegistrarIngresoManualErrorInesperado).mensaje, _mensajePermiso);

      final corregido = await controller.corregir(ingresoId: ingresoId, monto: 200000, motivo: 'Corrección con el permiso correcto');
      expect(corregido, isA<CorregirIngresoExitoso>());

      final cancelado = await controller.cancelar(ingresoId: ingresoId, motivo: 'Intento sin permiso');
      expect(cancelado, isA<CancelarIngresoErrorInesperado>());
      expect((cancelado as CancelarIngresoErrorInesperado).mensaje, _mensajePermiso);
    });

    test('ingresos.cancelar sin crear/corregir: SÍ cancela, NO registra, NO corrige', () async {
      final registrarSetup = _container(db, _sesionCon({'ingresos.crear'}));
      final registrado = await registrarSetup
          .read(ingresosControllerProvider.notifier)
          .registrarManual(monto: 100000, fecha: DateTime(2026, 1, 1), formaPago: 'efectivo', concepto: 'Concepto');
      final ingresoId = (registrado as RegistrarIngresoManualExitoso).ingreso.id;

      final container = _container(db, _sesionCon({'ingresos.cancelar'}));
      final controller = container.read(ingresosControllerProvider.notifier);

      final corregido = await controller.corregir(ingresoId: ingresoId, monto: 200000, motivo: 'Intento sin permiso');
      expect(corregido, isA<CorregirIngresoErrorInesperado>());
      expect((corregido as CorregirIngresoErrorInesperado).mensaje, _mensajePermiso);

      final cancelado = await controller.cancelar(ingresoId: ingresoId, motivo: 'Cancelación con el permiso correcto');
      expect(cancelado, isA<CancelarIngresoExitoso>());
    });

    test('Maestro: acceso completo sin ninguna fila de PermisoUsuario', () async {
      final container = _container(db, _sesionCon({}, esMaestro: true));
      final controller = container.read(ingresosControllerProvider.notifier);

      final registrado = await controller.registrarManual(monto: 100000, fecha: DateTime(2026, 1, 1), formaPago: 'efectivo', concepto: 'Concepto');
      expect(registrado, isA<RegistrarIngresoManualExitoso>());
      final ingresoId = (registrado as RegistrarIngresoManualExitoso).ingreso.id;

      final corregido = await controller.corregir(ingresoId: ingresoId, monto: 200000, motivo: 'Maestro corrige sin permisos otorgados');
      expect(corregido, isA<CorregirIngresoExitoso>());

      final cancelado = await controller.cancelar(ingresoId: ingresoId, motivo: 'Maestro cancela sin permisos otorgados');
      expect(cancelado, isA<CancelarIngresoExitoso>());
    });
  });

  group('Egresos', () {
    test('egresos.crear sin corregir/cancelar: SÍ registra, NO corrige, NO cancela', () async {
      final container = _container(db, _sesionCon({'egresos.crear'}));
      final controller = container.read(egresosControllerProvider.notifier);

      final registrado = await controller.registrar(monto: 100000, fecha: DateTime(2026, 1, 1), formaPago: 'efectivo', concepto: 'Concepto');
      expect(registrado, isA<RegistrarEgresoExitoso>());
      final egresoId = (registrado as RegistrarEgresoExitoso).egreso.id;

      final corregido = await controller.corregir(egresoId: egresoId, monto: 200000, motivo: 'Intento sin permiso');
      expect(corregido, isA<CorregirEgresoErrorInesperado>());
      expect((corregido as CorregirEgresoErrorInesperado).mensaje, _mensajePermiso);

      final cancelado = await controller.cancelar(egresoId: egresoId, motivo: 'Intento sin permiso');
      expect(cancelado, isA<CancelarEgresoErrorInesperado>());
      expect((cancelado as CancelarEgresoErrorInesperado).mensaje, _mensajePermiso);
    });

    test('egresos.corregir sin crear/cancelar: SÍ corrige un Egreso ya existente, NO registra, NO cancela', () async {
      final registrarSetup = _container(db, _sesionCon({'egresos.crear'}));
      final registrado = await registrarSetup
          .read(egresosControllerProvider.notifier)
          .registrar(monto: 100000, fecha: DateTime(2026, 1, 1), formaPago: 'efectivo', concepto: 'Concepto');
      final egresoId = (registrado as RegistrarEgresoExitoso).egreso.id;

      final container = _container(db, _sesionCon({'egresos.corregir'}));
      final controller = container.read(egresosControllerProvider.notifier);

      final registradoSinPermiso = await controller.registrar(monto: 100000, fecha: DateTime(2026, 1, 1), formaPago: 'efectivo', concepto: 'Concepto 2');
      expect(registradoSinPermiso, isA<RegistrarEgresoErrorInesperado>());
      expect((registradoSinPermiso as RegistrarEgresoErrorInesperado).mensaje, _mensajePermiso);

      final corregido = await controller.corregir(egresoId: egresoId, monto: 200000, motivo: 'Corrección con el permiso correcto');
      expect(corregido, isA<CorregirEgresoExitoso>());

      final cancelado = await controller.cancelar(egresoId: egresoId, motivo: 'Intento sin permiso');
      expect(cancelado, isA<CancelarEgresoErrorInesperado>());
      expect((cancelado as CancelarEgresoErrorInesperado).mensaje, _mensajePermiso);
    });

    test('egresos.cancelar sin crear/corregir: SÍ cancela, NO registra, NO corrige', () async {
      final registrarSetup = _container(db, _sesionCon({'egresos.crear'}));
      final registrado = await registrarSetup
          .read(egresosControllerProvider.notifier)
          .registrar(monto: 100000, fecha: DateTime(2026, 1, 1), formaPago: 'efectivo', concepto: 'Concepto');
      final egresoId = (registrado as RegistrarEgresoExitoso).egreso.id;

      final container = _container(db, _sesionCon({'egresos.cancelar'}));
      final controller = container.read(egresosControllerProvider.notifier);

      final corregido = await controller.corregir(egresoId: egresoId, monto: 200000, motivo: 'Intento sin permiso');
      expect(corregido, isA<CorregirEgresoErrorInesperado>());
      expect((corregido as CorregirEgresoErrorInesperado).mensaje, _mensajePermiso);

      final cancelado = await controller.cancelar(egresoId: egresoId, motivo: 'Cancelación con el permiso correcto');
      expect(cancelado, isA<CancelarEgresoExitoso>());
    });

    test('Maestro: acceso completo sin ninguna fila de PermisoUsuario', () async {
      final container = _container(db, _sesionCon({}, esMaestro: true));
      final controller = container.read(egresosControllerProvider.notifier);

      final registrado = await controller.registrar(monto: 100000, fecha: DateTime(2026, 1, 1), formaPago: 'efectivo', concepto: 'Concepto');
      expect(registrado, isA<RegistrarEgresoExitoso>());
      final egresoId = (registrado as RegistrarEgresoExitoso).egreso.id;

      final corregido = await controller.corregir(egresoId: egresoId, monto: 200000, motivo: 'Maestro corrige sin permisos otorgados');
      expect(corregido, isA<CorregirEgresoExitoso>());

      final cancelado = await controller.cancelar(egresoId: egresoId, motivo: 'Maestro cancela sin permisos otorgados');
      expect(cancelado, isA<CancelarEgresoExitoso>());
    });
  });
}

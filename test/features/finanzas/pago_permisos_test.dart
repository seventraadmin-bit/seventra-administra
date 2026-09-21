// Etapa 6 (Pagos de clientes — corrección completa, reaplicación y
// consistencia con CxC/Ingreso), Sección 15: `pagos.corregir` y
// `pagos.cancelar` son códigos INDEPENDIENTES — un usuario con uno
// pero no el otro puede realizar exactamente esa acción, nunca ambas.
// Mismo patrón que `finanzas_p0_autorizacion_test.dart` (`_SesionFija`/
// `_container`, llamada directa al Controller, sin montar ningún
// widget).

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cancelar_pago_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/corregir_pago_usecase.dart';
import 'package:riseg_one/features/finanzas/finanzas_providers.dart';
import 'package:riseg_one/features/finanzas/presentation/pagos/pagos_controller.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

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

Future<String> _crearPagoDePrueba(AppDatabase db) async {
  final sufijo = DateTime.now().microsecondsSinceEpoch;
  final cliente = await db.into(db.cliente).insertReturning(
        ClienteCompanion.insert(codigo: 'CLI-PERM-$sufijo', nombreComercial: 'Cliente Permisos'),
      );
  final pago = await db.into(db.pago).insertReturning(
        PagoCompanion.insert(
          folioPago: 'PAG-PERM-$sufijo',
          clienteId: Value(cliente.id),
          montoTotal: 100000,
          fechaPago: DateTime(2026, 1, 20),
          formaPago: 'efectivo',
        ),
      );
  return pago.id;
}

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await _sembrarUsuarioDePrueba(db);
  });

  tearDown(() => db.close());

  test('pagos.corregir sin pagos.cancelar: SÍ puede corregir, NO puede cancelar', () async {
    final pagoId = await _crearPagoDePrueba(db);
    final container = _container(db, _sesionCon({'pagos.corregir'}));

    final corregido = await container.read(pagosControllerProvider.notifier).corregir(
          pagoId: pagoId,
          referencia: 'REF-CORREGIDA',
          motivo: 'Corrección con el permiso correcto',
        );
    expect(corregido, isA<CorregirPagoExitoso>());
    expect((corregido as CorregirPagoExitoso).pago.referencia, 'REF-CORREGIDA');

    final cancelado = await container.read(pagosControllerProvider.notifier).cancelar(
          pagoId: pagoId,
          motivo: 'Intento sin pagos.cancelar',
        );
    expect(cancelado, isA<CancelarPagoErrorInesperado>());
    expect((cancelado as CancelarPagoErrorInesperado).mensaje, _mensajePermiso);
    final pagoTrasIntento = await container.read(pagoRepositoryProvider).obtenerPorId(pagoId);
    expect(pagoTrasIntento!.estatus, isNot('cancelado'), reason: 'nunca se cancela sin el permiso correcto');
  });

  test('pagos.cancelar sin pagos.corregir: SÍ puede cancelar, NO puede corregir', () async {
    final pagoId = await _crearPagoDePrueba(db);
    final container = _container(db, _sesionCon({'pagos.cancelar'}));

    final corregido = await container.read(pagosControllerProvider.notifier).corregir(
          pagoId: pagoId,
          referencia: 'REF-NO-DEBE-APLICAR',
          motivo: 'Intento sin pagos.corregir',
        );
    expect(corregido, isA<CorregirPagoErrorInesperado>());
    expect((corregido as CorregirPagoErrorInesperado).mensaje, _mensajePermiso);
    final pagoTrasIntento = await container.read(pagoRepositoryProvider).obtenerPorId(pagoId);
    expect(pagoTrasIntento!.referencia, isNot('REF-NO-DEBE-APLICAR'), reason: 'nunca se corrige sin el permiso correcto');

    final cancelado = await container.read(pagosControllerProvider.notifier).cancelar(
          pagoId: pagoId,
          motivo: 'Cancelación con el permiso correcto',
        );
    expect(cancelado, isA<CancelarPagoExitoso>());
    expect((cancelado as CancelarPagoExitoso).pago.estatus, 'cancelado');
  });
}

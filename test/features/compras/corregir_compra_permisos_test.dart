// Etapa 3 (Compras — corrección financiera completa Cuenta↔TDC),
// Sección 13: `compras.crear`/`compras.corregir`/`compras.cancelar`
// son códigos INDEPENDIENTES (Etapa 1) — esta corrección de origen
// financiero corre por el mismo `autorizarUseCase('compras.corregir', ...)`
// que ya protegía la corrección de datos generales, sin ninguna ruta
// alterna. Confirma que tener `compras.crear`/`compras.cancelar` (sin
// `compras.corregir`) NO alcanza para cambiar el origen financiero, y
// que `compras.corregir` (sin los otros dos) SÍ alcanza — y nada más.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/compras/compras_providers.dart';
import 'package:riseg_one/features/compras/data/tables/compra_partida_table.dart' show DestinoCompraPartida;
import 'package:riseg_one/features/compras/domain/repositories/compra_repository.dart' show PartidaCompraInput;
import 'package:riseg_one/features/compras/domain/usecases/cancelar_compra_usecase.dart';
import 'package:riseg_one/features/compras/domain/usecases/corregir_compra_usecase.dart';
import 'package:riseg_one/features/compras/domain/usecases/registrar_compra_usecase.dart';
import 'package:riseg_one/features/compras/presentation/compras_controller.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

class _SesionSinCorregir extends SesionController {
  @override
  SesionUsuario? build() {
    return const SesionUsuario(
      usuarioId: 'usuario-sin-corregir',
      nombre: 'Sin corregir',
      nombreUsuario: 'sin-corregir',
      esMaestro: false,
      // Tiene crear y cancelar, deliberadamente NO corregir.
      permisos: {'compras.crear', 'compras.cancelar', 'compras.ver'},
    );
  }
}

class _SesionSoloCorregir extends SesionController {
  @override
  SesionUsuario? build() {
    return const SesionUsuario(
      usuarioId: 'usuario-solo-corregir',
      nombre: 'Solo corregir',
      nombreUsuario: 'solo-corregir',
      esMaestro: false,
      permisos: {'compras.corregir', 'compras.ver'},
    );
  }
}

void main() {
  late AppDatabase db;
  late String compraId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
    addTearDown(container.dispose);
    final resultado = await container.read(registrarCompraUseCaseProvider).ejecutar(
      fecha: DateTime(2026, 8, 10),
      formaPago: FormaPago.efectivo.name,
      partidas: [
        PartidaCompraInput(destino: DestinoCompraPartida.gastoDirecto.name, concepto: 'Papelería', cantidad: 1, costoUnitario: 45000),
      ],
    );
    compraId = (resultado as RegistrarCompraExitosa).compra.id;
  });

  tearDown(() => db.close());

  test('tener compras.crear y compras.cancelar (sin compras.corregir) NO permite corregir el origen financiero', () async {
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db), sesionControllerProvider.overrideWith(_SesionSinCorregir.new)],
    );
    addTearDown(container.dispose);

    final resultado = await container.read(comprasControllerProvider.notifier).corregirCompra(
          compraId: compraId,
          proveedor: 'Proveedor Nuevo',
          motivo: 'Intento sin permiso',
        );

    expect(resultado, isA<CorregirCompraErrorInesperado>(), reason: 'autorizarUseCase rechaza sin compras.corregir');
    final actual = await container.read(compraRepositoryProvider).obtenerPorId(compraId);
    expect(actual!.proveedor, isNot('Proveedor Nuevo'), reason: 'nada cambia sin el permiso correcto');
  });

  test('compras.corregir (sin compras.crear ni compras.cancelar) SÍ permite corregir, incluido el origen financiero', () async {
    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(
            id: const Value('usuario-solo-corregir'),
            nombre: 'Solo corregir',
            nombreUsuario: 'solo-corregir',
            passwordHash: 'x',
          ),
        );
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db), sesionControllerProvider.overrideWith(_SesionSoloCorregir.new)],
    );
    addTearDown(container.dispose);

    final resultado = await container.read(comprasControllerProvider.notifier).corregirCompra(
          compraId: compraId,
          proveedor: 'Proveedor Nuevo',
          motivo: 'Corrección con el permiso correcto',
        );

    expect(resultado, isA<CorregirCompraExitosa>());
    final actual = await container.read(compraRepositoryProvider).obtenerPorId(compraId);
    expect(actual!.proveedor, 'Proveedor Nuevo');
  });

  test('compras.corregir NO alcanza para cancelar — compras.cancelar sigue siendo un permiso aparte', () async {
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db), sesionControllerProvider.overrideWith(_SesionSoloCorregir.new)],
    );
    addTearDown(container.dispose);

    final resultado = await container.read(comprasControllerProvider.notifier).cancelarCompra(
          compraId: compraId,
          motivo: MotivoCancelacionCompra.errorDeCaptura,
        );

    expect(resultado, isA<CancelarCompraErrorInesperado>());
    final actual = await container.read(compraRepositoryProvider).obtenerPorId(compraId);
    expect(actual!.estatus, isNot('cancelada'));
  });
}

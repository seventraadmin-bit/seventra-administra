// Etapa 15 — frontera de autorización de la eliminación física de
// Compra: `exigirMaestro` (nunca `AuthorizationService.verificar`), a
// nivel de provider — ningún permiso dinámico puede otorgar esta
// facultad a un usuario normal.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/compras/compras_providers.dart';
import 'package:riseg_one/features/compras/data/tables/compra_partida_table.dart' show DestinoCompraPartida;
import 'package:riseg_one/features/compras/domain/repositories/compra_repository.dart' show PartidaCompraInput;
import 'package:riseg_one/features/compras/domain/usecases/eliminar_compra_fisicamente_usecase.dart';
import 'package:riseg_one/features/compras/domain/usecases/registrar_compra_usecase.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

class _SesionMaestro extends SesionController {
  @override
  SesionUsuario? build() {
    return const SesionUsuario(
      usuarioId: 'usuario-maestro',
      nombre: 'Maestro de prueba',
      nombreUsuario: 'maestro',
      esMaestro: true,
      permisos: {},
    );
  }
}

class _SesionUsuarioNormal extends SesionController {
  @override
  SesionUsuario? build() {
    return const SesionUsuario(
      usuarioId: 'usuario-normal',
      nombre: 'Usuario normal',
      nombreUsuario: 'normal',
      esMaestro: false,
      // Incluso con TODOS los permisos dinámicos de Compras,
      // `exigirMaestro` nunca consulta esta lista.
      permisos: {'compras.crear', 'compras.archivar', 'compras.ver'},
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

  test('un usuario normal (incluso con todos los permisos dinámicos de Compras) no puede eliminar físicamente', () async {
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionUsuarioNormal.new),
      ],
    );
    addTearDown(container.dispose);

    final resultado = await container.read(eliminarCompraFisicamenteAutorizadoProvider)(
      compraId: compraId,
      motivo: 'Intento no autorizado',
    );

    expect(resultado, isA<EliminarCompraFisicamenteErrorInesperado>());
    expect(
      await container.read(compraRepositoryProvider).obtenerPorId(compraId),
      isNotNull,
      reason: 'nunca se elimina sin ser Maestro',
    );
  });

  test('el Usuario Maestro sí puede eliminar físicamente a través del mismo provider', () async {
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionMaestro.new),
      ],
    );
    addTearDown(container.dispose);
    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(
            id: const Value('usuario-maestro'),
            nombre: 'Maestro de prueba',
            nombreUsuario: 'maestro',
            passwordHash: 'x',
            esMaestro: const Value(true),
          ),
        );

    final resultado = await container.read(eliminarCompraFisicamenteAutorizadoProvider)(
      compraId: compraId,
      motivo: 'Captura de prueba',
    );

    expect(resultado, isA<EliminarCompraFisicamenteExitoso>());
    expect(await container.read(compraRepositoryProvider).obtenerPorId(compraId), isNull);
  });
}

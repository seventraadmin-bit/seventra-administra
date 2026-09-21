// Etapa 15 — frontera de autorización de la eliminación física de
// Egreso: `exigirMaestro` (nunca `AuthorizationService.verificar`), a
// nivel de provider — ningún permiso dinámico puede otorgar esta
// facultad a un usuario normal.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/eliminar_egreso_fisicamente_usecase.dart';
import 'package:riseg_one/features/finanzas/finanzas_providers.dart';
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
      // Incluso con TODOS los permisos dinámicos de Finanzas, `exigirMaestro`
      // nunca consulta esta lista — ninguna casilla de la matriz puede
      // otorgar esta facultad extraordinaria.
      permisos: {'egresos.crear', 'egresos.corregir', 'egresos.cancelar', 'finanzas.ver'},
    );
  }
}

void main() {
  late AppDatabase db;
  late String egresoId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final egreso = await EgresoRepositoryImpl(db).crear(
      folioEgreso: 'EGR-000001',
      monto: 150000,
      fecha: DateTime(2026, 1, 5),
      formaPago: 'efectivo',
      concepto: 'Papelería de oficina',
    );
    egresoId = egreso.id;
  });

  tearDown(() => db.close());

  test('un usuario normal (incluso con todos los permisos dinámicos de Finanzas) no puede eliminar físicamente', () async {
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionUsuarioNormal.new),
      ],
    );
    addTearDown(container.dispose);

    final resultado = await container.read(eliminarEgresoFisicamenteAutorizadoProvider)(
      egresoId: egresoId,
      motivo: 'Intento no autorizado',
    );

    expect(resultado, isA<EliminarEgresoFisicamenteErrorInesperado>());
    expect(await EgresoRepositoryImpl(db).obtenerPorId(egresoId), isNotNull, reason: 'nunca se elimina sin ser Maestro');
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

    final resultado = await container.read(eliminarEgresoFisicamenteAutorizadoProvider)(
      egresoId: egresoId,
      motivo: 'Captura de prueba',
    );

    expect(resultado, isA<EliminarEgresoFisicamenteExitoso>());
    expect(await EgresoRepositoryImpl(db).obtenerPorId(egresoId), isNull);
  });
}

// Etapa 15 — frontera de autorización de la eliminación física de
// Pago: `exigirMaestro` (nunca `AuthorizationService.verificar`), a
// nivel de provider — ningún permiso dinámico puede otorgar esta
// facultad a un usuario normal.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/finanzas/data/repositories/pago_repository_impl.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cancelar_pago_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/eliminar_pago_fisicamente_usecase.dart';
import 'package:riseg_one/features/finanzas/finanzas_providers.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_cliente_usecase.dart';
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
      // Incluso con TODOS los permisos dinámicos de Finanzas,
      // `exigirMaestro` nunca consulta esta lista.
      permisos: {'finanzas.crear', 'finanzas.modificar', 'finanzas.archivar', 'finanzas.ver'},
    );
  }
}

void main() {
  late AppDatabase db;
  late String pagoId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final pagoRepo = PagoRepositoryImpl(db);
    final clienteRepo = ClienteRepositoryImpl(db);
    final crearCliente = CrearClienteUseCase(clienteRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db)));
    final cliente = (await crearCliente.ejecutar(nombreComercial: 'Sportium')).when(
      ok: (c) => c,
      failure: (f) => throw StateError(f.message),
    );
    final pago = await pagoRepo.crear(
      folioPago: 'PAG-000001',
      clienteId: cliente.id,
      montoTotal: 100000,
      fechaPago: DateTime(2026, 8, 10),
      formaPago: 'efectivo',
    );
    await CancelarPagoUseCase(pagoRepo).ejecutar(pagoId: pago.id, motivo: 'Duplicado por error');
    pagoId = pago.id;
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

    final resultado = await container.read(eliminarPagoFisicamenteAutorizadoProvider)(
      pagoId: pagoId,
      motivo: 'Intento no autorizado',
    );

    expect(resultado, isA<EliminarPagoFisicamenteErrorInesperado>());
    expect(await PagoRepositoryImpl(db).obtenerPorId(pagoId), isNotNull, reason: 'nunca se elimina sin ser Maestro');
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

    final resultado = await container.read(eliminarPagoFisicamenteAutorizadoProvider)(
      pagoId: pagoId,
      motivo: 'Captura de prueba',
    );

    expect(resultado, isA<EliminarPagoFisicamenteExitoso>());
    expect(await PagoRepositoryImpl(db).obtenerPorId(pagoId), isNull);
  });
}

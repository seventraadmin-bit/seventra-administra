// Etapa 14D (Bóveda de Accesos del Maestro) — guardia real de
// exigirMaestro: sin Usuario Maestro, ningún XxxAutorizadoProvider debe
// siquiera invocar el caso de uso subyacente (fakes con noSuchMethod
// que fallan si se llaman) — mismo patrón que
// respaldo_autorizacion_test.dart (Etapa 14C) y
// eliminacion_fisica_test.dart (Etapa 11D).

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/features/boveda/boveda_providers.dart';
import 'package:riseg_one/features/boveda/domain/usecases/actualizar_credencial_boveda_usecase.dart';
import 'package:riseg_one/features/boveda/domain/usecases/cambiar_secreto_credencial_boveda_usecase.dart';
import 'package:riseg_one/features/boveda/domain/usecases/crear_credencial_boveda_usecase.dart';
import 'package:riseg_one/features/boveda/domain/usecases/dar_de_baja_credencial_boveda_usecase.dart';
import 'package:riseg_one/features/boveda/domain/usecases/reactivar_credencial_boveda_usecase.dart';
import 'package:riseg_one/features/boveda/domain/usecases/revelar_secreto_credencial_boveda_usecase.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import '../../support/sesion_en_base.dart';

class _SesionFija extends SesionController {
  _SesionFija(this._sesion);
  final SesionUsuario? _sesion;
  @override
  SesionUsuario? build() => _sesion;
}

class _NuncaInvocado {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('No debe invocarse sin Usuario Maestro');
}

class _CrearNuncaInvocado extends _NuncaInvocado implements CrearCredencialBovedaUseCase {}

class _ActualizarNuncaInvocado extends _NuncaInvocado implements ActualizarCredencialBovedaUseCase {}

class _CambiarSecretoNuncaInvocado extends _NuncaInvocado implements CambiarSecretoCredencialBovedaUseCase {}

class _RevelarNuncaInvocado extends _NuncaInvocado implements RevelarSecretoCredencialBovedaUseCase {}

class _DarDeBajaNuncaInvocado extends _NuncaInvocado implements DarDeBajaCredencialBovedaUseCase {}

class _ReactivarNuncaInvocado extends _NuncaInvocado implements ReactivarCredencialBovedaUseCase {}

const _sesionNoMaestro = SesionUsuario(
  usuarioId: 'usuario-normal',
  nombre: 'Usuario normal',
  nombreUsuario: 'normal',
  esMaestro: false,
  permisos: {'usuarios.administrar'},
);

const _sesionMaestro = SesionUsuario(
  usuarioId: 'usuario-maestro',
  nombre: 'Maestro',
  nombreUsuario: 'maestro',
  esMaestro: true,
  permisos: {},
);

/// Etapa 3B: la autorización se revalida contra la fuente
/// autoritativa, así que este archivo —que antes no necesitaba base
/// alguna— tiene que tener una y persistir en ella el escenario. Sin
/// eso, la cuenta que la sesión afirma ser no existiría y TODO saldría
/// denegado: hasta las pruebas positivas pasarían por el motivo
/// equivocado.
Future<ProviderContainer> _container(AppDatabase db, SesionUsuario? sesion) async {
  if (sesion != null) await sembrarSesionEnBase(db, sesion);
  final container = ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      sesionControllerProvider.overrideWith(() => _SesionFija(sesion)),
      crearCredencialBovedaUseCaseProvider.overrideWithValue(_CrearNuncaInvocado()),
      actualizarCredencialBovedaUseCaseProvider.overrideWithValue(_ActualizarNuncaInvocado()),
      cambiarSecretoCredencialBovedaUseCaseProvider.overrideWithValue(_CambiarSecretoNuncaInvocado()),
      revelarSecretoCredencialBovedaUseCaseProvider.overrideWithValue(_RevelarNuncaInvocado()),
      darDeBajaCredencialBovedaUseCaseProvider.overrideWithValue(_DarDeBajaNuncaInvocado()),
      reactivarCredencialBovedaUseCaseProvider.overrideWithValue(_ReactivarNuncaInvocado()),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  group('sin Usuario Maestro, ningún XxxAutorizadoProvider invoca su UseCase', () {
    test('crearCredencialBovedaAutorizadoProvider', () async {
      final container = await _container(db, _sesionNoMaestro);
      final resultado = await container.read(crearCredencialBovedaAutorizadoProvider)(nombre: 'X', tipo: 'otro');
      expect(resultado, isA<CrearCredencialBovedaErrorInesperado>());
    });

    test('actualizarCredencialBovedaAutorizadoProvider', () async {
      final container = await _container(db, _sesionNoMaestro);
      final resultado = await container.read(actualizarCredencialBovedaAutorizadoProvider)(id: 'x', nombre: 'X', tipo: 'otro');
      expect(resultado, isA<ActualizarCredencialBovedaErrorInesperado>());
    });

    test('cambiarSecretoCredencialBovedaAutorizadoProvider', () async {
      final container = await _container(db, _sesionNoMaestro);
      final resultado = await container.read(cambiarSecretoCredencialBovedaAutorizadoProvider)(id: 'x');
      expect(resultado, isA<CambiarSecretoCredencialBovedaErrorInesperado>());
    });

    test('revelarSecretoCredencialBovedaAutorizadoProvider', () async {
      final container = await _container(db, _sesionNoMaestro);
      final resultado = await container.read(revelarSecretoCredencialBovedaAutorizadoProvider)(
        credencialId: 'x',
        accion: AccionRevelacionSecreto.mostrar,
      );
      expect(resultado, isA<RevelarSecretoCredencialBovedaErrorInesperado>());
    });

    test('darDeBajaCredencialBovedaAutorizadoProvider', () async {
      final container = await _container(db, _sesionNoMaestro);
      final resultado = await container.read(darDeBajaCredencialBovedaAutorizadoProvider)(id: 'x');
      expect(resultado, isA<DarDeBajaCredencialBovedaErrorInesperado>());
    });

    test('reactivarCredencialBovedaAutorizadoProvider', () async {
      final container = await _container(db, _sesionNoMaestro);
      final resultado = await container.read(reactivarCredencialBovedaAutorizadoProvider)(id: 'x');
      expect(resultado, isA<ReactivarCredencialBovedaErrorInesperado>());
    });

    test('sin sesión, tampoco invoca', () async {
      final container = await _container(db, null);
      final resultado = await container.read(crearCredencialBovedaAutorizadoProvider)(nombre: 'X', tipo: 'otro');
      expect(resultado, isA<CrearCredencialBovedaErrorInesperado>());
    });
  });

  test('con Usuario Maestro, crearCredencialBovedaAutorizadoProvider sí invoca el UseCase', () async {
    final resultadoFijo = CrearCredencialBovedaNombreRequerido();
    // Esta prueba arma su contenedor a mano (necesita el doble `_CrearFijo`),
    // así que la siembra del escenario va explícita.
    await sembrarSesionEnBase(db, _sesionMaestro);
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(() => _SesionFija(_sesionMaestro)),
        crearCredencialBovedaUseCaseProvider.overrideWithValue(_CrearFijo(resultadoFijo)),
      ],
    );
    addTearDown(container.dispose);

    final resultado = await container.read(crearCredencialBovedaAutorizadoProvider)(nombre: 'X', tipo: 'otro');
    expect(resultado, same(resultadoFijo));
  });
}

class _CrearFijo implements CrearCredencialBovedaUseCase {
  _CrearFijo(this._resultado);
  final CrearCredencialBovedaResultado _resultado;

  @override
  Future<CrearCredencialBovedaResultado> ejecutar({
    required String nombre,
    required String tipo,
    String? usuarioAcceso,
    String? correo,
    String? secreto,
    String? url,
    String? observaciones,
    String? actorUsuarioId,
  }) async =>
      _resultado;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

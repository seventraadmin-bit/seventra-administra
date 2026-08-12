// Etapa 14D (Bóveda de Accesos del Maestro) — guardia real de
// exigirMaestro: sin Usuario Maestro, ningún XxxAutorizadoProvider debe
// siquiera invocar el caso de uso subyacente (fakes con noSuchMethod
// que fallan si se llaman) — mismo patrón que
// respaldo_autorizacion_test.dart (Etapa 14C) y
// eliminacion_fisica_test.dart (Etapa 11D).

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
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

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

ProviderContainer _container(SesionUsuario? sesion) {
  final container = ProviderContainer(
    overrides: [
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
  group('sin Usuario Maestro, ningún XxxAutorizadoProvider invoca su UseCase', () {
    test('crearCredencialBovedaAutorizadoProvider', () async {
      final container = _container(_sesionNoMaestro);
      final resultado = await container.read(crearCredencialBovedaAutorizadoProvider)(nombre: 'X', tipo: 'otro');
      expect(resultado, isA<CrearCredencialBovedaErrorInesperado>());
    });

    test('actualizarCredencialBovedaAutorizadoProvider', () async {
      final container = _container(_sesionNoMaestro);
      final resultado = await container.read(actualizarCredencialBovedaAutorizadoProvider)(id: 'x', nombre: 'X', tipo: 'otro');
      expect(resultado, isA<ActualizarCredencialBovedaErrorInesperado>());
    });

    test('cambiarSecretoCredencialBovedaAutorizadoProvider', () async {
      final container = _container(_sesionNoMaestro);
      final resultado = await container.read(cambiarSecretoCredencialBovedaAutorizadoProvider)(id: 'x');
      expect(resultado, isA<CambiarSecretoCredencialBovedaErrorInesperado>());
    });

    test('revelarSecretoCredencialBovedaAutorizadoProvider', () async {
      final container = _container(_sesionNoMaestro);
      final resultado = await container.read(revelarSecretoCredencialBovedaAutorizadoProvider)(
        credencialId: 'x',
        accion: AccionRevelacionSecreto.mostrar,
      );
      expect(resultado, isA<RevelarSecretoCredencialBovedaErrorInesperado>());
    });

    test('darDeBajaCredencialBovedaAutorizadoProvider', () async {
      final container = _container(_sesionNoMaestro);
      final resultado = await container.read(darDeBajaCredencialBovedaAutorizadoProvider)(id: 'x');
      expect(resultado, isA<DarDeBajaCredencialBovedaErrorInesperado>());
    });

    test('reactivarCredencialBovedaAutorizadoProvider', () async {
      final container = _container(_sesionNoMaestro);
      final resultado = await container.read(reactivarCredencialBovedaAutorizadoProvider)(id: 'x');
      expect(resultado, isA<ReactivarCredencialBovedaErrorInesperado>());
    });

    test('sin sesión, tampoco invoca', () async {
      final container = _container(null);
      final resultado = await container.read(crearCredencialBovedaAutorizadoProvider)(nombre: 'X', tipo: 'otro');
      expect(resultado, isA<CrearCredencialBovedaErrorInesperado>());
    });
  });

  test('con Usuario Maestro, crearCredencialBovedaAutorizadoProvider sí invoca el UseCase', () async {
    final resultadoFijo = CrearCredencialBovedaNombreRequerido();
    final container = ProviderContainer(
      overrides: [
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

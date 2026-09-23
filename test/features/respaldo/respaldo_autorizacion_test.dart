// Etapa 14C (Respaldo y restauración) — guardia real de
// exigirMaestro: sin Usuario Maestro, ni crearRespaldoAutorizadoProvider
// ni restaurarAutorizadoProvider deben siquiera invocar el caso de uso
// subyacente (fakes con noSuchMethod que fallan si se llaman) — mismo
// patrón que eliminacion_fisica_test.dart (Etapa 11D).

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/features/respaldo/domain/manifest_respaldo.dart';
import 'package:riseg_one/features/respaldo/domain/usecases/crear_respaldo_usecase.dart';
import 'package:riseg_one/features/respaldo/domain/usecases/preparar_restauracion_usecase.dart';
import 'package:riseg_one/features/respaldo/respaldo_providers.dart';
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

class _CrearRespaldoNuncaInvocado implements CrearRespaldoUseCase {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('No debe invocarse sin Usuario Maestro');
}

class _PrepararRestauracionNuncaInvocado implements PrepararRestauracionUseCase {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('No debe invocarse sin Usuario Maestro');
}

class _CrearRespaldoFijo implements CrearRespaldoUseCase {
  final resultado = RespaldoCreado(
    rutaZip: 'x.zip',
    manifiesto: ManifestRespaldo(
      formatVersion: 1,
      createdAt: DateTime(2026, 1, 1),
      appSchemaVersion: 44,
      integridadVerificada: true,
      archivosAdjuntos: 0,
      bytesAdjuntos: 0,
    ),
  );

  @override
  Future<ResultadoCrearRespaldo> ejecutar({required String destinoZip}) async => resultado;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _PrepararRestauracionFijo implements PrepararRestauracionUseCase {
  @override
  Future<ResultadoPrepararRestauracion> ejecutar({required String rutaZip, required int appSchemaVersionActual}) async =>
      RestauracionPreparada();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// Etapa 3B: la autorización se revalida contra la base, así que el
/// escenario se persiste aquí — una por prueba, con su propia cuenta.
Future<ProviderContainer> _container({
  required AppDatabase db,
  required SesionUsuario? sesion,
  required CrearRespaldoUseCase crear,
  required PrepararRestauracionUseCase preparar,
}) async {
  if (sesion != null) await sembrarSesionEnBase(db, sesion);
  final container = ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      sesionControllerProvider.overrideWith(() => _SesionFija(sesion)),
      crearRespaldoUseCaseProvider.overrideWithValue(crear),
      prepararRestauracionUseCaseProvider.overrideWithValue(preparar),
      // `restaurarAutorizadoProvider` resuelve `appSchemaVersionProvider`
      // (que a su vez leería `appDatabaseProvider`) como argumento antes
      // de invocar `exigirMaestro` — se sobreescribe directo para no
      // necesitar una `AppDatabase` real en esta prueba de autorización.
      appSchemaVersionProvider.overrideWithValue(44),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

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

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  group('crearRespaldoAutorizadoProvider', () {
    test('sin Usuario Maestro, nunca invoca CrearRespaldoUseCase', () async {
      final container = await _container(
        db: db,
        sesion: _sesionNoMaestro,
        crear: _CrearRespaldoNuncaInvocado(),
        preparar: _PrepararRestauracionNuncaInvocado(),
      );

      final resultado = await container.read(crearRespaldoAutorizadoProvider)(destinoZip: 'x.zip');

      expect(resultado, isA<RespaldoErrorInesperado>());
    });

    test('un permiso dinámico como "usuarios.administrar" no basta — sigue rechazado', () async {
      final container = await _container(
        db: db,
        sesion: _sesionNoMaestro,
        crear: _CrearRespaldoNuncaInvocado(),
        preparar: _PrepararRestauracionNuncaInvocado(),
      );

      final resultado = await container.read(crearRespaldoAutorizadoProvider)(destinoZip: 'x.zip');

      expect(resultado, isA<RespaldoErrorInesperado>());
    });

    test('con Usuario Maestro, invoca CrearRespaldoUseCase y devuelve su resultado', () async {
      final fijo = _CrearRespaldoFijo();
      final container = await _container(
        db: db,sesion: _sesionMaestro, crear: fijo, preparar: _PrepararRestauracionNuncaInvocado());

      final resultado = await container.read(crearRespaldoAutorizadoProvider)(destinoZip: 'x.zip');

      expect(resultado, same(fijo.resultado));
    });

    test('sin sesión, nunca invoca CrearRespaldoUseCase', () async {
      final container = await _container(
        db: db,
        sesion: null,
        crear: _CrearRespaldoNuncaInvocado(),
        preparar: _PrepararRestauracionNuncaInvocado(),
      );

      final resultado = await container.read(crearRespaldoAutorizadoProvider)(destinoZip: 'x.zip');

      expect(resultado, isA<RespaldoErrorInesperado>());
    });
  });

  group('restaurarAutorizadoProvider', () {
    test('sin Usuario Maestro, nunca invoca PrepararRestauracionUseCase', () async {
      final container = await _container(
        db: db,
        sesion: _sesionNoMaestro,
        crear: _CrearRespaldoNuncaInvocado(),
        preparar: _PrepararRestauracionNuncaInvocado(),
      );

      final resultado = await container.read(restaurarAutorizadoProvider)(rutaZip: 'x.zip');

      expect(resultado, isA<RestauracionErrorInesperado>());
    });

    test('con Usuario Maestro, invoca PrepararRestauracionUseCase', () async {
      final container = await _container(
        db: db,sesion: _sesionMaestro, crear: _CrearRespaldoNuncaInvocado(), preparar: _PrepararRestauracionFijo());

      final resultado = await container.read(restaurarAutorizadoProvider)(rutaZip: 'x.zip');

      expect(resultado, isA<RestauracionPreparada>());
    });
  });
}

// Integration Foundation IF-3 — el aislamiento por Company, demostrado.
//
// ESTE ARCHIVO ES LA DEMOSTRACIÓN DE §22 y no hace falta migrar un módulo real para
// tenerla: un provider remoto SINTÉTICO, escrito como se escribirán los de verdad,
// basta para probar lo que importa. Cuando la empresa activa cambia, Riverpod
// reconstruye lo que observa `companyIdActivoProvider` y el estado de la empresa
// anterior deja de existir — sin registro manual de invalidaciones, que es
// exactamente lo que se quería evitar: una lista explícita se queda obsoleta en
// cuanto nace un módulo nuevo, y eso ya lo documenta `SesionController` sobre la
// sesión.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riseg_one/core/api/api_providers.dart';
import 'package:riseg_one/core/auth/almacen_sesion_remota.dart';
import 'package:riseg_one/core/auth/auth_providers.dart';
import 'package:riseg_one/core/auth/sesion_remota.dart';
import 'package:riseg_one/core/company/almacen_company_recordada.dart';
import 'package:riseg_one/core/company/company_providers.dart';
import 'package:riseg_one/core/company/company_remota.dart';
import 'package:riseg_one/core/config/api_config.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/core/error/failure.dart';
import 'package:riseg_one/core/error/result.dart';
import 'package:riseg_one/core/logging/app_logger.dart';

class _AlmacenSesionEnMemoria implements AlmacenSesionRemota {
  CredencialRemota? guardada;

  @override
  Future<CredencialRemota?> leer() async => guardada;

  @override
  Future<void> escribir(CredencialRemota credencial) async =>
      guardada = credencial;

  @override
  Future<void> borrar() async => guardada = null;
}

class _PreferenciaEnMemoria implements AlmacenCompanyRecordada {
  String? recordada;

  @override
  Future<String?> leer() async => recordada;

  @override
  Future<void> escribir(String companyId) async => recordada = companyId;

  @override
  Future<void> borrar() async => recordada = null;
}

/// Un provider remoto sintético, escrito **como se escribirán los de verdad**:
/// empieza leyendo la empresa activa, y sin ella no inventa ningún inquilino.
///
/// Devuelve la ruta que pediría, que es justo lo que interesa afirmar: qué empresa
/// habría viajado en el path.
final _empleadosRemotosProvider = Provider<Result<String>>((ref) {
  final companyId = ref.watch(companyIdActivoProvider);

  if (companyId == null) {
    // NO se toma «la primera» ni se deja el hueco: el `companyId` viaja en la ruta,
    // así que suponerlo sería pedir datos de otra empresa.
    return const Result.failure(
      CompanySinSeleccionFailure('No hay una empresa activa.'),
    );
  }

  return Result.ok('/companies/$companyId/employees');
});

void main() {
  final config = ApiConfig.resolve(
    raw: 'http://localhost:5199',
  ).when(ok: (c) => c, failure: (f) => throw StateError(f.message));

  const empresaA = '0193f0a0-0000-7000-8000-00000000000a';
  const empresaB = '0193f0a0-0000-7000-8000-00000000000b';
  const organizationId = '0193f0a0-0000-7000-8000-0000000000ff';

  /// Las caducidades se calculan sobre el reloj REAL, y no sobre un instante fijo.
  ///
  /// Es una diferencia con las pruebas del motor, y tiene motivo: aquí el
  /// `GestorDeSesion` lo construye `gestorDeSesionProvider`, que no expone ningún
  /// reloj inyectable —y no debe: en producción el reloj es el del sistema—. Con un
  /// instante fijo de 2026 el token nacería caducado y el decorador dispararía un
  /// refresco preventivo antes de la primera petición de empresa, que es justo lo que
  /// ocurrió al escribir esto.
  String cuerpoDeSesion() {
    final ahora = DateTime.now().toUtc();

    return jsonEncode({
      'accessToken': 'at_1',
      'accessExpiresAt':
          ahora.add(const Duration(minutes: 30)).toIso8601String(),
      'refreshToken': 'rt_1',
      'refreshExpiresAt': ahora.add(const Duration(days: 14)).toIso8601String(),
      'sessionId': '0193f0a0-0000-7000-8000-00000000aaaa',
      'displayName': 'Ana Torres',
      'email': 'ana@seventra.mx',
    });
  }

  Map<String, Object?> companyJson(String id, String nombre) => {
    'companyId': id,
    'organizationId': organizationId,
    'companyName': nombre,
    'organizationName': 'Grupo RISEG',
    'role': 'maestro',
  };

  String contextoDe(String id) => jsonEncode({
    'companyId': id,
    'organizationId': organizationId,
    'companyName': 'Empresa $id',
    'companyStatus': 'activa',
    'organizationName': 'Grupo RISEG',
    'role': 'maestro',
    'isMaestro': true,
    'enabledModules': ['personal'],
    'effectivePermissions': ['personal.read'],
    'restricted': false,
  });

  ProviderContainer contenedor({List<Map<String, Object?>> lista = const []}) {
    final cliente = MockClient((peticion) async {
      if (peticion.url.path.endsWith('/auth/login')) {
        return http.Response(cuerpoDeSesion(), 200);
      }

      if (peticion.url.path.endsWith('/context')) {
        return http.Response(contextoDe(peticion.url.pathSegments[3]), 200);
      }

      return http.Response(jsonEncode(lista), 200);
    });

    final container = ProviderContainer(
      overrides: [
        apiConfigProvider.overrideWithValue(config),
        httpClientProvider.overrideWithValue(cliente),
        appLoggerProvider.overrideWithValue(AppLogger.console()),
        almacenSesionRemotaProvider.overrideWithValue(
          _AlmacenSesionEnMemoria(),
        ),
        almacenCompanyRecordadaProvider.overrideWithValue(
          _PreferenciaEnMemoria(),
        ),
      ],
    );

    addTearDown(container.dispose);

    return container;
  }

  Future<void> autenticar(ProviderContainer container) => container
      .read(gestorDeSesionProvider)
      .iniciarSesion(email: 'ana@seventra.mx', password: 'x');

  String exigirRuta(Result<String> resultado) => resultado.when(
    ok: (ruta) => ruta,
    failure: (f) => fail('Se esperaba una ruta y llegó: ${f.message}'),
  );

  Failure exigirFallo(Result<Object?> resultado) => resultado.when(
    ok: (v) => fail('Se esperaba un fallo y llegó: $v'),
    failure: (failure) => failure,
  );

  group('La cadena de providers se construye', () {
    test('sin empresa activa, companyIdActivo es null', () async {
      final container = contenedor();
      await autenticar(container);

      expect(container.read(companyIdActivoProvider), isNull);
      expect(container.read(companyContextProvider), isNull);
      expect(
        container.read(estadoCompanyProvider).value,
        isA<CompanySinResolver>(),
      );
    });

    test('el gestor es el mismo objeto en todo el contenedor', () async {
      // Reconstruirlo perdería la empresa activa y podría lanzar un descubrimiento
      // paralelo.
      final container = contenedor();

      expect(
        container.read(gestorDeCompanyProvider),
        same(container.read(gestorDeCompanyProvider)),
      );
    });
  });

  group('Aislamiento: un provider remoto sigue a la empresa activa', () {
    test('sin empresa NO inventa inquilino', () async {
      final container = contenedor();
      await autenticar(container);

      expect(
        exigirFallo(container.read(_empleadosRemotosProvider)),
        isA<CompanySinSeleccionFailure>(),
      );
    });

    test('con empresa A, la ruta lleva A', () async {
      final container = contenedor(lista: [companyJson(empresaA, 'Alfa')]);
      await autenticar(container);

      await container.read(gestorDeCompanyProvider).resolver();

      expect(
        exigirRuta(container.read(_empleadosRemotosProvider)),
        '/companies/$empresaA/employees',
      );
    });

    test(
      'al cambiar a B, el provider se RECONSTRUYE y deja de operar bajo A',
      () async {
        final container = contenedor(
          lista: [companyJson(empresaA, 'Alfa'), companyJson(empresaB, 'Beta')],
        );
        await autenticar(container);

        final gestor = container.read(gestorDeCompanyProvider);

        await gestor.cambiarA(empresaA);

        // Se observa el provider para que quede vivo: es lo que hará un widget.
        final observado = <Result<String>>[];
        container.listen(
          _empleadosRemotosProvider,
          (_, siguiente) => observado.add(siguiente),
          fireImmediately: true,
        );

        expect(exigirRuta(observado.last), contains(empresaA));

        await gestor.cambiarA(empresaB);

        // La verdad SÍNCRONA es la lectura: en el instante siguiente al cambio, el
        // provider ya recomputa con la empresa nueva.
        expect(
          exigirRuta(container.read(_empleadosRemotosProvider)),
          '/companies/$empresaB/employees',
          reason: 'Riverpod lo reconstruyó al cambiar la empresa activa',
        );

        // Y el aviso a quien lo observa llega en el turno siguiente: Riverpod
        // notifica a los oyentes de forma diferida, no dentro del propio cambio.
        await pumpEventQueue();

        expect(exigirRuta(observado.last), contains(empresaB));
        expect(
          observado.map(exigirRuta).where((r) => r.contains(empresaA)),
          hasLength(1),
          reason: 'la ruta de A no vuelve a aparecer bajo B',
        );
      },
    );

    test('olvidar la empresa devuelve el provider a «sin inquilino»', () async {
      final container = contenedor(lista: [companyJson(empresaA, 'Alfa')]);
      await autenticar(container);

      final gestor = container.read(gestorDeCompanyProvider);

      await gestor.resolver();
      container.listen(
        _empleadosRemotosProvider,
        (_, _) {},
        fireImmediately: true,
      );
      expect(
        exigirRuta(container.read(_empleadosRemotosProvider)),
        contains(empresaA),
      );

      await gestor.olvidarSeleccion();

      expect(
        exigirFallo(container.read(_empleadosRemotosProvider)),
        isA<CompanySinSeleccionFailure>(),
      );
    });

    test('companyContext también sigue a la empresa activa', () async {
      final container = contenedor(
        lista: [companyJson(empresaA, 'Alfa'), companyJson(empresaB, 'Beta')],
      );
      await autenticar(container);

      final gestor = container.read(gestorDeCompanyProvider);
      container.listen(
        companyContextProvider,
        (_, _) {},
        fireImmediately: true,
      );

      await gestor.cambiarA(empresaA);
      expect(container.read(companyContextProvider)?.companyId, empresaA);

      await gestor.cambiarA(empresaB);
      expect(container.read(companyContextProvider)?.companyId, empresaB);
    });
  });

  group('Lo que IF-3 NO hace con el contexto', () {
    test('conserva los cuatro campos de autorización sin aplicarlos', () async {
      final container = contenedor(lista: [companyJson(empresaA, 'Alfa')]);
      await autenticar(container);

      await container.read(gestorDeCompanyProvider).resolver();

      final contexto = container.read(companyContextProvider)!;

      expect(contexto.isMaestro, isTrue);
      expect(contexto.restricted, isFalse);
      expect(contexto.enabledModules, isNotEmpty);
      expect(contexto.effectivePermissions, isNotEmpty);
    });
  });
}

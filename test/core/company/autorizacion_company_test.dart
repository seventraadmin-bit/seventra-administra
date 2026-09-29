// Integration Foundation IF-4 — la vista de autorización remota.
//
// LO QUE SE DEFIENDE, y por qué cada cosa es corrección y no comodidad:
//
//  · **`puede` es pertenencia literal**. No expande `manage` a `read`, no interpreta
//    los puntos como jerarquía y no concede por ser Maestro. El servidor ya aplicó su
//    regla —módulo, herencia del rol según el catálogo, concesión explícita— y
//    recalcularla aquí crearía un segundo sistema de autorización que divergiría del
//    primero en el primer cambio;
//  · **ser Maestro NO es un comodín**. El Maestro del backend no hereda los permisos
//    protegidos, así que una interfaz que tradujera «es Maestro» por «puede todo»
//    ofrecería el expediente sensible a quien se le retiró el permiso;
//  · **`restricted` no oculta la posesión**. Distinguir «no tienes permiso» de «tienes
//    permiso y la operación está temporalmente restringida» es lo que evita que un
//    Maestro pierda el tiempo revisando permisos cuando el problema es una factura;
//  · **sin empresa se niega todo**, por construcción y no por una comprobación que
//    alguien deba recordar.

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
import 'package:riseg_one/core/company/autorizacion_company.dart';
import 'package:riseg_one/core/company/company_providers.dart';
import 'package:riseg_one/core/company/company_remota.dart';
import 'package:riseg_one/core/company/permiso_company.dart';
import 'package:riseg_one/core/config/api_config.dart';
import 'package:riseg_one/core/di/providers.dart';
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

void main() {
  const empresaA = '0193f0a0-0000-7000-8000-00000000000a';
  const empresaB = '0193f0a0-0000-7000-8000-00000000000b';
  const organizationId = '0193f0a0-0000-7000-8000-0000000000ff';

  CompanyContext contexto({
    String companyId = empresaA,
    String role = 'user',
    bool isMaestro = false,
    bool restricted = false,
    Set<String> modulos = const {'personal'},
    Set<String> permisos = const {'personal.read'},
  }) => CompanyContext(
    companyId: companyId,
    organizationId: organizationId,
    companyName: 'Seguridad RISEG',
    companyStatus: 'activa',
    organizationName: 'Grupo RISEG',
    role: role,
    isMaestro: isMaestro,
    restricted: restricted,
    enabledModules: modulos,
    effectivePermissions: permisos,
  );

  AutorizacionCompany vista({
    String role = 'user',
    bool isMaestro = false,
    bool restricted = false,
    Set<String> modulos = const {'personal'},
    Set<String> permisos = const {'personal.read'},
  }) => AutorizacionCompany(
    contexto(
      role: role,
      isMaestro: isMaestro,
      restricted: restricted,
      modulos: modulos,
      permisos: permisos,
    ),
  );

  const sinCompany = AutorizacionCompany.sinCompany();

  // =========================================================================
  group('Permisos', () {
    test('presente → true', () {
      expect(
        vista(
          permisos: {PermisoCompany.personalRead},
        ).puede(PermisoCompany.personalRead),
        isTrue,
      );
    });

    test('ausente → false', () {
      expect(
        vista(
          permisos: {PermisoCompany.personalRead},
        ).puede(PermisoCompany.personalManage),
        isFalse,
      );
    });

    test('desconocido → false, sin lanzar', () {
      // Un código que no existe en el catálogo del servidor se trata como cualquier
      // otro ausente. Enviarlo de verdad a un endpoint produciría un 500, y por eso los
      // códigos viven en `PermisoCompany`.
      final v = vista(permisos: {PermisoCompany.personalRead});

      expect(v.puede('finance.read'), isFalse);
      expect(v.puede('files.manage'), isFalse);
      expect(v.puede(''), isFalse);
      expect(v.puede('personal'), isFalse);
    });

    test('NO expande manage a read', () {
      // El backend los exige por separado: son dos códigos independientes.
      final v = vista(permisos: {PermisoCompany.personalManage});

      expect(v.puede(PermisoCompany.personalManage), isTrue);
      expect(
        v.puede(PermisoCompany.personalRead),
        isFalse,
        reason: 'administrar no implica consultar en este backend',
      );
    });

    test('NO interpreta los puntos como jerarquía', () {
      // Tener `personal.sensitive.read` no da `personal.read`, ni al contrario.
      final v = vista(permisos: {PermisoCompany.personalSensitiveRead});

      expect(v.puede(PermisoCompany.personalSensitiveRead), isTrue);
      expect(v.puede(PermisoCompany.personalRead), isFalse);
      expect(v.puede('personal.sensitive'), isFalse);
    });

    test('sin empresa → false', () {
      expect(sinCompany.puede(PermisoCompany.personalRead), isFalse);
      expect(sinCompany.hayCompany, isFalse);
    });

    test('puedeAlguno', () {
      final v = vista(
        permisos: {PermisoCompany.personalRead, PermisoCompany.payrollRead},
      );

      expect(
        v.puedeAlguno({
          PermisoCompany.personalRead,
          PermisoCompany.payrollClose,
        }),
        isTrue,
      );
      expect(
        v.puedeAlguno({
          PermisoCompany.payrollClose,
          PermisoCompany.companyAuditRead,
        }),
        isFalse,
      );
      expect(v.puedeAlguno(const {}), isFalse, reason: 'ninguno presente');
      expect(sinCompany.puedeAlguno({PermisoCompany.personalRead}), isFalse);
    });

    test('puedeTodos', () {
      final v = vista(
        permisos: {PermisoCompany.personalRead, PermisoCompany.personalManage},
      );

      expect(
        v.puedeTodos({
          PermisoCompany.personalRead,
          PermisoCompany.personalManage,
        }),
        isTrue,
      );
      expect(
        v.puedeTodos({PermisoCompany.personalRead, PermisoCompany.payrollRead}),
        isFalse,
      );
      expect(sinCompany.puedeTodos({PermisoCompany.personalRead}), isFalse);
    });

    test('puedeTodos del conjunto VACÍO: la decisión documentada', () {
      // Con empresa activa se elige la verdad vacua para que la operación COMPONGA:
      // `puedeTodos(a ∪ b) == puedeTodos(a) && puedeTodos(b)` se rompería con `false`
      // en cuanto uno de los conjuntos estuviera vacío.
      final v = vista(permisos: {PermisoCompany.personalRead});

      expect(v.puedeTodos(const {}), isTrue);

      // Y la composición, comprobada:
      const a = {PermisoCompany.personalRead};
      const b = <String>{};
      expect(v.puedeTodos(a.union(b)), v.puedeTodos(a) && v.puedeTodos(b));

      // SIN empresa gana denegar por omisión, sin excepción: no hay contexto del que
      // afirmar nada.
      expect(
        sinCompany.puedeTodos(const {}),
        isFalse,
        reason: 'denegar por omisión precede a cualquier otra consideración',
      );
    });

    test('el caso real de dos permisos a la vez: expediente sensible', () {
      // El backend exige el protegido Y el ordinario en `PersonnelSensitiveEndpoints`.
      const requeridos = {
        PermisoCompany.personalRead,
        PermisoCompany.personalSensitiveRead,
      };

      expect(
        vista(permisos: {PermisoCompany.personalRead}).puedeTodos(requeridos),
        isFalse,
      );
      expect(vista(permisos: requeridos).puedeTodos(requeridos), isTrue);
    });
  });

  // =========================================================================
  group('Módulos', () {
    test('habilitado → true', () {
      expect(
        vista(
          modulos: {ModuloCompany.personal},
        ).moduloHabilitado(ModuloCompany.personal),
        isTrue,
      );
    });

    test('deshabilitado → false', () {
      expect(
        vista(
          modulos: {ModuloCompany.personal},
        ).moduloHabilitado(ModuloCompany.payroll),
        isFalse,
      );
    });

    test('sin empresa → false', () {
      expect(sinCompany.moduloHabilitado(ModuloCompany.personal), isFalse);
    });

    test('NO se deriva de los permisos, y la distinción importa', () {
      // `effectivePermissions` ya EXCLUYE los permisos de un módulo apagado, así que
      // mirando sólo esa lista «apagado para toda la empresa» y «a ti no te toca» son
      // indistinguibles. Son dos arreglos distintos y el cliente necesita saber cuál
      // ofrecer.
      final moduloEncendidoSinPermiso = vista(
        modulos: {ModuloCompany.payroll},
        permisos: const {},
      );

      expect(
        moduloEncendidoSinPermiso.moduloHabilitado(ModuloCompany.payroll),
        isTrue,
      );
      expect(
        moduloEncendidoSinPermiso.puede(PermisoCompany.payrollRead),
        isFalse,
      );

      final conPermisoSinModulo = vista(
        modulos: const {},
        permisos: {PermisoCompany.payrollRead},
      );

      expect(
        conPermisoSinModulo.moduloHabilitado(ModuloCompany.payroll),
        isFalse,
      );
      expect(
        conPermisoSinModulo.puede(PermisoCompany.payrollRead),
        isTrue,
        reason: 'la vista NO reinterpreta: refleja lo que el servidor mandó',
      );
    });

    test('un módulo desconocido → false', () {
      expect(vista().moduloHabilitado('inventado'), isFalse);
    });
  });

  // =========================================================================
  group('Restricted', () {
    test('la POSESIÓN del permiso no se oculta', () {
      final v = vista(
        restricted: true,
        permisos: {PermisoCompany.personalRead, PermisoCompany.personalManage},
      );

      expect(v.restringido, isTrue);
      expect(v.puede(PermisoCompany.personalRead), isTrue);
      expect(
        v.puede(PermisoCompany.personalManage),
        isTrue,
        reason: 'tiene el permiso; lo que no puede es ejecutarlo ahora',
      );
    });

    test('puedeMutar es false aunque tenga el permiso', () {
      final v = vista(
        restricted: true,
        permisos: {PermisoCompany.personalManage},
      );

      expect(v.puedeMutar(PermisoCompany.personalManage), isFalse);
    });

    test('el permiso NO vence a restricted', () {
      // Ni teniendo los diez.
      final v = vista(restricted: true, permisos: PermisoCompany.todos);

      for (final permiso in PermisoCompany.todos) {
        expect(v.puede(permiso), isTrue);
        expect(v.puedeMutar(permiso), isFalse, reason: permiso);
      }
    });

    test('sin restricción, puedeMutar sigue al permiso', () {
      final v = vista(permisos: {PermisoCompany.personalManage});

      expect(v.puedeMutar(PermisoCompany.personalManage), isTrue);
      expect(v.puedeMutar(PermisoCompany.personalRead), isFalse);
    });

    test('sin empresa, restringido es FALSE, no true', () {
      // Mostrar una restricción comercial a quien simplemente no ha elegido empresa
      // sería inventar un problema: «sin empresa» tiene sus propios estados en IF-3.
      expect(sinCompany.restringido, isFalse);
      expect(sinCompany.puedeMutar(PermisoCompany.personalManage), isFalse);
    });

    test('las dos negativas se pueden distinguir para el mensaje', () {
      final sinPermiso = vista(permisos: const {});
      final restringida = vista(
        restricted: true,
        permisos: {PermisoCompany.personalManage},
      );

      // Mismo `puedeMutar`, motivos opuestos: por eso hay que preguntar `restringido`
      // antes de explicar algo.
      expect(sinPermiso.puedeMutar(PermisoCompany.personalManage), isFalse);
      expect(restringida.puedeMutar(PermisoCompany.personalManage), isFalse);

      expect(sinPermiso.restringido, isFalse);
      expect(restringida.restringido, isTrue);
    });
  });

  // =========================================================================
  group('Maestro', () {
    test('esMaestro refleja el contexto', () {
      expect(vista(role: 'maestro', isMaestro: true).esMaestro, isTrue);
      expect(vista().esMaestro, isFalse);
      expect(sinCompany.esMaestro, isFalse);
    });

    test('un Maestro SIN el permiso protegido obtiene false', () {
      // La regla crítica de esta capa. El Maestro del backend no hereda los
      // protegidos: los recibe como concesión explícita y puede perderlos.
      final maestro = vista(
        role: 'maestro',
        isMaestro: true,
        permisos: {PermisoCompany.personalRead, PermisoCompany.personalManage},
      );

      expect(maestro.esMaestro, isTrue);
      expect(
        maestro.puede(PermisoCompany.personalSensitiveRead),
        isFalse,
        reason: 'ser Maestro NO es un comodín',
      );
      expect(maestro.puede(PermisoCompany.personalSensitiveManage), isFalse);
    });

    test('esMaestro NO altera puede() en ningún caso', () {
      const permisos = {PermisoCompany.personalRead};

      final usuario = vista(permisos: permisos);
      final maestro = vista(
        role: 'maestro',
        isMaestro: true,
        permisos: permisos,
      );

      for (final permiso in PermisoCompany.todos) {
        expect(
          maestro.puede(permiso),
          usuario.puede(permiso),
          reason:
              'el rol no cambia la respuesta: la lista es la misma ($permiso)',
        );
      }
    });

    test('un módulo apagado tampoco se reinterpreta por ser Maestro', () {
      // En el backend el módulo se comprueba ANTES del atajo de Maestro, y el
      // servidor ya excluyó esos permisos de la lista.
      final maestro = vista(
        role: 'maestro',
        isMaestro: true,
        modulos: const {},
        permisos: const {},
      );

      expect(maestro.esMaestro, isTrue);
      expect(maestro.puede(PermisoCompany.personalRead), isFalse);
      expect(maestro.moduloHabilitado(ModuloCompany.personal), isFalse);
    });

    test('un Maestro restringido tampoco muta', () {
      final maestro = vista(
        role: 'maestro',
        isMaestro: true,
        restricted: true,
        permisos: PermisoCompany.todos,
      );

      expect(maestro.puedeMutar(PermisoCompany.companySettingsManage), isFalse);
    });
  });

  // =========================================================================
  group('Rol', () {
    test('expone la metadata del contexto', () {
      expect(vista(role: 'maestro', isMaestro: true).rol, 'maestro');
      expect(vista().rol, 'user');
      expect(sinCompany.rol, isNull);
    });

    test('NO concede nada', () {
      // Dos vistas con el mismo rol y permisos distintos responden distinto; dos con
      // rol distinto y los mismos permisos responden igual.
      final maestroSinNada = vista(
        role: 'maestro',
        isMaestro: true,
        permisos: const {},
      );

      expect(maestroSinNada.rol, 'maestro');
      for (final permiso in PermisoCompany.todos) {
        expect(maestroSinNada.puede(permiso), isFalse);
      }
    });
  });

  // =========================================================================
  group('El texto no filtra nada útil de más', () {
    test('describe sin volcar la lista de permisos', () {
      final texto =
          vista(
            permisos: {
              PermisoCompany.personalRead,
              PermisoCompany.personalManage,
            },
          ).toString();

      expect(texto, contains('2 permisos'));
      expect(texto, isNot(contains('personal.read')));
      expect(
        const AutorizacionCompany.sinCompany().toString(),
        contains('sin empresa'),
      );
    });
  });

  // =========================================================================
  // El cambio de empresa, sobre la cadena REAL de providers: es donde la
  // atomicidad se demuestra, no se supone.
  // =========================================================================
  group('Cambio de empresa', () {
    String cuerpoDeSesion() {
      final ahora = DateTime.now().toUtc();

      return jsonEncode({
        'accessToken': 'at_1',
        'accessExpiresAt':
            ahora.add(const Duration(minutes: 30)).toIso8601String(),
        'refreshToken': 'rt_1',
        'refreshExpiresAt':
            ahora.add(const Duration(days: 14)).toIso8601String(),
        'identityId': '0193f0a0-0000-7000-8000-00000000cafe',
        'sessionId': '0193f0a0-0000-7000-8000-00000000aaaa',
        'displayName': 'Ana Torres',
        'email': 'ana@seventra.mx',
      });
    }

    /// A es una empresa corriente; B tiene otro módulo, otros permisos, otro rol y
    /// está restringida. Todo lo que puede cambiar, cambia.
    String contextoDe(String id) => jsonEncode({
      'companyId': id,
      'organizationId': organizationId,
      'companyName': 'Empresa $id',
      'companyStatus': 'activa',
      'organizationName': 'Grupo RISEG',
      'role': id == empresaA ? 'user' : 'maestro',
      'isMaestro': id == empresaB,
      'enabledModules':
          id == empresaA
              ? [ModuloCompany.personal]
              : [ModuloCompany.payroll, ModuloCompany.clientsServices],
      'effectivePermissions':
          id == empresaA
              ? [PermisoCompany.personalRead]
              : [
                PermisoCompany.payrollRead,
                PermisoCompany.clientsServicesManage,
              ],
      'restricted': id == empresaB,
    });

    ProviderContainer contenedor() {
      final cliente = MockClient((peticion) async {
        if (peticion.url.path.endsWith('/auth/login')) {
          return http.Response(cuerpoDeSesion(), 200);
        }

        if (peticion.url.path.endsWith('/context')) {
          return http.Response(contextoDe(peticion.url.pathSegments[3]), 200);
        }

        return http.Response(
          jsonEncode([
            for (final id in [empresaA, empresaB])
              {
                'companyId': id,
                'organizationId': organizationId,
                'companyName': 'Empresa $id',
                'organizationName': 'Grupo RISEG',
                'role': 'maestro',
              },
          ]),
          200,
        );
      });

      final config = ApiConfig.resolve(
        raw: 'http://localhost:5199',
      ).when(ok: (c) => c, failure: (f) => throw StateError(f.message));

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

    test('sin empresa activa, la vista niega todo', () async {
      final container = contenedor();

      final autorizacion = container.read(autorizacionProvider);

      expect(autorizacion.hayCompany, isFalse);
      expect(autorizacion.puede(PermisoCompany.personalRead), isFalse);
      expect(autorizacion.moduloHabilitado(ModuloCompany.personal), isFalse);
      expect(autorizacion.esMaestro, isFalse);
      expect(autorizacion.restringido, isFalse);
      expect(autorizacion.rol, isNull);
    });

    test('A y B autorizan distinto, y el cambio es atómico', () async {
      final container = contenedor();

      await container
          .read(gestorDeSesionProvider)
          .iniciarSesion(email: 'ana@seventra.mx', password: 'x');

      final gestor = container.read(gestorDeCompanyProvider);

      // Se observa para que el provider quede vivo, como hará un widget.
      container.listen(autorizacionProvider, (_, _) {}, fireImmediately: true);

      await gestor.cambiarA(empresaA);

      final enA = container.read(autorizacionProvider);
      expect(enA.puede(PermisoCompany.personalRead), isTrue);
      expect(enA.moduloHabilitado(ModuloCompany.personal), isTrue);
      expect(enA.esMaestro, isFalse);
      expect(enA.restringido, isFalse);
      expect(enA.rol, 'user');

      await gestor.cambiarA(empresaB);

      final enB = container.read(autorizacionProvider);

      // Permisos: cambian.
      expect(enB.puede(PermisoCompany.payrollRead), isTrue);
      expect(
        enB.puede(PermisoCompany.personalRead),
        isFalse,
        reason: 'ningún permiso de A sobrevive bajo B',
      );

      // Módulos: cambian.
      expect(enB.moduloHabilitado(ModuloCompany.payroll), isTrue);
      expect(enB.moduloHabilitado(ModuloCompany.personal), isFalse);

      // Rol y Maestro: cambian.
      expect(enB.rol, 'maestro');
      expect(enB.esMaestro, isTrue);

      // Restricted: cambia, y con él la capacidad de mutar.
      expect(enB.restringido, isTrue);
      expect(enB.puede(PermisoCompany.clientsServicesManage), isTrue);
      expect(enB.puedeMutar(PermisoCompany.clientsServicesManage), isFalse);
    });

    test('olvidar la empresa devuelve la vista a negar todo', () async {
      final container = contenedor();

      await container
          .read(gestorDeSesionProvider)
          .iniciarSesion(email: 'ana@seventra.mx', password: 'x');

      final gestor = container.read(gestorDeCompanyProvider);
      container.listen(autorizacionProvider, (_, _) {}, fireImmediately: true);

      await gestor.cambiarA(empresaA);
      expect(
        container.read(autorizacionProvider).puede(PermisoCompany.personalRead),
        isTrue,
      );

      await gestor.olvidarSeleccion();

      final despues = container.read(autorizacionProvider);
      expect(despues.hayCompany, isFalse);
      expect(despues.puede(PermisoCompany.personalRead), isFalse);
    });

    test(
      'la vista se deriva del MISMO contexto: no hay segunda caché',
      () async {
        final container = contenedor();

        await container
            .read(gestorDeSesionProvider)
            .iniciarSesion(email: 'ana@seventra.mx', password: 'x');

        await container.read(gestorDeCompanyProvider).cambiarA(empresaB);

        final contextoLeido = container.read(companyContextProvider)!;
        final autorizacion = container.read(autorizacionProvider);

        // Lo que responde la vista es exactamente lo que trae el contexto.
        for (final permiso in PermisoCompany.todos) {
          expect(
            autorizacion.puede(permiso),
            contextoLeido.effectivePermissions.contains(permiso),
            reason: permiso,
          );
        }

        for (final modulo in ModuloCompany.todos) {
          expect(
            autorizacion.moduloHabilitado(modulo),
            contextoLeido.enabledModules.contains(modulo),
            reason: modulo,
          );
        }

        expect(autorizacion.restringido, contextoLeido.restricted);
        expect(autorizacion.esMaestro, contextoLeido.isMaestro);
        expect(autorizacion.rol, contextoLeido.role);
      },
    );
  });
}

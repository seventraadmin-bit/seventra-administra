// P2 — que quitar un permiso surta efecto sin recargar la página.
//
// LO QUE ESTAS PRUEBAS DEFIENDEN, y conviene empezar por lo que NO es:
//
// El servidor **no** tiene este problema. Autoriza contra la base en cada petición y
// su consulta exige `activa` en el acceso, la empresa y la organización; no hay caché.
// Medido el 22 de octubre de 2026, y corregido en las deudas: retirar un permiso surte
// efecto en la petición siguiente. Lo que se queda viejo es la copia que el navegador
// pidió al entrar, y de ella sale qué botones se pintan.
//
// Así que lo que se prueba aquí es una interfaz que deja de mentir:
//
//  1. **que un 403 de permiso o de módulo ponga el contexto al día**, porque son los
//     dos que viajan dentro de él;
//  2. **que los demás 403 NO lo hagan.** `autoridad_insuficiente` es de otro plano y
//     `self_grant_prohibido` es una regla de la operación: volver a pedir el contexto
//     devolvería lo mismo, y la petición sería puro ruido;
//  3. **que un 404 tampoco**, que es una decisión ya escrita en `revalidar()`: «un 404
//     de negocio puede significar simplemente que ese empleado no existe, y
//     engancharlo aquí cerraría empresas por errores ajenos»;
//  4. **que diez avisos a la vez pidan el contexto UNA vez.** Una pantalla lanza
//     varias peticiones y puede recibir varios 403 seguidos.

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riseg_one/core/api/api_client.dart';
import 'package:riseg_one/core/api/api_client_autenticado.dart';
import 'package:riseg_one/core/api/api_respuesta.dart';
import 'package:riseg_one/core/auth/almacen_sesion_remota.dart';
import 'package:riseg_one/core/auth/auth_api.dart';
import 'package:riseg_one/core/auth/gestor_de_sesion.dart';
import 'package:riseg_one/core/auth/sesion_remota.dart';
import 'package:riseg_one/core/company/almacen_company_recordada.dart';
import 'package:riseg_one/core/company/company_api.dart';
import 'package:riseg_one/core/company/company_remota.dart';
import 'package:riseg_one/core/company/gestor_de_company.dart';
import 'package:riseg_one/core/company/vigilante_de_contexto.dart';
import 'package:riseg_one/core/config/api_config.dart';
import 'package:riseg_one/core/logging/app_logger.dart';

const _empresa = '0193f0a0-0000-7000-8000-0000000000a1';

ApiRespuesta _respuesta(int codigo, String cuerpo) =>
    ApiRespuesta(statusCode: codigo, headers: const {}, cuerpo: cuerpo);

String _errorJson(String codigo) =>
    '{"code": "$codigo", "message": "No se pudo."}';

void main() {
  group('La regla, sin montar nada', () {
    test('un 403 de permiso o de módulo dice que el contexto es viejo', () {
      // LOS DOS VIAJAN EN EL CONTEXTO: la lista de permisos efectivos y la de módulos
      // habilitados. Si el servidor rechaza por uno de ellos, la copia discrepa.
      for (final codigo in ['permission_missing', 'module_disabled']) {
        expect(
          VigilanteDeContexto.diceQueElContextoEsViejo(
            _respuesta(403, _errorJson(codigo)),
          ),
          isTrue,
          reason: codigo,
        );
      }
    });

    test('los OTROS 403 no, y esa diferencia es el punto', () {
      // `autoridad_insuficiente` es del plano de Organization —no viaja en este
      // contexto—, y los dos de permisos protegidos son reglas de la operación: el
      // contexto no cambió, así que pedirlo otra vez sólo gasta una petición.
      for (final codigo in [
        'autoridad_insuficiente',
        'self_grant_prohibido',
        'permiso_protegido_no_poseido',
      ]) {
        expect(
          VigilanteDeContexto.diceQueElContextoEsViejo(
            _respuesta(403, _errorJson(codigo)),
          ),
          isFalse,
          reason: codigo,
        );
      }
    });

    test('ni el 404, ni el 402, ni un 200', () {
      // EL 404 ES UNA DECISIÓN ESCRITA, no un olvido: un 404 de negocio puede ser
      // simplemente que ese empleado no existe. El 402 conserva los permisos y sólo
      // rechaza mutaciones, así que el contexto sigue siendo correcto.
      expect(
        VigilanteDeContexto.diceQueElContextoEsViejo(
          _respuesta(404, _errorJson('empresa_no_disponible')),
        ),
        isFalse,
      );

      expect(
        VigilanteDeContexto.diceQueElContextoEsViejo(
          _respuesta(402, _errorJson('subscription_restricted')),
        ),
        isFalse,
      );

      // Y UN 200 QUE MENCIONE LA PALABRA no cuenta: el estado manda sobre el cuerpo.
      // Sin esto, una respuesta correcta que trajera el texto «permission_missing»
      // —por ejemplo, la auditoría de un rechazo— pediría el contexto sin motivo.
      expect(
        VigilanteDeContexto.diceQueElContextoEsViejo(
          _respuesta(200, '[{"accion": "permission_missing"}]'),
        ),
        isFalse,
      );
    });
  });

  group('El vigilante sobre el cliente', () {
    /// Un gestor con una empresa abierta, y la cuenta de cuántas veces se pidió el
    /// contexto. **Es lo que se mide**: una puesta al día es una lectura de
    /// `/context`, y lo que se defiende es cuántas.
    Future<({GestorDeCompany gestor, VigilanteDeContexto vigilado, List<String> contextos})>
    armar({
      required int codigoDeLaPeticion,
      required String cuerpoDeLaPeticion,
    }) async {
      final contextos = <String>[];

      final desnudo = ApiClient(
        config: ApiConfig.resolve(raw: 'http://localhost:5199').when(
          ok: (c) => c,
          failure: (f) => throw StateError(f.message),
        ),
        cliente: MockClient((peticion) async {
          final ruta = peticion.url.path;

          if (ruta.endsWith('/auth/login')) {
            return http.Response(
              '''
              {
                "accessToken": "at",
                "refreshToken": "rt",
                "identityId": "0193f0a0-0000-7000-8000-000000000001",
                "sessionId": "0193f0a0-0000-7000-8000-000000000002",
                "accessExpiresAt": "2099-01-01T00:00:00Z",
                "refreshExpiresAt": "2099-01-01T00:00:00Z",
                "displayName": "Ana",
                "email": "ana@seventra.mx"
              }
              ''',
              200,
              headers: const {'content-type': 'application/json'},
            );
          }

          if (ruta.endsWith('/companies')) {
            return http.Response(
              '[{"companyId": "$_empresa", '
              '"organizationId": "0193f0a0-0000-7000-8000-0000000000aa", '
              '"companyName": "RISEG", "organizationName": "Org", '
              '"role": "maestro", "status": "activa", "legalName": null}]',
              200,
              headers: const {'content-type': 'application/json'},
            );
          }

          if (ruta.endsWith('/context')) {
            contextos.add(ruta);

            return http.Response(
              '{"companyId": "$_empresa", '
              '"organizationId": "0193f0a0-0000-7000-8000-0000000000aa", '
              '"companyName": "RISEG", "companyStatus": "activa", '
              '"organizationName": "Org", "role": "maestro", '
              '"isMaestro": true, "enabledModules": ["personal"], '
              '"effectivePermissions": ["personal.read"], "restricted": false}',
              200,
              headers: const {'content-type': 'application/json'},
            );
          }

          // La petición de negocio, con lo que la prueba quiera que conteste.
          return http.Response(
            cuerpoDeLaPeticion,
            codigoDeLaPeticion,
            headers: const {'content-type': 'application/json'},
          );
        }),
        logger: AppLogger.console(),
      );

      final sesion = GestorDeSesion(
        api: AuthApi(desnudo),
        almacen: _SinSesion(),
        logger: AppLogger.console(),
      );
      addTearDown(sesion.dispose);

      await sesion.iniciarSesion(email: 'ana@seventra.mx', password: 'x');

      final autenticado = ApiClientAutenticado(cliente: desnudo, gestor: sesion);

      final gestor = GestorDeCompany(
        api: CompanyApi(autenticado),
        almacen: const _SinPreferencia(),
        logger: AppLogger.console(),
      );
      addTearDown(gestor.dispose);

      // Se entra: con una sola empresa, resolver carga su contexto y entra.
      await gestor.resolver();
      expect(gestor.estado, isA<CompanyActiva>());

      // La lectura del arranque no cuenta para lo que se mide.
      contextos.clear();

      return (
        gestor: gestor,
        vigilado: VigilanteDeContexto(
          cliente: autenticado,
          alDetectar: gestor.avisarDeContextoDesactualizado,
        ),
        contextos: contextos,
      );
    }

    /// Deja correr lo que el vigilante disparó.
    ///
    /// ⚠️ **NO SE LLAMA A `avisarDeContextoDesactualizado` DESDE LA PRUEBA, y la
    /// primera versión de esto sí lo hacía: entonces la lectura la provocaba la prueba
    /// y no el vigilante, así que habría pasado igual con el vigilante desconectado.
    /// Era teatro.** Aquí sólo se espera: el aviso es asíncrono porque el vigilante no
    /// bloquea la respuesta de negocio —hacerlo retrasaría la pantalla por algo que no
    /// necesita para pintar su error—.
    Future<void> dejarCorrer() async {
      for (var i = 0; i < 6; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    test('un 403 de permiso pone el contexto al día', () async {
      final t = await armar(
        codigoDeLaPeticion: 403,
        cuerpoDeLaPeticion: _errorJson('permission_missing'),
      );

      await t.vigilado.get('/companies/$_empresa/areas');
      await dejarCorrer();

      expect(t.contextos, hasLength(1));
    });

    test('DIEZ 403 a la vez piden el contexto UNA sola vez', () async {
      // ⚠️ ES EL CANDADO CONTRA LA TORMENTA. Una pantalla lanza varias peticiones al
      // abrirse; si a todas les retiraron el permiso, llegan varios 403 juntos. Sin
      // esto serían diez lecturas idénticas y diez repintados para enterarse de lo
      // mismo.
      final t = await armar(
        codigoDeLaPeticion: 403,
        cuerpoDeLaPeticion: _errorJson('permission_missing'),
      );

      await Future.wait([
        for (var i = 0; i < 10; i++) t.vigilado.get('/companies/$_empresa/areas'),
      ]);

      await dejarCorrer();

      expect(t.contextos, hasLength(1));
    });

    test('un 403 de OTRO código no pide nada', () async {
      final t = await armar(
        codigoDeLaPeticion: 403,
        cuerpoDeLaPeticion: _errorJson('autoridad_insuficiente'),
      );

      await t.vigilado.get('/organizations/x/companies/administration');
      await Future<void>.delayed(Duration.zero);

      expect(t.contextos, isEmpty);
    });

    test('un 404 de negocio tampoco', () async {
      // Lo dice `revalidar()` y se respeta: engancharlo aquí cerraría empresas por
      // errores ajenos.
      final t = await armar(
        codigoDeLaPeticion: 404,
        cuerpoDeLaPeticion: _errorJson('no_encontrado'),
      );

      await t.vigilado.get('/companies/$_empresa/employees/x');
      await Future<void>.delayed(Duration.zero);

      expect(t.contextos, isEmpty);
    });

    test('y una respuesta correcta no pide nada', () async {
      final t = await armar(codigoDeLaPeticion: 200, cuerpoDeLaPeticion: '[]');

      await t.vigilado.get('/companies/$_empresa/areas');
      await Future<void>.delayed(Duration.zero);

      expect(t.contextos, isEmpty);
    });
  });
}

class _SinSesion implements AlmacenSesionRemota {
  @override
  Future<CredencialRemota?> leer() async => null;

  @override
  Future<void> escribir(CredencialRemota credencial) async {}

  @override
  Future<void> borrar() async {}
}

class _SinPreferencia implements AlmacenCompanyRecordada {
  const _SinPreferencia();

  @override
  Future<String?> leer() async => null;

  @override
  Future<void> escribir(String companyId) async {}

  @override
  Future<void> borrar() async {}
}

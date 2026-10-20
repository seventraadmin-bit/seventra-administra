// Los dos expedientes en la web: los modelos y el repositorio.
//
// La pila es real de arriba abajo menos el transporte, igual que en el ciclo de vida:
// el repositorio habla con el `ApiClientAutenticado` de verdad, que pide el token a un
// `GestorDeSesion` de verdad, que se autenticó contra el mismo `MockClient`. Afirmar
// sobre la petición que llega al transporte es afirmar sobre lo que saldría por el
// cable.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riseg_one/core/api/api_client.dart';
import 'package:riseg_one/core/api/api_client_autenticado.dart';
import 'package:riseg_one/core/auth/almacen_sesion_remota.dart';
import 'package:riseg_one/core/auth/auth_api.dart';
import 'package:riseg_one/core/auth/gestor_de_sesion.dart';
import 'package:riseg_one/core/auth/sesion_remota.dart';
import 'package:riseg_one/core/config/api_config.dart';
import 'package:riseg_one/core/error/failure.dart';
import 'package:riseg_one/core/error/result.dart';
import 'package:riseg_one/core/logging/app_logger.dart';
import 'package:riseg_one/features/organizacion/web/datos/expedientes_repositorio_http.dart';
import 'package:riseg_one/features/organizacion/web/modelos/expediente.dart';

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

void main() {
  // =========================================================================
  // 1 · EL TRAMO DE HORARIO: el 24:00, el cruce y la ausencia
  // =========================================================================

  group('TramoDeHorario', () {
    test('un cierre de 00:00 se guarda como 1440, no como cero', () {
      // EL SERVIDOR RECHAZA UN FIN DE 0 con un mensaje que nombra el 24:00, y el
      // selector de hora no puede devolver 24:00 porque `TimeOfDay` no llega ahí. Sin
      // esta conversión la pantalla ofrecería una hora que la API no acepta.
      final t = TramoDeHorario.nuevo(dia: 1, inicio: 22 * 60, fin: 0);

      expect(t.fin, 1440);

      // Y NO CRUZA LA MEDIANOCHE: cierra EN la medianoche. Son dos horas de tramo, no
      // veintiséis.
      expect(t.cruzaMedianoche, isFalse);
    });

    test('el 1440 se muestra como 24:00 y no como 00:00', () {
      // «00:00» en la columna de cierre se leería como el principio del día, que es
      // justo lo contrario de lo que significa.
      expect(TramoDeHorario.comoHora(1440), '24:00');
      expect(TramoDeHorario.comoHora(0), '00:00');
    });

    test('un tramo que termina antes de empezar SÍ cruza', () {
      final t = TramoDeHorario.nuevo(dia: 7, inicio: 20 * 60, fin: 7 * 60);

      expect(t.cruzaMedianoche, isTrue);
      expect(t.horario, '20:00 – 07:00');
    });

    test('las 24 horas completas NO cruzan, aunque terminen en medianoche', () {
      final t = TramoDeHorario.nuevo(dia: 3, inicio: 0, fin: 1440);

      expect(t.cruzaMedianoche, isFalse);
      expect(t.horario, '00:00 – 24:00');
    });

    test('el cruce que MANDA es el del servidor, no el que calcula la pantalla', () {
      // AL LEER SE OBEDECE. `crossesMidnight` lo derivó el servidor y la pantalla lo
      // pinta; recalcularlo al leer sería una segunda regla que puede discrepar.
      final t = TramoDeHorario.deJson({
        'dayOfWeek': 2,
        'startMinute': 540,
        'endMinute': 840,
        'crossesMidnight': true,
      });

      expect(t.cruzaMedianoche, isTrue);
    });

    test('al mandar NO se envía el cruce', () {
      final json = TramoDeHorario.nuevo(dia: 4, inicio: 600, fin: 1200).aJson();

      expect(json.keys, containsAll(['dayOfWeek', 'startMinute', 'endMinute']));
      expect(json.containsKey('crossesMidnight'), isFalse);
    });

    test('los siete días tienen nombre, y el 1 es lunes', () {
      expect(TramoDeHorario.nuevo(dia: 1, inicio: 0, fin: 60).nombreDelDia, 'Lunes');
      expect(
        TramoDeHorario.nuevo(dia: 7, inicio: 0, fin: 60).nombreDelDia,
        'Domingo',
      );
    });
  });

  // =========================================================================
  // 2 · EL EXPEDIENTE DE LA SUCURSAL: varios tramos, y el día cerrado
  // =========================================================================

  group('ExpedienteDeSucursal', () {
    Map<String, dynamic> conHorario(List<Map<String, dynamic>> tramos) => {
      'branchId': '0193f0a0-0000-7000-8000-0000000000b1',
      'code': 'MATRIZ',
      'name': 'Matriz',
      'address': null,
      'schedule': tramos,
      'profileVersion': 3,
    };

    test('un día con DOS tramos los devuelve los dos, en orden', () {
      // LO QUE EL ESCRITORIO NO PODÍA EXPRESAR: allá el horario son siete filas fijas
      // con un tramo cada una, así que abrir 9–14 y 16–20 no caía en el modelo.
      //
      // Y SE DEVUELVEN ORDENADOS por hora de inicio, no en el orden en que lleguen:
      // una lista desordenada se leería como un horario incoherente.
      final e = ExpedienteDeSucursal.deJson(
        conHorario([
          {
            'dayOfWeek': 1,
            'startMinute': 16 * 60,
            'endMinute': 20 * 60,
            'crossesMidnight': false,
          },
          {
            'dayOfWeek': 1,
            'startMinute': 9 * 60,
            'endMinute': 14 * 60,
            'crossesMidnight': false,
          },
        ]),
      );

      expect(e.tramosDe(1).map((t) => t.horario), [
        '09:00 – 14:00',
        '16:00 – 20:00',
      ]);
    });

    test('un día CERRADO es la ausencia de tramos, no un tramo en ceros', () {
      // Un tramo de 00:00 a 00:00 sería un horario de duración cero que el motor
      // rechaza; la forma de decir «cerrado» es no tener fila.
      final e = ExpedienteDeSucursal.deJson(conHorario(const []));

      expect(e.horario, isEmpty);
      expect(e.tramosDe(1), isEmpty);
    });

    test('`tramosDe` no mezcla los días', () {
      final e = ExpedienteDeSucursal.deJson(
        conHorario([
          {
            'dayOfWeek': 1,
            'startMinute': 540,
            'endMinute': 1080,
            'crossesMidnight': false,
          },
          {
            'dayOfWeek': 6,
            'startMinute': 600,
            'endMinute': 840,
            'crossesMidnight': false,
          },
        ]),
      );

      expect(e.tramosDe(1).single.horario, '09:00 – 18:00');
      expect(e.tramosDe(6).single.horario, '10:00 – 14:00');
      expect(e.tramosDe(2), isEmpty);
    });

    test('un domicilio nulo se conserva nulo, y no se inventa uno vacío', () {
      // AUSENCIA NUNCA ES CERO, y aquí tampoco es una dirección de diez cadenas
      // vacías: la pantalla distingue «no hay domicilio» de «hay uno a medias».
      final e = ExpedienteDeSucursal.deJson(conHorario(const []));

      expect(e.direccion, isNull);
    });
  });

  // =========================================================================
  // 3 · LA DIRECCIÓN Y EL CONTACTO
  // =========================================================================

  group('Direccion', () {
    const completa = {
      'street': 'Av. Independencia',
      'exteriorNumber': '100',
      'interiorNumber': '3',
      'neighborhood': 'Centro',
      'municipality': 'Toluca',
      'city': 'Toluca de Lerdo',
      'state': 'Estado de México',
      'postalCode': '50000',
      'country': 'México',
      'landmarks': 'Frente al portal',
    };

    test('en una línea pone el interior sólo si existe', () {
      // UN «Int. » SUELTO SE LEE COMO UN DATO QUE FALTA, así que no se escribe.
      expect(
        Direccion.deJson(completa).enUnaLinea,
        'Av. Independencia 100 Int. 3, Centro, Toluca, '
        'Estado de México, C.P. 50000',
      );

      final sinInterior = {...completa, 'interiorNumber': null};

      expect(
        Direccion.deJson(sinInterior).enUnaLinea,
        'Av. Independencia 100, Centro, Toluca, Estado de México, C.P. 50000',
      );
    });

    test('ida y vuelta por JSON no pierde ningún campo', () {
      // LA FORMA ES LA MISMA EN LOS SEIS SITIOS que usan dirección, y el servidor
      // compara las seis tablas columna por columna. Aquí se vigila el otro lado: que
      // el cliente no se coma un campo opcional al mandarlo de vuelta.
      final ida = Direccion.deJson(completa);
      final vuelta = Direccion.deJson(ida.aJson());

      expect(vuelta.aJson(), ida.aJson());
      expect(ida.aJson().keys.length, completa.keys.length);
    });
  });

  group('Contacto', () {
    test('vacío es vacío aunque traiga espacios', () {
      // EL SERVIDOR NO GUARDA UN CONTACTO ASÍ, y un espacio no es un teléfono. Si
      // esto devolviera `false`, la pantalla mandaría una fila que el servidor
      // descarta y diría «guardado» de algo que no se guardó.
      expect(
        const Contacto(telefono: '  ', correo: '', sitio: null).estaVacio,
        isTrue,
      );
    });

    test('con un solo dato ya no está vacío', () {
      expect(const Contacto(correo: 'pagos@riseg.mx').estaVacio, isFalse);
    });
  });

  // =========================================================================
  // 4 · EL RÉGIMEN FISCAL
  // =========================================================================

  group('RegimenFiscal', () {
    test('`selectable` es lo que llega, no se deduce de un estado', () {
      // LA PANTALLA NO TIENE QUE SABER QUÉ SIGNIFICA «inactiva», sólo si puede
      // ofrecerlo. El servidor manda `selectable` ya decidido.
      final retirado = RegimenFiscal.deJson({
        'code': '601',
        'name': 'General de Ley Personas Morales',
        'personaFisica': false,
        'personaMoral': true,
        'selectable': false,
      });

      expect(retirado.seleccionable, isFalse);
      expect(retirado.etiqueta, '601 · General de Ley Personas Morales');
    });
  });

  // =========================================================================
  // 5 · EL REPOSITORIO, contra el transporte real
  // =========================================================================

  final config = ApiConfig.resolve(
    raw: 'http://localhost:5199',
  ).when(ok: (c) => c, failure: (f) => throw StateError(f.message));

  final t0 = DateTime.utc(2026, 10, 19, 12);

  const empresa = '0193f0a0-0000-7000-8000-000000000001';
  const sucursalId = '0193f0a0-0000-7000-8000-0000000000b1';

  String cuerpoDeSesion() => jsonEncode({
    'accessToken': 'at_1',
    'accessExpiresAt': t0.add(const Duration(minutes: 30)).toIso8601String(),
    'refreshToken': 'rt_1',
    'refreshExpiresAt': t0.add(const Duration(days: 14)).toIso8601String(),
    'identityId': '0193f0a0-0000-7000-8000-00000000cafe',
    'sessionId': '0193f0a0-0000-7000-8000-00000000aaaa',
    'displayName': 'Ana Torres',
    'email': 'ana@seventra.mx',
  });

  Future<({ExpedientesRepositorioHttp repo, List<http.Request> vistas})>
  construir(Future<http.Response> Function(http.Request) responder) async {
    final vistas = <http.Request>[];

    final desnudo = ApiClient(
      config: config,
      cliente: MockClient((peticion) async {
        vistas.add(peticion);

        if (peticion.url.path.endsWith('/auth/login')) {
          return http.Response(cuerpoDeSesion(), 200);
        }

        return responder(peticion);
      }),
      logger: AppLogger.console(),
    );

    final sesion = GestorDeSesion(
      api: AuthApi(desnudo),
      almacen: _AlmacenSesionEnMemoria(),
      logger: AppLogger.console(),
      ahora: () => t0,
    );

    addTearDown(sesion.dispose);

    await sesion.iniciarSesion(email: 'ana@seventra.mx', password: 'x');
    vistas.clear();

    return (
      repo: ExpedientesRepositorioHttp(
        ApiClientAutenticado(cliente: desnudo, gestor: sesion),
      ),
      vistas: vistas,
    );
  }

  Failure exigirFallo<T>(Result<T> resultado) => resultado.when(
    ok: (_) => fail('Se esperaba un fallo y llegó un valor.'),
    failure: (f) => f,
  );

  T exigirOk<T>(Result<T> resultado) => resultado.when(
    ok: (valor) => valor,
    failure: (f) => fail('Se esperaba un valor y llegó: ${f.message}'),
  );

  String expedienteDeEmpresa({int version = 2}) => jsonEncode({
    'companyId': empresa,
    'name': 'RISEG',
    'legalName': 'Seguridad Privada RISEG S.A. de C.V.',
    'taxId': 'SPR950101AB1',
    'legalRep': 'Juan Pérez',
    'slogan': null,
    'fiscalRegimeCode': '601',
    'address': null,
    'contact': null,
    'profileVersion': version,
    'fiscalCardReady': false,
  });

  group('guardar el expediente de la empresa', () {
    test('es PUT, y la VERSIÓN viaja en el cuerpo', () async {
      // LA VERSIÓN ES EL CANDADO. Si no saliera por el cable, el servidor no podría
      // negarse y el que guardara segundo borraría el trabajo del primero.
      final (repo: repo, vistas: vistas) = await construir(
        (_) async => http.Response(expedienteDeEmpresa(version: 3), 200),
      );

      await repo.guardarDeEmpresa(
        empresaId: empresa,
        version: 2,
        razonSocial: 'Seguridad Privada RISEG S.A. de C.V.',
      );

      final peticion = vistas.single;

      expect(peticion.method, 'PUT');
      expect(peticion.url.path, '/api/v1/companies/$empresa/profile');

      final cuerpo = jsonDecode(peticion.body) as Map<String, dynamic>;

      expect(cuerpo['profileVersion'], 2);
    });

    test('LOS NULOS SE MANDAN, porque el PUT reemplaza', () async {
      // OMITIRLOS HARÍA IMPOSIBLE VACIAR UN DATO. Si un eslogan nulo no viajara, el
      // servidor conservaría el anterior y la persona no podría borrarlo nunca.
      final (repo: repo, vistas: vistas) = await construir(
        (_) async => http.Response(expedienteDeEmpresa(), 200),
      );

      await repo.guardarDeEmpresa(
        empresaId: empresa,
        version: 1,
        razonSocial: 'Algo',
      );

      final cuerpo =
          jsonDecode(vistas.single.body) as Map<String, dynamic>;

      for (final clave in [
        'taxId',
        'legalRep',
        'slogan',
        'fiscalRegimeCode',
        'address',
        'contact',
      ]) {
        expect(
          cuerpo.containsKey(clave),
          isTrue,
          reason: 'Falta «$clave»: sin ella no se puede borrar ese dato.',
        );
        expect(cuerpo[clave], isNull);
      }
    });

    test('el 409 del candado se reconoce por su CÓDIGO, no por el 409', () async {
      // UN 409 TAMBIÉN PUEDE SER UN CÓDIGO REPETIDO. Confundirlos mandaría a la
      // persona a cambiar un dato cuando lo que pasó es que otra guardó antes.
      final (repo: repo, vistas: _) = await construir(
        (_) async => http.Response(
          jsonEncode({
            'code': 'expediente_desactualizado',
            'message': 'Alguien más guardó este expediente.',
          }),
          409,
        ),
      );

      final fallo = exigirFallo(
        await repo.guardarDeEmpresa(empresaId: empresa, version: 1),
      );

      expect(ExpedientesRepositorioHttp.esDesactualizado(fallo), isTrue);
    });

    test('y OTRO 409 no se confunde con el candado', () async {
      final (repo: repo, vistas: _) = await construir(
        (_) async => http.Response(
          jsonEncode({'code': 'code_conflict', 'message': 'Código repetido.'}),
          409,
        ),
      );

      final fallo = exigirFallo(
        await repo.guardarDeEmpresa(empresaId: empresa, version: 1),
      );

      expect(ExpedientesRepositorioHttp.esDesactualizado(fallo), isFalse);
    });

    test('el 400 conserva TODOS los campos señalados', () async {
      // EL SERVIDOR REÚNE TODOS LOS ERRORES ANTES DE FALLAR, a propósito. Si el
      // cliente se quedara con el primero, la persona los descubriría de uno en uno,
      // con un guardado por cada uno.
      final (repo: repo, vistas: _) = await construir(
        (_) async => http.Response(
          jsonEncode({
            'code': 'entrada_invalida',
            'message': 'Hay datos que no se pueden guardar.',
            'fields': [
              {'field': 'taxId', 'message': 'El RFC no tiene la forma correcta.'},
              {'field': 'address.postalCode', 'message': 'Cinco dígitos.'},
              {'field': 'contact.email', 'message': 'No parece un correo.'},
            ],
          }),
          400,
        ),
      );

      final fallo = exigirFallo(
        await repo.guardarDeEmpresa(empresaId: empresa, version: 1),
      );

      final campos = ExpedientesRepositorioHttp.camposDe(fallo);

      expect(campos, {
        'taxId': 'El RFC no tiene la forma correcta.',
        'address.postalCode': 'Cinco dígitos.',
        'contact.email': 'No parece un correo.',
      });

      // Y EL MENSAJE GENERAL NO SE PIERDE: es lo que se muestra si la pantalla no
      // sabe dónde poner un campo que no conoce.
      expect(fallo.message, 'Hay datos que no se pueden guardar.');
    });

    test('un 400 SIN campos no rompe nada y deja el mapa vacío', () async {
      // NO SE ROMPE LA PANTALLA POR UN ERROR AL INFORMAR DE UN ERROR. Un cuerpo sin
      // `fields` es legítimo —no todo 400 señala campos— y debe caer en el mensaje
      // general.
      final (repo: repo, vistas: _) = await construir(
        (_) async => http.Response(
          jsonEncode({'code': 'entrada_invalida', 'message': 'No se puede.'}),
          400,
        ),
      );

      final fallo = exigirFallo(
        await repo.guardarDeEmpresa(empresaId: empresa, version: 1),
      );

      expect(ExpedientesRepositorioHttp.camposDe(fallo), isEmpty);
      expect(fallo.message, 'No se puede.');
    });

    test('y un `fields` DEFORME tampoco, aunque llegue mal', () async {
      // Filas sin `field`, con tipos raros, o un `fields` que no es lista: se ignora
      // lo que no se entiende y el mensaje general sigue sirviendo.
      final (repo: repo, vistas: _) = await construir(
        (_) async => http.Response(
          jsonEncode({
            'code': 'entrada_invalida',
            'message': 'No se puede.',
            'fields': [
              {'message': 'sin campo'},
              {'field': '', 'message': 'campo vacío'},
              {'field': 'taxId', 'message': 42},
              'ni un objeto',
              {'field': 'slogan', 'message': 'éste sí vale'},
            ],
          }),
          400,
        ),
      );

      final fallo = exigirFallo(
        await repo.guardarDeEmpresa(empresaId: empresa, version: 1),
      );

      expect(ExpedientesRepositorioHttp.camposDe(fallo), {
        'slogan': 'éste sí vale',
      });
    });
  });

  group('el expediente de la sucursal', () {
    String expedienteDeSucursal() => jsonEncode({
      'branchId': sucursalId,
      'code': 'MATRIZ',
      'name': 'Matriz',
      'address': null,
      'schedule': const [],
      'profileVersion': 1,
    });

    test('la ruta cuelga de la sucursal, dentro de la empresa', () async {
      // EL `companyId` VA EN LA RUTA SIEMPRE, también aquí: es lo que el servidor
      // autoriza, y una ruta que lo omitiera pediría datos sin inquilino.
      final (repo: repo, vistas: vistas) = await construir(
        (_) async => http.Response(expedienteDeSucursal(), 200),
      );

      await repo.leerDeSucursal(empresaId: empresa, sucursalId: sucursalId);

      expect(
        vistas.single.url.path,
        '/api/v1/companies/$empresa/branches/$sucursalId/profile',
      );
    });

    test('UN HORARIO VACÍO SE MANDA VACÍO, y borra el que había', () async {
      // Tratar la lista vacía como «no cambies nada» haría imposible volver a no
      // tener horario, que es un estado legítimo.
      final (repo: repo, vistas: vistas) = await construir(
        (_) async => http.Response(expedienteDeSucursal(), 200),
      );

      await repo.guardarDeSucursal(
        empresaId: empresa,
        sucursalId: sucursalId,
        version: 1,
      );

      final cuerpo =
          jsonDecode(vistas.single.body) as Map<String, dynamic>;

      expect(cuerpo['schedule'], isEmpty);
      expect(cuerpo.containsKey('schedule'), isTrue);
    });

    test('los tramos viajan con día, inicio y fin, y el 1440 intacto', () async {
      final (repo: repo, vistas: vistas) = await construir(
        (_) async => http.Response(expedienteDeSucursal(), 200),
      );

      await repo.guardarDeSucursal(
        empresaId: empresa,
        sucursalId: sucursalId,
        version: 1,
        horario: [
          TramoDeHorario.nuevo(dia: 1, inicio: 9 * 60, fin: 14 * 60),
          TramoDeHorario.nuevo(dia: 1, inicio: 16 * 60, fin: 0),
        ],
      );

      final cuerpo =
          jsonDecode(vistas.single.body) as Map<String, dynamic>;

      expect(cuerpo['schedule'], [
        {'dayOfWeek': 1, 'startMinute': 540, 'endMinute': 840},
        // EL 0 SE CONVIRTIÓ EN 1440 ANTES DE SALIR. Si saliera como 0, el servidor lo
        // rechazaría pidiendo que se escriba 24:00 —y la persona no habría escrito
        // ningún 0—.
        {'dayOfWeek': 1, 'startMinute': 960, 'endMinute': 1440},
      ]);
    });

    test('el solape lo rechaza el SERVIDOR, y llega con su código', () async {
      // LA PANTALLA NO LO ADELANTA. Serían dos reglas para un mismo hecho, y la del
      // cliente se quedaría atrás el día que la del motor cambie.
      final (repo: repo, vistas: _) = await construir(
        (_) async => http.Response(
          jsonEncode({
            'code': 'horario_se_solapa',
            'message': 'Dos tramos del mismo día se enciman.',
          }),
          422,
        ),
      );

      final fallo = exigirFallo(
        await repo.guardarDeSucursal(
          empresaId: empresa,
          sucursalId: sucursalId,
          version: 1,
        ),
      );

      expect(fallo, isA<ApiHttpFailure>());
      expect((fallo as ApiHttpFailure).codigo, 'horario_se_solapa');
      expect(ExpedientesRepositorioHttp.esDesactualizado(fallo), isFalse);
    });
  });

  group('el catálogo del SAT', () {
    String catalogo() => jsonEncode([
      {
        'code': '601',
        'name': 'General de Ley Personas Morales',
        'personaFisica': false,
        'personaMoral': true,
        'selectable': true,
      },
      {
        'code': '605',
        'name': 'Sueldos y Salarios',
        'personaFisica': true,
        'personaMoral': false,
        'selectable': true,
      },
    ]);

    test('sin RFC no se manda el parámetro', () async {
      // MANDAR UN `rfc=` VACÍO haría que el servidor intentara filtrar por una
      // longitud de cero.
      final (repo: repo, vistas: vistas) = await construir(
        (_) async => http.Response(catalogo(), 200),
      );

      await repo.listarRegimenes(empresaId: empresa);

      expect(vistas.single.url.path, '/api/v1/companies/$empresa/fiscal-regimes');
      expect(vistas.single.url.queryParameters.containsKey('rfc'), isFalse);
    });

    test('con RFC lo manda como parámetro, recortado', () async {
      final (repo: repo, vistas: vistas) = await construir(
        (_) async => http.Response(catalogo(), 200),
      );

      await repo.listarRegimenes(empresaId: empresa, rfc: '  SPR950101AB1 ');

      expect(vistas.single.url.queryParameters['rfc'], 'SPR950101AB1');
    });

    test('un RFC de SÓLO ESPACIOS se trata como ausente', () async {
      // Si no se recortara, viajaría un `rfc=%20%20` que no es de 12 ni de 13 y el
      // filtro quedaría en manos de una cadena de espacios.
      final (repo: repo, vistas: vistas) = await construir(
        (_) async => http.Response(catalogo(), 200),
      );

      await repo.listarRegimenes(empresaId: empresa, rfc: '   ');

      expect(vistas.single.url.queryParameters.containsKey('rfc'), isFalse);
    });

    test('lee la lista y conserva las dos banderas de cada régimen', () async {
      final (repo: repo, vistas: _) = await construir(
        (_) async => http.Response(catalogo(), 200),
      );

      final lista = exigirOk(await repo.listarRegimenes(empresaId: empresa));

      expect(lista.map((r) => r.codigo), ['601', '605']);
      expect(lista.first.personaMoral, isTrue);
      expect(lista.first.personaFisica, isFalse);
      expect(lista.last.personaFisica, isTrue);
    });
  });
}

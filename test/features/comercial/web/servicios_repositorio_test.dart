// C2 · EL REPOSITORIO Y LOS MODELOS DE SERVICIOS.
//
// ## Qué se fija aquí, y por qué estas cosas y no otras
//
// Esto no vuelve a probar el servidor: lo prueba su suite. Lo que se fija aquí son las
// cuatro cosas que **sólo existen en este lado** y que se rompen en silencio:
//
//  1. **los filtros VIAJAN en la petición.** Un filtro aplicado en memoria funcionaría
//     igual con cuatro servicios y sería incorrecto con cincuenta y uno: con paginación,
//     filtrar una página no es filtrar la cartera. Se comprueba la URL, no el resultado;
//  2. **el sobre se EXIGE.** Un arreglo pelado se rechaza a propósito: aceptar las dos
//     formas «por compatibilidad» dejaría a la pantalla creyendo que nunca hay más
//     páginas en lugar de fallar a la vista;
//  3. **los dos selectores de tipo NO son la misma lista.** El del filtro pide
//     `?used=true` y el del alta no manda el parámetro. Si alguien los unificara, una de
//     las dos pantallas se rompería — y nada más lo diría;
//  4. **un 404 de un sub-recurso NO es un fallo.** El domicilio y el supervisor que no
//     están se traducen a nulo, para que la pantalla pinte el hueco en lugar de un error.
//
// ## Lo que NO está aquí
//
// Las pantallas. El listado, el alta y el expediente tienen sus propios archivos: aquí no
// se monta ningún widget, y por eso esta suite corre en milisegundos.

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
import 'package:riseg_one/core/direcciones/direccion.dart';
import 'package:riseg_one/core/error/failure.dart';
import 'package:riseg_one/core/fechas/dia_de_negocio.dart';
import 'package:riseg_one/core/logging/app_logger.dart';
import 'package:riseg_one/features/comercial/web/datos/servicios_repositorio_http.dart';
import 'package:riseg_one/features/comercial/web/modelos/servicio.dart';

class _Almacen implements AlmacenSesionRemota {
  CredencialRemota? guardada;

  @override
  Future<CredencialRemota?> leer() async => guardada;

  @override
  Future<void> escribir(CredencialRemota credencial) async =>
      guardada = credencial;

  @override
  Future<void> borrar() async => guardada = null;
}

/// Una petición tal como la vio el transporte. **Se guarda el método, la URL y el
/// cuerpo**, que es lo que distingue «pidió con filtro» de «pidió todo y filtró después».
class _Pedida {
  _Pedida(this.metodo, this.url, this.cuerpo);

  final String metodo;
  final Uri url;
  final String cuerpo;
}

void main() {
  final config = ApiConfig.resolve(
    raw: 'http://localhost:5199',
  ).when(ok: (c) => c, failure: (f) => throw StateError(f.message));

  final t0 = DateTime.utc(2026, 11, 9, 12);

  const empresa = '0193f0a0-0000-7000-8000-000000000001';
  const servicioId = '0193f0a0-0000-7000-8000-0000000000a1';
  const clienteId = '0193f0a0-0000-7000-8000-0000000000c1';

  Map<String, Object?> fila({
    String id = servicioId,
    String codigo = 'SRV-000001',
    String nombre = 'Sportium Satélite',
    String estatus = 'active',
    String condicion = 'inforce',
    String cliente = 'Sportium',
    String? logotipo,
    String? ubicacion = 'Naucalpan, Estado de México',
  }) => {
    'id': id,
    'clientId': clienteId,
    'code': codigo,
    'name': nombre,
    'serviceTypeId': '0193f0a0-0000-7000-8000-0000000000b1',
    'status': estatus,
    'temporalCondition': condicion,
    'startedOn': '2024-03-01',
    'endedOn': null,
    'clientCommercialName': cliente,
    'clientHasLogo': logotipo != null,
    'clientLogoFileId': logotipo,
    'location': ubicacion,
  };

  /// La FICHA, que trae más que la fila: observaciones, vínculos y marcas de tiempo.
  Map<String, Object?> ficha({
    String estatus = 'active',
    String? termino,
    String? supervisor,
  }) => {
    'id': servicioId,
    'clientId': clienteId,
    'code': 'SRV-000001',
    'name': 'Sportium Satélite',
    'serviceTypeId': '0193f0a0-0000-7000-8000-0000000000b1',
    'status': estatus,
    'temporalCondition': 'inforce',
    'startedOn': '2024-03-01',
    'endedOn': termino,
    'notes': 'Acceso por la puerta trasera',
    'supervisorEmployeeId': supervisor,
    'administrativeBranchId': null,
    'responsibleContactId': null,
    'fiscalEntityId': null,
    'createdAt': '2026-01-15T18:00:00Z',
    'updatedAt': '2026-10-20T18:00:00Z',
  };

  Map<String, Object?> sobre(
    List<Map<String, Object?>> items, {
    String? cursorSiguiente,
  }) => {'items': items, 'nextCursor': cursorSiguiente};

  /// El cliente HTTP, con la bitácora de lo que se pidió y una respuesta por prueba.
  Future<(ServiciosRepositorioHttp, List<_Pedida>)> repositorio({
    http.Response Function(_Pedida pedida)? responder,
  }) async {
    final pedidas = <_Pedida>[];

    final desnudo = ApiClient(
      config: config,
      cliente: MockClient((p) async {
        if (p.url.path.endsWith('/auth/login')) {
          return http.Response(
            jsonEncode({
              'accessToken': 'at_1',
              'accessExpiresAt': t0
                  .add(const Duration(minutes: 30))
                  .toIso8601String(),
              'refreshToken': 'rt_1',
              'refreshExpiresAt': t0
                  .add(const Duration(days: 14))
                  .toIso8601String(),
              'sessionId': '0193f0a0-0000-7000-8000-00000000aaaa',
              'identityId': '0193f0a0-0000-7000-8000-00000000bbbb',
              'displayName': 'Ana Torres',
              'email': 'ana@seventra.mx',
            }),
            200,
          );
        }

        final pedida = _Pedida(p.method, p.url, p.body);
        pedidas.add(pedida);

        if (responder != null) return responder(pedida);

        return http.Response(jsonEncode(sobre([fila()])), 200);
      }),
      logger: AppLogger.console(),
    );

    final gestor = GestorDeSesion(
      api: AuthApi(desnudo),
      almacen: _Almacen(),
      logger: AppLogger.console(),
      ahora: () => t0,
    );

    addTearDown(gestor.dispose);
    await gestor.iniciarSesion(email: 'ana@seventra.mx', password: 'x');

    return (
      ServiciosRepositorioHttp(
        ApiClientAutenticado(cliente: desnudo, gestor: gestor),
      ),
      pedidas,
    );
  }

  const domicilio = Direccion(
    calle: 'Circuito Centro Comercial',
    numeroExterior: '40',
    colonia: 'Ciudad Satélite',
    municipio: 'Naucalpan',
    estado: 'Estado de México',
    codigoPostal: '53100',
  );

  group('C2 · los filtros viajan al servidor', () {
    test('los cinco filtros y la paginación salen en la URL', () async {
      final (repo, pedidas) = await repositorio();

      await repo.listar(
        empresa,
        clienteId: clienteId,
        tipoId: '0193f0a0-0000-7000-8000-0000000000b1',
        estatus: EstatusDeServicio.suspendido,
        texto: 'sportium',
        cursor: 'c_1',
        limite: 50,
      );

      final q = pedidas.single.url.queryParameters;

      expect(q['clientId'], clienteId);
      expect(q['serviceTypeId'], '0193f0a0-0000-7000-8000-0000000000b1');
      expect(q['status'], 'suspended');
      expect(q['query'], 'sportium');
      expect(q['cursor'], 'c_1');
      expect(q['limit'], '50');
    });

    test('un texto en blanco NO viaja, porque casaría con todo', () async {
      final (repo, pedidas) = await repositorio();

      await repo.listar(empresa, texto: '   ');

      // MANDAR `query=` HARÍA QUE EL SERVIDOR BUSCARA LA CADENA VACÍA, que casa con
      // todas las filas y encima le cuesta cinco `ILIKE` por fila.
      expect(pedidas.single.url.queryParameters.containsKey('query'), isFalse);
    });

    test('sin filtros no viaja ningún parámetro', () async {
      final (repo, pedidas) = await repositorio();

      await repo.listar(empresa);

      // NULO ES «NO FILTRES POR ESTO», no «filtra por el valor vacío»: son dos cosas, y
      // la segunda no existe.
      expect(pedidas.single.url.queryParameters, isEmpty);
    });
  });

  group('C2 · el sobre del listado', () {
    test('un arreglo pelado se RECHAZA en lugar de leerse a medias', () async {
      final (repo, _) = await repositorio(
        responder: (_) => http.Response(jsonEncode([fila()]), 200),
      );

      final r = await repo.listar(empresa);

      // FALLA A LA VISTA. Aceptar el arreglo «por compatibilidad» dejaría a la pantalla
      // creyendo que nunca hay más páginas, que es un fallo silencioso y permanente.
      expect(
        r.when(ok: (_) => null, failure: (f) => f),
        isA<ApiJsonInvalidoFailure>(),
      );
    });

    test('el cursor nulo significa que no hay más', () async {
      final (repo, _) = await repositorio();

      final pagina = (await repo.listar(empresa)).when(
        ok: (p) => p,
        failure: (f) => throw StateError(f.message),
      );

      expect(pagina.servicios, hasLength(1));
      expect(pagina.cursorSiguiente, isNull);
      expect(pagina.hayMas, isFalse);
    });

    test('con cursor, hayMas es verdadero', () async {
      final (repo, _) = await repositorio(
        responder: (_) =>
            http.Response(jsonEncode(sobre([fila()], cursorSiguiente: 'c_2')), 200),
      );

      final pagina = (await repo.listar(empresa)).when(
        ok: (p) => p,
        failure: (f) => throw StateError(f.message),
      );

      expect(pagina.hayMas, isTrue);
      expect(pagina.cursorSiguiente, 'c_2');
    });
  });

  group('C2 · los dos selectores de tipo no son la misma lista', () {
    test('el del FILTRO pide used=true y el del ALTA no manda el parámetro', () async {
      final (repo, pedidas) = await repositorio(
        responder: (_) => http.Response(
          jsonEncode([
            {
              'id': '0193f0a0-0000-7000-8000-0000000000b1',
              'code': 'INTRAMUROS',
              'name': 'Vigilancia intramuros',
              'status': 'activa',
            },
          ]),
          200,
        ),
      );

      await repo.tipos(empresa, usados: true);
      expect(pedidas.last.url.queryParameters['used'], 'true');

      await repo.tipos(empresa, usados: null);

      // SIN EL PARÁMETRO: el alta necesita TODOS para quedarse con los activos, y un
      // tipo recién creado tiene que poder elegirse para el primer servicio que lo use.
      expect(pedidas.last.url.queryParameters.containsKey('used'), isFalse);
    });

    test('un tipo retirado se reconoce como no elegible', () async {
      final (repo, _) = await repositorio(
        responder: (_) => http.Response(
          jsonEncode([
            {
              'id': '0193f0a0-0000-7000-8000-0000000000b1',
              'code': 'ESCOLTA',
              'name': 'Escolta',
              'status': 'inactiva',
            },
          ]),
          200,
        ),
      );

      final tipos = (await repo.tipos(empresa, usados: true)).when(
        ok: (t) => t,
        failure: (f) => throw StateError(f.message),
      );

      // SALE EN LA LISTA DEL FILTRO Y NO ES ELEGIBLE: las dos cosas a la vez, que es
      // justo la distinción entre «existe» y «se puede elegir».
      expect(tipos.single.nombre, 'Escolta');
      expect(tipos.single.estaActivo, isFalse);
    });
  });

  group('C2 · un 404 de un sub-recurso no es un fallo', () {
    test('el domicilio que no está se traduce a nulo', () async {
      final (repo, _) = await repositorio(
        responder: (_) => http.Response('{"code":"servicio_no_encontrado"}', 404),
      );

      final r = await repo.domicilio(empresaId: empresa, servicioId: servicioId);

      // NULO Y NO UN FALLO: el servicio existe, el sub-recurso no. La pantalla pinta el
      // hueco en lugar de un error — y desde la 0059 esto no debería pasar nunca.
      expect(r.when(ok: (d) => d, failure: (f) => throw StateError(f.message)), isNull);
    });

    test('el supervisor que no está se traduce a nulo', () async {
      final (repo, _) = await repositorio(
        responder: (_) => http.Response('{"code":"servicio_no_encontrado"}', 404),
      );

      final r = await repo.supervisor(empresaId: empresa, servicioId: servicioId);

      expect(r.when(ok: (s) => s, failure: (f) => throw StateError(f.message)), isNull);
    });

    test('un 500 SÍ es un fallo, para que el nulo signifique una sola cosa', () async {
      final (repo, _) = await repositorio(
        responder: (_) => http.Response('{"code":"error_interno"}', 500),
      );

      final r = await repo.supervisor(empresaId: empresa, servicioId: servicioId);

      expect(r.when(ok: (_) => null, failure: (f) => f), isNotNull);
    });
  });

  group('C2 · el cuerpo de las mutaciones', () {
    test('el alta manda el domicilio EN LA MISMA petición', () async {
      final (repo, pedidas) = await repositorio(
        responder: (_) => http.Response(jsonEncode(ficha()), 201),
      );

      await repo.crear(
        empresaId: empresa,
        clienteId: clienteId,
        nombre: 'Torre Norte',
        tipoId: '0193f0a0-0000-7000-8000-0000000000b1',
        inicio: DiaDeNegocio.deTexto('2026-03-01')!,
        domicilio: domicilio,
      );

      final cuerpo = jsonDecode(pedidas.single.cuerpo) as Map<String, dynamic>;

      // UNA SOLA PETICIÓN, y con el domicilio dentro: desde la 0059 la base no admite un
      // servicio sin él, así que un alta en dos pasos no deja un servicio a medias —deja
      // un 400—.
      expect(pedidas, hasLength(1));
      expect(pedidas.single.metodo, 'POST');
      expect(cuerpo['name'], 'Torre Norte');
      expect(cuerpo['startedOn'], '2026-03-01');
      expect((cuerpo['address'] as Map)['municipality'], 'Naucalpan');
    });

    test('la corrección manda SÓLO lo que cambió, y el motivo siempre', () async {
      final (repo, pedidas) = await repositorio(
        responder: (_) => http.Response(jsonEncode(ficha()), 200),
      );

      await repo.corregir(
        empresaId: empresa,
        servicioId: servicioId,
        motivo: 'Cambió de nombre',
        nombre: 'Torre Norte y Sur',
      );

      final cuerpo = jsonDecode(pedidas.single.cuerpo) as Map<String, dynamic>;

      expect(cuerpo['reason'], 'Cambió de nombre');
      expect(cuerpo['name'], 'Torre Norte y Sur');

      // LO QUE NO SE TOCÓ NO VIAJA: un nulo significa «no toques esto», no «ponlo en
      // nulo». Mandar los tres siempre haría que corregir el nombre pisara unas
      // observaciones que otro acababa de escribir.
      expect(cuerpo.containsKey('notes'), isFalse);
      expect(cuerpo.containsKey('serviceTypeId'), isFalse);
    });

    test('retirar el término se dice EXPLÍCITAMENTE, no con un nulo', () async {
      final (repo, pedidas) = await repositorio(
        responder: (_) => http.Response(jsonEncode(ficha()), 200),
      );

      await repo.cambiarEstado(
        empresaId: empresa,
        servicioId: servicioId,
        estatus: EstatusDeServicio.activo,
        motivo: 'Volvió a operar',
        retirarTermino: true,
      );

      final retira = jsonDecode(pedidas.last.cuerpo) as Map<String, dynamic>;

      // `clearEndedOn` Y NO UN `endedOn: null`: en el cable, «nulo» y «no vino» son la
      // misma petición, así que retirar tiene que decirse. Una ausencia nunca se lee
      // como una decisión.
      expect(retira['clearEndedOn'], isTrue);
      expect(retira.containsKey('endedOn'), isFalse);

      await repo.cambiarEstado(
        empresaId: empresa,
        servicioId: servicioId,
        estatus: EstatusDeServicio.activo,
        motivo: 'Volvió a operar',
        termino: DiaDeNegocio.deTexto('2027-03-31'),
      );

      final sustituye = jsonDecode(pedidas.last.cuerpo) as Map<String, dynamic>;

      expect(sustituye['endedOn'], '2027-03-31');
      expect(sustituye.containsKey('clearEndedOn'), isFalse);
    });

    test('pedir las dos formas a la vez es un error de PROGRAMACIÓN', () async {
      final (repo, _) = await repositorio(
        responder: (_) => http.Response(jsonEncode(ficha()), 200),
      );

      // SALTA EN DESARROLLO en lugar de llegar al servidor y volver como un 400 que el
      // usuario ve: «retírala» y «ponla el 31 de marzo» no se pueden cumplir las dos.
      expect(
        () => repo.cambiarEstado(
          empresaId: empresa,
          servicioId: servicioId,
          estatus: EstatusDeServicio.activo,
          motivo: 'Volvió a operar',
          termino: DiaDeNegocio.deTexto('2027-03-31'),
          retirarTermino: true,
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('quitar la entidad fiscal manda el motivo en la CONSULTA', () async {
      final (repo, pedidas) = await repositorio(
        responder: (_) => http.Response(jsonEncode(ficha()), 200),
      );

      await repo.quitarEntidadFiscal(
        empresaId: empresa,
        servicioId: servicioId,
        motivo: 'Se factura al corporativo',
      );

      // EN LA CADENA DE CONSULTA Y NO EN EL CUERPO: un cuerpo en un `DELETE` lo
      // descartan algunos intermediarios, así que el motivo se perdería en el camino.
      expect(pedidas.single.metodo, 'DELETE');
      expect(
        pedidas.single.url.queryParameters['reason'],
        'Se factura al corporativo',
      );
      expect(pedidas.single.cuerpo, isEmpty);
    });

    test('asignar la PRIMERA entidad fiscal no manda motivo', () async {
      final (repo, pedidas) = await repositorio(
        responder: (_) => http.Response(jsonEncode(ficha()), 200),
      );

      await repo.asignarEntidadFiscal(
        empresaId: empresa,
        servicioId: servicioId,
        entidadFiscalId: '0193f0a0-0000-7000-8000-0000000000e1',
      );

      final cuerpo = jsonDecode(pedidas.single.cuerpo) as Map<String, dynamic>;

      // R9 ES CONDICIONAL y lo decide el SERVIDOR leyendo lo que había: la primera
      // asignación no lo pide, así que la pantalla no lo pregunta y el cuerpo no lo
      // lleva.
      expect(cuerpo['id'], '0193f0a0-0000-7000-8000-0000000000e1');
      expect(cuerpo.containsKey('reason'), isFalse);
    });
  });

  group('C2 · los modelos', () {
    test('el logotipo se lee del IDENTIFICADOR y no de hasLogo', () async {
      final sinLogo = ServicioEnLista.deJson(fila());
      final conLogo = ServicioEnLista.deJson(
        fila(logotipo: '0193f0a0-0000-7000-8000-0000000000f1'),
      );

      // UNA SOLA FUENTE: el identificador contesta las dos preguntas —si hay y cuál— y
      // dos campos para lo mismo pueden discrepar.
      expect(sinLogo.clienteTieneLogotipo, isFalse);
      expect(conLogo.clienteTieneLogotipo, isTrue);
      expect(conLogo.clienteLogotipoFileId, '0193f0a0-0000-7000-8000-0000000000f1');
    });

    test('inforce se traduce, y un código desconocido NO se inventa', () {
      expect(CondicionTemporal.deCodigo('inforce'), CondicionTemporal.vigente);
      expect(CondicionTemporal.deCodigo('upcoming'), CondicionTemporal.proxima);
      expect(CondicionTemporal.deCodigo('expired'), CondicionTemporal.vencida);

      // NULO Y NO UNA EXCEPCIÓN NI UN VALOR POR OMISIÓN: un `_ => vigente` enseñaría
      // como vigente algo que el servidor no dijo que lo fuera.
      expect(CondicionTemporal.deCodigo('quoted'), isNull);
      expect(EstatusDeServicio.deCodigo('quoted'), isNull);
    });

    test('el estatus desconocido no rompe la fila entera', () {
      final fantasma = ServicioEnLista.deJson(fila(estatus: 'archivado'));

      // LA FILA SE LEE IGUAL y su estatus queda sin reconocer: una excepción aquí
      // tumbaría el listado completo porque el servidor sea más nuevo que esta build.
      expect(fantasma.nombre, 'Sportium Satélite');
      expect(fantasma.estatus, 'archivado');
      expect(fantasma.estado, isNull);
    });

    test('«Finalizados» es el terminado, y vive en un solo sitio', () {
      expect(EstatusDeServicio.terminado.esFinalizado, isTrue);
      expect(EstatusDeServicio.activo.esFinalizado, isFalse);
      expect(EstatusDeServicio.suspendido.esFinalizado, isFalse);
    });

    test('la antigüedad se redacta, con sus bordes de plural', () {
      String texto(int meses) => IndicadoresDeServicio(
        importeMensual: const [],
        antiguedadEnMeses: meses,
      ).antiguedadEnPantalla;

      // CADA CASO ES UN BORDE, y los dos de «1» son los que más duelen: «1 meses» y
      // «1 años» se le notan a cualquiera que lea la pantalla.
      expect(texto(0), 'Menos de 1 mes');
      expect(texto(1), '1 mes');
      expect(texto(7), '7 meses');
      expect(texto(11), '11 meses');
      expect(texto(12), '1 año');
      expect(texto(13), '1 año, 1 mes');
      expect(texto(24), '2 años');
      expect(texto(30), '2 años, 6 meses');
    });

    test('el importe vacío NO es cero', () {
      final sinCondiciones = IndicadoresDeServicio.deJson({
        'monthlyAmount': <Object?>[],
        'seniorityMonths': 7,
      });

      // VACÍA Y NO UN CERO: un `$0.00` diría que se cobra nada, cuando lo que pasa es
      // que no hay nada contratado. La pantalla lo dice con palabras.
      expect(sinCondiciones.importeMensual, isEmpty);
    });

    test('la ficha distingue la fecha de captura del inicio', () {
      final servicio = Servicio.deJson(ficha());

      // D-58: `createdAt` es cuándo se capturó la fila y `startedOn` cuándo empezó a
      // operar. Son dos cosas, y la ficha las enseña por separado.
      expect(servicio.creadoEn.year, 2026);
      expect(servicio.inicio?.enTexto, '2024-03-01');
    });

    test('el supervisor de baja se reconoce', () {
      final deBaja = SupervisorDelServicio.deJson({
        'employeeId': '0193f0a0-0000-7000-8000-0000000000d1',
        'employeeNumber': 12,
        'fullName': 'Beto Luna Ríos',
        'isActive': false,
      });

      // ES LO QUE SOSTIENE LA INSIGNIA «Baja»: un supervisor que deja de estar activo no
      // se desvincula solo, así que la pantalla tiene que poder decir que ya no está.
      expect(deBaja.nombreCompleto, 'Beto Luna Ríos');
      expect(deBaja.estaActivo, isFalse);
    });
  });
}

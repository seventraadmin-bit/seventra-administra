// El ciclo de vida de la estructura en la web (M3): eliminar, cerrar y reabrir.
//
// La pila es real de arriba abajo menos el transporte, igual que en IF-3: el
// repositorio habla con el `ApiClientAutenticado` de verdad, que pide el token a un
// `GestorDeSesion` de verdad, que se autenticó contra el mismo `MockClient`. Así,
// afirmar sobre la petición que llega al transporte es afirmar sobre lo que saldría por
// el cable.

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
import 'package:riseg_one/features/organizacion/web/datos/areas_repositorio_http.dart';
import 'package:riseg_one/features/organizacion/web/datos/puestos_repositorio_http.dart';
import 'package:riseg_one/features/organizacion/web/datos/sucursales_repositorio_http.dart';
import 'package:riseg_one/features/organizacion/web/modelos/codigo_sugerido.dart';

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
  final config = ApiConfig.resolve(
    raw: 'http://localhost:5199',
  ).when(ok: (c) => c, failure: (f) => throw StateError(f.message));

  final t0 = DateTime.utc(2026, 10, 19, 12);

  const empresa = '0193f0a0-0000-7000-8000-000000000001';
  const areaId = '0193f0a0-0000-7000-8000-0000000000a1';
  const puestoId = '0193f0a0-0000-7000-8000-0000000000p1';
  const sucursalId = '0193f0a0-0000-7000-8000-0000000000b1';
  const tipoId = '0193f0a0-0000-7000-8000-0000000000t1';

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

  Future<({ApiClientAutenticado api, List<http.Request> vistas})> construir(
    Future<http.Response> Function(http.Request) responder,
  ) async {
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
      api: ApiClientAutenticado(cliente: desnudo, gestor: sesion),
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

  String json409(String codigo, String mensaje) =>
      jsonEncode({'code': codigo, 'message': mensaje});

  // =========================================================================
  // 1 · EL CONTRATO DEL BORRADO: verbo, ruta y dónde va el motivo
  // =========================================================================

  group('eliminar', () {
    test('es DELETE a la fila, y el motivo va en el CUERPO, no en la URL', () async {
      // ESTO NO ES ESTILO, ES PRIVACIDAD. Una URL acaba en los registros de acceso,
      // en el historial del navegador y en la barra de direcciones de quien comparte
      // su pantalla; el motivo de un borrado puede nombrar a una persona.
      final (api: api, vistas: vistas) = await construir(
        (_) async => http.Response(
          jsonEncode({
            'id': areaId,
            'code': 'SOBRANTE',
            'name': 'Sobrante',
            'status': 'activa',
          }),
          200,
        ),
      );

      final borrada = exigirOk(
        await AreasRepositorioHttp(api).eliminar(
          empresaId: empresa,
          areaId: areaId,
          motivo: 'Se capturó por error.',
        ),
      );

      expect(borrada.codigo, 'SOBRANTE');

      final peticion = vistas.single;
      expect(peticion.method, 'DELETE');
      expect(peticion.url.path, '/api/v1/companies/$empresa/areas/$areaId');

      // EL MOTIVO NO ESTÁ EN LA URL. Si alguien lo moviera a la cadena de consulta
      // «porque es más cómodo», esta afirmación lo caza.
      expect(peticion.url.query, isEmpty);
      expect(
        jsonDecode(peticion.body),
        {'reason': 'Se capturó por error.'},
      );
    });

    test('las cuatro entidades pegan a su propia ruta', () async {
      final rutas = <String>[];

      // LA RESPUESTA SE AJUSTA A LA ENTIDAD, y no es un detalle del arnés: una
      // sucursal sin `operationalStatus` no se puede leer, y un cuerpo genérico
      // «que valga para los cuatro» haría que esta prueba fallara por el JSON en vez
      // de por la ruta, que es lo que mide.
      final (api: api, vistas: _) = await construir((peticion) async {
        rutas.add('${peticion.method} ${peticion.url.path}');

        final cuerpo = <String, Object?>{
          'id': 'x',
          'code': 'X',
          'name': 'X',
          'status': 'activa',
          if (peticion.url.path.contains('/positions')) ...{
            'areaId': areaId,
            'kind': 'operativo',
          },
          if (peticion.url.path.contains('/branches/')) ...{
            'branchTypeId': tipoId,
            'operationalStatus': 'operando',
          },
        };

        return http.Response(jsonEncode(cuerpo), 200);
      });

      await AreasRepositorioHttp(api).eliminar(
        empresaId: empresa,
        areaId: areaId,
        motivo: 'm',
      );
      await PuestosRepositorioHttp(api).eliminar(
        empresaId: empresa,
        puestoId: puestoId,
        motivo: 'm',
      );
      await SucursalesRepositorioHttp(api).eliminar(
        empresaId: empresa,
        sucursalId: sucursalId,
        motivo: 'm',
      );
      await SucursalesRepositorioHttp(api).eliminarTipo(
        empresaId: empresa,
        tipoId: tipoId,
        motivo: 'm',
      );

      expect(rutas, [
        'DELETE /api/v1/companies/$empresa/areas/$areaId',
        'DELETE /api/v1/companies/$empresa/positions/$puestoId',
        'DELETE /api/v1/companies/$empresa/branches/$sucursalId',
        'DELETE /api/v1/companies/$empresa/branch-types/$tipoId',
      ]);
    });
  });

  // =========================================================================
  // 2 · EL 409 QUE NO ES DEL CÓDIGO — el error que esto vino a cazar
  // =========================================================================

  group('un 409 que NO es código duplicado', () {
    // ESTE GRUPO EXISTE POR UN ERROR REAL QUE ESTUVO A PUNTO DE ENTRAR.
    //
    // Hasta M3 el único 409 que el servidor podía dar en estas rutas era el código
    // duplicado, así que los tres repositorios reescribían **todo** 409 como «ya existe
    // algo con el código X». La 0049 trajo dos 409 más —`estructura_en_uso` y
    // `desactivacion_bloqueada`— y sin tocar nada la pantalla habría dicho «Ya existe
    // un área con el código OPERACIONES» a quien lo que tiene son tres puestos
    // activos dentro: un mensaje que manda a arreglar algo que no está roto.
    //
    // El arreglo fue mirar `code` y no `statusCode`. Estas pruebas lo fijan.

    test('«estructura_en_uso» llega TAL CUAL, con su conteo', () async {
      final (api: api, vistas: _) = await construir(
        (_) async => http.Response(
          json409(
            'estructura_en_uso',
            "No se puede eliminar el área 'Operaciones'. Tiene 3 puesto(s) "
                'registrado(s). Si ya no se usa, desactívala.',
          ),
          409,
        ),
      );

      final fallo = exigirFallo(
        await AreasRepositorioHttp(api).eliminar(
          empresaId: empresa,
          areaId: areaId,
          motivo: 'Ya no la quiero.',
        ),
      );

      expect(fallo, isA<ApiHttpFailure>());
      expect((fallo as ApiHttpFailure).codigo, 'estructura_en_uso');

      // EL CONTEO SOBREVIVE. Es lo que cambia qué hace la persona: a tres puestos los
      // mueve, a doscientos los deja y desactiva.
      expect(fallo.message, contains('3 puesto(s)'));

      // Y NO SE REESCRIBIÓ como choque de código.
      expect(fallo.message, isNot(contains('Ya existe')));
      expect(fallo.message, isNot(contains('no se repiten')));
    });

    test('«desactivacion_bloqueada» tampoco se confunde con el código', () async {
      final (api: api, vistas: _) = await construir(
        (_) async => http.Response(
          json409(
            'desactivacion_bloqueada',
            'No se puede desactivar: 2 persona(s) activa(s) tienen este puesto. '
                'Primero cámbialas a otro puesto.',
          ),
          409,
        ),
      );

      final fallo =
          exigirFallo(
                await PuestosRepositorioHttp(api).modificar(
                  empresaId: empresa,
                  puestoId: puestoId,
                  activo: false,
                ),
              )
              as ApiHttpFailure;

      expect(fallo.codigo, 'desactivacion_bloqueada');
      expect(fallo.message, contains('2 persona(s) activa(s)'));
      expect(fallo.message, isNot(contains('Ya existe')));
    });

    test('y el choque de código SÍ se sigue nombrando con su código', () async {
      // La otra mitad: el arreglo no debía apagar lo que ya funcionaba. El servidor no
      // dice qué código se repitió —no lo sabe desde su respuesta—, así que el
      // repositorio lo añade, y eso es lo único que el usuario puede arreglar solo.
      final (api: api, vistas: _) = await construir(
        (_) async => http.Response(
          json409('code_conflict', "Ya existe un área con el código 'OPS'."),
          409,
        ),
      );

      final fallo =
          exigirFallo(
                await AreasRepositorioHttp(api).crear(
                  empresaId: empresa,
                  codigo: 'OPS',
                  nombre: 'Operaciones',
                ),
              )
              as ApiHttpFailure;

      expect(fallo.codigo, 'code_conflict');
      expect(fallo.message, contains('OPS'));
      expect(fallo.message, contains('no se repiten'));
    });
  });

  // =========================================================================
  // 3 · CERRAR Y REABRIR: dos rutas, sin cuerpo, y fuera del PATCH
  // =========================================================================

  group('cerrar y reabrir', () {
    String sucursalJson(String estadoOperativo, {String status = 'activa'}) =>
        jsonEncode({
          'id': sucursalId,
          'code': 'MATRIZ',
          'name': 'Matriz',
          'status': status,
          'branchTypeId': tipoId,
          'operationalStatus': estadoOperativo,
        });

    test('son POST a sus propias rutas y van SIN cuerpo', () async {
      // SIN CUERPO ES PARTE DEL DISEÑO: el destino lo dice la ruta. Un cuerpo con
      // `operationalStatus` sería otra vez el campo editable que se sacó del PATCH,
      // con otro nombre.
      final (api: api, vistas: vistas) = await construir(
        (peticion) async => http.Response(
          sucursalJson(
            peticion.url.path.endsWith('/reopen')
                ? 'operando'
                : 'cerrada_temporalmente',
          ),
          200,
        ),
      );

      final repo = SucursalesRepositorioHttp(api);

      final cerrada = exigirOk(
        await repo.cerrarTemporalmente(
          empresaId: empresa,
          sucursalId: sucursalId,
        ),
      );

      expect(cerrada.estadoOperativo, 'cerrada_temporalmente');

      // `status` INTACTO: cerrar no da de baja.
      expect(cerrada.activa, isTrue);

      final reabierta = exigirOk(
        await repo.reabrir(empresaId: empresa, sucursalId: sucursalId),
      );

      expect(reabierta.estadoOperativo, 'operando');

      expect(vistas.map((p) => '${p.method} ${p.url.path}'), [
        'POST /api/v1/companies/$empresa/branches/$sucursalId/close-temporarily',
        'POST /api/v1/companies/$empresa/branches/$sucursalId/reopen',
      ]);

      expect(vistas.every((p) => p.body.isEmpty), isTrue);
    });

    test('el PATCH manda SÓLO el estado: ni nombre, ni tipo, ni operationalStatus',
        () async {
      // DOS CAMBIOS DE CONTRATO, los dos invisibles desde el código de respuesta:
      //
      //  · M3 sacó `operationalStatus` —cerrar es una acción, no un campo—;
      //  · el 21 de octubre de 2026 salieron `name` y `branchTypeId`, que se guardan
      //    ahora en el `PUT` del expediente, en una sola transacción con la dirección
      //    y el horario.
      //
      // ⚠️ ESTA PRUEBA EXIGÍA `name` EN EL CUERPO —`containsAll(['name', 'status'])`—
      // y era correcta cuando se escribió. Se reescribe porque el contrato cambió: lo
      // que no se puede dejar es una prueba verde exigiendo un campo que el servidor
      // ya rechaza con un 400.
      final (api: api, vistas: vistas) = await construir(
        (_) async => http.Response(sucursalJson('operando'), 200),
      );

      await SucursalesRepositorioHttp(api).cambiarEstado(
        empresaId: empresa,
        sucursalId: sucursalId,
        activa: false,
      );

      final cuerpo = jsonDecode(vistas.single.body) as Map<String, dynamic>;

      // EL CUERPO ENTERO ES UNA SOLA CLAVE. Se afirma por su contenido y no por su
      // tamaño: `status` tiene que estar y valer lo que se pidió, y las tres que se
      // retiraron no pueden estar.
      expect(cuerpo['status'], 'inactiva');
      expect(cuerpo.containsKey('name'), isFalse);
      expect(cuerpo.containsKey('branchTypeId'), isFalse);
      expect(cuerpo.containsKey('operationalStatus'), isFalse);
    });

    test('el rechazo de reabrir una inactiva llega con su motivo', () async {
      final (api: api, vistas: _) = await construir(
        (_) async => http.Response(
          json409(
            'desactivacion_bloqueada',
            'No se puede reabrir una sucursal inactiva. Reactívala primero.',
          ),
          409,
        ),
      );

      final fallo = exigirFallo(
        await SucursalesRepositorioHttp(
          api,
        ).reabrir(empresaId: empresa, sucursalId: sucursalId),
      );

      // SE MUESTRA EL MOTIVO, y la pantalla no esconde el botón por esto: esconderlo
      // dejaría a la persona sin saber qué le falta.
      expect(fallo.message, contains('Reactívala primero'));
    });
  });

  // =========================================================================
  // 4 · LOS CÓDIGOS SUGERIDOS: ARE, PUE y SUC
  // =========================================================================

  group('siguienteCodigo', () {
    test('cada prefijo arranca en 0001 cuando no hay nada', () {
      expect(siguienteCodigo(PrefijoDeCodigo.area, const []), 'ARE-0001');
      expect(siguienteCodigo(PrefijoDeCodigo.puesto, const []), 'PUE-0001');
      expect(siguienteCodigo(PrefijoDeCodigo.sucursal, const []), 'SUC-0001');
    });

    test('es el MÁXIMO más uno, no el primer hueco', () {
      // Rellenar el hueco reutilizaría un número que alguien pudo imprimir, decir por
      // teléfono o meter en una hoja de cálculo.
      expect(
        siguienteCodigo(PrefijoDeCodigo.area, const ['ARE-0001', 'ARE-0003']),
        'ARE-0004',
      );
    });

    test('el prefijo de OTRO catálogo no cuenta', () {
      // Es lo que un generador compartido podría estropear fácilmente: un `PUE-0007`
      // no debe empujar la siguiente área a `ARE-0008`.
      expect(
        siguienteCodigo(PrefijoDeCodigo.area, const [
          'PUE-0007',
          'SUC-0009',
          'ARE-0002',
        ]),
        'ARE-0003',
      );
    });

    test('los códigos escritos a mano se ignoran y no frenan la sugerencia', () {
      // El campo es editable: alguien pudo escribir `MATRIZ` en vez de `SUC-0001`.
      expect(
        siguienteCodigo(PrefijoDeCodigo.sucursal, const [
          'MATRIZ',
          'NORTE',
          'SUC-0002',
        ]),
        'SUC-0003',
      );

      expect(
        siguienteCodigo(PrefijoDeCodigo.sucursal, const ['MATRIZ', 'NORTE']),
        'SUC-0001',
      );
    });

    test('pasado el 9999 crece a cinco dígitos en vez de volver a empezar', () {
      // Un código repetido es peor que uno largo.
      expect(
        siguienteCodigo(PrefijoDeCodigo.area, const ['ARE-9999']),
        'ARE-10000',
      );

      // Y LA COMPARACIÓN ES NUMÉRICA, NO DE TEXTO: por texto, `ARE-10000` quedaría
      // antes de `ARE-9999` y la sugerencia retrocedería.
      expect(
        siguienteCodigo(PrefijoDeCodigo.area, const ['ARE-9999', 'ARE-10000']),
        'ARE-10001',
      );
    });

    test('tolera minúsculas y espacios de sobra', () {
      expect(
        siguienteCodigo(PrefijoDeCodigo.puesto, const ['  pue-0004 ']),
        'PUE-0005',
      );
    });
  });

  // =========================================================================
  // 5 · EL REINTENTO: la contra de sugerir desde el cliente, resuelta
  // =========================================================================

  group('ayudaDelCodigo', () {
    // LOS TRES TEXTOS YA DIVERGIERON una vez: Áreas decía «Sugerido…», Sucursales
    // «Corto y en mayúsculas, como CEN» —de antes de que existiera la sugerencia— y
    // Puestos «Se sugiere automáticamente». Tres pantallas que hacen lo mismo
    // explicándolo de tres formas enseñan que no hacen lo mismo.
    //
    // Esto fija que sea UNA sola función, así que no pueden volver a divergir sin que
    // se vea aquí.

    test('el texto es el MISMO para las tres, salvo qué identifica', () {
      final textos = <String>[
        for (final queEs in ['al área', 'a la sucursal', 'al puesto'])
          ayudaDelCodigo(esNuevo: true, haySugerencia: true, queEs: queEs),
      ];

      // Al crear no se nombra la entidad, así que los tres son idénticos.
      expect(textos.toSet(), hasLength(1));
      expect(textos.first, contains('Sugerido'));

      // Y DICE QUE DESPUÉS NO SE PODRÁ CAMBIAR, que era lo más útil de los tres textos
      // viejos y sólo lo tenía Puestos.
      expect(textos.first, contains('no se podrá cambiar'));
    });

    test('sin sugerencia NO dice «sugerido», y explica por qué', () {
      // Si la lista no se pudo leer, el campo llega VACÍO: decir «sugerido» ahí sería
      // mentir sobre un campo vacío.
      final texto = ayudaDelCodigo(
        esNuevo: true,
        haySugerencia: false,
        queEs: 'al área',
      );

      expect(texto, isNot(contains('Sugerido')));
      expect(texto, contains('no se pudo leer la lista'));
      expect(texto, contains('no se podrá cambiar'));
    });

    test('al editar dice que no se cambia, y QUÉ identifica', () {
      expect(
        ayudaDelCodigo(esNuevo: false, haySugerencia: true, queEs: 'a la sucursal'),
        'El código no se cambia: identifica a la sucursal.',
      );
    });
  });

  group('crearConReintentoDeCodigo', () {
    // La sugerencia la calcula el cliente, así que dos personas creando a la vez
    // reciben el mismo número y la segunda recibe un 409 por algo que no escribió.
    // Esto es lo que lo arregla, y estas pruebas fijan sus cuatro límites.

    Result<String> choque() => const Result.failure(
      ApiHttpFailure(
        statusCode: 409,
        message: 'Ya existe.',
        codigo: 'code_conflict',
      ),
    );

    test('reintenta UNA vez con el código recalculado', () async {
      final intentos = <String>[];

      final resultado = await crearConReintentoDeCodigo<String>(
        prefijo: PrefijoDeCodigo.area,
        codigoUsado: 'ARE-0002',
        codigoSugerido: 'ARE-0002',
        crear: (c) async {
          intentos.add(c);
          // El primero choca —alguien se adelantó—, el segundo entra.
          return intentos.length == 1 ? choque() : Result.ok('creada con $c');
        },
        // La relectura ya ve el `ARE-0002` del otro.
        codigosActuales: () async =>
            const Result.ok(['ARE-0001', 'ARE-0002']),
      );

      expect(intentos, ['ARE-0002', 'ARE-0003']);
      expect(resultado.when(ok: (v) => v, failure: (f) => f.message), 'creada con ARE-0003');
    });

    test('NO reintenta si el código lo escribió la persona', () async {
      // Cambiarle el código por su cuenta sería crear una fila distinta de la que
      // pidió. El reintento arregla un problema de la máquina, no una decisión.
      final intentos = <String>[];

      final resultado = await crearConReintentoDeCodigo<String>(
        prefijo: PrefijoDeCodigo.area,
        codigoUsado: 'OPERACIONES',
        codigoSugerido: 'ARE-0002',
        crear: (c) async {
          intentos.add(c);
          return choque();
        },
        codigosActuales: () async => fail('no debió releer la lista'),
      );

      expect(intentos, ['OPERACIONES']);
      expect(
        resultado.when(ok: (_) => null, failure: (f) => (f as ApiHttpFailure).codigo),
        'code_conflict',
      );
    });

    test('NO reintenta un 409 que no sea choque de código', () async {
      final intentos = <String>[];

      await crearConReintentoDeCodigo<String>(
        prefijo: PrefijoDeCodigo.area,
        codigoUsado: 'ARE-0002',
        codigoSugerido: 'ARE-0002',
        crear: (c) async {
          intentos.add(c);
          return const Result.failure(
            ApiHttpFailure(
              statusCode: 409,
              message: 'Tiene 3 puesto(s).',
              codigo: 'estructura_en_uso',
            ),
          );
        },
        codigosActuales: () async => fail('no debió releer la lista'),
      );

      expect(intentos, ['ARE-0002']);
    });

    test('si la relectura falla, devuelve el CHOQUE y no el fallo de red', () async {
      // Lo que la persona necesita saber es que el código chocó, no que el segundo
      // intento de leer la lista se cayó: lo primero es accionable y lo segundo no.
      final resultado = await crearConReintentoDeCodigo<String>(
        prefijo: PrefijoDeCodigo.area,
        codigoUsado: 'ARE-0002',
        codigoSugerido: 'ARE-0002',
        crear: (_) async => choque(),
        codigosActuales: () async =>
            const Result.failure(ApiSinConexionFailure('Sin red.')),
      );

      expect(
        resultado.when(ok: (_) => null, failure: (f) => (f as ApiHttpFailure).codigo),
        'code_conflict',
      );
    });

    test('no reintenta con el MISMO código: sería otro 409 seguro', () async {
      // Si la relectura propone lo mismo, el choque no era una carrera —alguien tiene
      // ese código escrito de una forma que el patrón no reconoce—, y repetirlo
      // gastaría otro viaje para el mismo error.
      final intentos = <String>[];

      await crearConReintentoDeCodigo<String>(
        prefijo: PrefijoDeCodigo.area,
        codigoUsado: 'ARE-0002',
        codigoSugerido: 'ARE-0002',
        crear: (c) async {
          intentos.add(c);
          return choque();
        },
        // La lista no cambió, así que el consecutivo vuelve a dar ARE-0002.
        codigosActuales: () async => const Result.ok(['ARE-0001']),
      );

      expect(intentos, ['ARE-0002']);
    });
  });
}

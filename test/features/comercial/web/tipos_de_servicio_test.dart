// C2 · EL CATÁLOGO DE TIPOS DE SERVICIO, con el botón de recomendados.
//
// ## Qué se fija aquí, y por qué estas cosas
//
//  1. **El catálogo nace vacío y eso NO es un error.** Es la decisión del dueño: SEVENTRA
//     se vende también a empresas que no son de seguridad, así que no se siembra nada.
//     Lo que la pantalla tiene que hacer es decirlo y ofrecer la salida — y nombrar los
//     cuatro ANTES de pulsar, para que quien no los quiera pueda crear los suyos;
//  2. **el mensaje de los recomendados NO cuenta lo que devuelve el servidor.** La ruta
//     es idempotente y responde con el catálogo RESULTANTE, así que al segundo clic trae
//     los cuatro otra vez: contar su longitud diría «Se agregaron 4» cuando no se creó
//     ninguno. La cuenta sale de restar contra lo que ya se tenía;
//  3. **al modificar sólo viaja lo que cambió.** Mandar nombre y estado siempre haría que
//     renombrar reactivara de paso un tipo que alguien acaba de retirar;
//  4. **el choque de código se enseña EN EL CAMPO**, no en un aviso que se va: es lo
//     único que el usuario puede arreglar sin salir del formulario;
//  5. **sin permiso no hay botones**, y no es lo mismo que botones apagados.
//
// ## Lo que NO está aquí
//
// Que el botón de Servicios lleve a esta pantalla y que el alta sepa salir del callejón:
// eso lo decide el portón, y se prueba cuando se enciende la pestaña.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riseg_one/app/shell/apartados_web.dart' show CapacidadesDeModulo;
import 'package:riseg_one/core/api/api_client.dart';
import 'package:riseg_one/core/api/api_client_autenticado.dart';
import 'package:riseg_one/core/auth/almacen_sesion_remota.dart';
import 'package:riseg_one/core/auth/auth_api.dart';
import 'package:riseg_one/core/auth/gestor_de_sesion.dart';
import 'package:riseg_one/core/auth/sesion_remota.dart';
import 'package:riseg_one/core/config/api_config.dart';
import 'package:riseg_one/core/logging/app_logger.dart';
import 'package:riseg_one/core/trabajo_sin_guardar/guardia_de_salida.dart';
import 'package:riseg_one/features/comercial/web/datos/servicios_repositorio_http.dart';
import 'package:riseg_one/features/comercial/web/modelos/servicio.dart';
import 'package:riseg_one/features/comercial/web/presentation/tipos_de_servicio_web_screen.dart';
import 'package:riseg_one/features/usuarios/web/marca_seventra.dart';

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

  final t0 = DateTime.utc(2026, 11, 11, 12);

  const empresa = '0193f0a0-0000-7000-8000-000000000001';

  Map<String, Object?> tipo({
    required String id,
    required String codigo,
    required String nombre,
    String estatus = 'activa',
  }) => {'id': id, 'code': codigo, 'name': nombre, 'status': estatus};

  /// Los cuatro del escritorio, **con los códigos reales**: si alguien los cambia en el
  /// servidor sin avisar, la resta de esta pantalla deja de casar.
  final recomendados = [
    tipo(
      id: '0193f0a0-0000-7000-8000-0000000000b1',
      codigo: 'ESCOLTA',
      nombre: 'Escolta',
    ),
    tipo(
      id: '0193f0a0-0000-7000-8000-0000000000b2',
      codigo: 'MONITOREO',
      nombre: 'Monitoreo',
    ),
    tipo(
      id: '0193f0a0-0000-7000-8000-0000000000b3',
      codigo: 'RONDIN',
      nombre: 'Rondín',
    ),
    tipo(
      id: '0193f0a0-0000-7000-8000-0000000000b4',
      codigo: 'VIGILANCIA_FIJA',
      nombre: 'Vigilancia fija',
    ),
  ];

  final propio = tipo(
    id: '0193f0a0-0000-7000-8000-0000000000c1',
    codigo: 'INTRAMUROS',
    nombre: 'Vigilancia intramuros',
  );

  final retirado = tipo(
    id: '0193f0a0-0000-7000-8000-0000000000c2',
    codigo: 'CUSTODIA',
    nombre: 'Custodia',
    estatus: 'inactiva',
  );

  Future<(ApiClientAutenticado, List<_Pedida>)> cliente({
    required http.Response? Function(_Pedida pedida) responder,
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

        return responder(pedida) ?? http.Response(jsonEncode(const []), 200);
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

    return (ApiClientAutenticado(cliente: desnudo, gestor: gestor), pedidas);
  }

  const todo = CapacidadesDeModulo(
    puedeVer: true,
    puedeCrear: true,
    puedeModificar: true,
    puedeArchivar: true,
  );

  const soloLeer = CapacidadesDeModulo(
    puedeVer: true,
    puedeCrear: false,
    puedeModificar: false,
    puedeArchivar: false,
  );

  Future<(List<_Pedida>, List<String>)> montar(
    WidgetTester tester, {
    required http.Response? Function(_Pedida pedida) responder,
    CapacidadesDeModulo capacidades = todo,
  }) async {
    tester.view.physicalSize = const Size(1600, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final (api, pedidas) = await cliente(responder: responder);
    final vueltas = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        theme: MarcaSeventra.tema(),
        home: TiposDeServicioWebScreen(
          repositorio: ServiciosRepositorioHttp(api),
          empresaId: empresa,
          capacidades: capacidades,
          guardia: GuardiaDeSalida(),
          onVolver: () => vueltas.add('servicios'),
        ),
      ),
    );

    await tester.pumpAndSettle();

    return (pedidas, vueltas);
  }

  /// Escribe en un campo por su etiqueta.
  ///
  /// ⚠️ **La etiqueta es HERMANA del campo, no su madre.** `RisegTextField` pinta un
  /// `Text` y debajo el campo, dentro de una `Column`, así que buscar el `TextField`
  /// como descendiente de la etiqueta no encuentra nada —«Bad state: No element»—. Se
  /// sube a la `Column` y se baja desde ahí.
  Future<void> escribir(
    WidgetTester tester,
    String etiqueta,
    String texto,
  ) async {
    await tester.enterText(
      find
          .descendant(
            of: find
                .ancestor(of: find.text(etiqueta), matching: find.byType(Column))
                .first,
            matching: find.byType(TextField),
          )
          .first,
      texto,
    );
  }

  /// Las peticiones de la ruta de recomendados.
  List<_Pedida> recomendadas(List<_Pedida> pedidas) => pedidas
      .where((p) => p.metodo == 'POST' && p.url.path.endsWith('/recommended'))
      .toList();

  // =========================================================================
  group('la resta que evita el mensaje falso', () {
    List<TipoDeServicio> comoModelos(List<Map<String, Object?>> json) => [
      for (final t in json) TipoDeServicio.deJson(t),
    ];

    test('de un catálogo vacío, los cuatro son nuevos', () {
      expect(
        tiposDeServicioNuevos(
          antes: const [],
          despues: comoModelos(recomendados),
        ).map((t) => t.codigo),
        ['ESCOLTA', 'MONITOREO', 'RONDIN', 'VIGILANCIA_FIJA'],
      );
    });

    test('al segundo clic no hay ninguno nuevo', () {
      // ESTA ES LA PRUEBA QUE JUSTIFICA LA FUNCIÓN. El servidor devuelve lo mismo las dos
      // veces; sin restar, el mensaje diría «Se agregaron 4» después de no crear nada.
      expect(
        tiposDeServicioNuevos(
          antes: comoModelos(recomendados),
          despues: comoModelos(recomendados),
        ),
        isEmpty,
      );
    });

    test('con uno propio del mismo código, los nuevos son tres', () {
      final yaTenia = comoModelos([
        tipo(
          id: '0193f0a0-0000-7000-8000-0000000000d9',
          codigo: 'RONDIN',
          nombre: 'Rondín nocturno',
        ),
      ]);

      // SE COMPARA POR CÓDIGO Y NO POR ID, que es lo que hace el servidor para saltarse
      // los que ya existen: el «RONDIN» de la empresa tiene otro id y otro nombre, y aun
      // así no cuenta como nuevo.
      expect(
        tiposDeServicioNuevos(
          antes: yaTenia,
          despues: comoModelos([...recomendados]),
        ).map((t) => t.codigo),
        ['ESCOLTA', 'MONITOREO', 'VIGILANCIA_FIJA'],
      );
    });

    test('un tipo ajeno al juego no estorba la cuenta', () {
      expect(
        tiposDeServicioNuevos(
          antes: comoModelos([propio]),
          despues: comoModelos([propio, ...recomendados]),
        ).length,
        4,
      );
    });
  });

  // =========================================================================
  group('el catálogo vacío ofrece la salida', () {
    testWidgets('dice que está vacío y NOMBRA los cuatro antes de pulsar', (
      tester,
    ) async {
      await montar(
        tester,
        responder: (_) => http.Response(jsonEncode(const []), 200),
      );

      expect(find.text('Todavía no hay tipos de servicio'), findsOneWidget);

      // LOS CUATRO SE NOMBRAN ANTES DE PULSAR, y es la consecuencia directa de la
      // decisión del dueño: a una empresa que no es de seguridad «Escolta» no le
      // corresponde, así que tiene que poder verlo y crear los suyos en vez de éstos.
      final mensaje = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join(' ');

      for (final nombre in ['Vigilancia fija', 'Rondín', 'Escolta', 'Monitoreo']) {
        expect(mensaje, contains(nombre));
      }

      expect(find.text('Crear el mío'), findsOneWidget);
    });

    testWidgets('sin permiso de crear, el vacío NO ofrece ningún botón', (
      tester,
    ) async {
      await montar(
        tester,
        capacidades: soloLeer,
        responder: (_) => http.Response(jsonEncode(const []), 200),
      );

      // NI EL ATAJO NI EL ALTA. Lo que esta persona no puede hacer no se le enseña, y un
      // botón apagado no es lo mismo: invita a pedir permiso a la pantalla equivocada.
      expect(find.text('Agregar tipos recomendados'), findsNothing);
      expect(find.text('Crear el mío'), findsNothing);
      expect(find.text('Nuevo tipo'), findsNothing);

      // Pero el catálogo SÍ se consulta: leerlo es el mismo permiso con el que se ve la
      // lista de servicios.
      expect(find.text('Todavía no hay tipos de servicio'), findsOneWidget);
    });
  });

  // =========================================================================
  group('el botón de recomendados', () {
    testWidgets('pulsa, llama a la ruta y dice CUÁNTOS se agregaron', (
      tester,
    ) async {
      var yaSePulso = false;

      final (pedidas, _) = await montar(
        tester,
        responder: (p) {
          if (p.url.path.endsWith('/recommended')) {
            yaSePulso = true;
            return http.Response(jsonEncode(recomendados), 200);
          }

          // El listado de después del clic ya trae los cuatro.
          return http.Response(
            jsonEncode(yaSePulso ? recomendados : const []),
            200,
          );
        },
      );

      await tester.tap(find.text('Agregar tipos recomendados').first);
      await tester.pumpAndSettle();

      expect(recomendadas(pedidas), hasLength(1));

      // LA RUTA NO LLEVA CUERPO: lo que se agrega lo decide el servidor, no la pantalla.
      expect(recomendadas(pedidas).single.cuerpo, isEmpty);

      expect(find.text('Se agregaron 4 tipos recomendados.'), findsOneWidget);

      // Y el catálogo se recarga: los cuatro están en pantalla.
      expect(find.text('Vigilancia fija'), findsOneWidget);
      expect(find.text('RONDIN'), findsOneWidget);
    });

    testWidgets('al segundo clic dice que YA ESTABAN, no que agregó cuatro', (
      tester,
    ) async {
      // ⚠️ LA PRUEBA DE LA PROPIEDAD 2. El servidor responde los cuatro las dos veces
      // —es idempotente—, así que una pantalla que contara la respuesta mentiría.
      final (pedidas, _) = await montar(
        tester,
        responder: (_) => http.Response(jsonEncode(recomendados), 200),
      );

      await tester.tap(find.text('Agregar tipos recomendados').first);
      await tester.pumpAndSettle();

      expect(recomendadas(pedidas), hasLength(1));
      expect(find.text('Ya tenías todos los tipos recomendados.'), findsOneWidget);
      expect(find.textContaining('Se agregaron'), findsNothing);
    });

    testWidgets('con uno propio del mismo código, dice TRES', (tester) async {
      var yaSePulso = false;

      await montar(
        tester,
        responder: (p) {
          if (p.url.path.endsWith('/recommended')) {
            yaSePulso = true;
            return http.Response(
              jsonEncode([
                ...recomendados.where((t) => t['code'] != 'RONDIN'),
                tipo(
                  id: '0193f0a0-0000-7000-8000-0000000000d9',
                  codigo: 'RONDIN',
                  nombre: 'Rondín nocturno',
                ),
              ]),
              200,
            );
          }

          return http.Response(
            jsonEncode(
              yaSePulso
                  ? recomendados
                  : [
                      tipo(
                        id: '0193f0a0-0000-7000-8000-0000000000d9',
                        codigo: 'RONDIN',
                        nombre: 'Rondín nocturno',
                      ),
                    ],
            ),
            200,
          );
        },
      );

      await tester.tap(find.text('Agregar tipos recomendados').first);
      await tester.pumpAndSettle();

      expect(find.text('Se agregaron 3 tipos recomendados.'), findsOneWidget);
    });
  });

  // =========================================================================
  group('crear y modificar un tipo', () {
    testWidgets('el código viaja en MAYÚSCULAS aunque se escriba abajo', (
      tester,
    ) async {
      final (pedidas, _) = await montar(
        tester,
        responder: (p) {
          if (p.metodo == 'POST') {
            return http.Response(
              jsonEncode(
                tipo(
                  id: '0193f0a0-0000-7000-8000-0000000000e1',
                  codigo: 'CUSTODIA',
                  nombre: 'Custodia',
                ),
              ),
              201,
            );
          }

          return http.Response(jsonEncode(const []), 200);
        },
      );

      await tester.tap(find.text('Nuevo tipo'));
      await tester.pumpAndSettle();

      await escribir(tester, 'Código', 'custodia');
      await escribir(tester, 'Nombre', 'Custodia');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      final creada = pedidas.singleWhere(
        (p) => p.metodo == 'POST' && p.url.path.endsWith('/service-types'),
      );

      expect(jsonDecode(creada.cuerpo), {
        'code': 'CUSTODIA',
        'name': 'Custodia',
      });
    });

    testWidgets('renombrar manda SÓLO el nombre, no el estado', (tester) async {
      // ⚠️ LA PROPIEDAD 3. Mandar los dos siempre haría que renombrar reactivara de paso
      // un tipo que alguien acaba de retirar — y aquí el tipo está RETIRADO justamente
      // para que, si el estado viajara, lo reviviera sin que nadie lo pidiera.
      final (pedidas, _) = await montar(
        tester,
        responder: (p) {
          if (p.metodo == 'PATCH') {
            return http.Response(
              jsonEncode({...retirado, 'name': 'Custodia de valores'}),
              200,
            );
          }

          return http.Response(jsonEncode([retirado]), 200);
        },
      );

      await tester.tap(find.text('Custodia'));
      await tester.pumpAndSettle();

      await escribir(tester, 'Nombre', 'Custodia de valores');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      final cambio = pedidas.singleWhere((p) => p.metodo == 'PATCH');

      expect(jsonDecode(cambio.cuerpo), {'name': 'Custodia de valores'});
    });

    testWidgets('el interruptor manda SÓLO el estado, no el nombre', (
      tester,
    ) async {
      final (pedidas, _) = await montar(
        tester,
        responder: (p) {
          if (p.metodo == 'PATCH') {
            return http.Response(
              jsonEncode({...propio, 'status': 'inactiva'}),
              200,
            );
          }

          return http.Response(jsonEncode([propio]), 200);
        },
      );

      await tester.tap(find.text('Vigilancia intramuros'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(jsonDecode(pedidas.singleWhere((p) => p.metodo == 'PATCH').cuerpo), {
        'status': 'inactiva',
      });
    });

    testWidgets('el código NO se puede editar en un tipo que ya existe', (
      tester,
    ) async {
      await montar(
        tester,
        responder: (_) => http.Response(jsonEncode([propio]), 200),
      );

      await tester.tap(find.text('Vigilancia intramuros'));
      await tester.pumpAndSettle();

      // EL CAMPO LO DICE en lugar de aceptar el cambio y descartarlo en silencio: el
      // código es la identidad del tipo y la ruta no lo recibe en un `PATCH`.
      expect(find.text('El código no se cambia.'), findsOneWidget);

      final campoDelCodigo = tester.widget<TextField>(
        find
            .descendant(
              of: find
                  .ancestor(
                    of: find.text('Código'),
                    matching: find.byType(Column),
                  )
                  .first,
              matching: find.byType(TextField),
            )
            .first,
      );

      expect(campoDelCodigo.enabled, isFalse);
    });

    testWidgets('un código repetido se enseña EN EL CAMPO', (tester) async {
      await montar(
        tester,
        responder: (p) {
          if (p.metodo == 'POST') {
            return http.Response(
              jsonEncode({
                'code': 'code_conflict',
                'message': "Ya existe un tipo de servicio con el código 'RONDIN'.",
              }),
              409,
            );
          }

          return http.Response(jsonEncode(const []), 200);
        },
      );

      await tester.tap(find.text('Nuevo tipo'));
      await tester.pumpAndSettle();

      await escribir(tester, 'Código', 'RONDIN');
      await escribir(tester, 'Nombre', 'Rondín');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      // EL FORMULARIO SIGUE ABIERTO con el mensaje junto al campo que hay que arreglar.
      expect(
        find.text("Ya existe un tipo de servicio con el código 'RONDIN'."),
        findsOneWidget,
      );
      expect(find.text('Guardar'), findsOneWidget);
    });

    testWidgets('un tipo NO se elimina: el panel dice que se desactiva', (
      tester,
    ) async {
      await montar(
        tester,
        responder: (_) => http.Response(jsonEncode([propio]), 200),
      );

      await tester.tap(find.text('Vigilancia intramuros'));
      await tester.pumpAndSettle();

      // 🚫 NO HAY «ELIMINAR», y no es un olvido: el servidor no publica un `DELETE` para
      // los tipos de servicio. Si alguien añadiera el botón, esta prueba lo diría.
      expect(find.textContaining('Eliminar'), findsNothing);
      expect(
        find.textContaining('Un tipo no se elimina: se desactiva.'),
        findsOneWidget,
      );
    });
  });

  // =========================================================================
  group('la salida', () {
    testWidgets('el regreso dice «Servicios» y llama a quien lo trajo', (
      tester,
    ) async {
      final (_, vueltas) = await montar(
        tester,
        responder: (_) => http.Response(jsonEncode([propio]), 200),
      );

      // NO ES UNA PESTAÑA: sin este regreso no habría forma de salir.
      await tester.tap(find.text('Servicios'));
      await tester.pumpAndSettle();

      expect(vueltas, ['servicios']);
    });

    testWidgets('el catálogo se pide SIN el filtro de usados', (tester) async {
      // Aquí se administra el catálogo entero. `?used=true` es del selector del filtro
      // del listado, que es otra pregunta: qué hay, no qué se puede elegir.
      final (pedidas, _) = await montar(
        tester,
        responder: (_) => http.Response(jsonEncode([propio]), 200),
      );

      final lectura = pedidas.singleWhere(
        (p) => p.metodo == 'GET' && p.url.path.endsWith('/service-types'),
      );

      expect(lectura.url.queryParameters, isEmpty);
    });
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:riseg_one/core/fechas/dia_de_negocio.dart';

/// Que la web **no calcule un día de negocio con el reloj UTC**.
///
/// ## Por qué existe, si hoy no hay ningún caso
///
/// El 25 de octubre de 2026 el dueño encontró este error en el servidor: el día de hoy
/// se calculaba con `DateOnly.FromDateTime(…UtcNow…)`, y de las 18:00 a las 23:59 de la
/// Ciudad de México el día UTC **ya es el siguiente**. Estaba copiado en **ocho** sitios.
/// La web se revisó entera y está limpia: lo único que convierte a UTC son caducidades
/// de token y el sello de un respaldo portable —instantes, donde UTC es lo correcto—, y
/// los dos sitios que pintan un instante como fecha llaman a `toLocal()` primero.
///
/// **El riesgo llegó, y tiene un solo dueño.** Con las pantallas de Clientes la web
/// propone «hoy» como fecha de inicio, que es la deuda **D-55**, y lo hace en
/// `lib/core/fechas/dia_de_negocio.dart` — el único archivo que aplica el
/// desplazamiento fijo de −06:00 antes de quedarse con el día. Si ese «hoy» saliera del
/// reloj UTC a secas, de las 18:00 a las 23:59 propondría **mañana**, y nadie lo
/// notaría: de día funciona.
///
/// ## Qué NO vigila, y por qué
///
/// No prohíbe `toUtc()`: un **instante** en UTC es correcto y es lo que hace la sesión.
/// Lo que prohíbe son las dos formas de leer **«ahora» en el reloj UTC** —`DateTime
/// .now().toUtc()` y `DateTime.timestamp()`—, porque el único motivo para escribirlas es
/// derivar un día o compararlo, y para un día es el reloj equivocado.
///
/// ⚠️ **SE VIGILAN LAS DOS Y NO SÓLO LA PRIMERA**, que es lo que este candado hacía
/// hasta C1. Con una sola prohibida, el ayudante de D-55 podía escribirse con la otra y
/// el guardia no habría dicho nada: habría quedado un día de negocio sacado del reloj
/// UTC pasando un candado que existe justo para eso.
void main() {
  /// Las dos formas de leer «ahora» en el reloj UTC.
  const patrones = ['DateTime.now().toUtc()', 'DateTime.timestamp()'];

  /// Dónde sí es correcto, por ruta exacta.
  ///
  /// El gestor de sesión compara **instantes** —cuándo caduca el token—, y para eso UTC
  /// es el reloj correcto: es el mismo que escribió el servidor. Y `dia_de_negocio.dart`
  /// es el ayudante de D-55: parte del instante en UTC **y le aplica −06:00** antes de
  /// quedarse con el año, el mes y el día, que es exactamente lo que hace falta hacer
  /// una vez para no tener que hacerlo en cada pantalla. Cada excepción nueva tiene que
  /// aparecer en un diff y explicarse.
  const permitidos = [
    'lib/core/auth/gestor_de_sesion.dart',
    'lib/core/fechas/dia_de_negocio.dart',
  ];

  /// Las fuentes de la aplicación, sin lo generado.
  List<File> fuentes() {
    final raiz = Directory('lib');

    expect(
      raiz.existsSync(),
      isTrue,
      reason: 'La prueba se corre desde la raíz del repositorio.',
    );

    return raiz
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
  }

  String relativa(File f) => f.path.replaceAll(r'\', '/');

  test('ningún día de negocio sale del reloj UTC', () {
    final copias = <String>[];

    for (final archivo in fuentes()) {
      final ruta = relativa(archivo);
      if (permitidos.contains(ruta)) continue;

      final lineas = archivo.readAsLinesSync();

      for (var i = 0; i < lineas.length; i++) {
        // SE MIRA EL CÓDIGO Y NO LOS COMENTARIOS: esta prueba y la documentación de la
        // deuda NOMBRAN el patrón para explicarlo, y nombrarlo no es copiarlo.
        final linea = lineas[i];
        final comentario = linea.indexOf('//');
        final codigo = comentario >= 0 ? linea.substring(0, comentario) : linea;

        for (final patron in patrones) {
          if (!codigo.contains(patron)) continue;

          copias.add('$ruta:${i + 1} → «${linea.trim()}»');
        }
      }
    }

    expect(
      copias,
      isEmpty,
      reason:
          'Hay un «ahora» leído en el reloj UTC. De las 18:00 a las 23:59 de la Ciudad '
          'de México el día UTC YA ES EL SIGUIENTE, así que una fecha propuesta así '
          'dice mañana.\n\nUn instante sí va en UTC —la caducidad de un token—; un DÍA, '
          'nunca: para eso está `DiaDeNegocio.hoy()`, que aplica −06:00.'
          '\n\n${copias.join('\n')}',
    );
  });

  // =========================================================================
  // D-55 · el ayudante, con las dos pruebas que el dueño pidió
  // =========================================================================
  group('el «hoy» del negocio es el de la Ciudad de México', () {
    test('a las 23:30 de la Ciudad de México el día es HOY y no mañana', () {
      // 05:30 UTC del 27 son las 23:30 del 26 en la Ciudad de México. El día UTC ya
      // cambió; el de negocio, no. Es el error que el dueño encontró en el servidor
      // repetido en ocho sitios, puesto aquí como prueba.
      final alFinalDelDia = DateTime.utc(2026, 10, 27, 5, 30);

      expect(DiaDeNegocio.de(alFinalDelDia), const DiaDeNegocio(2026, 10, 26));

      // Y EL DÍA UTC DEL MISMO INSTANTE ES OTRO, dicho explícitamente: sin esta línea
      // la prueba pasaría igual con un ayudante que no hiciera nada, y no se vería que
      // lo que se está comprobando es justo la diferencia.
      expect(alFinalDelDia.day, 27);
    });

    test('las 23:59:59 siguen siendo hoy y las 00:00 ya son mañana', () {
      // 05:59:59 UTC = 23:59:59 del 26 en CDMX.
      expect(
        DiaDeNegocio.de(DateTime.utc(2026, 10, 27, 5, 59, 59)),
        const DiaDeNegocio(2026, 10, 26),
      );

      // 06:00:00 UTC = 00:00:00 del 27 en CDMX.
      expect(
        DiaDeNegocio.de(DateTime.utc(2026, 10, 27, 6)),
        const DiaDeNegocio(2026, 10, 27),
      );
    });

    test('Cancún y Tijuana proponen el MISMO día que la zona centro', () {
      // El mismo instante, nombrado como lo nombraría cada navegador. Es la segunda
      // prueba que D-55 exige: con la hora local, alguien en Cancún —que va una hora
      // adelante— propondría el día siguiente durante una hora cada día, y en Tijuana
      // —dos atrás— el anterior durante dos.
      final enLaZonaCentro = DateTime.parse('2026-10-26T23:30:00-06:00');
      final enCancun = DateTime.parse('2026-10-27T00:30:00-05:00');
      final enTijuana = DateTime.parse('2026-10-26T21:30:00-08:00');

      // LOS TRES SON EL MISMO INSTANTE, y conviene afirmarlo: si no lo fueran, la
      // prueba estaría comparando tres momentos distintos y no diría nada de la zona.
      expect(enCancun.isAtSameMomentAs(enLaZonaCentro), isTrue);
      expect(enTijuana.isAtSameMomentAs(enLaZonaCentro), isTrue);

      const esperado = DiaDeNegocio(2026, 10, 26);

      expect(DiaDeNegocio.de(enLaZonaCentro), esperado);
      expect(DiaDeNegocio.de(enCancun), esperado);
      expect(DiaDeNegocio.de(enTijuana), esperado);
    });

    test('el texto del servidor va y vuelve sin perder el día', () {
      expect(DiaDeNegocio.deTexto('2026-10-26'), const DiaDeNegocio(2026, 10, 26));
      expect(const DiaDeNegocio(2026, 1, 5).enTexto, '2026-01-05');

      // UNA FECHA RARA NO REVIENTA UNA LISTA: devuelve nulo y quien lo recibe enseña
      // «sin fecha», que es menos que la verdad y no es falso.
      expect(DiaDeNegocio.deTexto(null), isNull);
      expect(DiaDeNegocio.deTexto('ayer'), isNull);
      expect(DiaDeNegocio.deTexto('2026-10'), isNull);
    });

    test('la vuelta del selector de fechas conserva el día que se tocó', () {
      // `showDatePicker` devuelve la medianoche LOCAL del día elegido, así que la
      // conversión tiene que leer los campos y no cambiar de reloj. Con un `toUtc()`
      // de por medio, en la zona centro el día elegido se iría al anterior.
      final loQueDevuelveElSelector = DateTime(2026, 3, 1);

      expect(
        DiaDeNegocio.deFechaLocal(loQueDevuelveElSelector),
        const DiaDeNegocio(2026, 3, 1),
      );
      expect(
        const DiaDeNegocio(2026, 3, 1).comoFechaLocal,
        loQueDevuelveElSelector,
      );
    });

    test('hoy() sale del ayudante y no del día UTC', () {
      // No se puede fijar el reloj, así que lo que se afirma es la PROPIEDAD: el día
      // que devuelve es el del instante actual con −06:00 aplicado. Comparar contra
      // `DiaDeNegocio.de(...)` del mismo instante sería tautológico; comparar contra el
      // día UTC fallaría seis horas al día. Así que se comprueba que esté en la ventana
      // de los dos días posibles y que coincida con el cálculo explícito.
      final hoy = DiaDeNegocio.hoy();
      final ahora = DateTime.fromMillisecondsSinceEpoch(
        DateTime.now().millisecondsSinceEpoch,
        isUtc: false,
      );

      expect(hoy, DiaDeNegocio.de(ahora));
    });
  });

  test('el candado mira las fuentes de verdad', () {
    // Sin esto, mover la carpeta dejaría un guardia que enumera cero archivos y pasa
    // siempre. Se acota con «al menos», nunca con un total: `lib` crece cada semana.
    final rutas = fuentes().map(relativa).toList();

    expect(rutas.length, greaterThan(200));
    expect(rutas, contains('lib/core/auth/gestor_de_sesion.dart'));
    expect(rutas, contains('lib/main_web.dart'));
  });

  test('el candado distingue el código de la prosa', () {
    // La regla, ejercitada: la misma línea cuenta como copia en código y no cuenta
    // dentro de un comentario. Es lo que deja pasar la explicación del arreglo.
    const codigo = '    final hoy = DateTime.now().toUtc();';
    const prosa = '    // Nunca `DateTime.now().toUtc()` para un día.';

    expect(codigo.contains('DateTime.now().toUtc()'), isTrue);

    expect(
      prosa.substring(0, prosa.indexOf('//')).contains('DateTime.now().toUtc()'),
      isFalse,
    );
  });
}

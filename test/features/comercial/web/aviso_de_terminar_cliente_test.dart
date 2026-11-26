import 'package:flutter_test/flutter_test.dart';
import 'package:riseg_one/core/fechas/dia_de_negocio.dart';
import 'package:riseg_one/features/comercial/web/modelos/cliente.dart';
import 'package:riseg_one/features/comercial/web/modelos/servicio.dart';
import 'package:riseg_one/features/comercial/web/presentation/aviso_de_terminar_cliente.dart';

/// **EL AVISO DE TERMINAR UN CLIENTE QUE TODAVÍA TIENE SERVICIOS COBRANDO** (D-88).
///
/// ## Qué se mide aquí, y por qué es una función pura
///
/// El defecto que esto cierra lo encontró el dueño el **26-nov-2026** en el ensayo: terminó
/// el cliente PRUEBA B teniendo **SRV-000003 Activo/Vigente con $54,000** y la pantalla no
/// dijo nada. Lo que hacía falta no era un candado —terminar NO toca los servicios, y eso es
/// paridad exacta con RISEG ONE— sino **decirlo con números antes de confirmar**.
///
/// Lo único que puede estar mal es **el texto**: qué dice y, sobre todo, **qué NO dice
/// cuando falta un dato**. Eso se afirma aquí sin montar un widget ni un servidor.
///
/// ## 🚫 La familia de fallos que estas pruebas persiguen
///
/// Las tres entradas pueden faltar, y **cada falta se dice distinto**: unos indicadores que
/// no llegaron NO son «no tiene servicios», una lista que no cargó NO es una lista vacía, y
/// un importe que no se pudo consultar NO es `$0.00`. Las tres mentiras son creíbles, y las
/// tres dejarían terminar tranquilo a alguien con dinero vivo colgando.
void main() {
  IndicadoresDeCliente indicadores({
    int activos = 0,
    int suspendidos = 0,
    List<Monto> importe = const [Monto(moneda: 'MXN', menores: 5400000)],
    List<MontoPorCerrar> porCerrar = const [],
  }) => IndicadoresDeCliente(
    serviciosActivos: activos,
    serviciosSuspendidos: suspendidos,
    importeMensual: importe,
    porCerrar: porCerrar,
  );

  ServicioDelAviso servicio({
    String codigo = 'SRV-000003',
    String nombre = 'Vigilancia nocturna',
    EstatusDeServicio? estatus = EstatusDeServicio.activo,
    List<Monto>? montos = const [Monto(moneda: 'MXN', menores: 5400000)],
    List<MontoPorCerrar> porCerrar = const [],
  }) => ServicioDelAviso(
    codigo: codigo,
    nombre: nombre,
    estatus: estatus,
    montos: montos,
    porCerrar: porCerrar,
  );

  group('Con servicios, el aviso dice cuántos, cuánto y cuáles', () {
    test('el caso exacto del dueño: un activo con su folio y su importe', () {
      final aviso = avisoDeTerminarCliente(
        indicadores: indicadores(activos: 1),
        servicios: [servicio()],
      );

      expect(aviso, isNotNull);
      expect(aviso, contains('1 servicio activo'));
      expect(aviso, contains(r'$54,000.00 MXN'));
      expect(aviso, contains('SRV-000003'));
      expect(aviso, contains('Vigilancia nocturna'));

      // Y DICE QUE NO LOS TERMINA, que es la mitad que convierte el dato en una decisión:
      // sin esa frase, los números se leen como un impedimento.
      expect(aviso, contains('no los termina'));
    });

    test('los SUSPENDIDOS se cuentan y se marcan cuál es cuál', () {
      // 🔑 DECISIÓN DEL DUEÑO DEL 26-nov-2026: un suspendido **puede volver a cobrar**, así
      // que cuenta igual. Y en una lista mezclada hay que poder distinguirlos: «activo» y
      // «suspendido» cambian lo que significa la fila.
      final aviso = avisoDeTerminarCliente(
        indicadores: indicadores(activos: 2, suspendidos: 1),
        servicios: [
          servicio(),
          servicio(codigo: 'SRV-000004', nombre: 'Rondines'),
          servicio(
            codigo: 'SRV-000005',
            nombre: 'Monitoreo',
            estatus: EstatusDeServicio.suspendido,
          ),
        ],
      );

      expect(aviso, contains('2 servicios activos y 1 suspendido'));
      expect(aviso, contains('SRV-000005'));
      expect(aviso, contains('suspendido'));
      expect(aviso, contains('activo'));
    });

    test('sólo suspendidos TAMBIÉN avisa, porque pueden volver a cobrar', () {
      // ⚠️ Esconder el aviso aquí escondería justo el caso que se pidió incluir. Y el
      // plural se cuida: «1 suspendido», no «1 suspendidos».
      final aviso = avisoDeTerminarCliente(
        indicadores: indicadores(suspendidos: 1),
        servicios: [servicio(estatus: EstatusDeServicio.suspendido)],
      );

      expect(aviso, isNotNull);
      expect(aviso, contains('1 suspendido'));

      // Y NO ENUMERA EL LADO VACÍO: «0 servicios activos y 1 suspendido» es más largo y
      // dice lo mismo, y de paso pone un cero donde no hace falta ninguno.
      expect(aviso, isNot(contains('servicio activo')));
      expect(aviso, isNot(contains('0 servicios')));
    });

    test('el dinero POR CERRAR se menciona con su fecha final', () {
      // 🚫 NO SE SUMA AL IMPORTE —decisión del dueño del 24-nov-2026, aquí reutilizada—:
      // es dinero cierto que SE ACABA un día, así que sumarlo diría una cifra que el mes
      // que viene ya no es.
      final aviso = avisoDeTerminarCliente(
        indicadores: indicadores(activos: 1),
        servicios: [
          servicio(
            porCerrar: const [
              MontoPorCerrar(
                monto: Monto(moneda: 'MXN', menores: 900000),
                hasta: DiaDeNegocio(2026, 12, 14),
              ),
            ],
          ),
        ],
      );

      expect(aviso, contains('deja de cobrar'));
      expect(aviso, contains(r'$9,000.00 MXN'));
      expect(aviso, contains('14/dic/2026'));
    });

    test('dos monedas se dicen las dos, y NO se suman', () {
      // La misma regla que el encabezado: el día que un cliente tenga condiciones en dos
      // monedas, un total sería un número inventado.
      final aviso = avisoDeTerminarCliente(
        indicadores: indicadores(
          activos: 1,
          importe: const [
            Monto(moneda: 'MXN', menores: 100000),
            Monto(moneda: 'USD', menores: 50000),
          ],
        ),
        servicios: [servicio()],
      );

      expect(aviso, contains(r'$1,000.00 MXN'));
      expect(aviso, contains(r'$500.00 USD'));
    });
  });

  group('Sin servicios no sale aviso', () {
    test('cero y cero devuelve nulo, porque no hay nada que decir', () {
      // Un aviso que sale siempre deja de leerse, y éste tiene que leerse.
      expect(
        avisoDeTerminarCliente(indicadores: indicadores(), servicios: const []),
        isNull,
      );
    });
  });

  group('🚫 Ninguna falta se convierte en un cero', () {
    test('indicadores que NO llegaron dicen «no se pudo comprobar»', () {
      // ⚠️ AUSENCIA NUNCA ES CERO, y aquí es la mentira más peligrosa de las tres: «no
      // tiene servicios» es creíble, es falso y deja terminar tranquilo.
      final aviso = avisoDeTerminarCliente(
        indicadores: null,
        servicios: const [],
      );

      expect(aviso, isNotNull);
      expect(aviso, contains('No se pudo comprobar'));
      expect(aviso, contains('no los termina'));

      // Y NO INVENTA UNA CUENTA: sin indicadores no hay N que decir.
      expect(aviso, isNot(contains('0 servicios')));
      expect(aviso, isNot(contains('servicio activo')));
    });

    test('la lista que NO cargó deja los números y lo dice', () {
      // Media verdad dicha es mejor que una lista vacía que parece completa: los números
      // vienen de los indicadores, que sí llegaron.
      final aviso = avisoDeTerminarCliente(
        indicadores: indicadores(activos: 3, suspendidos: 1),
        servicios: null,
      );

      expect(aviso, contains('3 servicios activos y 1 suspendido'));
      expect(aviso, contains(r'$54,000.00 MXN'));
      expect(aviso, contains('No se pudo cargar la lista'));
    });

    test('un importe no consultado NO sale como cero pesos', () {
      final aviso = avisoDeTerminarCliente(
        indicadores: indicadores(activos: 1),
        servicios: [servicio(montos: null)],
      );

      expect(aviso, contains('importe no consultado'));
      expect(aviso, isNot(contains(r'$0.00')));
    });

    test('un servicio SIN condiciones vigentes lo dice, y tampoco es cero', () {
      // Lista vacía y lista nula son dos cosas distintas, y el aviso las separa.
      final aviso = avisoDeTerminarCliente(
        indicadores: indicadores(activos: 1),
        servicios: [servicio(montos: const [])],
      );

      expect(aviso, contains('sin condiciones vigentes'));
      expect(aviso, isNot(contains('importe no consultado')));
      expect(aviso, isNot(contains(r'$0.00')));
    });

    test('un cliente sin condiciones vigentes tampoco dice cero pesos', () {
      final aviso = avisoDeTerminarCliente(
        indicadores: indicadores(activos: 1, importe: const []),
        servicios: [servicio(montos: const [])],
      );

      // LA FRASE CAMBIA DE FORMA Y NO SÓLO DE PALABRAS: «por sin condiciones vigentes» no
      // es español, y era lo que decía hasta que el dueño lo leyó el 26-nov-2026.
      expect(
        aviso,
        'Este cliente tiene 1 servicio activo, sin condiciones vigentes; '
            'terminarlo no los termina ni les quita lo que cobran.\n'
            '  · SRV-000003 · Vigilancia nocturna — activo — sin condiciones vigentes',
      );

      expect(aviso, isNot(contains('por sin')));
      expect(aviso, isNot(contains(r'$0.00')));
    });
  });

  group('La lista acotada DICE que está acotada', () {
    test('«y N más» cuando se enseñan menos de los que hay', () {
      // ⚠️ EL DEFECTO QUE ESTO EVITA es silencioso: una lista de diez en un cliente con
      // treinta servicios se lee como la lista completa, así que el aviso diría MENOS de
      // lo que hay mientras parece exacto. El total sale de los INDICADORES, que no
      // paginan; la lista sale del listado, que sí.
      final aviso = avisoDeTerminarCliente(
        indicadores: indicadores(activos: 25, suspendidos: 5),
        servicios: [
          for (var i = 0; i < 10; i++)
            servicio(codigo: 'SRV-00000$i', nombre: 'Servicio $i'),
        ],
      );

      expect(aviso, contains('25 servicios activos y 5 suspendidos'));
      expect(aviso, contains('y 20 más'));
    });

    test('y NO lo dice cuando la lista está completa', () {
      final aviso = avisoDeTerminarCliente(
        indicadores: indicadores(activos: 2),
        servicios: [servicio(), servicio(codigo: 'SRV-000004')],
      );

      expect(aviso, isNot(contains('más')));
    });

    test('ni se inventa un número negativo si llegaran MÁS de los contados', () {
      // Entre el conteo y el listado alguien puede haber dado de baja un servicio. Lo que
      // no puede salir es «y -1 más».
      final aviso = avisoDeTerminarCliente(
        indicadores: indicadores(activos: 1),
        servicios: [servicio(), servicio(codigo: 'SRV-000004')],
      );

      expect(aviso, isNot(contains('-1')));
      expect(aviso, isNot(contains('más')));
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:riseg_one/app/shell/router_web.dart';
import 'package:riseg_one/core/company/permiso_company.dart';

/// El guardia del router: **a dónde va una dirección que no se puede ver**.
///
/// **POR QUÉ SE PRUEBA SIN MONTAR NADA.** `redireccion` es la regla entera —las
/// direcciones raras del §7 del diseño— y es pura: recibe la dirección y la autoridad
/// que confirmó el servidor, y responde a dónde ir. Comprobarla bombeando pantallas
/// costaría segundos por caso y taparía la regla detrás de un árbol de widgets.
///
/// **Lo que NO prueba este archivo**, a propósito: que el router llame a esta función
/// —eso es cableado— y que la pantalla correcta se pinte —eso es del portón—.
void main() {
  // Alguien con la estructura y la auditoría, que NO es Maestro: es el usuario normal
  // de una empresa, y el caso que más veces se va a dar.
  const deEstructura = {
    PermisoCompany.organizacionVer,
    PermisoCompany.companyAuditRead,
  };

  group('mientras no hay empresa abierta', () {
    test('no se redirige NADA', () {
      // El portón está enseñando el login, el selector o una espera. Moverle la
      // dirección debajo sólo cambiaría la barra del navegador, y además borraría la
      // dirección que esa persona pidió antes de entrar.
      expect(
        redireccion('/organizacion/sucursales', esMaestro: null, permisos: null),
        isNull,
      );

      expect(redireccion('/', esMaestro: null, permisos: null), isNull);
    });
  });

  group('la dirección que no dice nada', () {
    test('la raíz lleva al primer apartado CON PANTALLA', () {
      // No al primero del menú: Dashboard no está mudado, y recibir a todo el mundo
      // con un «Próximamente» haría pensar que no hay nada hecho.
      final destino = redireccion('/', esMaestro: false, permisos: deEstructura);

      expect(destino, '/organizacion/sucursales');
    });

    test('una errata también', () {
      expect(
        redireccion('/inventado', esMaestro: false, permisos: deEstructura),
        '/organizacion/sucursales',
      );
    });
  });

  group('la dirección de un apartado', () {
    test('sin pestaña se completa con la primera disponible', () {
      // Así la dirección dice SIEMPRE dónde estás, y el rastro no tiene que adivinar.
      expect(
        redireccion('/organizacion', esMaestro: false, permisos: deEstructura),
        '/organizacion/sucursales',
      );
    });

    test('un apartado que esta sesión no ve lleva al primero que sí', () {
      // Configuración necesita ser Maestro o tener auditoría; sin ninguno de los dos,
      // no es un 404: la dirección existe y no es para esta persona.
      expect(
        redireccion(
          '/configuracion',
          esMaestro: false,
          permisos: const {PermisoCompany.organizacionVer},
        ),
        '/organizacion/sucursales',
      );
    });

    test('un apartado NO MUDADO lleva al primero con pantalla', () {
      expect(
        redireccion('/personal', esMaestro: false, permisos: deEstructura),
        '/organizacion/sucursales',
      );
    });
  });

  group('la dirección de una pestaña', () {
    test('una que sí se ve NO se toca', () {
      expect(
        redireccion('/organizacion/areas', esMaestro: false, permisos: deEstructura),
        isNull,
      );
    });

    test('lo que se abrió DENTRO tampoco se toca', () {
      // Es lo que hace que «Tipos de sucursal» pueda ser una dirección y no un `bool`
      // con un aviso hacia arriba, que era la deuda D-39.
      expect(
        redireccion(
          '/organizacion/sucursales/tipos',
          esMaestro: false,
          permisos: deEstructura,
        ),
        isNull,
      );
    });

    test('un expediente con su id dentro tampoco', () {
      // DOS SEGMENTOS DENTRO, y el primero es un identificador: el guardia **no los
      // mira**, y es deliberado. Quien sabe si ese id existe es la pantalla, que lo
      // busca en lo que el servidor ya devolvió; juzgarlo aquí obligaría al guardia a
      // pedir datos, y un guardia que pide datos deja de ser una regla pura.
      expect(
        redireccion(
          '/organizacion/sucursales/0193f0a0-0000-7000-8000-0000000000c1/expediente',
          esMaestro: false,
          permisos: deEstructura,
        ),
        isNull,
      );
    });

    test('la pestaña se juzga IGUAL lleve algo dentro o no', () {
      // Lo de dentro no es una puerta trasera: una pestaña que esta sesión no ve sigue
      // llevando a la primera de su apartado aunque la dirección pida algo de dentro.
      expect(
        redireccion(
          '/configuracion/usuarios/algo',
          esMaestro: false,
          permisos: deEstructura,
        ),
        '/configuracion/auditoria',
      );
    });

    test('una pestaña de Maestro, sin serlo, lleva a la primera de SU apartado', () {
      // A Auditoría y NO a Organización: quien pidió Configuración quería
      // Configuración, y echarlo al otro apartado sería perderle el sitio.
      expect(
        redireccion(
          '/configuracion/usuarios',
          esMaestro: false,
          permisos: deEstructura,
        ),
        '/configuracion/auditoria',
      );
    });

    test('para el Maestro esa misma dirección vale', () {
      expect(
        redireccion(
          '/configuracion/usuarios',
          esMaestro: true,
          permisos: deEstructura,
        ),
        isNull,
      );
    });

    test('una pestaña inventada lleva a la primera de su apartado', () {
      expect(
        redireccion(
          '/organizacion/inventada',
          esMaestro: false,
          permisos: deEstructura,
        ),
        '/organizacion/sucursales',
      );
    });
  });

  group('sin ningún apartado visible', () {
    test('no se redirige, porque no hay a dónde', () {
      // Con cero permisos y sin ser Maestro no hay nada que abrir. El portón ya tiene
      // su pantalla para eso —la bienvenida sin accesos—, y devolver una dirección
      // inventada aquí haría un bucle de redirecciones.
      expect(redireccion('/', esMaestro: false, permisos: const {}), isNull);

      expect(
        redireccion('/organizacion/areas', esMaestro: false, permisos: const {}),
        isNull,
      );
    });
  });
}

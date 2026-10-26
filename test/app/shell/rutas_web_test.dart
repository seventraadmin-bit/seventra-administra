import 'package:flutter_test/flutter_test.dart';
import 'package:riseg_one/app/shell/rutas_web.dart';

/// Cómo se lee una dirección de Administra en la web.
///
/// **POR QUÉ ESTO SE PRUEBA SOLO.** Es la regla que el router aplica en cada
/// navegación y que el rastro lee en cada repintado, y no necesita una sola pantalla
/// para ejercitarse. Si estuviera dentro del router haría falta bombear widgets para
/// comprobar que `/organizacion/sucursales/tipos` se parte en tres.
void main() {
  group('leerUbicacion', () {
    test('un apartado solo', () {
      final u = leerUbicacion('/organizacion')!;

      expect(u.apartado, '/organizacion');
      expect(u.pestana, isNull);
      expect(u.dentro, isNull);
    });

    test('un apartado con su pestaña', () {
      final u = leerUbicacion('/organizacion/sucursales')!;

      expect(u.apartado, '/organizacion');
      expect(u.pestana, 'sucursales');
      expect(u.dentro, isNull);
    });

    test('lo que se abrió dentro de la pestaña', () {
      final u = leerUbicacion('/organizacion/sucursales/tipos')!;

      expect(u.pestana, 'sucursales');
      expect(u.dentro, ['tipos']);
    });

    test('un identificador y lo que se abrió de él', () {
      final u = leerUbicacion('/organizacion/sucursales/abc-123/expediente')!;

      expect(u.pestana, 'sucursales');
      expect(u.dentro, ['abc-123', 'expediente']);
    });

    test('la cadena de consulta no es parte de la ubicación', () {
      // Sólo las rutas deciden qué se ve. Un `?` con estado dentro sería una segunda
      // forma de decir dónde estás, y dos formas acaban discrepando.
      expect(leerUbicacion('/organizacion/areas?x=1')!.pestana, 'areas');
    });

    test('las barras de sobra no cambian nada', () {
      expect(leerUbicacion('//organizacion//areas//')!.pestana, 'areas');
    });

    test('un apartado que no existe es NULO y no una excepción', () {
      // Una dirección escrita a mano llega tal cual: reventar convertiría una errata
      // en una pantalla roja, y quien recibe el nulo decide a dónde mandar a esa
      // persona.
      expect(leerUbicacion('/inventado'), isNull);
      expect(leerUbicacion('/'), isNull);
      expect(leerUbicacion(''), isNull);
    });

    test('un apartado NO MUDADO sí es una ubicación válida', () {
      // Que no tenga pantalla no significa que no exista: su «Próximamente» se abre, y
      // el router tiene que poder llevar a esa dirección.
      expect(leerUbicacion('/personal')!.apartado, '/personal');
    });
  });

  group('direccion', () {
    test('se compone y se vuelve a leer igual', () {
      const u = UbicacionWeb(
        apartado: '/organizacion',
        pestana: 'sucursales',
        dentro: ['tipos'],
      );

      expect(u.direccion, '/organizacion/sucursales/tipos');
      expect(leerUbicacion(u.direccion)!.dentro, ['tipos']);
    });

    test('un apartado solo no arrastra barras', () {
      expect(const UbicacionWeb(apartado: '/areas').direccion, '/areas');
    });

    test('direccionDe arma la de una pestaña', () {
      expect(direccionDe('/configuracion', 'usuarios'), '/configuracion/usuarios');
    });
  });

  group('nombreDeLoDeDentro', () {
    test('traduce lo que el rastro enseña', () {
      expect(nombreDeLoDeDentro('sucursales', ['tipos']), 'Tipos de sucursal');
      expect(nombreDeLoDeDentro('sucursales', ['abc', 'expediente']), 'Expediente');
    });

    test('un identificador NO sale en el rastro', () {
      // «Organización › Sucursales › 9f3c…» no le dice nada a nadie. Lo que se abrió es
      // el expediente; el id es de qué.
      expect(nombreDeLoDeDentro('sucursales', ['9f3c-0001']), isNull);
    });

    test('sin nada dentro no hay tercer segmento', () {
      expect(nombreDeLoDeDentro('sucursales', null), isNull);
      expect(nombreDeLoDeDentro('sucursales', []), isNull);
    });

    test('la misma palabra en otra pestaña no se confunde', () {
      // La tabla es por (pestaña, segmento) y no por segmento suelto: el día que otra
      // pestaña tenga su propio «tipos», no heredará el nombre de Sucursales.
      expect(nombreDeLoDeDentro('puestos', ['tipos']), isNull);
    });

    test('los pasos de Empresa también tienen nombre', () {
      expect(nombreDeLoDeDentro('empresa', ['editar']), 'Editar');
      expect(nombreDeLoDeDentro('empresa', ['administracion']), 'Administración');
    });
  });

  group('idDeLoDeDentro', () {
    test('un expediente lleva el id de su sucursal', () {
      expect(idDeLoDeDentro(['9f3c-0001', 'expediente']), '9f3c-0001');
    });

    test('un catálogo no identifica nada', () {
      // `tipos` no es «el tipo 7»: es la lista entera. Devolver el segmento como id
      // haría que el rastro intentara ponerle nombre a algo que no lo tiene.
      expect(idDeLoDeDentro(['tipos']), isNull);
      expect(idDeLoDeDentro(null), isNull);
      expect(idDeLoDeDentro([]), isNull);
    });
  });

  group('rastroConNombre', () {
    test('mientras no se conoce el nombre, dice sólo qué es', () {
      // Es el estado de carga, y es el correcto: «Expediente» es cierto desde el primer
      // instante. Esperar a saber el nombre dejaría el rastro en blanco un momento.
      expect(rastroConNombre('Expediente', null), 'Expediente');
    });

    test('con el nombre cargado, lo dice', () {
      expect(rastroConNombre('Expediente', 'Matriz'), 'Expediente de Matriz');
    });

    test('sin nada abierto no hay tercer segmento', () {
      // Y un nombre suelto no inventa un segmento: si no se abrió nada, el rastro
      // termina en la pestaña.
      expect(rastroConNombre(null, 'Matriz'), isNull);
      expect(rastroConNombre(null, null), isNull);
    });
  });

  group('seAbreLoDeDentro', () {
    test('la administración de empresas SIN autoridad no se abre', () {
      // ⚠️ ES LA ÚNICA DIRECCIÓN QUE EL GUARDIA DEL ROUTER NO PUEDE JUZGAR: pide
      // autoridad de ORGANIZATION y el guardia sólo entiende permisos de Company. Así
      // que escrita a mano llega hasta la pantalla de Empresa, que enseña la ficha — y
      // el rastro no debe nombrar lo que no se abrió.
      expect(
        seAbreLoDeDentro(
          'empresa',
          ['administracion'],
          puedeAdministrarEmpresas: false,
        ),
        isFalse,
      );
    });

    test('con autoridad sí', () {
      // EL CONTRAPUNTO, y no sobra: una regla que dijera «no» siempre pasaría la
      // prueba de arriba y dejaría el rastro mudo para quien sí administra.
      expect(
        seAbreLoDeDentro(
          'empresa',
          ['administracion'],
          puedeAdministrarEmpresas: true,
        ),
        isTrue,
      );
    });

    test('lo demás se abre, con autoridad o sin ella', () {
      // LA EXCEPCIÓN ES UNA, y la regla no se ensancha: el formulario del expediente,
      // el catálogo de tipos y el expediente de una sucursal no piden nada de
      // Organization, así que la autoridad no los gobierna.
      for (final puede in [true, false]) {
        expect(
          seAbreLoDeDentro('empresa', ['editar'], puedeAdministrarEmpresas: puede),
          isTrue,
        );
        expect(
          seAbreLoDeDentro('sucursales', ['tipos'], puedeAdministrarEmpresas: puede),
          isTrue,
        );
        expect(
          seAbreLoDeDentro(
            'sucursales',
            ['9f3c-0001', 'expediente'],
            puedeAdministrarEmpresas: puede,
          ),
          isTrue,
        );

        // Y SIN NADA DENTRO NO HAY NADA QUE NEGAR.
        expect(
          seAbreLoDeDentro('empresa', null, puedeAdministrarEmpresas: puede),
          isTrue,
        );
        expect(
          seAbreLoDeDentro('empresa', [], puedeAdministrarEmpresas: puede),
          isTrue,
        );
      }
    });

    test('«administracion» en OTRA pestaña no la gobierna esta autoridad', () {
      // La regla mira la pestaña y no sólo el último segmento: el día que otra pestaña
      // tenga algo llamado igual, no debe heredar una puerta que no es la suya.
      expect(
        seAbreLoDeDentro(
          'sucursales',
          ['administracion'],
          puedeAdministrarEmpresas: false,
        ),
        isTrue,
      );
    });
  });
}

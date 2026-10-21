// LA BASE DE PERMISOS DE LA WEB: capacidades por pantalla y el emparejado del panel.
//
// Las dos piezas que esto fija son **base de todos los módulos**, no de Organización:
// cualquier módulo que se mude tendrá su `ver` y sus escrituras, y querrá que sus
// pantallas pregunten por capacidades en vez de cablear banderas a mano.
//
// ## El defecto que la primera pieza vino a cazar
//
// Las tres pantallas de la estructura recibían `bool` sueltos y cada una los cableaba
// por su cuenta. Áreas y Puestos sólo recibían `esMaestro` —que gobierna el BORRADO— y
// sus botones de alta no colgaban de nada. Un usuario con cero permisos lo veía todo.
//
// Y al arreglarlo a mano se olvidó el estado vacío, que tiene su propio botón de alta.
// Tres pantallas, tres cableados, tres oportunidades de olvidar lo mismo.
//
// ## El de la segunda
//
// Conceder «Modificar la organización» sin «Consultar la organización» produce una
// cuenta que puede guardar y no puede ver el formulario. En el servidor son dos códigos
// independientes y cada ruta exige el suyo —de esa separación depende que `restricted`
// responda 402 al escribir y siga permitiendo leer—, así que la pantalla es la única que
// puede evitar esa combinación absurda.

import 'package:flutter_test/flutter_test.dart';
import 'package:riseg_one/app/shell/apartados_web.dart';
import 'package:riseg_one/core/company/permiso_company.dart';

void main() {
  group('Capacidades de un módulo', () {
    test('sin permisos, no se puede nada', () {
      const nada = CapacidadesDeModulo.ninguna();

      expect(nada.puedeVer, isFalse);
      expect(nada.puedeCrear, isFalse);
      expect(nada.puedeModificar, isFalse);
      expect(nada.puedeArchivar, isFalse);
      expect(nada.puedeAlgo, isFalse);
    });

    test('cada capacidad sale de SU permiso, no de una bandera común', () {
      // ES LA PROPIEDAD ENTERA DE LA PIEZA. Con una sola bandera de «puede editar»,
      // quien puede crear podría desactivar, que es el colapso que había.
      final soloCrear = CapacidadesDeModulo.deLaOrganizacion({
        PermisoCompany.organizacionVer,
        PermisoCompany.organizacionCrear,
      });

      expect(soloCrear.puedeVer, isTrue);
      expect(soloCrear.puedeCrear, isTrue);
      expect(soloCrear.puedeModificar, isFalse);
      expect(soloCrear.puedeArchivar, isFalse);

      final soloArchivar = CapacidadesDeModulo.deLaOrganizacion({
        PermisoCompany.organizacionVer,
        PermisoCompany.organizacionArchivar,
      });

      expect(soloArchivar.puedeArchivar, isTrue);
      expect(soloArchivar.puedeCrear, isFalse);
      expect(soloArchivar.puedeModificar, isFalse);
    });

    test('el permiso del EXPEDIENTE no da capacidades sobre la estructura', () {
      // LA FRONTERA QUE DECIDE QUIÉN VE EL RFC. `company.settings.*` es el expediente
      // fiscal; `organizacion.*` es la lista de áreas y puestos. Colapsarlas daría el
      // RFC a quien pidió ver la estructura.
      final soloExpediente = CapacidadesDeModulo.deLaOrganizacion({
        PermisoCompany.companySettingsRead,
        PermisoCompany.companySettingsManage,
      });

      expect(soloExpediente.puedeVer, isFalse);
      expect(soloExpediente.puedeAlgo, isFalse);
    });

    test('la fábrica genérica sirve a un módulo cualquiera', () {
      // ES LO QUE HACE QUE EL MÓDULO SIGUIENTE NO REPITA ESTE TRABAJO: pasa sus
      // cuatro códigos y ya tiene la pieza.
      final personal = CapacidadesDeModulo.de(
        {PermisoCompany.personalRead, PermisoCompany.personalManage},
        ver: PermisoCompany.personalRead,
        crear: PermisoCompany.personalManage,
        modificar: PermisoCompany.personalManage,
        archivar: PermisoCompany.personalSensitiveManage,
      );

      expect(personal.puedeVer, isTrue);
      expect(personal.puedeCrear, isTrue);
      expect(personal.puedeArchivar, isFalse);
    });
  });

  group('Las cuatro pestañas de Organización declaran su permiso', () {
    // ⚠️ NINGUNA LO DECLARABA, y por eso el apartado se ofrecía a cualquiera con
    // acceso a la empresa: entraba, y el servidor le servía las listas porque tampoco
    // las pedía.
    final organizacion = apartados.firstWhere((a) => a.ruta == '/organizacion');

    test('ninguna se queda sin permiso', () {
      final mudas = organizacion.pestanas
          .where((p) => p.permiso == null)
          .map((p) => p.id)
          .toList();

      expect(
        mudas,
        isEmpty,
        reason:
            'una pestaña sin permiso se ofrece a cualquiera con acceso a la empresa',
      );
    });

    test('Empresa pide el del EXPEDIENTE y las otras tres el de la ESTRUCTURA', () {
      String permisoDe(String id) =>
          organizacion.pestanas.firstWhere((p) => p.id == id).permiso!;

      expect(permisoDe('empresa'), PermisoCompany.companySettingsRead);
      expect(permisoDe('sucursales'), PermisoCompany.organizacionVer);
      expect(permisoDe('puestos'), PermisoCompany.organizacionVer);
      expect(permisoDe('areas'), PermisoCompany.organizacionVer);
    });

    test('con CERO permisos el apartado NO aparece', () {
      expect(
        queHacerCon(organizacion, esMaestro: false, permisos: const {}),
        QueHacerConElApartado.noAparece,
      );
    });

    test('con sólo «Consultar la organización» aparece, y sin Empresa', () {
      // EL CONTRAPUNTO: sin él, la prueba de arriba pasaría también si el apartado
      // no apareciera NUNCA, que sería otro defecto.
      final permisos = {PermisoCompany.organizacionVer};

      expect(
        queHacerCon(organizacion, esMaestro: false, permisos: permisos),
        QueHacerConElApartado.seAbre,
      );

      final visibles = pestanasPara(
        organizacion,
        esMaestro: false,
        permisos: permisos,
      ).map((p) => p.id);

      expect(visibles, containsAll(['sucursales', 'puestos', 'areas']));
      expect(visibles, isNot(contains('empresa')));
    });

    test('con sólo «Consultar la empresa» aparece SÓLO Empresa', () {
      final visibles = pestanasPara(
        organizacion,
        esMaestro: false,
        permisos: {PermisoCompany.companySettingsRead},
      ).map((p) => p.id);

      expect(visibles, ['empresa']);
    });
  });

  group('El emparejado Consultar ↔ escrituras', () {
    test('cada escritura arrastra SÓLO su lectura', () {
      expect(
        lecturaQueImplica(PermisoCompany.organizacionCrear),
        PermisoCompany.organizacionVer,
      );
      expect(
        lecturaQueImplica(PermisoCompany.organizacionModificar),
        PermisoCompany.organizacionVer,
      );
      expect(
        lecturaQueImplica(PermisoCompany.organizacionArchivar),
        PermisoCompany.organizacionVer,
      );

      // CONFIGURAR ARRASTRA «CONSULTAR LA EMPRESA», NO LA DE LA ORGANIZACIÓN. Son
      // dos familias, y arrastrar las dos daría el RFC a quien pidió ver las áreas.
      expect(
        lecturaQueImplica(PermisoCompany.companySettingsManage),
        PermisoCompany.companySettingsRead,
      );
      expect(
        lecturaQueImplica(PermisoCompany.companySettingsManage),
        isNot(PermisoCompany.organizacionVer),
      );
    });

    test('una lectura no arrastra nada, y un permiso suelto tampoco', () {
      expect(lecturaQueImplica(PermisoCompany.organizacionVer), isNull);
      expect(lecturaQueImplica(PermisoCompany.companySettingsRead), isNull);
      expect(lecturaQueImplica(PermisoCompany.companyAuditRead), isNull);
      expect(lecturaQueImplica(PermisoCompany.personalManage), isNull);
    });

    test('la lectura está RETENIDA mientras quede una escritura suya', () {
      expect(
        laLecturaEstaRetenida(PermisoCompany.organizacionVer, {
          PermisoCompany.organizacionModificar,
        }),
        isTrue,
      );

      expect(
        laLecturaEstaRetenida(PermisoCompany.organizacionVer, const {}),
        isFalse,
      );
    });

    test('la retiene sólo SU familia', () {
      // «Consultar la empresa» no la retiene una escritura de la estructura, ni al
      // contrario. Es la misma frontera, vista desde el otro lado.
      expect(
        laLecturaEstaRetenida(PermisoCompany.companySettingsRead, {
          PermisoCompany.organizacionModificar,
        }),
        isFalse,
      );

      expect(
        laLecturaEstaRetenida(PermisoCompany.organizacionVer, {
          PermisoCompany.companySettingsManage,
        }),
        isFalse,
      );
    });

    test('toda escritura emparejada apunta a una lectura que existe', () {
      // SIN ESTO, UNA ERRATA EN UN LITERAL pasaría inadvertida: el panel marcaría un
      // código que el servidor no sembró, y el backend responde 500 —no 403— ante un
      // permiso inexistente, que el usuario lee como una avería.
      for (final par in PermisoCompany.lecturaQueImplica.entries) {
        expect(
          PermisoCompany.todos,
          contains(par.key),
          reason: 'la escritura ${par.key} no está en el catálogo',
        );
        expect(
          PermisoCompany.todos,
          contains(par.value),
          reason: 'la lectura ${par.value} no está en el catálogo',
        );
      }
    });
  });
}

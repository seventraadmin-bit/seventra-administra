// Integration Foundation IF-4 — el catálogo de permisos y módulos remotos.
//
// Un catálogo es una lista de nombres, así que la tentación es no probarlo. Lo que se
// defiende aquí no son los nombres: es que el catálogo **no crezca por simetría**. El
// backend responde **500** —no 403— ante un código que nadie sembró, porque para él es
// un cliente exigiendo algo inexistente; así que un `finance.read` inventado «porque
// existe personal.read» no produce una denegación elegante, produce un error de
// servidor que el usuario lee como una avería.

import 'package:flutter_test/flutter_test.dart';
import 'package:riseg_one/core/company/permiso_company.dart';

void main() {
  group('Los permisos del backend que la web USA', () {
    // ⚠️ ESTE GRUPO SE LLAMABA «los diez permisos que el backend tiene sembrados», y
    // el nombre era falso: el backend tiene más de cien sembrados desde la 0022. Lo
    // que esta lista es, y lo único que puede ser, es **lo que la web nombra**.
    //
    // Y la diferencia no fue cosmética. Creyendo que la lista era el catálogo, se
    // concluyó que no existía ningún permiso de lectura para la Organización y se
    // propuso una migración para crear cuatro que YA ESTABAN en la tabla. La única
    // fuente de verdad es `app.platform_permission`; esto es un espejo parcial, y
    // decirlo en el título es parte del arreglo.
    test('son estos, y la lista no crece por simetría', () {
      expect(PermisoCompany.todos, {
        'personal.read',
        'personal.manage',
        'personal.sensitive.read',
        'personal.sensitive.manage',
        'payroll.read',
        'payroll.close',
        'clients_services.read',
        'clients_services.manage',
        'organizacion.ver',
        'organizacion.crear',
        'organizacion.modificar',
        'organizacion.archivar',
        'company.settings.read',
        'company.settings.manage',
        'company.audit.read',
      });
    });

    test('las constantes coinciden con sus literales', () {
      expect(PermisoCompany.personalRead, 'personal.read');
      expect(PermisoCompany.personalManage, 'personal.manage');
      expect(PermisoCompany.personalSensitiveRead, 'personal.sensitive.read');
      expect(
        PermisoCompany.personalSensitiveManage,
        'personal.sensitive.manage',
      );
      expect(PermisoCompany.payrollRead, 'payroll.read');
      expect(PermisoCompany.payrollClose, 'payroll.close');
      expect(PermisoCompany.clientsServicesRead, 'clients_services.read');
      expect(PermisoCompany.clientsServicesManage, 'clients_services.manage');
      expect(PermisoCompany.organizacionVer, 'organizacion.ver');
      expect(PermisoCompany.organizacionCrear, 'organizacion.crear');
      expect(PermisoCompany.organizacionModificar, 'organizacion.modificar');
      expect(PermisoCompany.organizacionArchivar, 'organizacion.archivar');
      expect(PermisoCompany.companySettingsRead, 'company.settings.read');
      expect(PermisoCompany.companySettingsManage, 'company.settings.manage');
      expect(PermisoCompany.companyAuditRead, 'company.audit.read');
    });

    test('los dos PROTEGIDOS son los del expediente sensible', () {
      // Son la diferencia semántica más grande con el sistema local, donde el Maestro
      // posee los 95 códigos sin excepción.
      expect(PermisoCompany.protegidos, {
        'personal.sensitive.read',
        'personal.sensitive.manage',
      });
      expect(
        PermisoCompany.protegidos.every(PermisoCompany.todos.contains),
        isTrue,
      );
    });

    test('los CORE no pertenecen a ningún módulo', () {
      expect(PermisoCompany.core, {
        'organizacion.ver',
        'organizacion.crear',
        'organizacion.modificar',
        'organizacion.archivar',
        'company.settings.read',
        'company.settings.manage',
        'company.audit.read',
      });

      // ⚠️ AQUÍ HABÍA UNA CONVENCIÓN INVENTADA: esta prueba exigía que todo permiso
      // core empezara por `company.`, «la convención del servidor para lo core». No
      // era una convención, era una coincidencia de que sólo había dos. Los cuatro de
      // `organizacion.*` son core desde la 0022 y no la siguen.
      //
      // Lo que de verdad define un permiso core es `module_code IS NULL` en la
      // tabla, y eso no se puede leer desde aquí. Lo que sí se puede afirmar —y es
      // la propiedad que importa— es que **ningún core está en un módulo**.
      for (final permiso in PermisoCompany.core) {
        expect(
          PermisoCompany.todos,
          contains(permiso),
          reason: 'un core que no está en el catálogo de la web',
        );
      }
    });

    test(
      'NO existe payroll.manage: una acción sensible tiene permiso propio',
      () {
        // El backend usa `payroll.close` para demostrar justamente eso.
        expect(PermisoCompany.todos, isNot(contains('payroll.manage')));
        expect(PermisoCompany.todos, contains('payroll.close'));
      },
    );
  });

  group('Los siete módulos', () {
    test('son exactamente siete, y estos', () {
      expect(ModuloCompany.todos, {
        'personal',
        'payroll',
        'clients_services',
        'collections',
        'finance',
        'purchases_inventory',
        'assets',
      });
    });

    test('CUATRO no tienen todavía ni un permiso', () {
      expect(modulosSinPermisos, {
        'collections',
        'finance',
        'purchases_inventory',
        'assets',
      });
      expect(
        modulosSinPermisos.every(ModuloCompany.todos.contains),
        isTrue,
        reason: 'existen como módulos; lo que falta son sus capacidades',
      );
    });

    test('ningún permiso pertenece a un módulo sin permisos', () {
      // El guardia contra completar el catálogo por simetría.
      for (final modulo in modulosSinPermisos) {
        for (final permiso in PermisoCompany.todos) {
          expect(
            permiso.startsWith('$modulo.'),
            isFalse,
            reason:
                '«$permiso» pertenecería a un módulo sin permisos sembrados, y el '
                'backend responde 500 a un código que no existe en su catálogo',
          );
        }
      }
    });

    test('tres módulos SÍ tienen permisos', () {
      final conPermisos =
          ModuloCompany.todos
              .where(
                (m) => PermisoCompany.todos.any((p) => p.startsWith('$m.')),
              )
              .toSet();

      expect(conPermisos, {'personal', 'payroll', 'clients_services'});
    });
  });

  group('Lo que NO se inventa', () {
    test('no hay permisos de archivos', () {
      // Los archivos se autorizan con el permiso de su RECURSO DE DOMINIO: en el
      // backend, `ClientFileEndpoints` reutiliza `clients_services.*` y
      // `PersonnelDocumentEndpoints` reutiliza `personal.*`. Un permiso de archivos
      // sería inventar catálogo.
      for (final inventado in [
        'files.read',
        'files.manage',
        'file.read',
        'documents.read',
        'documents.manage',
      ]) {
        expect(PermisoCompany.todos, isNot(contains(inventado)));
      }
    });

    test('no hay permisos de los cuatro módulos vacíos', () {
      for (final inventado in [
        'finance.read',
        'finance.manage',
        'collections.read',
        'assets.read',
        'purchases_inventory.read',
      ]) {
        expect(PermisoCompany.todos, isNot(contains(inventado)));
      }
    });

    test('no hay traducción de los códigos locales', () {
      // `personal.ver` no es `personal.read` sólo porque se parezcan, y decidir que lo
      // son es trabajo de la migración de cada módulo, con criterio humano.
      for (final local in [
        'personal.ver',
        'personal.crear',
        'personal.cambiarSueldo',
        'nomina.cerrar',
        'telefonia.verCredenciales',
        'usuarios.administrar',
      ]) {
        expect(PermisoCompany.todos, isNot(contains(local)));
      }
    });

    test('no hay permisos del plano Organization', () {
      // `subscription.manage` pertenece al gobierno de la Organization, que tiene su
      // propia autoridad y NO viaja en /context.
      expect(PermisoCompany.todos, isNot(contains('subscription.manage')));
      expect(PermisoCompany.todos, isNot(contains('organization.manage')));
    });
  });

  group('La convención de nombres del servidor', () {
    test('todo permiso tiene forma modulo.accion, en minúsculas', () {
      final forma = RegExp(r'^[a-z_]+(\.[a-z_]+)+$');

      for (final permiso in PermisoCompany.todos) {
        expect(
          forma.hasMatch(permiso),
          isTrue,
          reason: '«$permiso» no sigue la convención del backend',
        );
      }
    });

    test('todo módulo es un identificador simple, sin puntos', () {
      for (final modulo in ModuloCompany.todos) {
        expect(modulo, isNot(contains('.')));
        expect(RegExp(r'^[a-z_]+$').hasMatch(modulo), isTrue);
      }
    });

    test('los permisos de módulo llevan el prefijo de su módulo', () {
      final deModulo = PermisoCompany.todos.difference(PermisoCompany.core);

      for (final permiso in deModulo) {
        expect(
          ModuloCompany.todos.any((m) => permiso.startsWith('$m.')),
          isTrue,
          reason: '«$permiso» no pertenece a ningún módulo conocido',
        );
      }
    });
  });
}

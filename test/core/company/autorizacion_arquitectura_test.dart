// Integration Foundation IF-4 — los LÍMITES de la etapa, verificados sobre el árbol
// de código.
//
// IF-4 construye el motor de autorización remota **sin aplicarlo a ninguna pantalla**.
// La frontera que estas pruebas protegen es simétrica, y las dos mitades importan por
// igual:
//
//   · los permisos REMOTOS no autorizan una mutación de Drift;
//   · los permisos LOCALES no autorizan un endpoint del backend.
//
// Soldar cualquiera de las dos sería fácil y costaría mucho revertirlo: hay 73 `hasCode`
// y 81 `exigirMaestro` en el árbol, y los catálogos tienen granularidades incompatibles
// —95 códigos locales frente a 10 remotos—.
//
// SE IGNORAN LOS COMENTARIOS, y es el séptimo tropiezo del proyecto con lo mismo. Un
// guardia que se dispara contra su propia explicación obliga a borrar la explicación.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:riseg_one/core/company/autorizacion_company.dart';
import 'package:riseg_one/core/company/permiso_company.dart';
import 'package:riseg_one/core/permissions/modulos_permiso.dart';

/// Los archivos que IF-4 añade o toca.
const List<String> _archivosDeIF4 = [
  'lib/core/company/permiso_company.dart',
  'lib/core/company/autorizacion_company.dart',
  'lib/core/company/company_providers.dart',
];

/// Los dos archivos NUEVOS: la vista y el catálogo. `company_providers` queda fuera
/// porque es de IF-3 y sí conoce Riverpod y el resto de la cadena.
const List<String> _nucleoDeIF4 = [
  'lib/core/company/permiso_company.dart',
  'lib/core/company/autorizacion_company.dart',
];

/// Cómo se reconoce que un archivo habla de la autorización remota.
const List<String> _simbolosRemotos = [
  'AutorizacionCompany',
  'autorizacionProvider',
  'PermisoCompany',
  'ModuloCompany',
  'modulosSinPermisos',
];

/// Cómo se reconoce que un archivo habla de la autorización LOCAL.
const List<String> _simbolosLegacy = [
  'PermissionService',
  'hasCode',
  'todosLosCodigosDePermiso',
  'autorizarUseCase',
  'exigirMaestro',
  'AuthorizationService',
  'PermisoDenegado',
  'SesionUsuario',
  'permisoUsuario',
];

void main() {
  String normalizar(String ruta) => ruta.replaceAll(r'\', '/');

  List<File> fuentesDeLib() =>
      Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'))
          .toList();

  String sinComentarios(String fuente) => fuente
      .split('\n')
      .where((linea) => !linea.trimLeft().startsWith('//'))
      .join('\n');

  String codigoDe(String ruta) => sinComentarios(File(ruta).readAsStringSync());

  // =========================================================================
  group('Los literales del catálogo tienen un dueño único', () {
    test('ningún permiso remoto aparece fuera de permiso_company.dart', () {
      // Un `'personal.read'` escrito a mano no falla: devuelve `false` en silencio y la
      // acción desaparece de la interfaz sin que nada lo señale.
      final infractores = <String>[];

      for (final archivo in fuentesDeLib()) {
        final ruta = normalizar(archivo.path);
        if (ruta == 'lib/core/company/permiso_company.dart') continue;

        final codigo = sinComentarios(archivo.readAsStringSync());

        for (final permiso in PermisoCompany.todos) {
          if (codigo.contains("'$permiso'") || codigo.contains('"$permiso"')) {
            infractores.add('$ruta → $permiso');
          }
        }
      }

      expect(infractores, isEmpty);
    });

    test('los módulos remotos tampoco se escriben a mano', () {
      // Se comprueban los compuestos, que son los inequívocos: `personal` y `finance`
      // son palabras que aparecen legítimamente en rutas y textos del producto local,
      // y prohibirlas sería un guardia que impide usos legítimos.
      final infractores = <String>[];

      for (final archivo in fuentesDeLib()) {
        final ruta = normalizar(archivo.path);
        if (ruta == 'lib/core/company/permiso_company.dart') continue;

        final codigo = sinComentarios(archivo.readAsStringSync());

        for (final modulo in ['clients_services', 'purchases_inventory']) {
          if (codigo.contains("'$modulo'")) infractores.add('$ruta → $modulo');
        }
      }

      expect(infractores, isEmpty);
    });
  });

  // =========================================================================
  group('La frontera legacy ↔ remoto, en los dos sentidos', () {
    test('la autorización remota NO conoce la local', () {
      for (final ruta in _nucleoDeIF4) {
        final codigo = codigoDe(ruta);

        for (final simbolo in _simbolosLegacy) {
          expect(
            codigo,
            isNot(contains(simbolo)),
            reason: '$ruta no debe conocer «$simbolo»',
          );
        }
      }
    });

    test('NINGÚN archivo mezcla los dos sistemas de autorización', () {
      // Es la forma que tendría una tabla de traducción: un archivo que hable de
      // `PermisoCompany` y a la vez de `hasCode`.
      final sospechosos = <String>[];

      for (final archivo in fuentesDeLib()) {
        final codigo = sinComentarios(archivo.readAsStringSync());

        final remoto = _simbolosRemotos.any(codigo.contains);
        final legacy = _simbolosLegacy.any(codigo.contains);

        if (remoto && legacy) sospechosos.add(normalizar(archivo.path));
      }

      expect(
        sospechosos,
        isEmpty,
        reason:
            '`personal.ver` no es `personal.read` sólo porque se parezcan: traducir es '
            'trabajo de la migración de cada módulo, con criterio humano',
      );
    });

    test('la autorización remota NUNCA llega a Drift', () {
      final sospechosos = <String>[];

      for (final archivo in fuentesDeLib()) {
        final codigo = sinComentarios(archivo.readAsStringSync());

        if (!_simbolosRemotos.any(codigo.contains)) continue;

        for (final local in [
          'drift',
          'AppDatabase',
          'EmpresaData',
          'empresaId',
        ]) {
          if (codigo.contains(local)) {
            sospechosos.add('${normalizar(archivo.path)} → $local');
          }
        }
      }

      expect(sospechosos, isEmpty);
    });

    test('no hay respaldo en la Empresa local', () {
      for (final ruta in _archivosDeIF4) {
        final codigo = codigoDe(ruta);

        for (final simbolo in [
          'EmpresaRepository',
          'EmpresaData',
          'obtenerActiva',
          'empresaId',
        ]) {
          expect(codigo, isNot(contains(simbolo)), reason: '$ruta → $simbolo');
        }
      }
    });
  });

  // =========================================================================
  group('La vista es pura', () {
    late String vista;

    setUp(() => vista = codigoDe('lib/core/company/autorizacion_company.dart'));

    test('sin I/O: nada asíncrono, ninguna petición', () {
      for (final prohibido in [
        'Future',
        'async',
        'await',
        'Stream',
        'http',
        'ApiClient',
        'CompanyApi',
        'GestorDeCompany',
      ]) {
        expect(vista, isNot(contains(prohibido)), reason: prohibido);
      }
    });

    test('sin estado mutable: ni un campo que no sea el contexto', () {
      expect(vista, isNot(contains('late ')));
      expect(vista, isNot(contains('var ')));

      // UN solo campo, y es el contexto. Se buscan los campos —declaraciones con
      // nombre privado en el primer nivel de la clase— y no cualquier `final`: las
      // variables locales de `puedeAlguno` y `puedeTodos` también son `final`, y
      // contarlas haría que el guardia se disparara contra código correcto.
      final campos =
          RegExp(
            r'^  final .+ (_\w+);$',
            multiLine: true,
          ).allMatches(vista).map((m) => m.group(1)).toList();

      expect(campos, ['_contexto']);
      expect(vista, contains('final CompanyContext? _contexto;'));
    });

    test('UNA sola fuente: sólo importa el modelo de Company', () {
      final imports =
          RegExp(
            r"^import '.+';$",
            multiLine: true,
          ).allMatches(vista).map((m) => m.group(0)).toList();

      expect(imports, ["import 'company_remota.dart';"]);
    });

    test('no dibuja nada', () {
      for (final ruta in _nucleoDeIF4) {
        final codigo = codigoDe(ruta);

        expect(codigo, isNot(contains('package:flutter/material.dart')));
        expect(codigo, isNot(contains('Widget')));
        expect(codigo, isNot(contains('BuildContext')));
      }
    });

    test('el catálogo no depende de nada', () {
      expect(
        RegExp(
          '^import ',
          multiLine: true,
        ).allMatches(codigoDe('lib/core/company/permiso_company.dart')),
        isEmpty,
        reason: 'son nombres: no necesita importar nada',
      );
    });
  });

  // =========================================================================
  group('El producto sigue sin usar la autorización remota', () {
    test('el router, el shell y el login la ignoran', () {
      for (final ruta in [
        'lib/app/router/app_router.dart',
        'lib/app/bootstrap.dart',
        'lib/app/shell/app_shell_screen.dart',
        'lib/app/shell/shell_permissions.dart',
        'lib/app/shell/widgets/app_top_bar.dart',
        'lib/app/shell/widgets/app_sidebar.dart',
        'lib/features/usuarios/presentation/auth/login_screen.dart',
      ]) {
        final codigo = codigoDe(ruta);

        for (final simbolo in _simbolosRemotos) {
          expect(codigo, isNot(contains(simbolo)), reason: '$ruta → $simbolo');
        }
      }
    });

    test('NINGUNA feature la consume', () {
      final infractores = <String>[];

      for (final archivo in fuentesDeLib()) {
        if (!normalizar(archivo.path).contains('/features/')) continue;

        final codigo = sinComentarios(archivo.readAsStringSync());

        if (_simbolosRemotos.any(codigo.contains)) {
          infractores.add(normalizar(archivo.path));
        }
      }

      expect(infractores, isEmpty);
    });

    test('la capa de Company sigue siendo sólo motor', () {
      final archivos =
          fuentesDeLib()
              .map((f) => normalizar(f.path))
              .where((ruta) => ruta.startsWith('lib/core/company/'))
              .toList()
            ..sort();

      expect(archivos, [
        'lib/core/company/almacen_company_recordada.dart',
        'lib/core/company/autorizacion_company.dart',
        'lib/core/company/company_api.dart',
        'lib/core/company/company_providers.dart',
        'lib/core/company/company_remota.dart',
        'lib/core/company/company_ruta.dart',
        'lib/core/company/gestor_de_company.dart',
        'lib/core/company/permiso_company.dart',
      ]);
    });
  });

  // =========================================================================
  group('El sistema local queda intacto', () {
    test('siguen siendo 95 códigos en 25 módulos', () {
      // La cifra exacta que IF-4A midió. Que esté fijada aquí hace visible cualquier
      // intento de «alinear» el catálogo local con el remoto.
      expect(todosLosCodigosDePermiso(), hasLength(95));
      expect(modulosPermiso, hasLength(25));
    });

    test('ningún código local se parece a uno remoto por accidente', () {
      // Los dos catálogos no comparten ni un código, y eso es lo correcto: son dos
      // vocabularios distintos, no dos versiones del mismo.
      expect(
        todosLosCodigosDePermiso().intersection(PermisoCompany.todos),
        isEmpty,
      );
    });

    test('los embudos de autorización local siguen en su sitio', () {
      expect(
        codigoDe('lib/core/permissions/authorization_service.dart'),
        contains('verificarVigente'),
      );
      expect(
        codigoDe('lib/core/permissions/permission_service.dart'),
        contains('esMaestroActivo'),
      );
      expect(
        codigoDe('lib/app/shell/shell_permissions.dart'),
        contains('permisosQueAbrenRuta'),
      );
    });
  });

  // =========================================================================
  group('IF-2 e IF-3 no se modificaron', () {
    test('el motor de sesión no conoce la autorización de empresa', () {
      for (final ruta in [
        'lib/core/auth/gestor_de_sesion.dart',
        'lib/core/auth/auth_api.dart',
        'lib/core/auth/sesion_remota.dart',
      ]) {
        final codigo = codigoDe(ruta);

        for (final simbolo in _simbolosRemotos) {
          expect(codigo, isNot(contains(simbolo)), reason: '$ruta → $simbolo');
        }
      }
    });

    test('el motor de empresa tampoco: la vista se deriva, no se inyecta', () {
      for (final ruta in [
        'lib/core/company/gestor_de_company.dart',
        'lib/core/company/company_api.dart',
        'lib/core/company/company_remota.dart',
        'lib/core/company/company_ruta.dart',
      ]) {
        final codigo = codigoDe(ruta);

        expect(codigo, isNot(contains('AutorizacionCompany')));
        expect(codigo, isNot(contains('PermisoCompany')));
      }
    });

    test('el provider se deriva del contexto y de nada más', () {
      final codigo = codigoDe('lib/core/company/company_providers.dart');

      expect(
        codigo,
        contains('AutorizacionCompany(ref.watch(companyContextProvider))'),
      );
      expect(
        codigo,
        isNot(contains('invalidate(autorizacion')),
        reason:
            'sin invalidación manual: Riverpod lo reconstruye por dependencia',
      );
    });
  });

  // =========================================================================
  group('El alcance de IF-4', () {
    test('la vista no decide política de red', () {
      // Un 402 o un 403 nunca se convierten automáticamente en cierre de sesión ni en
      // revocación de empresa, y esta clase no está en condiciones de intentarlo.
      final vista = codigoDe('lib/core/company/autorizacion_company.dart');

      for (final prohibido in [
        'revalidar',
        'cerrarSesion',
        'olvidarSeleccion',
        '402',
        '403',
        'statusCode',
      ]) {
        expect(vista, isNot(contains(prohibido)), reason: prohibido);
      }
    });

    test('la etapa no trajo ningún paquete nuevo', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();

      for (final descartado in ['dio', 'hive', 'get_it', 'freezed']) {
        expect(
          RegExp('^\\s+$descartado:', multiLine: true).hasMatch(pubspec),
          isFalse,
          reason: descartado,
        );
      }
    });

    test('la vista sin empresa es construible como constante', () {
      // Denegar por omisión no cuesta ni una asignación.
      const sin = AutorizacionCompany.sinCompany();

      expect(sin.hayCompany, isFalse);
      expect(sin.rol, isNull);
    });
  });
}

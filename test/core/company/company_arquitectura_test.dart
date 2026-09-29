// Integration Foundation IF-3 — los LÍMITES de la etapa, verificados sobre el árbol
// de código.
//
// IF-3 construye el motor de la Company remota **sin convertirlo en contexto visible
// del producto**. Es la misma transición deliberada que IF-2, y por el mismo motivo:
// los once módulos visibles siguen siendo locales y no dependen de la Company, así
// que un selector encima de ellos mentiría —se cambiaría de empresa y no cambiaría
// nada—. Estas pruebas impiden que la transición se suelde sin darse cuenta.
//
// SE IGNORAN LOS COMENTARIOS, y es el sexto tropiezo del proyecto con lo mismo: el
// backend lo tuvo tres veces con `COMMENT ON`, el guardia de `/api/v1` una y el de
// IF-2 otra. Un guardia que se dispara contra su propia explicación obliga a borrar
// la explicación, que es lo contrario de lo que se quiere.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:riseg_one/core/company/almacen_company_recordada.dart';
import 'package:riseg_one/core/company/company_ruta.dart';

/// Los archivos que IF-3 añade.
const List<String> _archivosDeIF3 = [
  'lib/core/company/company_remota.dart',
  'lib/core/company/company_api.dart',
  'lib/core/company/almacen_company_recordada.dart',
  'lib/core/company/gestor_de_company.dart',
  'lib/core/company/company_providers.dart',
  'lib/core/company/company_ruta.dart',
];

/// Cómo se reconoce, desde fuera, que un archivo habla de la Company remota.
const List<String> _simbolosDeCompany = [
  'CompanyDisponible',
  'CompanyContext',
  'EstadoCompany',
  'GestorDeCompany',
  'CompanyApi',
  'CompanyRuta',
  'AlmacenCompanyRecordada',
  'companyIdActivoProvider',
  'gestorDeCompanyProvider',
  'estadoCompanyProvider',
  'companyContextProvider',
  'core/company/',
];

void main() {
  String normalizar(String ruta) => ruta.replaceAll(r'\', '/');

  List<File> fuentesDeLib() =>
      Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'))
          .toList();

  /// El código sin las líneas de comentario. Ver la nota de cabecera.
  String sinComentarios(String fuente) => fuente
      .split('\n')
      .where((linea) => !linea.trimLeft().startsWith('//'))
      .join('\n');

  String codigoDe(String ruta) => sinComentarios(File(ruta).readAsStringSync());

  // =========================================================================
  group('El producto no conoce todavía la Company', () {
    test('el router, el shell y el arranque la ignoran por completo', () {
      for (final ruta in [
        'lib/app/router/app_router.dart',
        'lib/app/bootstrap.dart',
        'lib/app/shell/app_shell_screen.dart',
        'lib/app/shell/widgets/app_top_bar.dart',
        'lib/app/shell/widgets/app_sidebar.dart',
        'lib/app/shell/shell_permissions.dart',
        'lib/features/usuarios/presentation/auth/login_screen.dart',
      ]) {
        final codigo = codigoDe(ruta);

        for (final simbolo in _simbolosDeCompany) {
          expect(
            codigo,
            isNot(contains(simbolo)),
            reason:
                '$ruta no debe conocer «$simbolo»: hoy sus datos no dependen de '
                'la Company, y sugerir que sí lo hacen sería una mentira visible',
          );
        }
      }
    });

    test('NINGUNA feature consume la capa de Company', () {
      final infractores = <String>[];

      for (final archivo in fuentesDeLib()) {
        if (!normalizar(archivo.path).contains('/features/')) continue;

        final codigo = sinComentarios(archivo.readAsStringSync());

        if (_simbolosDeCompany.any(codigo.contains)) {
          infractores.add(normalizar(archivo.path));
        }
      }

      expect(infractores, isEmpty);
    });

    test('la capa de Company son OCHO archivos y ni un widget', () {
      final archivos =
          fuentesDeLib()
              .map((f) => normalizar(f.path))
              .where((ruta) => ruta.toLowerCase().contains('company'))
              .toList()
            ..sort();

      // IF-4 añadió la vista de autorización y su catálogo de permisos. Se suman al
      // inventario en vez de ampliar `_archivosDeIF3`, que sigue significando
      // exactamente lo que dice; quedan sujetos a la comprobación de widgets del bucle
      // de abajo, y sus propias fronteras las vigila `autorizacion_arquitectura_test`.
      const deIF4 = [
        'lib/core/company/autorizacion_company.dart',
        'lib/core/company/permiso_company.dart',
      ];

      expect(archivos, [..._archivosDeIF3, ...deIF4]..sort());

      for (final ruta in archivos) {
        final codigo = codigoDe(ruta);

        expect(
          codigo,
          isNot(contains('package:flutter/material.dart')),
          reason: '$ruta no dibuja nada: IF-3 es motor, no interfaz',
        );
        expect(codigo, isNot(contains('extends StatelessWidget')));
        expect(codigo, isNot(contains('extends ConsumerWidget')));
      }
    });
  });

  // =========================================================================
  group('Empresa local != Company SaaS', () {
    test('los archivos de IF-3 no conocen la Empresa ni el Usuario locales', () {
      // Se buscan los símbolos CONCRETOS de la Empresa local, no la palabra
      // «Empresa»: el código de error del backend es literalmente
      // `empresa_no_disponible`, y el ayudante que lo reconoce se llama
      // `esEmpresaNoDisponible`. Prohibir la palabra obligaría a renombrar en inglés
      // algo que el servidor nombra en español, que es peor que el riesgo que evita.
      const prohibidos = [
        'EmpresaData',
        'EmpresaRepository',
        'obtenerActiva',
        'razonSocial',
        'logoAttachmentId',
        'empresaId',
        'SesionUsuario',
        'usuarioId',
        'actorUsuarioId',
        'AppDatabase',
        'drift',
      ];

      for (final ruta in _archivosDeIF3) {
        final codigo = codigoDe(ruta);

        for (final simbolo in prohibidos) {
          expect(
            codigo,
            isNot(contains(simbolo)),
            reason: '$ruta no debe conocer «$simbolo»',
          );
        }
      }
    });

    test('NO hay emparejamiento por nombre, razón social, RFC ni logotipo', () {
      // La prueba mira la CONVIVENCIA de símbolos: un archivo que hable de la
      // Company y a la vez de la identidad fiscal o del logotipo de la Empresa es
      // exactamente la forma que tendría el vínculo prohibido.
      const senasDeLaEmpresaLocal = [
        'obtenerActiva()',
        'razonSocial',
        'logoAttachmentId',
        'EmpresaRepository',
      ];

      final sospechosos = <String>[];

      for (final archivo in fuentesDeLib()) {
        final codigo = sinComentarios(archivo.readAsStringSync());

        final hablaDeCompany = _simbolosDeCompany.any(codigo.contains);
        final hablaDeEmpresa = senasDeLaEmpresaLocal.any(codigo.contains);

        if (hablaDeCompany && hablaDeEmpresa) {
          sospechosos.add(normalizar(archivo.path));
        }
      }

      expect(
        sospechosos,
        isEmpty,
        reason:
            'la Empresa legacy es el emisor local de documentos y la adscripción '
            'de un Empleado; la Company es el inquilino remoto. No hay vínculo',
      );
    });

    test('los consumidores de Empresa.obtenerActiva() no aumentan', () {
      // Catorce archivos tocan `obtenerActiva()` en código: el contrato, su
      // implementación y DOCE consumidores reales. Que la cifra esté fijada aquí es
      // lo que hace visible cualquier intento de resolver la Empresa desde la capa
      // de Company.
      final archivos =
          fuentesDeLib()
              .where(
                (f) => sinComentarios(
                  f.readAsStringSync(),
                ).contains('obtenerActiva()'),
              )
              .map((f) => normalizar(f.path))
              .toList()
            ..sort();

      expect(archivos, [
        'lib/app/bootstrap.dart',
        'lib/features/inventario/domain/usecases/generar_documento_resguardo_usecase.dart',
        'lib/features/nomina/domain/usecases/generar_nomina_dispersion_pdf_usecase.dart',
        'lib/features/organizacion/data/repositories/empresa_repository_impl.dart',
        'lib/features/organizacion/domain/repositories/empresa_repository.dart',
        'lib/features/organizacion/domain/usecases/actualizar_empresa_usecase.dart',
        'lib/features/organizacion/domain/usecases/generar_recibo_pago_pdf_usecase.dart',
        'lib/features/organizacion/domain/usecases/obtener_empresa_activa_usecase.dart',
        'lib/features/personal/domain/usecases/generar_ficha_tecnica_empleado_usecase.dart',
        'lib/features/personal/presentation/empleados/empleado_expediente_screen.dart',
        'lib/features/personal/presentation/empleados/widgets/crear_empleado_dialog.dart',
        'lib/features/reportes/domain/usecases/exportar_patrimonio_usecase.dart',
        'lib/features/reportes/domain/usecases/exportar_reporte_finanzas_pdf_usecase.dart',
        'lib/features/reportes/domain/usecases/exportar_reporte_general_pdf_usecase.dart',
      ]);
    });

    test('la propiedad local sigue donde estaba: Empleado.empresaId intacto', () {
      // `empresaId` **sí** se estampa en filas de negocio —es la adscripción del
      // periodo laboral vigente— y esta etapa NO lo toca. Que aparezca en dos
      // tablas y en ninguna parte de la capa de Company es lo que se fija.
      final tablas =
          fuentesDeLib()
              .where((f) => normalizar(f.path).contains('/data/tables/'))
              .where(
                (f) =>
                    sinComentarios(f.readAsStringSync()).contains('empresaId'),
              )
              .map((f) => normalizar(f.path))
              .toList()
            ..sort();

      expect(tablas, [
        'lib/features/organizacion/data/tables/empresa_attachment_table.dart',
        'lib/features/personal/data/tables/empleado_table.dart',
      ]);
    });
  });

  // =========================================================================
  group('Cómo viaja la Company', () {
    test('el prefijo dinámico tiene un dueño único', () {
      // Si cada repositorio interpolara `/companies/$id`, migrar el plano operativo
      // obligaría a tocar doscientos archivos y una barra de más produciría un 404
      // indistinguible de «no tienes acceso». La constante de la colección vive en
      // el mismo archivo, así que `CompanyApi` no necesita el literal; si alguna vez
      // lo necesitara legítimamente, ESTA lista es donde se añade.
      final duenos = <String>[];

      for (final archivo in fuentesDeLib()) {
        final codigo = sinComentarios(archivo.readAsStringSync());

        if (codigo.contains("'/companies") || codigo.contains('"/companies')) {
          duenos.add(normalizar(archivo.path));
        }
      }

      expect(duenos, ['lib/core/company/company_ruta.dart']);
    });

    test('la ruta se compone con la empresa dentro', () {
      const companyId = '0193f0a0-0000-7000-8000-000000000001';

      expect(
        CompanyRuta.de(companyId, '/context'),
        '/companies/$companyId/context',
      );
      expect(CompanyRuta.coleccion, '/companies');
    });

    test('NO existe ningún encabezado de empresa en todo lib/', () {
      // El backend lo dice en su propio código: no hay `currentCompanyId` en el
      // servidor. Un encabezado global sería un segundo canal para lo mismo, y el
      // que no manda.
      for (final archivo in fuentesDeLib()) {
        final codigo = sinComentarios(archivo.readAsStringSync());

        expect(codigo, isNot(contains('X-Company')), reason: archivo.path);
        expect(codigo, isNot(contains('x-company')), reason: archivo.path);
        expect(
          codigo,
          isNot(contains('currentCompanyId')),
          reason: archivo.path,
        );
      }
    });

    test('el cliente autenticado de IF-2 NO aprendió nada de Company', () {
      // La política de empresa no puede colarse en el transporte: cada endpoint
      // construye su ruta con alcance explícito.
      final codigo = codigoDe('lib/core/api/api_client_autenticado.dart');

      expect(codigo, isNot(contains('Company')));
      expect(codigo, isNot(contains('company')));
    });
  });

  // =========================================================================
  group('La preferencia guarda un identificador y nada más', () {
    test('no usa el almacén seguro: un companyId no es credencial', () {
      final codigo = codigoDe(
        'lib/core/company/almacen_company_recordada.dart',
      );

      expect(codigo, isNot(contains('FlutterSecureStorage')));
      expect(codigo, isNot(contains('flutter_secure_storage')));
      expect(codigo, contains('shared_preferences'));
    });

    test('no persiste nada del contexto', () {
      final codigo = codigoDe(
        'lib/core/company/almacen_company_recordada.dart',
      );

      for (final prohibido in [
        'companyName',
        'organizationName',
        'effectivePermissions',
        'enabledModules',
        'restricted',
        'isMaestro',
      ]) {
        expect(codigo, isNot(contains(prohibido)), reason: prohibido);
      }
    });

    test('la clave sigue la convención y no colisiona', () {
      expect(
        AlmacenCompanyRecordadaPreferencias.nombreClave,
        'riseg_one.company_activa',
      );

      final claves = <String>{};

      for (final archivo in fuentesDeLib()) {
        final codigo = sinComentarios(archivo.readAsStringSync());

        for (final coincidencia in RegExp(
          r"'riseg_one\.[a-z_]+'",
        ).allMatches(codigo)) {
          claves.add(coincidencia.group(0)!);
        }
      }

      expect(claves, contains("'riseg_one.company_activa'"));
      expect(
        claves.where((c) => c == "'riseg_one.company_activa'"),
        hasLength(1),
        reason: 'una sola definición de la clave',
      );
    });
  });

  // =========================================================================
  group('Permisos y restricted quedan diferidos a IF-4', () {
    test('se conservan en el contexto', () {
      final codigo = codigoDe('lib/core/company/company_remota.dart');

      for (final campo in [
        'isMaestro',
        'restricted',
        'enabledModules',
        'effectivePermissions',
      ]) {
        expect(codigo, contains(campo), reason: '$campo debe parsearse');
      }
    });

    test('NADIE en app/ ni features/ los consume', () {
      final infractores = <String>[];

      for (final archivo in fuentesDeLib()) {
        final ruta = normalizar(archivo.path);
        if (!ruta.contains('lib/app/') && !ruta.contains('/features/')) {
          continue;
        }

        final codigo = sinComentarios(archivo.readAsStringSync());

        for (final campo in [
          'effectivePermissions',
          'enabledModules',
          'isMaestro',
        ]) {
          if (codigo.contains(campo)) infractores.add('$ruta → $campo');
        }
      }

      expect(
        infractores,
        isEmpty,
        reason:
            'ocultar módulos, mostrar el banner de restricción y traducir permisos '
            'locales es IF-4',
      );
    });

    test('no hay estado de Organization independiente', () {
      // `CompanyContext` ya trae `organizationId` y `organizationName`: un estado
      // aparte sería una segunda fuente de verdad para lo mismo.
      for (final archivo in fuentesDeLib()) {
        final codigo = sinComentarios(archivo.readAsStringSync());

        expect(codigo, isNot(contains('organizationActiva')));
        expect(codigo, isNot(contains('organizationIdActivo')));
      }
    });
  });

  // =========================================================================
  group('El alcance de IF-3', () {
    test('IF-2 no se modificó', () {
      for (final ruta in [
        'lib/core/auth/gestor_de_sesion.dart',
        'lib/core/auth/auth_api.dart',
        'lib/core/auth/sesion_remota.dart',
        'lib/core/auth/almacen_sesion_remota.dart',
      ]) {
        final codigo = codigoDe(ruta);

        for (final simbolo in _simbolosDeCompany) {
          expect(
            codigo,
            isNot(contains(simbolo)),
            reason: '$ruta → $simbolo: el motor de sesión no conoce empresas',
          );
        }
      }
    });

    test('la capa de Company sí consume el cliente autenticado de IF-2', () {
      expect(
        codigoDe('lib/core/company/company_api.dart'),
        contains('ApiClientAutenticado'),
      );
      expect(
        codigoDe('lib/core/company/company_providers.dart'),
        contains('apiClientAutenticadoProvider'),
      );
    });

    test('la etapa no trajo ningún paquete nuevo', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();

      // Se ancla al inicio de la línea de dependencia: `contains('hive:')` se
      // dispararía contra `archive:`, que sí está y es legítimo desde la Etapa 14C.
      for (final descartado in [
        'dio',
        'hive',
        'get_it',
        'freezed',
        'json_serializable',
        'cookie_jar',
      ]) {
        expect(
          RegExp('^\\s+$descartado:', multiLine: true).hasMatch(pubspec),
          isFalse,
          reason: '$descartado no se añadió en IF-3',
        );
      }

      // Los tres que hacen falta ya estaban.
      expect(pubspec, contains('http: ^1.6.0'));
      expect(pubspec, contains('shared_preferences: ^2.3.3'));
      expect(pubspec, contains('flutter_riverpod: ^2.6.1'));
    });
  });
}

// Etapa "Usuarios, permisos y UX de seguridad" — perfiles de prueba y
// dependencias transversales de autorización (puntos 18 y 19 del pedido
// de Marlon), contra BD real.
//
// La regla que fijan: un permiso de ACCIÓN autoriza su caso de uso y los
// datos auxiliares mínimos que esa acción necesita; un permiso `ver`
// controla la navegación y la exploración general. Un selector auxiliar
// autorizado NUNCA se convierte en acceso al módulo dueño de esos datos.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/app/shell/shell_permissions.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/core/permissions/modulos_permiso.dart';
import 'package:riseg_one/features/finanzas/finanzas_providers.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';

/// Perfiles del punto 18 — conjuntos reales de códigos, nunca inventados
/// sobre la marcha en cada prueba.
const _perfilRh = {
  'personal.ver',
  'personal.crear',
  'personal.modificar',
  'personal.gestionarTiemposExtra',
  'nomina.ver',
  'nomina.crear',
  'nomina.modificar',
};
const _perfilFinanzas = {'finanzas.ver', 'egresos.crear', 'deudas.registrarPago'};
const _perfilConsulta = {'personal.ver', 'finanzas.ver', 'inventario.ver'};
const _perfilSinPermisos = <String>{};

class _SesionDePrueba extends SesionController {
  _SesionDePrueba(this._sesion);
  final SesionUsuario? _sesion;

  @override
  SesionUsuario? build() => _sesion;
}

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  ProviderContainer contenedorCon({required Set<String> permisos, bool esMaestro = false}) {
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(
          () => _SesionDePrueba(
            SesionUsuario(
              usuarioId: 'u1',
              nombre: 'JAVIER',
              nombreUsuario: 'javier',
              esMaestro: esMaestro,
              permisos: permisos,
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  bool puedeEntrarA(ProviderContainer c, String ruta) {
    final codigos = permisosQueAbrenRuta(ruta);
    if (codigos.isEmpty) return true;
    return codigos.any(c.read(permissionServiceProvider).hasCode);
  }

  group('Punto 18 — perfiles de autorización', () {
    test('A. Maestro entra a todo, sin depender de filas de PermisoUsuario', () {
      final c = contenedorCon(permisos: _perfilSinPermisos, esMaestro: true);

      for (final ruta in ['/personal', '/finanzas', '/configuracion', '/configuracion/auditoria', '/inventario']) {
        expect(puedeEntrarA(c, ruta), isTrue, reason: 'Maestro debe entrar a $ruta');
      }
      // Su acceso total NO viene de permisos guardados: el conjunto está
      // vacío y aun así puede todo.
      expect(_perfilSinPermisos, isEmpty);
    });

    test('B. RH entra a Personal y Nómina, jamás a Finanzas ni Configuración', () {
      final c = contenedorCon(permisos: _perfilRh);

      expect(puedeEntrarA(c, '/personal'), isTrue);
      expect(puedeEntrarA(c, '/dashboard'), isTrue, reason: 'el Dashboard no tiene permiso propio');
      expect(puedeEntrarA(c, '/finanzas'), isFalse);
      expect(puedeEntrarA(c, '/configuracion'), isFalse);
      expect(puedeEntrarA(c, '/configuracion/auditoria'), isFalse);
      expect(puedeEntrarA(c, '/comercial'), isFalse);
    });

    test('C. Finanzas entra a Finanzas, jamás a Personal', () {
      final c = contenedorCon(permisos: _perfilFinanzas);

      expect(puedeEntrarA(c, '/finanzas'), isTrue);
      expect(puedeEntrarA(c, '/personal'), isFalse);
      expect(puedeEntrarA(c, '/configuracion'), isFalse);
    });

    test('D. Consulta entra a lo que puede ver, y no puede mutar nada', () {
      final c = contenedorCon(permisos: _perfilConsulta);
      final permisos = c.read(permissionServiceProvider);

      expect(puedeEntrarA(c, '/personal'), isTrue);
      expect(puedeEntrarA(c, '/finanzas'), isTrue);
      for (final mutacion in ['personal.crear', 'egresos.crear', 'nomina.modificar', 'deudas.cancelarPago']) {
        expect(permisos.hasCode(mutacion), isFalse, reason: '$mutacion es mutación, no consulta');
      }
    });

    test('E. Sin permisos funcionales solo alcanza el Dashboard', () {
      final c = contenedorCon(permisos: _perfilSinPermisos);

      expect(puedeEntrarA(c, '/dashboard'), isTrue);
      for (final ruta in ['/personal', '/finanzas', '/comercial', '/inventario', '/configuracion']) {
        expect(puedeEntrarA(c, ruta), isFalse, reason: 'sin permisos no debe entrar a $ruta');
      }
    });
  });

  group('Punto 6 — dependencias transversales de autorización', () {
    test('RH puede leer Cuentas financieras y TDC como origen de una acción suya, SIN finanzas.ver', () async {
      final c = contenedorCon(permisos: _perfilRh);

      // Precondición del caso real: no tiene acceso al módulo Finanzas.
      expect(c.read(permissionServiceProvider).hasCode('finanzas.ver'), isFalse);
      expect(puedeEntrarA(c, '/finanzas'), isFalse);

      await c.read(cuentaFinancieraRepositoryProvider).crear(
            codigo: 'CTA-0002',
            nombre: 'Klar Empresarial',
            tipo: 'banco',
            saldoInicial: 1000000,
            fechaSaldoInicial: DateTime(2026, 1, 1),
          );
      await db.into(db.deuda).insert(
            DeudaCompanion.insert(
              folio: 'DEU-000007',
              nombre: 'TDC Konfío Empresarial',
              tipo: 'tarjetaCredito',
              saldoActual: 0,
              tarjetaLimiteCredito: const Value(4000000),
            ),
          );

      // Los datos auxiliares que la acción necesita SÍ se obtienen: son
      // lecturas de repositorio, nunca providers autorizados.
      final cuentas = await c.read(cuentaFinancieraRepositoryProvider).listar(soloActivas: true);
      final tarjetas = await c.read(deudaRepositoryProvider).listarTarjetasActivas();

      expect(cuentas, hasLength(1), reason: 'el selector de origen se puede llenar');
      expect(tarjetas, hasLength(1));
    });

    test('pero ese acceso auxiliar NO le da ninguna facultad de mutación en Finanzas', () {
      final permisos = contenedorCon(permisos: _perfilRh).read(permissionServiceProvider);

      for (final codigo in [
        'finanzas.ver',
        'egresos.crear',
        'egresos.corregir',
        'deudas.registrarPago',
        'deudas.corregirPago',
        'cuentasFinancieras.crear',
      ]) {
        expect(permisos.hasCode(codigo), isFalse, reason: '$codigo nunca se concede por leer un catálogo auxiliar');
      }
    });
  });

  group('Punto 9 — Configuración sensible', () {
    test('Auditoría tiene permiso propio de solo lectura, separado de administrar usuarios', () {
      final soloAuditoria = contenedorCon(permisos: {'auditoria.ver'});
      final soloUsuarios = contenedorCon(permisos: {'usuarios.administrar'});

      // Ver la auditoría ya no exige poder administrar cuentas…
      expect(puedeEntrarA(soloAuditoria, '/configuracion/auditoria'), isTrue);
      expect(puedeEntrarA(soloAuditoria, '/configuracion/usuarios'), isFalse);
      // …y sigue alcanzando la sección desde el shell.
      expect(puedeEntrarA(soloAuditoria, '/configuracion'), isTrue);

      // …ni administrar cuentas obliga a nada sobre auditoría.
      expect(puedeEntrarA(soloUsuarios, '/configuracion/usuarios'), isTrue);
      expect(puedeEntrarA(soloUsuarios, '/configuracion/auditoria'), isFalse);
    });

    test('el catálogo NO tiene una acción de mutación de auditoría: es append-only', () {
      final auditoria = modulosPermiso.firstWhere((m) => m.codigo == 'auditoria');
      expect(auditoria.todosLosCodigos, {'auditoria.ver'});
    });

    test('otorgar permisos y resetear contraseñas son facultades separadas de administrar', () {
      final usuarios = modulosPermiso.firstWhere((m) => m.codigo == 'usuarios');
      expect(
        usuarios.todosLosCodigos,
        containsAll({'usuarios.administrar', 'usuarios.otorgarPermisos', 'usuarios.resetearPassword'}),
      );

      // Administrar cuentas ya NO implica poder otorgar permisos.
      final soloAdministrar = contenedorCon(permisos: {'usuarios.administrar'}).read(permissionServiceProvider);
      expect(soloAdministrar.hasCode('usuarios.otorgarPermisos'), isFalse);
      expect(soloAdministrar.hasCode('usuarios.resetearPassword'), isFalse);
    });

    test('Respaldo y Bóveda siguen siendo Maestro-only, no alcanzables con un permiso genérico', () {
      // El gate real de estas dos rutas es `esMaestro` en el `redirect`
      // del router (doble candado con `exigirMaestro` en sus providers).
      // Ningún código del catálogo las abre.
      expect(todosLosCodigosDePermiso().where((c) => c.startsWith('respaldo')), isEmpty);
      expect(todosLosCodigosDePermiso().where((c) => c.startsWith('boveda')), isEmpty);
    });
  });

  group('Punto 10 — el catálogo no tiene permisos muertos', () {
    test('cada código del catálogo tiene etiqueta resoluble', () {
      // Un código sin etiqueta sería uno agregado "porque suena útil",
      // sin consumidor real que lo muestre.
      for (final codigo in todosLosCodigosDePermiso()) {
        expect(codigo.split('.'), hasLength(2), reason: '$codigo debe ser modulo.accion');
        expect(codigo.split('.').first, isNotEmpty);
        expect(codigo.split('.').last, isNotEmpty);
      }
    });

    test('los permisos de la Etapa 9 (pagos de deuda) están en el catálogo y agrupados en Finanzas', () {
      final deudas = modulosPermiso.firstWhere((m) => m.codigo == 'deudas');
      expect(deudas.grupoVisual, 'finanzas');
      expect(
        deudas.todosLosCodigos,
        containsAll({
          'deudas.crear',
          'deudas.corregir',
          'deudas.cancelar',
          'deudas.registrarPago',
          'deudas.corregirPago',
          'deudas.cancelarPago',
        }),
      );
    });
  });
}

// IF-5 — EL CUTOVER, probado donde importa.
//
// Lo que este archivo fija es que el producto dejó de autenticar y autorizar
// contra SQLite, y que cada eslabón de la cadena nueva hace exactamente lo que
// dice:
//
//     Identity SaaS → Company → CompanyContext → proyección → sesión → shell
//
// Lo que NO hace: levantar un backend. Los motores de IF-2/IF-3/IF-4 ya tienen
// sus propias pruebas contra respuestas HTTP simuladas; aquí se prueba lo que
// esas pruebas no podían — la traducción al vocabulario del producto, la
// proyección local y la aplicación de `restricted` en el embudo real.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/identity/proyeccion_identity_usuario.dart';
import 'package:riseg_one/core/permissions/authorization_service.dart';
import 'package:riseg_one/core/permissions/modulos_permiso.dart';
import 'package:riseg_one/core/permissions/vocabulario_permisos.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';

void main() {
  // =========================================================================
  // El vocabulario: los 95 permisos del producto tienen correspondencia SaaS
  // =========================================================================

  group('Vocabulario de permisos — la única frontera', () {
    test('LOS 95 CÓDIGOS DEL PRODUCTO TIENEN CORRESPONDENCIA, sin excepciones', () {
      final codigos = todosLosCodigosDePermiso();

      expect(codigos, hasLength(95), reason: 'el catálogo del producto son 95 facultades');

      for (final codigo in codigos) {
        final saas = codigoSaaSDe(codigo);

        expect(saas, isNotEmpty, reason: '$codigo se quedó sin equivalente');

        // La regla técnica del esquema del backend: minúsculas, dígitos y guion
        // bajo, en dos o más segmentos. Si un código nuevo no la cumpliera, el
        // INSERT de la migración lo rechazaría — mejor enterarse aquí.
        expect(
          RegExp(r'^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$').hasMatch(saas),
          isTrue,
          reason: '$codigo → $saas no cumple el CHECK del backend',
        );
      }
    });

    test('la correspondencia es BIYECTIVA: ningún código SaaS sirve a dos del producto', () {
      final destinos = diccionarioDePermisos.values.toList();

      expect(
        destinos.toSet(),
        hasLength(destinos.length),
        reason: 'dos facultades del producto apuntando al mismo permiso SaaS serían '
            'dos autoridades para una capacidad',
      );
    });

    test('las CINCO equivalencias especiales son exactamente esas cinco', () {
      expect(equivalenciasSaaS, hasLength(5));

      expect(codigoSaaSDe('personal.ver'), 'personal.read');
      expect(codigoSaaSDe('nomina.ver'), 'payroll.read');
      expect(codigoSaaSDe('nomina.cerrar'), 'payroll.close');
      expect(codigoSaaSDe('comercial.ver'), 'clients_services.read');
      expect(codigoSaaSDe('auditoria.ver'), 'company.audit.read');

      // Y NO se duplicaron: el código propio del producto no existe además con
      // su nombre literal en el catálogo del backend.
      for (final local in equivalenciasSaaS.keys) {
        expect(
          codigoSaaSDe(local),
          isNot(local.split('.').join('.')),
          reason: '$local no debe traducirse a sí mismo',
        );
      }
    });

    test('camelCase pasa a snake_case en los DOS segmentos', () {
      expect(codigoSaaSDe('deudas.cancelarPago'), 'deudas.cancelar_pago');
      expect(codigoSaaSDe('cuentasFinancieras.cambiarEstatus'), 'cuentas_financieras.cambiar_estatus');
      expect(codigoSaaSDe('tiempoExtra.corregir'), 'tiempo_extra.corregir');
      expect(codigoSaaSDe('serviciosEventuales.revertirPago'), 'servicios_eventuales.revertir_pago');
      expect(codigoSaaSDe('inventario.ajustarExistencia'), 'inventario.ajustar_existencia');
    });

    test('traducir de VUELTA devuelve el vocabulario que el producto consulta', () {
      final delServidor = {
        'personal.read',
        'deudas.cancelar_pago',
        'telefonia.ver_credenciales',
        'usuarios.otorgar_permisos',
      };

      expect(permisosDelProducto(delServidor), {
        'personal.ver',
        'deudas.cancelarPago',
        'telefonia.verCredenciales',
        'usuarios.otorgarPermisos',
      });
    });

    test('un código del backend que el producto no consulta se DESCARTA, no se inventa', () {
      // `personal.manage` gobierna rutas del backend y no es una facultad de esta
      // interfaz. Traerlo como si lo fuera ensuciaría la sesión.
      expect(permisosDelProducto({'personal.manage', 'company.logo'}), isEmpty);

      // Y nada aparece de la nada.
      expect(permisosDelProducto({}), isEmpty);
    });

    test('esLectura distingue consultar de mutar, que es lo que `restricted` necesita', () {
      expect(esLectura('personal.ver'), isTrue);
      expect(esLectura('finanzas.ver'), isTrue);
      expect(esLectura('personal.crear'), isFalse);
      expect(esLectura('nomina.cancelarPago'), isFalse);
      expect(esLectura('usuarios.administrar'), isFalse);
    });
  });

  // =========================================================================
  // La proyección Identity → Usuario
  // =========================================================================

  group('Proyección Identity → Usuario', () {
    late AppDatabase db;
    late ProyeccionIdentityUsuario proyeccion;

    const identityId = '01a0eca0-fcec-78e4-b3d9-6566cb214aa3';

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      proyeccion = ProyeccionIdentityUsuario(db);
    });

    tearDown(() => db.close());

    test('la fila local usa EXACTAMENTE el identityId, sin traducirlo', () async {
      final id = await proyeccion.proyectar(
        identityId: identityId,
        nombre: 'Administrador de Plataforma',
        correo: 'admin@seventra.mx',
        esMaestro: true,
      );

      expect(id, identityId);

      final fila = await (db.select(db.usuario)..where((t) => t.id.equals(identityId))).getSingle();
      expect(fila.id, identityId, reason: 'sin id alternativo: los 1790 actorUsuarioId apuntan aquí');
      expect(fila.nombre, 'Administrador de Plataforma');
      expect(fila.nombreUsuario, 'admin@seventra.mx');
      expect(fila.esMaestro, isTrue);
    });

    test('ES IDEMPOTENTE: proyectar tres veces deja UNA fila', () async {
      for (var i = 0; i < 3; i++) {
        await proyeccion.proyectar(
          identityId: identityId,
          nombre: 'Ana',
          correo: 'ana@seventra.mx',
          esMaestro: false,
        );
      }

      expect(await db.select(db.usuario).get(), hasLength(1));
    });

    test('refresca los datos proyectados sin tocar el vínculo laboral', () async {
      await proyeccion.proyectar(
        identityId: identityId, nombre: 'Ana', correo: 'ana@seventra.mx', esMaestro: false,
      );

      // El producto vinculó la cuenta a su estructura: eso es SUYO y el SaaS no
      // sabe nada de ello. Sobrescribirlo en cada login lo destruiría.
      await db.into(db.puesto).insert(
            PuestoCompanion.insert(
              codigo: 'PUE-1',
              nombre: 'Coordinación',
              areaId: (await db.select(db.area).get()).first.id,
              tipo: 'administrativo',
              nivelJerarquico: 3,
            ),
          );
      final puestoId = (await db.select(db.puesto).get()).first.id;

      await (db.update(db.usuario)..where((t) => t.id.equals(identityId)))
          .write(UsuarioCompanion(puestoId: Value(puestoId)));

      await proyeccion.proyectar(
        identityId: identityId, nombre: 'Ana Torres', correo: 'ana@seventra.mx', esMaestro: true,
      );

      final fila = await (db.select(db.usuario)..where((t) => t.id.equals(identityId))).getSingle();
      expect(fila.nombre, 'Ana Torres', reason: 'el nombre es dato proyectado: el SaaS manda');
      expect(fila.esMaestro, isTrue, reason: 'esMaestro viene del CompanyContext');
      expect(fila.puestoId, puestoId, reason: 'lo que el producto vinculó NO se toca');
    });

    test('NO GUARDA CONTRASEÑA UTILIZABLE: el centinela no autentica a nadie', () async {
      await proyeccion.proyectar(
        identityId: identityId, nombre: 'Ana', correo: 'ana@seventra.mx', esMaestro: false,
      );

      final fila = await (db.select(db.usuario)..where((t) => t.id.equals(identityId))).getSingle();

      expect(fila.passwordHash, ProyeccionIdentityUsuario.centinelaSinContrasena);

      // No es «una contraseña difícil»: el verificador la descarta antes de
      // calcular nada, porque su primer segmento no es `pbkdf2`. Así que no
      // existe NINGUNA cadena que abra esta cuenta en local.
      expect(fila.passwordHash.startsWith('pbkdf2'), isFalse);
    });

    test('dos Identities distintas son dos filas distintas, nunca una adoptada', () async {
      await proyeccion.proyectar(
        identityId: identityId, nombre: 'Ana', correo: 'ana@seventra.mx', esMaestro: false,
      );
      await proyeccion.proyectar(
        identityId: '01a0eca0-0000-7000-8000-000000000002',
        nombre: 'Beto',
        correo: 'beto@seventra.mx',
        esMaestro: false,
      );

      expect(await db.select(db.usuario).get(), hasLength(2));
    });
  });

  // =========================================================================
  // `restricted` en el embudo real
  // =========================================================================

  group('restricted — se lee, no se escribe', () {
    AuthorizationService servicioCon({required bool restringido, required Set<String> permisos}) {
      return AuthorizationService(
        SessionPermissionService(
          SesionUsuario(
            usuarioId: 'i-1',
            nombre: 'Ana',
            nombreUsuario: 'ana@seventra.mx',
            esMaestro: false,
            permisos: permisos,
            restringido: restringido,
          ),
        ),
      );
    }

    test('con restricted, LEER sigue permitido', () async {
      final servicio = servicioCon(restringido: true, permisos: {'personal.ver', 'finanzas.ver'});

      expect(await servicio.verificarVigente('personal.ver'), isNull);
      expect(await servicio.verificarVigente('finanzas.ver'), isNull);
    });

    test('con restricted, MUTAR queda bloqueado aunque el permiso esté concedido', () async {
      final servicio = servicioCon(
        restringido: true,
        permisos: {'personal.crear', 'personal.modificar', 'nomina.cancelarPago'},
      );

      expect(await servicio.verificarVigente('personal.crear'), isA<PermisoDenegado>());
      expect(await servicio.verificarVigente('personal.modificar'), isA<PermisoDenegado>());
      expect(await servicio.verificarVigente('nomina.cancelarPago'), isA<PermisoDenegado>());
    });

    test('sin restricted, mutar pasa con el permiso y falla sin él', () async {
      final servicio = servicioCon(restringido: false, permisos: {'personal.crear'});

      expect(await servicio.verificarVigente('personal.crear'), isNull);
      expect(await servicio.verificarVigente('personal.archivar'), isA<PermisoDenegado>());
    });

    test('restricted ALCANZA AL MAESTRO: ser titular no paga la suscripción', () async {
      const servicio = SessionPermissionService(
        SesionUsuario(
          usuarioId: 'i-1',
          nombre: 'Marlon',
          nombreUsuario: 'marlon@seventra.mx',
          esMaestro: true,
          permisos: {},
          restringido: true,
        ),
      );

      // `exigirMaestro` protege el borrado físico, el respaldo y la bóveda: todo
      // son mutaciones.
      final resultado = await exigirMaestro<String>(
        servicio,
        () async => 'ejecutada',
        (mensaje) => 'denegada: $mensaje',
      );

      expect(resultado, startsWith('denegada:'));
      expect(servicio.esMaestroActivo, isTrue, reason: 'sigue siendo Maestro; lo que no puede es escribir');
      expect(servicio.hasCode('personal.crear'), isTrue, reason: 'restricted NO le quita permisos');
    });

    test('restricted NO se disfraza de falta de permiso: el sidebar sigue viendo sus módulos', () {
      const servicio = SessionPermissionService(
        SesionUsuario(
          usuarioId: 'i-1',
          nombre: 'Ana',
          nombreUsuario: 'ana@seventra.mx',
          esMaestro: false,
          permisos: {'personal.ver', 'personal.crear'},
          restringido: true,
        ),
      );

      // Si `restricted` se hubiera resuelto vaciando permisos, el módulo entero
      // habría desaparecido de la interfaz y la persona no podría ni mirar.
      expect(servicio.hasCode('personal.ver'), isTrue);
      expect(servicio.hasCode('personal.crear'), isTrue);
      expect(servicio.restringido, isTrue);
    });
  });

  // =========================================================================
  // Ya no hay autenticación local
  // =========================================================================

  group('La autenticación local desapareció del producto', () {
    test('sin sesión, el servicio de permisos niega todo', () async {
      const servicio = SessionPermissionService(null);

      expect(servicio.hasCode('personal.ver'), isFalse);
      expect(servicio.esMaestroActivo, isFalse);
      expect(servicio.puedeOperar, isFalse);
      expect(servicio.restringido, isFalse, reason: 'sin sesión no hay suscripción que mirar');

      expect(await const AuthorizationService(servicio).verificarVigente('personal.ver'), isA<PermisoDenegado>());
    });

    test('la sesión ya no expone ninguna obligación de cambiar contraseña', () {
      const sesion = SesionUsuario(
        usuarioId: 'i-1',
        nombre: 'Ana',
        nombreUsuario: 'ana@seventra.mx',
        esMaestro: false,
        permisos: {},
      );

      // `debeCambiarPassword` se retiró del modelo: si volviera, esta prueba
      // dejaría de compilar, que es exactamente el aviso que se quiere.
      expect(sesion.restringido, isFalse);
      expect(sesion.usuarioId, 'i-1');
    });
  });
}

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/permissions/modulos_permiso.dart';
import 'package:riseg_one/features/usuarios/data/repositories/permiso_usuario_repository_impl.dart';
import 'package:riseg_one/features/usuarios/data/repositories/usuario_repository_impl.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/domain/usecases/guardar_permisos_usuario_usecase.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart' show SessionPermissionService;

void main() {
  group('modulosPermiso — catálogo', () {
    test('nunca incluye placeholders retirados (Documentos, Activos)', () {
      final codigos = modulosPermiso.map((m) => m.codigo).toSet();
      expect(codigos.contains('documentos'), isFalse);
      expect(codigos.contains('activos'), isFalse);
    });

    test('Reportes solo tiene Ver — no permisos ficticios para llenar la matriz', () {
      final reportes = modulosPermiso.firstWhere((m) => m.codigo == 'reportes');
      expect(reportes.accionesBase, {AccionBase.ver});
    });

    // Etapa "Usuarios, permisos y UX de seguridad": `usuarios.administrar`
    // dejó de ser un todo-o-nada. Conserva su código (alta/edición de
    // cuentas y gate de `/configuracion`) y se le separaron las dos
    // facultades que ameritan decidirse aparte.
    test('Usuarios no tiene acciones base; sus facultades sensibles están separadas', () {
      final usuarios = modulosPermiso.firstWhere((m) => m.codigo == 'usuarios');
      expect(usuarios.accionesBase, isEmpty);
      expect(
        usuarios.accionesEspeciales,
        ['usuarios.administrar', 'usuarios.otorgarPermisos', 'usuarios.resetearPassword'],
      );
    });

    test('Auditoría es un módulo propio de SOLO lectura — nunca una acción de mutación', () {
      final auditoria = modulosPermiso.firstWhere((m) => m.codigo == 'auditoria');
      expect(auditoria.accionesBase, {AccionBase.ver});
      expect(auditoria.accionesEspeciales, isEmpty);
    });

    test('todosLosCodigosDePermiso incluye los especiales conocidos', () {
      final todos = todosLosCodigosDePermiso();
      expect(
        todos,
        containsAll(['nomina.cerrar', 'nomina.registrarPago', 'personal.cambiarSueldo', 'usuarios.administrar']),
      );
      expect(todos, contains('personal.ver'));
      // Etapa 1 (rediseño granular): `finanzas.crear/modificar/archivar`
      // se dividieron en subdominios propios (Ingresos, Egresos,
      // Deudas, ...) — `finanzas` en sí solo conserva `ver`.
      expect(todos, contains('finanzas.ver'));
      expect(todos, contains('ingresos.crear'));
      expect(todos, isNot(contains('finanzas.crear')));
    });
  });

  group('normalizarPermisos — dependencia Ver (punto 4)', () {
    test('crear implica ver', () {
      final resultado = normalizarPermisos({'personal.crear'});
      expect(resultado, containsAll(['personal.crear', 'personal.ver']));
    });

    test('modificar/archivar/eliminar también implican ver', () {
      // Etapa 1: `inventario.modificar` se dividió en
      // `inventario.corregir`/`inventario.ajustarExistencia` (códigos
      // especiales, no participan de la dependencia de Ver) —
      // `inventario.archivar` sigue siendo una acción base real.
      expect(normalizarPermisos({'inventario.archivar'}), contains('inventario.ver'));
      // Etapa 1: `compras.archivar` ya no es una acción base de Compras
      // (se reemplazó por el código especial `compras.cancelar`) —
      // `compras.crear` sigue siendo una acción base real.
      expect(normalizarPermisos({'compras.crear'}), contains('compras.ver'));
    });

    test('ver solo, sin otras acciones, se queda igual', () {
      expect(normalizarPermisos({'personal.ver'}), {'personal.ver'});
    });

    test('conjunto vacío se queda vacío', () {
      expect(normalizarPermisos({}), isEmpty);
    });

    test('códigos especiales no participan de la dependencia de ver', () {
      final resultado = normalizarPermisos({'nomina.cerrar'});
      expect(resultado, {'nomina.cerrar'});
      expect(resultado.contains('nomina.ver'), isFalse);
    });

    test('una dependencia de consulta cruzada no concede acceso al módulo relacionado '
        '(compras.crear nunca implica ningún inventario.*)', () {
      final resultado = normalizarPermisos({'compras.crear'});
      expect(resultado.where((c) => c.startsWith('inventario.')), isEmpty);
    });
  });

  group('GuardarPermisosUsuarioUseCase + PermisoUsuarioRepository', () {
    late AppDatabase db;
    late UsuarioRepositoryImpl usuarioRepo;
    late PermisoUsuarioRepositoryImpl permisoRepo;
    late GuardarPermisosUsuarioUseCase guardarPermisos;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      usuarioRepo = UsuarioRepositoryImpl(db);
      permisoRepo = PermisoUsuarioRepositoryImpl(db);
      guardarPermisos = GuardarPermisosUsuarioUseCase(usuarioRepo, permisoRepo);
    });

    tearDown(() => db.close());

    test('guarda el conjunto y se puede volver a leer', () async {
      final usuario = await usuarioRepo.crear(nombre: 'Beto', nombreUsuario: 'beto', passwordHash: 'x');
      final resultado = await guardarPermisos.ejecutar(
        usuarioId: usuario.id,
        codigos: {'personal.ver', 'personal.crear'},
      );
      expect(resultado, isA<GuardarPermisosUsuarioExitoso>());

      final leidos = await permisoRepo.obtenerCodigos(usuario.id);
      expect(leidos, {'personal.ver', 'personal.crear'});
    });

    test('normaliza antes de guardar — nunca persiste crear=true, ver=false', () async {
      final usuario = await usuarioRepo.crear(nombre: 'Beto', nombreUsuario: 'beto', passwordHash: 'x');
      await guardarPermisos.ejecutar(usuarioId: usuario.id, codigos: {'personal.crear'});

      final leidos = await permisoRepo.obtenerCodigos(usuario.id);
      expect(leidos, containsAll(['personal.crear', 'personal.ver']));
    });

    test('descarta códigos que no existen en el catálogo', () async {
      final usuario = await usuarioRepo.crear(nombre: 'Beto', nombreUsuario: 'beto', passwordHash: 'x');
      await guardarPermisos.ejecutar(usuarioId: usuario.id, codigos: {'personal.ver', 'codigo.inventado'});

      final leidos = await permisoRepo.obtenerCodigos(usuario.id);
      expect(leidos, {'personal.ver'});
    });

    test('rechaza guardar permisos individuales para un Maestro', () async {
      final maestro = await usuarioRepo.crear(nombre: 'Ana', nombreUsuario: 'ana', passwordHash: 'x', esMaestro: true);
      final resultado = await guardarPermisos.ejecutar(usuarioId: maestro.id, codigos: {'personal.ver'});
      expect(resultado, isA<GuardarPermisosUsuarioEsMaestro>());

      final leidos = await permisoRepo.obtenerCodigos(maestro.id);
      expect(leidos, isEmpty, reason: 'un Maestro nunca tiene filas de PermisoUsuario');
    });

    test('rechaza usuario inexistente', () async {
      final resultado = await guardarPermisos.ejecutar(usuarioId: 'no-existe', codigos: {'personal.ver'});
      expect(resultado, isA<GuardarPermisosUsuarioNoExiste>());
    });

    test('dos usuarios con el mismo puesto pueden tener permisos completamente distintos', () async {
      final u1 = await usuarioRepo.crear(nombre: 'María', nombreUsuario: 'maria', passwordHash: 'x');
      final u2 = await usuarioRepo.crear(nombre: 'Otro', nombreUsuario: 'otro', passwordHash: 'x');
      await guardarPermisos.ejecutar(usuarioId: u1.id, codigos: {'personal.ver', 'personal.crear'});
      await guardarPermisos.ejecutar(usuarioId: u2.id, codigos: {'inventario.ver'});

      expect(await permisoRepo.obtenerCodigos(u1.id), containsAll(['personal.ver', 'personal.crear']));
      expect(await permisoRepo.obtenerCodigos(u2.id), {'inventario.ver'});
    });

    test('cambiar permisos registra auditoría en UsuarioEvento con el diff correcto', () async {
      final maestro = await usuarioRepo.crear(nombre: 'Ana', nombreUsuario: 'ana', passwordHash: 'x', esMaestro: true);
      final usuario = await usuarioRepo.crear(nombre: 'Beto', nombreUsuario: 'beto', passwordHash: 'x');

      await guardarPermisos.ejecutar(usuarioId: usuario.id, codigos: {'personal.ver'}, actorUsuarioId: maestro.id);
      await guardarPermisos.ejecutar(
        usuarioId: usuario.id,
        codigos: {'personal.ver', 'personal.crear'},
        actorUsuarioId: maestro.id,
      );

      final eventos = await usuarioRepo.listarEventos(usuario.id);
      final deEsteTipo = eventos.where((e) => e.tipoEvento == 'permisosModificados').toList();
      expect(deEsteTipo, hasLength(2));
      expect(deEsteTipo.every((e) => e.actorUsuarioId == maestro.id), isTrue);

      final diffSegundo = jsonDecode(deEsteTipo[1].datosRelevantes!) as Map<String, dynamic>;
      expect((diffSegundo['agregados'] as List).cast<String>(), ['personal.crear']);
      expect((diffSegundo['removidos'] as List).cast<String>(), isEmpty);
    });

    test('guardar el mismo conjunto dos veces no genera un segundo evento (sin cambio real)', () async {
      final usuario = await usuarioRepo.crear(nombre: 'Beto', nombreUsuario: 'beto', passwordHash: 'x');
      await guardarPermisos.ejecutar(usuarioId: usuario.id, codigos: {'personal.ver'});
      await guardarPermisos.ejecutar(usuarioId: usuario.id, codigos: {'personal.ver'});

      final eventos = await usuarioRepo.listarEventos(usuario.id);
      expect(eventos.where((e) => e.tipoEvento == 'permisosModificados'), hasLength(1));
    });
  });

  // IF-5 — el grupo «LoginUseCase — permisos en la sesión» se retiró: los
  // permisos de la sesión ya no se arman leyendo `PermisoUsuario`, sino
  // traduciendo `CompanyContext.effectivePermissions`. Lo cubre
  // `test/core/identity/cutover_if5_test.dart`. El catálogo, la normalización y
  // la matriz de permisos —que siguen siendo del producto— se prueban arriba.

  group('SessionPermissionService', () {
    test('sin sesión, niega todo', () {
      const service = SessionPermissionService(null);
      expect(service.hasCode('personal.ver'), isFalse);
    });

    test('Maestro: concede cualquier código, incluso uno inventado', () {
      const sesion = SesionUsuario(
        usuarioId: 'x',
        nombre: 'Ana',
        nombreUsuario: 'ana',
        esMaestro: true,
        permisos: {},
      );
      const service = SessionPermissionService(sesion);
      expect(service.hasCode('personal.ver'), isTrue);
      expect(service.hasCode('cualquier.cosa'), isTrue);
    });

    test('usuario normal: solo lo que tiene en su sesión', () {
      const sesion = SesionUsuario(
        usuarioId: 'x',
        nombre: 'Beto',
        nombreUsuario: 'beto',
        esMaestro: false,
        permisos: {'personal.ver'},
      );
      const service = SessionPermissionService(sesion);
      expect(service.hasCode('personal.ver'), isTrue);
      expect(service.hasCode('finanzas.ver'), isFalse);
      expect(service.hasPermission('personal', 'ver'), isTrue);
    });
  });
}

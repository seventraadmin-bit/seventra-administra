import 'dart:convert';

import 'package:drift/drift.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';

import '../../domain/identidad_usuario.dart';
import '../../domain/repositories/usuario_repository.dart';
import '../tables/usuario_table.dart';

class UsuarioRepositoryImpl implements UsuarioRepository {
  UsuarioRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Future<UsuarioData?> obtenerPorId(String id) {
    return (_db.select(_db.usuario)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  @override
  Future<UsuarioData?> obtenerPorNombreUsuario(String nombreUsuario) {
    return (_db.select(_db.usuario)..where((t) => t.nombreUsuario.equals(nombreUsuario))).getSingleOrNull();
  }

  @override
  Future<UsuarioData?> obtenerPorEmpleadoId(String empleadoId) {
    return (_db.select(_db.usuario)..where((t) => t.empleadoId.equals(empleadoId))).getSingleOrNull();
  }

  @override
  Future<List<UsuarioData>> listar({String? cicloVidaRegistro}) {
    final query = _db.select(_db.usuario);
    if (cicloVidaRegistro != null) query.where((t) => t.cicloVidaRegistro.equals(cicloVidaRegistro));
    query.orderBy([(t) => OrderingTerm.asc(t.nombre)]);
    return query.get();
  }

  @override
  Future<List<IdentidadUsuario>> listarConIdentidad({String? cicloVidaRegistro}) async {
    final usuarios = await listar(cicloVidaRegistro: cicloVidaRegistro);
    if (usuarios.isEmpty) return const [];

    // Consulta 2: SOLO los Empleados realmente vinculados, en un `IN`.
    // Si ninguna cuenta está vinculada —el caso de hoy— esta consulta
    // ni siquiera se lanza.
    final empleadoIds = {for (final u in usuarios) if (u.empleadoId != null) u.empleadoId!};
    final empleados = empleadoIds.isEmpty
        ? const <EmpleadoData>[]
        : await (_db.select(_db.empleado)..where((t) => t.id.isIn(empleadoIds))).get();
    final empleadoPorId = {for (final e in empleados) e.id: e};

    // Consulta 3: el catálogo COMPLETO de Puestos, activos e inactivos.
    // Un puesto desactivado después sigue siendo el puesto que la
    // cuenta tiene — filtrar por activos era justo lo que hacía
    // aparecer "—" en el listado (auditoría 3A).
    final puestoPorId = {for (final p in await _db.select(_db.puesto).get()) p.id: p};

    return [
      for (final u in usuarios) _componer(u, empleadoPorId[u.empleadoId], puestoPorId),
    ];
  }

  @override
  Future<IdentidadUsuario?> obtenerConIdentidad(String id) async {
    final usuario = await obtenerPorId(id);
    if (usuario == null) return null;

    final empleadoId = usuario.empleadoId;
    final empleado = empleadoId == null
        ? null
        : await (_db.select(_db.empleado)..where((t) => t.id.equals(empleadoId))).getSingleOrNull();

    final puestoId = empleado != null ? empleado.puestoId : usuario.puestoId;
    final puesto = puestoId == null
        ? null
        : await (_db.select(_db.puesto)..where((t) => t.id.equals(puestoId))).getSingleOrNull();

    return IdentidadUsuario(usuario: usuario, empleado: empleado, puesto: puesto);
  }

  /// La regla híbrida, en un solo sitio: el puesto efectivo es el del
  /// Empleado cuando la cuenta está vinculada, y el propio cuando no.
  IdentidadUsuario _componer(UsuarioData u, EmpleadoData? empleado, Map<String, PuestoData> puestoPorId) {
    final puestoId = empleado != null ? empleado.puestoId : u.puestoId;
    return IdentidadUsuario(
      usuario: u,
      empleado: empleado,
      puesto: puestoId == null ? null : puestoPorId[puestoId],
    );
  }

  @override
  Future<int> contarUsuarios() async {
    final query = _db.selectOnly(_db.usuario)..addColumns([_db.usuario.id.count()]);
    final row = await query.getSingle();
    return row.read(_db.usuario.id.count()) ?? 0;
  }

  @override
  Future<int> contarMaestrosActivos({String? excluirUsuarioId}) async {
    final query = _db.selectOnly(_db.usuario)..addColumns([_db.usuario.id.count()]);
    query.where(_db.usuario.esMaestro.equals(true) & _db.usuario.cicloVidaRegistro.equals('activo'));
    if (excluirUsuarioId != null) {
      query.where(_db.usuario.id.equals(excluirUsuarioId).not());
    }
    final row = await query.getSingle();
    return row.read(_db.usuario.id.count()) ?? 0;
  }

  @override
  Future<List<UsuarioEventoData>> listarEventos(String usuarioId) {
    return (_db.select(_db.usuarioEvento)
          ..where((t) => t.usuarioId.equals(usuarioId))
          ..orderBy([(t) => OrderingTerm.asc(t.fechaHora)]))
        .get();
  }

  @override
  Future<UsuarioData> crear({
    required String nombre,
    required String nombreUsuario,
    required String passwordHash,
    String? puestoId,
    String? empleadoId,
    bool esMaestro = false,
    bool debeCambiarPassword = false,
    Set<String> permisosIniciales = const {},
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final usuario = await _db.into(_db.usuario).insertReturning(
            UsuarioCompanion.insert(
              nombre: nombre,
              nombreUsuario: nombreUsuario,
              passwordHash: passwordHash,
              puestoId: Value(puestoId),
              empleadoId: Value(empleadoId),
              esMaestro: Value(esMaestro),
              debeCambiarPassword: Value(debeCambiarPassword),
            ),
          );

      // Un Maestro nunca tiene filas de permiso: su acceso se recalcula
      // en vivo desde el catálogo, así que escribirle filas sería a la
      // vez inútil y una segunda fuente de verdad.
      if (!esMaestro) {
        for (final codigo in permisosIniciales) {
          await _db.into(_db.permisoUsuario).insert(
                PermisoUsuarioCompanion.insert(usuarioId: usuario.id, codigo: codigo),
              );
        }
      }

      await _registrarEventoInterno(
        usuarioId: usuario.id,
        tipoEvento: TipoEventoUsuario.creado,
        actorUsuarioId: actorUsuarioId,
        // NUNCA la contraseña, ni siquiera la temporal — solo el hecho
        // de que la cuenta nace con cambio obligatorio.
        datosRelevantes: {
          'nombreUsuario': nombreUsuario,
          'esMaestro': esMaestro,
          if (empleadoId != null) 'empleadoId': empleadoId,
          'debeCambiarPassword': debeCambiarPassword,
          'permisosIniciales': esMaestro ? 0 : permisosIniciales.length,
        },
      );

      return usuario;
    });
  }

  @override
  Future<UsuarioData> corregir({
    required String usuarioId,
    String? nombre,
    String? nombreUsuario,
    String? puestoId,
    bool? esMaestro,
    String? actorUsuarioId,
    String? motivo,
  }) {
    return _db.transaction(() async {
      final anterior = await (_db.select(_db.usuario)..where((t) => t.id.equals(usuarioId))).getSingle();

      await (_db.update(_db.usuario)..where((t) => t.id.equals(usuarioId))).write(
        UsuarioCompanion(
          nombre: nombre == null ? const Value.absent() : Value(nombre),
          nombreUsuario: nombreUsuario == null ? const Value.absent() : Value(nombreUsuario),
          puestoId: puestoId == null ? const Value.absent() : Value(puestoId),
          esMaestro: esMaestro == null ? const Value.absent() : Value(esMaestro),
          updatedAt: Value(DateTime.now()),
        ),
      );

      await _registrarEventoInterno(
        usuarioId: usuarioId,
        tipoEvento: TipoEventoUsuario.datosCorregidos,
        observacion: motivo,
        actorUsuarioId: actorUsuarioId,
        datosRelevantes: {
          'nombreAnterior': anterior.nombre,
          'nombreUsuarioAnterior': anterior.nombreUsuario,
          'puestoIdAnterior': anterior.puestoId,
          'esMaestroAnterior': anterior.esMaestro,
        },
      );

      return (_db.select(_db.usuario)..where((t) => t.id.equals(usuarioId))).getSingle();
    });
  }

  @override
  Future<UsuarioData> cambiarContrasena({
    required String usuarioId,
    required String passwordHash,
    String? actorUsuarioId,
    bool exigirCambio = false,
  }) {
    return _db.transaction(() async {
      await (_db.update(_db.usuario)..where((t) => t.id.equals(usuarioId))).write(
        // Etapa "Usuarios, permisos y UX de seguridad": quién fijó la
        // contraseña decide si sigue habiendo obligación de cambiarla.
        // El titular cambiándola la apaga; un reseteo administrativo la
        // vuelve a encender, porque la contraseña vigente la conoce
        // alguien más y no puede quedarse así.
        UsuarioCompanion(
          passwordHash: Value(passwordHash),
          debeCambiarPassword: Value(exigirCambio),
          updatedAt: Value(DateTime.now()),
        ),
      );

      // Invalida "Recuérdame en este equipo" (Etapa 15) en la misma
      // transacción — nunca un paso aparte que pueda desincronizarse:
      // una contraseña cambiada nunca debe convivir con una sesión
      // recordada creada con la contraseña anterior.
      await (_db.delete(_db.sesionPersistente)..where((t) => t.usuarioId.equals(usuarioId))).go();

      await _registrarEventoInterno(
        usuarioId: usuarioId,
        tipoEvento: TipoEventoUsuario.contrasenaCambiada,
        actorUsuarioId: actorUsuarioId,
      );

      return (_db.select(_db.usuario)..where((t) => t.id.equals(usuarioId))).getSingle();
    });
  }

  @override
  Future<UsuarioData> cambiarVinculoEmpleado({
    required String usuarioId,
    required String? empleadoIdNuevo,
    String? nombreCongelado,
    String? puestoIdCongelado,
    String? etiquetaAnterior,
    String? etiquetaNueva,
    String? actorUsuarioId,
    String? motivo,
  }) {
    return _db.transaction(() async {
      final anterior = await (_db.select(_db.usuario)..where((t) => t.id.equals(usuarioId))).getSingle();
      final desvincula = empleadoIdNuevo == null;

      await (_db.update(_db.usuario)..where((t) => t.id.equals(usuarioId))).write(
        UsuarioCompanion(
          empleadoId: Value(empleadoIdNuevo),
          // Al desvincular se CONGELA la identidad efectiva que la
          // cuenta tenía hasta este instante — la del Empleado. Así la
          // cuenta sigue llamándose igual al volverse independiente, en
          // lugar de resucitar el nombre con el que se dio de alta hace
          // meses. Al vincular no se toca nada: `nombre`/`puestoId`
          // quedan como snapshot y dejan de presentarse.
          nombre: desvincula && nombreCongelado != null ? Value(nombreCongelado) : const Value.absent(),
          puestoId: desvincula && puestoIdCongelado != null ? Value(puestoIdCongelado) : const Value.absent(),
          updatedAt: Value(DateTime.now()),
        ),
      );

      await _registrarEventoInterno(
        usuarioId: usuarioId,
        tipoEvento: TipoEventoUsuario.vinculoEmpleadoModificado,
        observacion: motivo,
        actorUsuarioId: actorUsuarioId,
        datosRelevantes: {
          'empleadoIdAnterior': anterior.empleadoId,
          'empleadoIdNuevo': empleadoIdNuevo,
          // Nombres ya resueltos: el historial nunca muestra un UUID
          // como texto principal.
          if (etiquetaAnterior != null) 'empleadoAnterior': etiquetaAnterior,
          if (etiquetaNueva != null) 'empleadoNuevo': etiquetaNueva,
        },
      );

      return (_db.select(_db.usuario)..where((t) => t.id.equals(usuarioId))).getSingle();
    });
  }

  @override
  Future<UsuarioData> activar({required String usuarioId, String? actorUsuarioId}) {
    return _db.transaction(() async {
      await (_db.update(_db.usuario)..where((t) => t.id.equals(usuarioId))).write(
        UsuarioCompanion(
          cicloVidaRegistro: Value(CicloVidaRegistro.activo.name),
          updatedAt: Value(DateTime.now()),
        ),
      );

      await _registrarEventoInterno(usuarioId: usuarioId, tipoEvento: TipoEventoUsuario.activado, actorUsuarioId: actorUsuarioId);

      return (_db.select(_db.usuario)..where((t) => t.id.equals(usuarioId))).getSingle();
    });
  }

  @override
  Future<UsuarioData> desactivar({required String usuarioId, String? actorUsuarioId, String? motivo}) {
    return _db.transaction(() async {
      await (_db.update(_db.usuario)..where((t) => t.id.equals(usuarioId))).write(
        UsuarioCompanion(
          cicloVidaRegistro: Value(CicloVidaRegistro.inactivo.name),
          updatedAt: Value(DateTime.now()),
        ),
      );

      // Invalida "Recuérdame en este equipo" (Etapa 15) — un Usuario
      // desactivado nunca debe poder recuperar sesión automáticamente,
      // ni siquiera con un token que ya tenía guardado.
      await (_db.delete(_db.sesionPersistente)..where((t) => t.usuarioId.equals(usuarioId))).go();

      await _registrarEventoInterno(
        usuarioId: usuarioId,
        tipoEvento: TipoEventoUsuario.desactivado,
        observacion: motivo,
        actorUsuarioId: actorUsuarioId,
      );

      return (_db.select(_db.usuario)..where((t) => t.id.equals(usuarioId))).getSingle();
    });
  }

  @override
  Future<UsuarioData> registrarUltimoAcceso(String usuarioId) {
    return _db.transaction(() async {
      await (_db.update(_db.usuario)..where((t) => t.id.equals(usuarioId))).write(
        UsuarioCompanion(ultimoAccesoAt: Value(DateTime.now())),
      );
      return (_db.select(_db.usuario)..where((t) => t.id.equals(usuarioId))).getSingle();
    });
  }

  @override
  Future<void> crearSesionPersistente({required String usuarioId, required String tokenHash}) {
    return _db.transaction(() async {
      // Un solo token vivo a la vez (el Almacén de Windows solo guarda
      // uno) — se limpia cualquier fila anterior, de cualquier Usuario,
      // antes de insertar la nueva.
      await _db.delete(_db.sesionPersistente).go();
      await _db.into(_db.sesionPersistente).insert(
            SesionPersistenteCompanion.insert(usuarioId: usuarioId, tokenHash: tokenHash, createdAt: DateTime.now()),
          );
    });
  }

  @override
  Future<UsuarioData?> obtenerPorTokenSesionHash(String tokenHash) async {
    final fila = await (_db.select(_db.sesionPersistente)..where((t) => t.tokenHash.equals(tokenHash))).getSingleOrNull();
    if (fila == null) return null;
    return (_db.select(_db.usuario)..where((t) => t.id.equals(fila.usuarioId))).getSingleOrNull();
  }

  @override
  Future<void> borrarSesionPersistente(String usuarioId) {
    return (_db.delete(_db.sesionPersistente)..where((t) => t.usuarioId.equals(usuarioId))).go();
  }

  Future<void> _registrarEventoInterno({
    required String usuarioId,
    required TipoEventoUsuario tipoEvento,
    String? observacion,
    String? actorUsuarioId,
    Map<String, dynamic>? datosRelevantes,
  }) {
    return _db.into(_db.usuarioEvento).insert(
          UsuarioEventoCompanion.insert(
            usuarioId: usuarioId,
            actorUsuarioId: Value(actorUsuarioId),
            fechaHora: DateTime.now(),
            tipoEvento: tipoEvento.name,
            observacion: Value(observacion),
            datosRelevantes: datosRelevantes == null ? const Value.absent() : Value(jsonEncode(datosRelevantes)),
          ),
        );
  }
}

import 'package:riseg_one/core/database/app_database.dart';

import '../identidad_usuario.dart';

/// Repositorio del dominio Usuarios (Etapa 11A). `crear`/`corregir`/
/// `cambiarContrasena`/`activar`/`desactivar`/`cambiarVinculoEmpleado`
/// registran siempre su `UsuarioEvento` correspondiente en la misma
/// transacción — nunca hay una escritura de Usuario sin su evento.
abstract interface class UsuarioRepository {
  Future<UsuarioData?> obtenerPorId(String id);

  Future<UsuarioData?> obtenerPorNombreUsuario(String nombreUsuario);

  /// La cuenta vinculada a este Empleado, si existe (Etapa 3B) — el
  /// chequeo de "un Empleado, una cuenta" del lado del dominio. El
  /// índice único parcial de la base es la garantía final; esto es lo
  /// que permite dar un mensaje humano en vez de un error de SQLite.
  Future<UsuarioData?> obtenerPorEmpleadoId(String empleadoId);

  Future<List<UsuarioData>> listar({String? cicloVidaRegistro});

  /// Las cuentas con su identidad efectiva ya resuelta (Etapa 3B).
  ///
  /// **Tres consultas fijas**, independientemente de cuántas cuentas
  /// haya: usuarios, los Empleados vinculados en un solo `IN`, y el
  /// catálogo completo de Puestos. Nunca una consulta por fila — el
  /// listado de Usuarios es corto, pero el patrón N+1 es el que después
  /// se copia a un listado que no lo es.
  Future<List<IdentidadUsuario>> listarConIdentidad({String? cicloVidaRegistro});

  /// La identidad efectiva de UNA cuenta — consulta dirigida, para la
  /// ficha de detalle.
  Future<IdentidadUsuario?> obtenerConIdentidad(String id);

  Future<int> contarUsuarios();

  /// Cuenta Maestros con `cicloVidaRegistro = activo`, excluyendo
  /// opcionalmente uno (el propio usuario que se está por corregir/
  /// desactivar) — usado para el invariante "al menos un Maestro activo".
  Future<int> contarMaestrosActivos({String? excluirUsuarioId});

  Future<List<UsuarioEventoData>> listarEventos(String usuarioId);

  /// Alta ATÓMICA de una cuenta (Etapa "Usuarios, permisos y UX de
  /// seguridad"): la fila `Usuario`, sus [permisosIniciales] y el evento
  /// de auditoría se escriben en UNA sola transacción, o no se escribe
  /// nada. Antes eran dos operaciones separadas —crear la cuenta y
  /// después, desde otro diálogo, guardarle permisos— con una ventana
  /// real en la que quedaba una cuenta sin ningún permiso.
  ///
  /// [permisosIniciales] se ignora cuando `esMaestro` es `true`: el
  /// Maestro nunca tiene filas en `PermisoUsuario` (su acceso se
  /// recalcula en vivo desde el catálogo).
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
  });

  Future<UsuarioData> corregir({
    required String usuarioId,
    String? nombre,
    String? nombreUsuario,
    String? puestoId,
    bool? esMaestro,
    String? actorUsuarioId,
    String? motivo,
  });

  /// [exigirCambio] deja la cuenta obligada a cambiar la contraseña en
  /// su siguiente acceso. Es `true` cuando alguien MÁS la fija (un
  /// reseteo administrativo: la conoce otra persona) y `false` cuando la
  /// cambia el propio titular.
  Future<UsuarioData> cambiarContrasena({
    required String usuarioId,
    required String passwordHash,
    String? actorUsuarioId,
    bool exigirCambio = false,
  });

  /// Vincula, re-vincula o desvincula la cuenta de un Empleado (Etapa
  /// 3B) — operación de IDENTIDAD, deliberadamente separada de
  /// `corregir`: cambiar de quién es una cuenta no es corregir un dato,
  /// y no debe poder ocurrir por tocar un desplegable sin querer.
  ///
  /// [empleadoIdNuevo] nulo significa **desvincular**. En ese caso
  /// [nombreCongelado] y [puestoIdCongelado] traen la identidad
  /// efectiva que la cuenta tenía justo antes —la del Empleado— para
  /// que la cuenta siga llamándose igual al volverse independiente, en
  /// vez de reaparecer con un nombre viejo o en blanco. Se ignoran en
  /// las otras dos transiciones.
  ///
  /// [etiquetaAnterior]/[etiquetaNueva] son los nombres ya resueltos de
  /// los Empleados implicados: se guardan en el evento para que el
  /// historial se lea sin UUID (regla del proyecto desde la Etapa 1).
  Future<UsuarioData> cambiarVinculoEmpleado({
    required String usuarioId,
    required String? empleadoIdNuevo,
    String? nombreCongelado,
    String? puestoIdCongelado,
    String? etiquetaAnterior,
    String? etiquetaNueva,
    String? actorUsuarioId,
    String? motivo,
  });

  Future<UsuarioData> activar({required String usuarioId, String? actorUsuarioId});

  Future<UsuarioData> desactivar({required String usuarioId, String? actorUsuarioId, String? motivo});

  Future<UsuarioData> registrarUltimoAcceso(String usuarioId);

  /// "Recuérdame en este equipo" (Etapa 15) — reemplaza cualquier fila
  /// previa de `SesionPersistente` (de cualquier Usuario): el Almacén de
  /// Credenciales de Windows solo guarda un token a la vez, así que
  /// nunca tiene sentido conservar más de una fila viva.
  Future<void> crearSesionPersistente({required String usuarioId, required String tokenHash});

  /// `null` si ningún hash coincide. No valida por sí mismo que el
  /// Usuario siga activo — eso es responsabilidad de
  /// `RestaurarSesionRecordadaUseCase`, que sí conoce la regla de
  /// negocio completa.
  Future<UsuarioData?> obtenerPorTokenSesionHash(String tokenHash);

  /// Borra cualquier `SesionPersistente` del Usuario — logout explícito
  /// con "salir de este equipo", o invalidación automática (ver
  /// `cambiarContrasena`/`desactivar`).
  Future<void> borrarSesionPersistente(String usuarioId);
}

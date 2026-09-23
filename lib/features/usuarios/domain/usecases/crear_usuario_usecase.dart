import 'package:riseg_one/core/auth/password_hasher.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/permissions/modulos_permiso.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/puesto_repository.dart';
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart';
import 'package:riseg_one/features/personal/domain/repositories/empleado_repository.dart';

import '../repositories/usuario_repository.dart';

sealed class CrearUsuarioResultado {}

class CrearUsuarioExitoso extends CrearUsuarioResultado {
  CrearUsuarioExitoso(this.usuario);
  final UsuarioData usuario;
}

class CrearUsuarioNombreRequerido extends CrearUsuarioResultado {}

class CrearUsuarioNombreUsuarioRequerido extends CrearUsuarioResultado {}

class CrearUsuarioNombreUsuarioDuplicado extends CrearUsuarioResultado {}

/// Mínimo 8 caracteres — sin exigir símbolos/mayúsculas por ahora, es
/// una app interna sin recuperación por correo todavía (ver el plan de
/// la Etapa 11A).
class CrearUsuarioContrasenaInvalida extends CrearUsuarioResultado {}

class CrearUsuarioPuestoInvalido extends CrearUsuarioResultado {}

/// Etapa 3B — el Empleado elegido no existe. No debería llegar por la
/// UI (el desplegable sólo ofrece empleados reales), y por eso mismo se
/// valida aquí: el desplegable es una comodidad, no una garantía.
class CrearUsuarioEmpleadoNoExiste extends CrearUsuarioResultado {}

/// Etapa 3B — el Empleado existe pero no está laboralmente activo. Una
/// cuenta de acceso nace para alguien que trabaja hoy; dar de alta a
/// quien ya causó baja sería crear el problema que esta etapa cierra.
class CrearUsuarioEmpleadoNoElegible extends CrearUsuarioResultado {}

/// Etapa 3B — ese Empleado ya tiene cuenta. Una persona, una cuenta. El
/// índice único parcial de la base es la garantía final; esta rama
/// existe para poder decirlo con palabras en vez de con un error de
/// SQLite.
class CrearUsuarioEmpleadoYaTieneCuenta extends CrearUsuarioResultado {}

class CrearUsuarioErrorInesperado extends CrearUsuarioResultado {
  CrearUsuarioErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Da de alta un Usuario (Etapa 11A) — valida unicidad de
/// `nombreUsuario`, longitud mínima de contraseña y que el Puesto
/// capturado exista/esté activo (descriptivo, nunca de seguridad — ver
/// el doc comment de `Puesto`), hashea la contraseña y delega a
/// `UsuarioRepository.crear`.
///
/// **Etapa 3B — dos altas, no una.** Si la cuenta se vincula a un
/// Empleado, su identidad viene de Personal: no se captura nombre ni
/// puesto, y **no se exige puesto**. Antes sí se exigía, y con un
/// Empleado sin puesto (o con puesto inactivo) el alta quedaba en un
/// callejón sin salida: fallaba con "Puesto inválido" señalando un
/// selector que el propio formulario tenía deshabilitado. Un puesto
/// faltante se corrige en Personal, nunca inventándolo desde aquí.
class CrearUsuarioUseCase {
  CrearUsuarioUseCase(this._usuarioRepository, this._puestoRepository, this._passwordHasher, this._empleadoRepository);

  final UsuarioRepository _usuarioRepository;
  final PuestoRepository _puestoRepository;
  final PasswordHasher _passwordHasher;
  final EmpleadoRepository _empleadoRepository;

  static const _longitudMinimaContrasena = 8;

  Future<CrearUsuarioResultado> ejecutar({
    required String nombre,
    required String nombreUsuario,
    required String password,
    String? puestoId,
    String? empleadoId,
    bool esMaestro = false,
    Set<String> permisosIniciales = const {},
    String? actorUsuarioId,
  }) async {
    final nombreLimpio = nombre.trim();
    if (nombreLimpio.isEmpty) return CrearUsuarioNombreRequerido();

    final nombreUsuarioLimpio = nombreUsuario.trim();
    if (nombreUsuarioLimpio.isEmpty) return CrearUsuarioNombreUsuarioRequerido();

    if (password.length < _longitudMinimaContrasena) return CrearUsuarioContrasenaInvalida();

    try {
      final existente = await _usuarioRepository.obtenerPorNombreUsuario(nombreUsuarioLimpio);
      if (existente != null) return CrearUsuarioNombreUsuarioDuplicado();

      // El puesto a guardar. Para una cuenta vinculada es un snapshot
      // técnico (la verdad es el Empleado) y puede quedar nulo sin que
      // eso sea un error; para una independiente es su identidad y se
      // exige activo.
      String? puestoAGuardar;
      if (empleadoId == null) {
        final puesto = puestoId == null ? null : await _puestoRepository.obtenerPorId(puestoId);
        if (puesto == null || puesto.cicloVidaRegistro != 'activo') return CrearUsuarioPuestoInvalido();
        puestoAGuardar = puestoId;
      } else {
        // El desplegable ya filtra, pero eso no vale como validación:
        // esta comprobación es la que corre también cuando el caso de
        // uso se invoca sin pasar por ninguna pantalla.
        final empleado = await _empleadoRepository.obtenerPorId(empleadoId);
        if (empleado == null) return CrearUsuarioEmpleadoNoExiste();
        if (EstatusEmpleado.values.byName(empleado.estatus) != EstatusEmpleado.activo) {
          return CrearUsuarioEmpleadoNoElegible();
        }
        final yaTieneCuenta = await _usuarioRepository.obtenerPorEmpleadoId(empleadoId);
        if (yaTieneCuenta != null) return CrearUsuarioEmpleadoYaTieneCuenta();
        puestoAGuardar = empleado.puestoId;
      }

      final usuario = await _usuarioRepository.crear(
        nombre: nombreLimpio,
        nombreUsuario: nombreUsuarioLimpio,
        passwordHash: _passwordHasher.hash(password),
        puestoId: puestoAGuardar,
        empleadoId: empleadoId,
        esMaestro: esMaestro,
        // Toda cuenta creada por un Maestro nace con contraseña
        // TEMPORAL: su titular debe cambiarla antes de poder usar el
        // sistema. El primer Maestro del bootstrap no pasa por aquí.
        debeCambiarPassword: true,
        permisosIniciales: esMaestro ? const {} : normalizarPermisos(permisosIniciales),
        actorUsuarioId: actorUsuarioId,
      );
      return CrearUsuarioExitoso(usuario);
    } catch (e) {
      return CrearUsuarioErrorInesperado(e.toString());
    }
  }
}

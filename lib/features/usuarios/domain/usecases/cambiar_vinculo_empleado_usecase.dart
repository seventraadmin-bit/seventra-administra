import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart';
import 'package:riseg_one/features/personal/domain/repositories/empleado_repository.dart';
import 'package:riseg_one/features/personal/presentation/empleados/empleados_list_screen.dart' show empleadoNombreCompleto;

import '../repositories/usuario_repository.dart';

sealed class CambiarVinculoEmpleadoResultado {}

class CambiarVinculoEmpleadoExitoso extends CambiarVinculoEmpleadoResultado {
  CambiarVinculoEmpleadoExitoso(this.usuario);
  final UsuarioData usuario;
}

class CambiarVinculoEmpleadoUsuarioNoExiste extends CambiarVinculoEmpleadoResultado {}

class CambiarVinculoEmpleadoNoExiste extends CambiarVinculoEmpleadoResultado {}

class CambiarVinculoEmpleadoNoElegible extends CambiarVinculoEmpleadoResultado {}

class CambiarVinculoEmpleadoYaTieneCuenta extends CambiarVinculoEmpleadoResultado {}

/// No hay nada que cambiar — el vínculo pedido ya es el vigente. Se
/// rechaza en vez de escribir: un evento de auditoría que dice "se
/// cambió el Empleado" cuando no cambió nada es ruido que después
/// alguien tiene que interpretar.
class CambiarVinculoEmpleadoSinCambio extends CambiarVinculoEmpleadoResultado {}

/// Motivo obligatorio — mismo criterio que desactivar una cuenta
/// (Etapa 11D). Cambiar de quién es una cuenta de acceso es una
/// decisión administrativa que siempre debe quedar explicada.
class CambiarVinculoEmpleadoMotivoRequerido extends CambiarVinculoEmpleadoResultado {}

class CambiarVinculoEmpleadoErrorInesperado extends CambiarVinculoEmpleadoResultado {
  CambiarVinculoEmpleadoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Vincula, re-vincula o desvincula una cuenta de un Empleado (Etapa
/// 3B) — las tres transiciones de identidad, en un caso de uso propio.
///
/// **Por qué no vive dentro de `CorregirUsuarioUseCase`:** corregir es
/// arreglar un dato mal escrito; esto cambia de quién ES la cuenta, y
/// con ello el nombre y el puesto que verá todo el sistema. Que exija
/// su propio motivo y produzca su propio evento no es ceremonia: es lo
/// que impide que cambie por tocar un desplegable sin querer.
///
/// **Qué NO hace:** no toca permisos, no toca la contraseña, no toca el
/// estado de la cuenta y no crea ni modifica ningún Empleado. Vincular
/// a alguien no le da acceso a nada nuevo — los permisos siguen siendo
/// explícitos, y el puesto sigue sin determinarlos.
///
/// **Al desvincular** la cuenta conserva como identidad propia el
/// nombre y el puesto que tenía *en ese instante* —los del Empleado—,
/// no los que traía al darse de alta. La alternativa (resucitar el
/// snapshot viejo) haría que una cuenta cambiara de nombre sola al
/// desvincularla, que es justo la sorpresa que no queremos.
class CambiarVinculoEmpleadoUseCase {
  CambiarVinculoEmpleadoUseCase(this._usuarioRepository, this._empleadoRepository);

  final UsuarioRepository _usuarioRepository;
  final EmpleadoRepository _empleadoRepository;

  /// [empleadoIdNuevo] nulo significa desvincular.
  Future<CambiarVinculoEmpleadoResultado> ejecutar({
    required String usuarioId,
    required String? empleadoIdNuevo,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    final motivoLimpio = motivo.trim();
    if (motivoLimpio.isEmpty) return CambiarVinculoEmpleadoMotivoRequerido();

    try {
      final actual = await _usuarioRepository.obtenerConIdentidad(usuarioId);
      if (actual == null) return CambiarVinculoEmpleadoUsuarioNoExiste();
      if (actual.usuario.empleadoId == empleadoIdNuevo) return CambiarVinculoEmpleadoSinCambio();

      EmpleadoData? nuevo;
      if (empleadoIdNuevo != null) {
        nuevo = await _empleadoRepository.obtenerPorId(empleadoIdNuevo);
        if (nuevo == null) return CambiarVinculoEmpleadoNoExiste();
        if (EstatusEmpleado.values.byName(nuevo.estatus) != EstatusEmpleado.activo) {
          return CambiarVinculoEmpleadoNoElegible();
        }
        final ocupante = await _usuarioRepository.obtenerPorEmpleadoId(empleadoIdNuevo);
        if (ocupante != null && ocupante.id != usuarioId) return CambiarVinculoEmpleadoYaTieneCuenta();
      }

      final usuario = await _usuarioRepository.cambiarVinculoEmpleado(
        usuarioId: usuarioId,
        empleadoIdNuevo: empleadoIdNuevo,
        // Sólo se usan al desvincular: la identidad efectiva de AHORA,
        // congelada como identidad propia.
        nombreCongelado: empleadoIdNuevo == null ? actual.nombreEfectivo : null,
        puestoIdCongelado: empleadoIdNuevo == null ? actual.puestoEfectivoId : null,
        etiquetaAnterior: actual.empleado == null ? null : empleadoNombreCompleto(actual.empleado!),
        etiquetaNueva: nuevo == null ? null : empleadoNombreCompleto(nuevo),
        actorUsuarioId: actorUsuarioId,
        motivo: motivoLimpio,
      );
      return CambiarVinculoEmpleadoExitoso(usuario);
    } catch (e) {
      return CambiarVinculoEmpleadoErrorInesperado(e.toString());
    }
  }
}

import 'package:riseg_one/core/database/app_database.dart';

import '../../data/tables/articulo_unidad_table.dart' show EstatusArticuloUnidad;
import '../repositories/inventario_repository.dart';
import '../repositories/linea_telefonica_de_unidad.dart';

sealed class RegistrarBajaUnidadResultado {}

class RegistrarBajaUnidadExitoso extends RegistrarBajaUnidadResultado {
  RegistrarBajaUnidadExitoso(this.unidad);
  final ArticuloUnidadData unidad;
}

class RegistrarBajaUnidadNoExiste extends RegistrarBajaUnidadResultado {}

/// La unidad ya está dada de baja — nunca se vuelve a dar de baja.
class RegistrarBajaUnidadYaDeBaja extends RegistrarBajaUnidadResultado {}

/// Etapa 0 (corrección de bug real) — la unidad está `asignada` (en
/// custodia activa de un Empleado): debe cerrarse la Asignación
/// primero (`CerrarAsignacionUseCase`), nunca darse de baja
/// directamente por encima de ese flujo.
class RegistrarBajaUnidadAsignada extends RegistrarBajaUnidadResultado {}

/// §18 — la unidad todavía trae una línea telefónica. Dar de baja el
/// aparato dejaría una asociación activa apuntando a algo que ya no
/// existe. Primero hay que retirar el equipo de la línea (operación
/// puramente telefónica, que no devuelve nada físicamente); la historia
/// de ambos se conserva y la línea puede recibir otro aparato después.
class RegistrarBajaUnidadTraeLineaTelefonica extends RegistrarBajaUnidadResultado {}

class RegistrarBajaUnidadObservacionesRequeridas extends RegistrarBajaUnidadResultado {}

class RegistrarBajaUnidadErrorInesperado extends RegistrarBajaUnidadResultado {
  RegistrarBajaUnidadErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Da de baja definitivamente una unidad serializada (Etapa 7A) —
/// marca su `estatus` en `baja` y registra el movimiento
/// correspondiente. Siempre requiere `observaciones`.
class RegistrarBajaUnidadUseCase {
  RegistrarBajaUnidadUseCase(this._repository, this._lineaTelefonica);

  final InventarioRepository _repository;
  final LineaTelefonicaDeUnidad _lineaTelefonica;

  Future<RegistrarBajaUnidadResultado> ejecutar({
    required String unidadId,
    required String observaciones,
    String? actorUsuarioId,
  }) async {
    final unidad = await _repository.obtenerUnidadPorId(unidadId);
    if (unidad == null) return RegistrarBajaUnidadNoExiste();
    final estatusActual = EstatusArticuloUnidad.values.byName(unidad.estatus);
    if (estatusActual == EstatusArticuloUnidad.baja) {
      return RegistrarBajaUnidadYaDeBaja();
    }
    if (estatusActual == EstatusArticuloUnidad.asignado) {
      return RegistrarBajaUnidadAsignada();
    }
    if (await _lineaTelefonica.traeLineaVigente(unidadId)) {
      return RegistrarBajaUnidadTraeLineaTelefonica();
    }
    if (observaciones.trim().isEmpty) return RegistrarBajaUnidadObservacionesRequeridas();

    try {
      final actualizada = await _repository.registrarBajaUnidad(
        unidadId: unidadId,
        observaciones: observaciones.trim(),
        actorUsuarioId: actorUsuarioId,
      );
      return RegistrarBajaUnidadExitoso(actualizada);
    } catch (e) {
      return RegistrarBajaUnidadErrorInesperado(e.toString());
    }
  }
}

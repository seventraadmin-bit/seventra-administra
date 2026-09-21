import 'package:riseg_one/core/auditoria/diff_evento.dart';
import 'package:riseg_one/core/database/app_database.dart';

import '../../data/tables/vehiculo_table.dart';
import '../repositories/vehiculo_documento_repository.dart';
import '../repositories/vehiculo_repository.dart';

sealed class CorregirDocumentoVehiculoResultado {}

class CorregirDocumentoVehiculoExitoso extends CorregirDocumentoVehiculoResultado {
  CorregirDocumentoVehiculoExitoso(this.documento);
  final VehiculoDocumentoData documento;
}

class CorregirDocumentoVehiculoNoExiste extends CorregirDocumentoVehiculoResultado {}

class CorregirDocumentoVehiculoMotivoRequerido extends CorregirDocumentoVehiculoResultado {}

class CorregirDocumentoVehiculoDescripcionRequerida extends CorregirDocumentoVehiculoResultado {}

class CorregirDocumentoVehiculoFechasInvalidas extends CorregirDocumentoVehiculoResultado {}

class CorregirDocumentoVehiculoErrorInesperado extends CorregirDocumentoVehiculoResultado {
  CorregirDocumentoVehiculoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Corrige un documento ya registrado (schemaVersion 80) — el gap que
/// quedaba en el ciclo de vida de las sub-entidades del Vehículo.
///
/// **Corregir no es renovar, y ese es justo el punto.** Renovar crea una
/// fila nueva porque la póliza o la verificación cambió en la realidad;
/// hasta esta etapa, un folio capturado con un dígito de más solo se
/// podía "arreglar" registrando una renovación falsa, que inventaba una
/// vigencia que nunca existió y ensuciaba las alertas de vencimiento.
///
/// Por eso la corrección exige `motivo` y deja un evento
/// `documentoCorregido` con el antes/después de **solo** los campos que
/// cambiaron — mismo contrato exacto que `CorregirVehiculoUseCase` y
/// `CorregirMantenimientoVehiculoUseCase`. El historial de renovaciones
/// del documento no se toca.
class CorregirDocumentoVehiculoUseCase {
  CorregirDocumentoVehiculoUseCase(this._documentoRepository, this._vehiculoRepository);

  final VehiculoDocumentoRepository _documentoRepository;
  final VehiculoRepository _vehiculoRepository;

  Future<CorregirDocumentoVehiculoResultado> ejecutar({
    required String vehiculoDocumentoId,
    String? tipo,
    String? tipoOtroDescripcion,
    String? numeroFolio,
    bool limpiarNumeroFolio = false,
    DateTime? fechaEmision,
    bool limpiarFechaEmision = false,
    DateTime? fechaVencimiento,
    bool limpiarFechaVencimiento = false,
    String? observaciones,
    bool limpiarObservaciones = false,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    if (!motivoEsValido(motivo)) return CorregirDocumentoVehiculoMotivoRequerido();

    final actual = await _documentoRepository.obtenerPorId(vehiculoDocumentoId);
    if (actual == null) return CorregirDocumentoVehiculoNoExiste();

    final tipoFinal = tipo ?? actual.tipo;
    final descripcionFinal = tipoOtroDescripcion ?? actual.tipoOtroDescripcion;
    if (tipoFinal == 'otro' && (descripcionFinal == null || descripcionFinal.trim().isEmpty)) {
      return CorregirDocumentoVehiculoDescripcionRequerida();
    }

    // Las fechas se validan sobre el resultado FINAL, nunca solo sobre
    // lo que llegó: corregir únicamente la emisión también puede dejar
    // el documento con vencimiento anterior a ella.
    final emisionFinal = limpiarFechaEmision ? null : (fechaEmision ?? actual.fechaEmision);
    final vencimientoFinal = limpiarFechaVencimiento ? null : (fechaVencimiento ?? actual.fechaVencimiento);
    if (emisionFinal != null && vencimientoFinal != null && vencimientoFinal.isBefore(emisionFinal)) {
      return CorregirDocumentoVehiculoFechasInvalidas();
    }

    try {
      final actualizado = await _documentoRepository.corregir(
        vehiculoDocumentoId: vehiculoDocumentoId,
        tipo: tipo,
        tipoOtroDescripcion: tipoFinal == 'otro' ? descripcionFinal!.trim() : null,
        numeroFolio: numeroFolio?.trim().isEmpty ?? true ? null : numeroFolio!.trim(),
        limpiarNumeroFolio: limpiarNumeroFolio,
        fechaEmision: fechaEmision,
        limpiarFechaEmision: limpiarFechaEmision,
        fechaVencimiento: fechaVencimiento,
        limpiarFechaVencimiento: limpiarFechaVencimiento,
        observaciones: observaciones?.trim().isEmpty ?? true ? null : observaciones!.trim(),
        limpiarObservaciones: limpiarObservaciones,
      );

      final diff = DiffEvento()
        ..anotar('tipo', actual.tipo, actualizado.tipo)
        ..anotar('tipoOtroDescripcion', actual.tipoOtroDescripcion, actualizado.tipoOtroDescripcion)
        ..anotar('numeroFolio', actual.numeroFolio, actualizado.numeroFolio)
        ..anotar('fechaEmision', actual.fechaEmision, actualizado.fechaEmision)
        ..anotar('fechaVencimiento', actual.fechaVencimiento, actualizado.fechaVencimiento)
        ..anotar('observaciones', actual.observaciones, actualizado.observaciones);

      // Una "corrección" que no cambió nada no es una corrección: no
      // ensucia el historial con ruido.
      if (diff.hayCambios) {
        await _vehiculoRepository.registrarEvento(
          vehiculoId: actual.vehiculoId,
          tipoEvento: TipoEventoVehiculo.documentoCorregido,
          observacion: motivo,
          estadoAnterior: diff.estadoAnteriorJson,
          estadoNuevo: diff.estadoNuevoJson,
          actorUsuarioId: actorUsuarioId,
        );
      }

      return CorregirDocumentoVehiculoExitoso(actualizado);
    } catch (e) {
      return CorregirDocumentoVehiculoErrorInesperado(e.toString());
    }
  }
}

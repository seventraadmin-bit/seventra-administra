import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/inventario/domain/repositories/asignacion_repository.dart';
import 'package:riseg_one/features/inventario/domain/repositories/inventario_repository.dart';

import '../repositories/equipo_telefonico_repository.dart';
import '../repositories/linea_telefonica_equipo_repository.dart';
import '../repositories/linea_telefonica_repository.dart';
import '../repositories/recarga_linea_telefonica_repository.dart';

/// Un período en el que una `LineaTelefonica` estuvo vinculada a este
/// equipo, junto con las recargas de esa línea que ocurrieron
/// **durante ese período exacto** — así una recarga hecha cuando la
/// línea estaba en otro teléfono nunca aparece atribuida a este (punto
/// 8 de la Etapa 9D: "recargas relacionadas con sus líneas durante los
/// periodos correspondientes").
class PeriodoLineaConRecargas {
  const PeriodoLineaConRecargas({required this.periodo, required this.linea, required this.recargas});

  final LineaTelefonicaEquipoData periodo;
  final LineaTelefonicaData linea;
  final List<RecargaLineaTelefonicaData> recargas;
}

/// Vida completa de un teléfono físico (Etapa 9D, punto 8) — enteramente
/// derivada de los ledgers/asignaciones/eventos ya existentes, sin
/// tabla "Historial" propia.
class HistoriaEquipoTelefonico {
  const HistoriaEquipoTelefonico({
    required this.movimientoAdquisicion,
    required this.periodosLinea,
    required this.asignaciones,
    required this.descuentos,
    required this.eventosConfiguracion,
  });

  /// El movimiento `entrada` original — fecha de compra y costo de
  /// adquisición (fuente real, ver `ArticuloExpedienteScreen`/
  /// `ObtenerOrigenCompraUseCase`). `null` si, por alguna razón, la
  /// unidad no tiene movimiento de entrada (no debería ocurrir en la
  /// práctica).
  final MovimientoInventarioData? movimientoAdquisicion;

  final List<PeriodoLineaConRecargas> periodosLinea;

  /// A quién estuvo asignado y cuándo — orden descendente por
  /// `fechaEntrega` (mismo orden que `AsignacionRepository.listarPorUnidad`).
  final List<AsignacionData> asignaciones;

  /// Daños/pérdidas con descuento generado, si los hay.
  final List<DescuentoInventarioData> descuentos;

  /// Configuración del expediente (equipo configurado, correo
  /// actualizado, contraseña actualizada/revelada/copiada) — nunca el
  /// secreto en sí.
  final List<EquipoTelefonicoEventoData> eventosConfiguracion;
}

class ObtenerHistoriaEquipoTelefonicoUseCase {
  ObtenerHistoriaEquipoTelefonicoUseCase(
    this._inventarioRepository,
    this._asignacionRepository,
    this._lineaTelefonicaEquipoRepository,
    this._lineaTelefonicaRepository,
    this._recargaRepository,
    this._equipoRepository,
  );

  final InventarioRepository _inventarioRepository;
  final AsignacionRepository _asignacionRepository;
  final LineaTelefonicaEquipoRepository _lineaTelefonicaEquipoRepository;
  final LineaTelefonicaRepository _lineaTelefonicaRepository;
  final RecargaLineaTelefonicaRepository _recargaRepository;
  final EquipoTelefonicoRepository _equipoRepository;

  Future<HistoriaEquipoTelefonico> ejecutar(String unidadId) async {
    final movimientos = await _inventarioRepository.listarMovimientos(unidadId: unidadId);
    MovimientoInventarioData? movimientoAdquisicion;
    for (final m in movimientos) {
      if (m.tipoMovimiento == 'entrada') {
        movimientoAdquisicion = m;
        break;
      }
    }

    final periodos = await _lineaTelefonicaEquipoRepository.listarPorUnidad(unidadId);
    final periodosConRecargas = <PeriodoLineaConRecargas>[];
    for (final periodo in periodos) {
      final linea = await _lineaTelefonicaRepository.obtenerPorId(periodo.lineaTelefonicaId);
      if (linea == null) continue;
      final recargasDeLaLinea = await _recargaRepository.listarPorLinea(periodo.lineaTelefonicaId);
      final recargasDelPeriodo = recargasDeLaLinea.where((r) {
        final dentroDeInicio = !r.fecha.isBefore(periodo.fechaInicio);
        final dentroDeFin = periodo.fechaFin == null || r.fecha.isBefore(periodo.fechaFin!);
        return dentroDeInicio && dentroDeFin;
      }).toList();
      periodosConRecargas.add(PeriodoLineaConRecargas(periodo: periodo, linea: linea, recargas: recargasDelPeriodo));
    }

    final asignaciones = await _asignacionRepository.listarPorUnidad(unidadId);
    final descuentos = <DescuentoInventarioData>[];
    for (final asignacion in asignaciones) {
      final descuento = await _asignacionRepository.obtenerDescuentoPorAsignacion(asignacion.id);
      if (descuento != null) descuentos.add(descuento);
    }

    final eventos = await _equipoRepository.listarEventos(unidadId);

    return HistoriaEquipoTelefonico(
      movimientoAdquisicion: movimientoAdquisicion,
      periodosLinea: periodosConRecargas,
      asignaciones: asignaciones,
      descuentos: descuentos,
      eventosConfiguracion: eventos,
    );
  }
}

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';
import 'package:riseg_one/core/utils/clock.dart';

import '../repositories/servicio_comercial_repository.dart';
import 'linea_comercial_con_vigencia.dart';

sealed class CerrarLineaComercialResultado {}

class CerrarLineaComercialExitoso extends CerrarLineaComercialResultado {
  CerrarLineaComercialExitoso(this.vigencia);
  final ServicioLineaComercialVigenciaData vigencia;
}

/// No hay ninguna vigencia vigente hoy que cerrar — la línea ya está
/// sin condición vigente, o solo tiene vigencias programadas a futuro.
class CerrarLineaComercialSinCondicionVigente extends CerrarLineaComercialResultado {}

/// Ya existe una vigencia programada — debe cancelarse primero (ver
/// `CancelarVigenciaProgramadaUseCase`) antes de poder cerrar la línea
/// sin reemplazo, para no dejar una programada "huérfana" apuntando a
/// una línea ya declarada sin futuro comercial.
class CerrarLineaComercialTieneVigenciaProgramada extends CerrarLineaComercialResultado {}

class CerrarLineaComercialFechaAnteriorInicio extends CerrarLineaComercialResultado {}

class CerrarLineaComercialLineaNoExiste extends CerrarLineaComercialResultado {}

class CerrarLineaComercialErrorInesperado extends CerrarLineaComercialResultado {
  CerrarLineaComercialErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Cierra sin reemplazo la vigencia vigente actual de una línea —
/// acción administrativa explícita, deliberadamente NO bloqueada por
/// `Servicio.estatus == terminado` (cerrar es orden, no alta nueva).
class CerrarLineaComercialUseCase {
  CerrarLineaComercialUseCase(this._repository, this._clock);

  final ServicioComercialRepository _repository;
  final Clock _clock;

  Future<CerrarLineaComercialResultado> ejecutar({
    required String lineaComercialId,
    required DateTime fechaEfectiva,
  }) async {
    final linea = await _repository.obtenerLinea(lineaComercialId);
    if (linea == null) {
      return CerrarLineaComercialLineaNoExiste();
    }

    final historial = await _repository.listarHistorial(lineaComercialId);
    final activas = historial.where((v) => v.cicloVidaRegistro == CicloVidaRegistro.activo.name).toList();
    final (:vigente, :programadas) = clasificarVigencias(activas, _clock.now());

    if (vigente == null) {
      return CerrarLineaComercialSinCondicionVigente();
    }
    if (programadas.isNotEmpty) {
      return CerrarLineaComercialTieneVigenciaProgramada();
    }
    if (soloFecha(fechaEfectiva).isBefore(soloFecha(vigente.fechaInicioVigencia))) {
      return CerrarLineaComercialFechaAnteriorInicio();
    }

    try {
      final vigencia = await _repository.cerrarVigencia(vigenciaId: vigente.id, fechaEfectiva: fechaEfectiva);
      return CerrarLineaComercialExitoso(vigencia);
    } catch (e) {
      return CerrarLineaComercialErrorInesperado(e.toString());
    }
  }
}

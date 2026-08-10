import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/asignacion_servicio_repository.dart';
import 'asignacion_servicio_validator.dart';
import 'asignacion_sueldo_con_vigencia.dart';

sealed class CambiarVigenciaSueldoAsignacionResultado {}

class CambiarVigenciaSueldoAsignacionExitoso extends CambiarVigenciaSueldoAsignacionResultado {
  CambiarVigenciaSueldoAsignacionExitoso(this.vigencia);
  final AsignacionServicioSueldoVigenciaData vigencia;
}

class CambiarVigenciaSueldoAsignacionNoExiste extends CambiarVigenciaSueldoAsignacionResultado {}

class CambiarVigenciaSueldoAsignacionSueldoInvalido extends CambiarVigenciaSueldoAsignacionResultado {}

class CambiarVigenciaSueldoAsignacionBonoInvalido extends CambiarVigenciaSueldoAsignacionResultado {}

class CambiarVigenciaSueldoAsignacionFechaInvalida extends CambiarVigenciaSueldoAsignacionResultado {}

/// Ya existe una vigencia de sueldo que empieza exactamente esa fecha —
/// mismo criterio que `CodigoErrorLineaComercial.fechaDuplicada`.
class CambiarVigenciaSueldoAsignacionFechaDuplicada extends CambiarVigenciaSueldoAsignacionResultado {}

class CambiarVigenciaSueldoAsignacionErrorInesperado extends CambiarVigenciaSueldoAsignacionResultado {
  CambiarVigenciaSueldoAsignacionErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Registra un cambio de sueldo/bono dentro de una `AsignacionServicio`
/// ya existente (Etapa 6B) — reemplaza la vigencia vigente (si la fecha
/// efectiva es hoy) o queda programada (si es futura, Resolución
/// explícita de Marlon), nunca actualiza in place ni afecta periodos
/// anteriores. Mismo patrón que `CambiarVigenciaLineaComercialUseCase`
/// (Etapa 4G.2), sin el equivalente de fecha de fin manual — el cierre
/// de la vigencia predecesora/sucesora siempre es automático (ver el
/// doc comment de `AsignacionServicioSueldoVigencia`).
class CambiarVigenciaSueldoAsignacionUseCase {
  CambiarVigenciaSueldoAsignacionUseCase(this._repository, this._validator);

  final AsignacionServicioRepository _repository;
  final AsignacionServicioValidator _validator;

  Future<CambiarVigenciaSueldoAsignacionResultado> ejecutar({
    required String asignacionServicioId,
    required int sueldoMensual,
    required int bonoMensual,
    required DateTime fechaInicioVigencia,
    String? observaciones,
  }) async {
    final asignacion = await _repository.obtenerPorId(asignacionServicioId);
    if (asignacion == null) return CambiarVigenciaSueldoAsignacionNoExiste();

    if (!_validator.sueldoValido(sueldoMensual)) return CambiarVigenciaSueldoAsignacionSueldoInvalido();
    if (!_validator.bonoValido(bonoMensual)) return CambiarVigenciaSueldoAsignacionBonoInvalido();

    if (!_validator.fechaVigenciaSueldoValida(fechaInicioVigencia, asignacion.fechaInicio)) {
      return CambiarVigenciaSueldoAsignacionFechaInvalida();
    }

    final existentes = await _repository.listarVigenciasSueldoActivas(asignacionServicioId);
    if (existentes.any((v) => soloFechaSueldo(v.fechaInicioVigencia) == soloFechaSueldo(fechaInicioVigencia))) {
      return CambiarVigenciaSueldoAsignacionFechaDuplicada();
    }

    try {
      final vigencia = await _repository.registrarVigenciaSueldo(
        asignacionServicioId: asignacionServicioId,
        sueldoMensual: sueldoMensual,
        bonoMensual: bonoMensual,
        fechaInicioVigencia: fechaInicioVigencia,
        observaciones: observaciones,
      );
      return CambiarVigenciaSueldoAsignacionExitoso(vigencia);
    } catch (e) {
      return CambiarVigenciaSueldoAsignacionErrorInesperado(e.toString());
    }
  }
}

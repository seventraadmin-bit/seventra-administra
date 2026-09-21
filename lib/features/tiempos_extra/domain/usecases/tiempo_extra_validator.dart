import 'package:riseg_one/features/tiempos_extra/data/tables/tiempo_extra_table.dart';

/// Validación pura de la cobertura (Etapa Tiempos Extra) — sin acceso a
/// BD, mismo estilo que `ConfiguracionCobroValidator`/
/// `AsignacionServicioValidator`. Exactamente uno de
/// `empleadoCubreId`/`nombreExternoCubre` debe estar presente: una FK
/// nullable no puede expresar "uno de los dos, nunca ambos" a nivel de
/// esquema, así que se valida aquí, antes de tocar el repositorio.
enum TiempoExtraCoberturaValidacion { valida, faltaCobertura, coberturaAmbigua }

/// Por qué el conjunto (origen + sus campos) no es coherente — Etapa
/// "Tiempo Extra: origen de cobertura".
///
/// Cada origen tiene una forma EXACTA: no basta con que estén los
/// campos que necesita, además deben faltar los que no le corresponden.
/// Si no se exigiera lo segundo, un TiempoExtra corregido de `vacante`
/// a `ausenciaEmpleado` podría quedarse con la FK de la vacante
/// colgando, y el registro diría dos cosas a la vez.
enum TiempoExtraOrigenValidacion {
  valida,

  /// `ausenciaEmpleado` sin `empleadoAusenteId`.
  faltaEmpleadoAusente,

  /// `ausenciaEmpleado` sin `motivoAusencia`.
  faltaMotivoAusencia,

  /// `vacante` sin `vacanteOperativaId`.
  faltaVacante,

  /// `otro` sin `descripcionOrigen` (o sólo espacios).
  faltaDescripcionOrigen,

  /// Hay un campo poblado que no pertenece a este origen — el residuo
  /// típico de haber cambiado de origen sin limpiar.
  camposIncompatibles,
}

class TiempoExtraValidator {
  static TiempoExtraCoberturaValidacion validarCobertura({
    String? empleadoCubreId,
    String? nombreExternoCubre,
  }) {
    final tieneEmpleado = empleadoCubreId != null && empleadoCubreId.trim().isNotEmpty;
    final tieneExterno = nombreExternoCubre != null && nombreExternoCubre.trim().isNotEmpty;

    if (tieneEmpleado && tieneExterno) return TiempoExtraCoberturaValidacion.coberturaAmbigua;
    if (!tieneEmpleado && !tieneExterno) return TiempoExtraCoberturaValidacion.faltaCobertura;
    return TiempoExtraCoberturaValidacion.valida;
  }

  /// Invariantes de cada origen de cobertura. Se validan en dominio, no
  /// escondiendo campos en la UI: un caso de uso llamado desde una
  /// prueba, un script o una pantalla futura tiene que toparse con la
  /// misma regla.
  ///
  /// | origen            | exige                          | prohíbe                                        |
  /// |-------------------|--------------------------------|------------------------------------------------|
  /// | ausenciaEmpleado  | empleadoAusente + motivo       | vacante, descripciónOrigen                     |
  /// | vacante           | vacanteOperativa               | empleadoAusente, motivo, descripciónOrigen     |
  /// | otro              | descripciónOrigen no vacía     | empleadoAusente, motivo, vacante               |
  static TiempoExtraOrigenValidacion validarOrigen({
    required OrigenCoberturaTiempoExtra origen,
    String? empleadoAusenteId,
    String? motivoAusencia,
    String? vacanteOperativaId,
    String? descripcionOrigen,
  }) {
    final tieneEmpleadoAusente = (empleadoAusenteId ?? '').trim().isNotEmpty;
    final tieneMotivo = (motivoAusencia ?? '').trim().isNotEmpty;
    final tieneVacante = (vacanteOperativaId ?? '').trim().isNotEmpty;
    final tieneDescripcion = (descripcionOrigen ?? '').trim().isNotEmpty;

    switch (origen) {
      case OrigenCoberturaTiempoExtra.ausenciaEmpleado:
        if (tieneVacante || tieneDescripcion) return TiempoExtraOrigenValidacion.camposIncompatibles;
        if (!tieneEmpleadoAusente) return TiempoExtraOrigenValidacion.faltaEmpleadoAusente;
        if (!tieneMotivo) return TiempoExtraOrigenValidacion.faltaMotivoAusencia;
        return TiempoExtraOrigenValidacion.valida;

      case OrigenCoberturaTiempoExtra.vacante:
        // En una vacante no falta nadie: no hay titular. Un
        // `empleadoAusenteId` aquí sería un empleado inventado.
        if (tieneEmpleadoAusente || tieneMotivo || tieneDescripcion) {
          return TiempoExtraOrigenValidacion.camposIncompatibles;
        }
        if (!tieneVacante) return TiempoExtraOrigenValidacion.faltaVacante;
        return TiempoExtraOrigenValidacion.valida;

      case OrigenCoberturaTiempoExtra.otro:
        if (tieneEmpleadoAusente || tieneMotivo || tieneVacante) {
          return TiempoExtraOrigenValidacion.camposIncompatibles;
        }
        if (!tieneDescripcion) return TiempoExtraOrigenValidacion.faltaDescripcionOrigen;
        return TiempoExtraOrigenValidacion.valida;
    }
  }

  /// Longitud máxima razonable de [TiempoExtra.descripcionOrigen] — es
  /// una nota breve ("reforzamiento por evento masivo"), no un campo de
  /// observaciones. Las observaciones generales siguen existiendo
  /// aparte.
  static const maximoDescripcionOrigen = 200;

  static bool descripcionOrigenExcedeLimite(String? descripcion) =>
      (descripcion ?? '').trim().length > maximoDescripcionOrigen;

  /// El mismo Empleado no puede ser quien falta y quien cubre — el
  /// turno quedaría descubierto igual. Sólo aplica a
  /// `ausenciaEmpleado`: en los otros orígenes no hay nadie ausente.
  static bool ausenteYCubreSonElMismo({String? empleadoAusenteId, String? empleadoCubreId}) {
    if (empleadoAusenteId == null || empleadoCubreId == null) return false;
    return empleadoAusenteId == empleadoCubreId;
  }

  /// Deja en `null` los campos que NO pertenecen a [origen] (§18 del
  /// pedido: al corregir cambiando de origen, "limpiar lógicamente las
  /// referencias incompatibles… no dejar residuos ocultos del origen
  /// anterior"). Se aplica ANTES de validar, para que corregir de
  /// `vacante` a `ausenciaEmpleado` no falle por una FK que la pantalla
  /// arrastró sin querer.
  static ({
    String? empleadoAusenteId,
    String? motivoAusencia,
    String? vacanteOperativaId,
    String? descripcionOrigen,
  }) normalizarSegunOrigen({
    required OrigenCoberturaTiempoExtra origen,
    String? empleadoAusenteId,
    String? motivoAusencia,
    String? vacanteOperativaId,
    String? descripcionOrigen,
  }) {
    String? limpio(String? valor) {
      final v = valor?.trim();
      return (v == null || v.isEmpty) ? null : v;
    }

    switch (origen) {
      case OrigenCoberturaTiempoExtra.ausenciaEmpleado:
        return (
          empleadoAusenteId: limpio(empleadoAusenteId),
          motivoAusencia: limpio(motivoAusencia),
          vacanteOperativaId: null,
          descripcionOrigen: null,
        );
      case OrigenCoberturaTiempoExtra.vacante:
        return (
          empleadoAusenteId: null,
          motivoAusencia: null,
          vacanteOperativaId: limpio(vacanteOperativaId),
          descripcionOrigen: null,
        );
      case OrigenCoberturaTiempoExtra.otro:
        return (
          empleadoAusenteId: null,
          motivoAusencia: null,
          vacanteOperativaId: null,
          descripcionOrigen: limpio(descripcionOrigen),
        );
    }
  }
}

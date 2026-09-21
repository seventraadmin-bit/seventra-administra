import 'dart:convert';

/// Convención común de auditoría para correcciones sensibles (Etapa
/// 2): construye el par `estadoAnterior`/`estadoNuevo` de un evento de
/// corrección — nunca un snapshot completo del objeto, únicamente los
/// campos que realmente cambiaron. Generaliza el patrón `anotarSiCambio`
/// que ya usaba `TiempoExtraRepositoryImpl` (el dominio más maduro en
/// este aspecto), para que el resto de los dominios con corrección real
/// (Compra, Pagos, Nómina, ...) lo reutilicen en vez de reinventarlo
/// campo por campo o guardar snapshots gigantes en `datosRelevantes`.
///
/// Puro — no toca la base de datos ni conoce ninguna tabla `*Evento`
/// específica. El llamador decide qué campos comparar y en qué orden;
/// este helper solo decide "cambió o no" y arma el JSON resultante.
class DiffEvento {
  final Map<String, Object?> _antes = {};
  final Map<String, Object?> _despues = {};

  /// Registra [campo] únicamente si [antes] y [despues] son distintos
  /// — un campo sin cambio real nunca aparece en el JSON final, ni
  /// siquiera con el mismo valor repetido.
  ///
  /// `DateTime` se serializa siempre con `toIso8601String()` (nunca
  /// `toString()`, cuyo formato no es estable/parseable de vuelta) —
  /// mismo criterio en cualquier dominio que lo use, para que el JSON
  /// resultante sea comparable de forma predecible. Los montos del
  /// proyecto son siempre `int` en centavos: se guardan tal cual, sin
  /// pasar por `double` en ningún punto — cero pérdida de precisión.
  void anotar(String campo, Object? antes, Object? despues) {
    if (antes == despues) return;
    _antes[campo] = _normalizar(antes);
    _despues[campo] = _normalizar(despues);
  }

  Object? _normalizar(Object? valor) {
    if (valor is DateTime) return valor.toIso8601String();
    return valor;
  }

  /// `false` mientras `anotar` nunca haya detectado una diferencia real
  /// — el llamador lo usa para decidir si vale la pena registrar el
  /// evento de corrección en absoluto (una "corrección" que no cambió
  /// ningún campo comparado no es una corrección real).
  bool get hayCambios => _antes.isNotEmpty;

  /// `null` — nunca `'{}'` — cuando [hayCambios] es `false`.
  String? get estadoAnteriorJson => hayCambios ? jsonEncode(_antes) : null;

  /// `null` — nunca `'{}'` — cuando [hayCambios] es `false`.
  String? get estadoNuevoJson => hayCambios ? jsonEncode(_despues) : null;
}

/// Motivo obligatorio para toda corrección sensible (Etapa 2) — nunca
/// cadenas vacías ni solo espacios. Cada dominio sigue construyendo su
/// propio resultado sellado de rechazo (ej. `CorregirCompraMotivoRequerido()`,
/// mismo patrón ya usado por `EliminarEgresoFisicamenteMotivoRequerido`/
/// `CorregirIdentidadUnidadMotivoRequerido`); este helper solo
/// centraliza la regla de validación en sí, para que no se reimplemente
/// `motivo.trim().isEmpty` de forma ligeramente distinta en cada
/// use case.
bool motivoEsValido(String? motivo) => motivo != null && motivo.trim().isNotEmpty;

/// Un día de un [HorarioSemanalInput] ya validado — listo para persistir.
///
/// `horaInicioMinutos`/`horaFinMinutos` son minutos desde medianoche
/// (0-1439), igual que la columna de Drift — nulos cuando `abierto` es
/// `false`. `cruzaMedianoche` se infiere en la validación
/// (`horaFinMinutos < horaInicioMinutos`), nunca es una decisión de la UI.
class HorarioDiaInput {
  const HorarioDiaInput({
    required this.diaSemana,
    required this.abierto,
    this.horaInicioMinutos,
    this.horaFinMinutos,
    this.cruzaMedianoche = false,
  });

  /// 0 = lunes ... 6 = domingo.
  final int diaSemana;
  final bool abierto;
  final int? horaInicioMinutos;
  final int? horaFinMinutos;
  final bool cruzaMedianoche;
}

/// Horario semanal completo ya validado — siempre exactamente 7 días
/// (uno por cada valor de `diaSemana`, incluidos los cerrados).
class HorarioSemanalInput {
  const HorarioSemanalInput({required this.dias});

  final List<HorarioDiaInput> dias;
}

/// Día de la semana para Horario — `index` coincide con
/// `HorarioDetalle.diaSemana`/`ServicioLineaComercialVigenciaHorario.diaSemana`
/// (0 = lunes ... 6 = domingo). Compartido por Sucursal y por el
/// horario personalizado de una línea comercial (Etapa 15) — un solo
/// lugar para no repetir el mismo enum con dos nombres distintos.
enum DiaSemana { lunes, martes, miercoles, jueves, viernes, sabado, domingo }

enum CodigoErrorHorario { horaInicioRequerida, horaFinRequerida, horasIguales }

/// Un día del Horario tal como llega del formulario — sin validar
/// todavía. `horaInicioMinutos`/`horaFinMinutos` son minutos desde
/// medianoche (lo que produce la conversión de `TimeOfDay` en la
/// pantalla; el dominio no depende de Flutter).
class HorarioDiaBorrador {
  const HorarioDiaBorrador({required this.abierto, this.horaInicioMinutos, this.horaFinMinutos});

  final bool abierto;
  final int? horaInicioMinutos;
  final int? horaFinMinutos;
}

/// Siempre exactamente 7 días (índice 0 = lunes ... 6 = domingo).
class HorarioSemanalBorrador {
  const HorarioSemanalBorrador({required this.dias});

  final List<HorarioDiaBorrador> dias;

  bool get estaCompletamenteVacio => dias.every((d) => !d.abierto);
}

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

/// Un error de validación de horario, todavía sin envolver en el tipo
/// de error propio de cada dominio (`ErrorHorarioSucursal`,
/// `ErrorLineaComercial`) — cada llamador lo adapta a su propia
/// jerarquía sellada; esto solo carga el día y el código.
class HorarioErrorDia {
  const HorarioErrorDia({required this.dia, required this.codigo});

  final DiaSemana dia;
  final CodigoErrorHorario codigo;
}

/// Valida un [HorarioSemanalBorrador] día por día — compartido por
/// Sucursal (`GuardarExpedienteSucursalUseCase`) y por el horario
/// personalizado de una línea comercial (`LineaComercialValidator`,
/// Etapa 15): un día cerrado no exige horas; un día abierto exige
/// ambas horas y que no sean iguales; `cruzaMedianoche` se infiere aquí
/// (`fin < inicio`), nunca es una decisión de la UI — así un turno
/// nocturno como 20:00→07:00 es válido sin ningún control extra.
///
/// `resultado` es `null` si algún día abierto reportó un error — en ese
/// caso `errores` explica cuáles, y el llamador nunca debe persistir
/// nada.
({HorarioSemanalInput? resultado, List<HorarioErrorDia> errores}) validarHorarioSemanal(
  HorarioSemanalBorrador borrador,
) {
  final errores = <HorarioErrorDia>[];
  final dias = <HorarioDiaInput>[];

  for (var i = 0; i < borrador.dias.length; i++) {
    final dia = borrador.dias[i];
    final diaSemana = DiaSemana.values[i];

    if (!dia.abierto) {
      dias.add(HorarioDiaInput(diaSemana: i, abierto: false));
      continue;
    }

    final inicio = dia.horaInicioMinutos;
    final fin = dia.horaFinMinutos;

    if (inicio == null) {
      errores.add(HorarioErrorDia(dia: diaSemana, codigo: CodigoErrorHorario.horaInicioRequerida));
    }
    if (fin == null) {
      errores.add(HorarioErrorDia(dia: diaSemana, codigo: CodigoErrorHorario.horaFinRequerida));
    }
    if (inicio == null || fin == null) continue;

    if (inicio == fin) {
      errores.add(HorarioErrorDia(dia: diaSemana, codigo: CodigoErrorHorario.horasIguales));
      continue;
    }

    dias.add(
      HorarioDiaInput(
        diaSemana: i,
        abierto: true,
        horaInicioMinutos: inicio,
        horaFinMinutos: fin,
        cruzaMedianoche: fin < inicio,
      ),
    );
  }

  if (errores.isNotEmpty) return (resultado: null, errores: errores);
  return (resultado: HorarioSemanalInput(dias: dias), errores: const []);
}

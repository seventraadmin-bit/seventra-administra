import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../domain/analitica/comparacion_periodo.dart';

part 'reportes_rango_controller.g.dart';

/// Periodos de uso frecuente, para no obligar a capturar dos fechas
/// cada vez que alguien quiere ver el mes.
///
/// Son cuatro a propósito: cubren lo que la operación realmente
/// consulta. Un catálogo largo de presets se vuelve un menú que nadie
/// lee.
enum PresetRangoReportes {
  esteMes,
  mesAnterior,
  ultimos30Dias,
  anioActual,

  /// El usuario movió Desde/Hasta a mano — ningún preset queda marcado.
  personalizado,
}

/// Periodo seleccionado en Reportes, con el preset que lo produjo.
class SeleccionRangoReportes {
  const SeleccionRangoReportes({required this.rango, required this.preset});

  final RangoPeriodo rango;
  final PresetRangoReportes preset;

  /// El periodo anterior de la misma longitud — lo que alimenta las
  /// comparaciones de todos los KPIs.
  RangoPeriodo get rangoAnterior => rango.anterior;
}

/// Periodo compartido por las cuatro pestañas de Reportes.
///
/// `keepAlive` porque el rango tiene que **sobrevivir al cambio de
/// pestaña**: el comportamiento anterior —cada pestaña con su propio
/// rango, reiniciado al mes en curso— obligaba a recapturar las fechas
/// en cada pestaña y hacía imposible comparar General contra Finanzas
/// sobre el mismo periodo. Sin `keepAlive` el provider se destruiría al
/// desmontarse la pestaña y el rango volvería al default, que es
/// exactamente el defecto que se está corrigiendo.
@Riverpod(keepAlive: true)
class ReportesRangoController extends _$ReportesRangoController {
  @override
  SeleccionRangoReportes build() => _deDefecto(PresetRangoReportes.esteMes);

  void aplicarPreset(PresetRangoReportes preset) {
    if (preset == PresetRangoReportes.personalizado) return;
    state = _deDefecto(preset);
  }

  /// Mover una fecha a mano siempre deja el periodo en
  /// `personalizado` — marcar "Este mes" sobre un rango que ya no es el
  /// mes sería mentirle al usuario sobre lo que está viendo.
  void cambiarInicio(DateTime inicio) {
    final fin = state.rango.fin;
    state = SeleccionRangoReportes(
      rango: RangoPeriodo(inicio: inicio, fin: inicio.isAfter(fin) ? inicio : fin),
      preset: PresetRangoReportes.personalizado,
    );
  }

  void cambiarFin(DateTime fin) {
    final inicio = state.rango.inicio;
    state = SeleccionRangoReportes(
      rango: RangoPeriodo(inicio: fin.isBefore(inicio) ? fin : inicio, fin: fin),
      preset: PresetRangoReportes.personalizado,
    );
  }

  static SeleccionRangoReportes _deDefecto(PresetRangoReportes preset, {DateTime? hoy}) {
    final ahora = hoy ?? DateTime.now();
    final dia = DateTime(ahora.year, ahora.month, ahora.day);
    final rango = switch (preset) {
      // "Este mes" termina HOY, no el último día del mes: incluir días
      // que todavía no ocurren haría que la comparación contra el mes
      // anterior completo mostrara una caída falsa todos los meses.
      PresetRangoReportes.esteMes => RangoPeriodo(inicio: DateTime(ahora.year, ahora.month), fin: dia),
      PresetRangoReportes.mesAnterior => RangoPeriodo(
          inicio: DateTime(ahora.year, ahora.month - 1),
          fin: DateTime(ahora.year, ahora.month, 0),
        ),
      PresetRangoReportes.ultimos30Dias => RangoPeriodo(inicio: dia.subtract(const Duration(days: 29)), fin: dia),
      PresetRangoReportes.anioActual => RangoPeriodo(inicio: DateTime(ahora.year), fin: dia),
      PresetRangoReportes.personalizado => RangoPeriodo(inicio: DateTime(ahora.year, ahora.month), fin: dia),
    };
    return SeleccionRangoReportes(rango: rango, preset: preset);
  }

  /// Expuesto solo para pruebas deterministas: calcular un preset sin
  /// depender del reloj.
  static SeleccionRangoReportes calcular(PresetRangoReportes preset, DateTime hoy) =>
      _deDefecto(preset, hoy: hoy);
}

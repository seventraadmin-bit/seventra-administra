import 'package:riseg_one/features/finanzas/domain/repositories/egreso_repository.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/ingreso_repository.dart';

/// Ingresos/Egresos de UN día — la fila de la gráfica financiera (Parte
/// H del rediseño gerencial).
class PuntoSerieFinanciera {
  const PuntoSerieFinanciera({required this.fecha, required this.ingresos, required this.egresos});

  final DateTime fecha;
  final int ingresos;
  final int egresos;

  int get resultado => ingresos - egresos;
}

/// Serie diaria de Ingresos/Egresos dentro de un rango — Parte H:
/// "debe agrupar por día dentro del periodo seleccionado". Reutiliza
/// `IngresoRepository`/`EgresoRepository.listar` (ya existentes,
/// mismo filtro `estatus: 'registrado'` que ya usa
/// `totalIngresos`/`totalEgresos` — nunca cuenta un movimiento
/// cancelado) y agrega en memoria por día — sin nueva columna ni tabla
/// agregada, un día sin ningún movimiento aparece con `0` en ambas
/// series (nunca se omite, para que la gráfica no tenga huecos).
class ObtenerSerieFinancieraUseCase {
  ObtenerSerieFinancieraUseCase(this._ingresoRepository, this._egresoRepository);

  final IngresoRepository _ingresoRepository;
  final EgresoRepository _egresoRepository;

  Future<List<PuntoSerieFinanciera>> ejecutar({required DateTime rangoInicio, required DateTime rangoFin}) async {
    final ingresos = await _ingresoRepository.listar(estatus: 'registrado', rangoInicio: rangoInicio, rangoFin: rangoFin);
    // `soloSalidaDeEfectivo` (Etapa "Origen financiero de Egresos
    // manuales"): esta serie grafica movimiento de caja día por día —
    // un gasto financiado con TDC no mueve caja hasta que se pague la
    // tarjeta, y ese pago sí aparecerá como Egreso el día que ocurra.
    final egresos = await _egresoRepository.listar(
      estatus: 'registrado',
      rangoInicio: rangoInicio,
      rangoFin: rangoFin,
      soloSalidaDeEfectivo: true,
    );

    DateTime soloFecha(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

    final ingresosPorDia = <DateTime, int>{};
    for (final i in ingresos) {
      final dia = soloFecha(i.fecha);
      ingresosPorDia[dia] = (ingresosPorDia[dia] ?? 0) + i.monto;
    }
    final egresosPorDia = <DateTime, int>{};
    for (final e in egresos) {
      final dia = soloFecha(e.fecha);
      egresosPorDia[dia] = (egresosPorDia[dia] ?? 0) + e.monto;
    }

    final inicio = soloFecha(rangoInicio);
    final fin = soloFecha(rangoFin);
    final puntos = <PuntoSerieFinanciera>[];
    for (var dia = inicio; !dia.isAfter(fin); dia = dia.add(const Duration(days: 1))) {
      puntos.add(PuntoSerieFinanciera(fecha: dia, ingresos: ingresosPorDia[dia] ?? 0, egresos: egresosPorDia[dia] ?? 0));
    }
    return puntos;
  }
}

import '../../data/tables/nomina_table.dart' show TipoPeriodoNomina;

/// Un periodo de Nómina ya resuelto a fechas de calendario concretas.
class PeriodoNomina {
  const PeriodoNomina({
    required this.anio,
    required this.mes,
    required this.tipo,
    required this.fechaInicio,
    required this.fechaFin,
    required this.fechaPago,
  });

  final int anio;
  final int mes;
  final TipoPeriodoNomina tipo;
  final DateTime fechaInicio;
  final DateTime fechaFin;
  final DateTime fechaPago;

  /// Días reales del periodo — 15 siempre en la primera quincena; 13/14/
  /// 15/16 en la segunda, según el mes (28/29/30/31 días). Este número
  /// **nunca** es el mismo que `diasPagables` de un Empleado — ver el
  /// doc comment de `calcularDiasPagablesEmpleado` para por qué.
  int get diasRealesPeriodo => fechaFin.difference(fechaInicio).inDays + 1;
}

/// Calcula las fechas de un periodo de Nómina (Etapa 6C) — puro, sin
/// acceso a BD. Primera quincena: días 1 a 15, paga el día 20 del mismo
/// mes. Segunda quincena: día 16 al último día del mes (28/29/30/31,
/// según corresponda), paga el día 5 del mes siguiente (o de enero del
/// año siguiente, si `mes == 12`).
PeriodoNomina calcularPeriodoNomina({required int anio, required int mes, required TipoPeriodoNomina tipo}) {
  return switch (tipo) {
    TipoPeriodoNomina.primera => PeriodoNomina(
        anio: anio,
        mes: mes,
        tipo: tipo,
        fechaInicio: DateTime(anio, mes, 1),
        fechaFin: DateTime(anio, mes, 15),
        fechaPago: DateTime(anio, mes, 20),
      ),
    TipoPeriodoNomina.segunda => PeriodoNomina(
        anio: anio,
        mes: mes,
        tipo: tipo,
        fechaInicio: DateTime(anio, mes, 16),
        // Día 0 del mes siguiente = último día del mes actual — mismo
        // truco ya usado en `calcular_fechas_cobro_usecase.dart`.
        fechaFin: DateTime(anio, mes + 1, 0),
        fechaPago: mes == 12 ? DateTime(anio + 1, 1, 5) : DateTime(anio, mes + 1, 5),
      ),
  };
}

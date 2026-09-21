import 'package:riseg_one/core/database/app_database.dart';

/// Resumen del conjunto filtrado de Ingresos (Etapa 17) — agregado en
/// memoria, solo Ingresos `registrado` (un `cancelado` no es dinero
/// vigente). "Automáticos"/"Manuales" derivan de `pagoId` — el único
/// discriminador real de origen, nunca inventado.
class IngresosResumen {
  const IngresosResumen({required this.totalIngresos, required this.automaticos, required this.manuales});

  final int totalIngresos;
  final int automaticos;
  final int manuales;
}

IngresosResumen calcularResumenIngresos(List<IngresoData> ingresos) {
  var total = 0;
  var automaticos = 0;
  var manuales = 0;

  for (final i in ingresos) {
    if (i.estatus != 'registrado') continue;
    total += i.monto;
    if (i.pagoId != null) {
      automaticos += i.monto;
    } else {
      manuales += i.monto;
    }
  }

  return IngresosResumen(totalIngresos: total, automaticos: automaticos, manuales: manuales);
}

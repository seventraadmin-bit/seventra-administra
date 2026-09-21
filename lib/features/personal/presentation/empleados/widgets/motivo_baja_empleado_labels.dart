import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:riseg_one/features/personal/data/tables/empleado_table.dart';

/// Etiqueta legible de un motivo de baja laboral.
///
/// Vivía dentro de `baja_laboral_empleado_dialog.dart`, retirado al
/// sustituir la baja por el flujo de conciliación. La etiqueta sí se
/// sigue usando (listado de Bajas, expediente), así que se conserva
/// aquí en vez de duplicarse en cada pantalla.
String motivoBajaEmpleadoLabel(AppLocalizations l10n, String valor) {
  return switch (MotivoBajaEmpleado.values.byName(valor)) {
    MotivoBajaEmpleado.abandonoServicio => l10n.motivoBajaEmpleadoAbandonoServicio,
    MotivoBajaEmpleado.robo => l10n.motivoBajaEmpleadoRobo,
    MotivoBajaEmpleado.malaConducta => l10n.motivoBajaEmpleadoMalaConducta,
    MotivoBajaEmpleado.inasistencias => l10n.motivoBajaEmpleadoInasistencias,
    MotivoBajaEmpleado.incumplimientoConsignas => l10n.motivoBajaEmpleadoIncumplimientoConsignas,
    MotivoBajaEmpleado.noAproboCapacitacion => l10n.motivoBajaEmpleadoNoAproboCapacitacion,
    MotivoBajaEmpleado.renuncia => l10n.motivoBajaEmpleadoRenuncia,
    MotivoBajaEmpleado.finContrato => l10n.motivoBajaEmpleadoFinContrato,
    MotivoBajaEmpleado.reduccionPersonal => l10n.motivoBajaEmpleadoReduccionPersonal,
    MotivoBajaEmpleado.otro => l10n.motivoBajaEmpleadoOtro,
  };
}

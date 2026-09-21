import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart' show EstatusEmpleado;

import 'bajas_list_screen.dart';
import 'personal_activo_list_screen.dart';

String empleadoNombreCompleto(EmpleadoData empleado) {
  final materno = empleado.apellidoMaterno;
  return '${empleado.nombres} ${empleado.apellidoPaterno}${materno == null ? '' : ' $materno'}';
}

String empleadoEstatusLabel(AppLocalizations l10n, String valor) {
  return switch (EstatusEmpleado.values.byName(valor)) {
    EstatusEmpleado.activo => l10n.empleadoEstatusActivo,
    EstatusEmpleado.baja => l10n.empleadoEstatusBaja,
  };
}

RisegStatusTone empleadoEstatusTono(String valor) {
  return switch (EstatusEmpleado.values.byName(valor)) {
    EstatusEmpleado.activo => RisegStatusTone.success,
    EstatusEmpleado.baja => RisegStatusTone.neutral,
  };
}

/// Línea compacta "Puesto · Servicio · Turno" — mismo formato en el
/// Historial laboral del expediente y en la vista Bajas (Etapa 15),
/// para que ambos lugares muestren el snapshot exactamente igual.
/// Omite los segmentos ausentes; `null` si los 3 son nulos (nunca
/// texto vacío ni "—" repetido tres veces).
String? lineaPuestoServicioTurno({String? puesto, String? servicio, String? turno}) {
  final partes = [puesto, servicio, turno].whereType<String>().where((p) => p.trim().isNotEmpty).toList();
  return partes.isEmpty ? null : partes.join(' · ');
}

/// Empleados (Etapa 5A, rediseñado en la Etapa 15) — dos subpestañas:
/// "Personal activo" (predeterminada) y "Bajas". Un empleado con baja
/// vigente nunca aparece en Personal activo — pasa de inmediato a
/// Bajas (nunca se elimina información histórica, solo cambia la
/// vista). Subpestañas locales (no rutas de `go_router`): mismo
/// contenido de siempre en `/personal/empleados`, sin abrir un nuevo
/// nivel de URL para esta separación puramente visual.
class EmpleadosListScreen extends StatefulWidget {
  const EmpleadosListScreen({this.filtroInicialSinAsignar = false, super.key});

  /// Deep-link real desde el Dashboard (Etapa 20, "Sin asignar").
  final bool filtroInicialSinAsignar;

  @override
  State<EmpleadosListScreen> createState() => _EmpleadosListScreenState();
}

class _EmpleadosListScreenState extends State<EmpleadosListScreen> {
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.xl, AppSpacing.xl, 0),
          child: RisegTabs(
            tabs: [
              RisegTabItem(label: l10n.empleadosTabActivo),
              RisegTabItem(label: l10n.empleadosTabBajas),
            ],
            selectedIndex: _tabIndex,
            onChanged: (index) => setState(() => _tabIndex = index),
          ),
        ),
        Expanded(
          child: switch (_tabIndex) {
            0 => PersonalActivoListScreen(filtroInicialSinAsignar: widget.filtroInicialSinAsignar),
            _ => const BajasListScreen(),
          },
        ),
      ],
    );
  }
}

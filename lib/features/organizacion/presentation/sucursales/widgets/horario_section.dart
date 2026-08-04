import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/sucursal_expediente_errors.dart';
import 'package:riseg_one/features/organizacion/presentation/shared/campo_consulta.dart';
import 'package:riseg_one/features/organizacion/presentation/sucursales/sucursal_expediente_form_controllers.dart';
import 'package:riseg_one/features/organizacion/presentation/sucursales/sucursal_expediente_state.dart';

/// Sección "Horario" — 7 filas fijas (lunes a domingo). `cruzaMedianoche`
/// nunca es un control propio: se infiere al guardar
/// (`GuardarExpedienteSucursalUseCase`), aquí solo se capturan hora de
/// inicio/fin.
class HorarioSection extends StatelessWidget {
  const HorarioSection({
    required this.modo,
    required this.horario,
    required this.controllers,
    required this.habilitado,
    required this.errores,
    required this.onDiaCambiado,
    super.key,
  });

  final SucursalExpedienteModo modo;
  final List<HorarioDetalleData>? horario;
  final HorarioControllers controllers;
  final bool habilitado;
  final List<ErrorHorarioSucursal> errores;

  /// La pantalla decide qué hacer con el cambio (mutar `controllers`,
  /// llamar `setState`, marcar cambios sin guardar) — este widget nunca
  /// muta `controllers` directamente, es puramente presentacional.
  final void Function(int diaSemana, HorarioDiaControlador nuevoValor) onDiaCambiado;

  String _nombreDia(AppLocalizations l10n, int diaSemana) {
    return switch (diaSemana) {
      0 => l10n.horarioDiaLunes,
      1 => l10n.horarioDiaMartes,
      2 => l10n.horarioDiaMiercoles,
      3 => l10n.horarioDiaJueves,
      4 => l10n.horarioDiaViernes,
      5 => l10n.horarioDiaSabado,
      _ => l10n.horarioDiaDomingo,
    };
  }

  String? _formatoHora(BuildContext context, int minutos) {
    final hora = TimeOfDay(hour: minutos ~/ 60, minute: minutos % 60);
    return hora.format(context);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (modo == SucursalExpedienteModo.consulta) {
      return RisegFormSection(
        title: l10n.sucursalSeccionHorarioTitulo,
        children: [
          for (var dia = 0; dia < 7; dia++) _filaConsulta(context, l10n, dia),
        ],
      );
    }

    return RisegFormSection(
      title: l10n.sucursalSeccionHorarioTitulo,
      children: [
        for (var dia = 0; dia < 7; dia++) _filaEdicion(context, l10n, dia),
      ],
    );
  }

  Widget _filaConsulta(BuildContext context, AppLocalizations l10n, int diaSemana) {
    HorarioDetalleData? detalle;
    for (final d in horario ?? const <HorarioDetalleData>[]) {
      if (d.diaSemana == diaSemana) detalle = d;
    }
    final abierto = detalle?.activo ?? false;
    final valor = !abierto
        ? null
        : '${_formatoHora(context, detalle!.horaInicio)} – ${_formatoHora(context, detalle.horaFin)}';

    return CampoConsulta(label: _nombreDia(l10n, diaSemana), value: valor);
  }

  Widget _filaEdicion(BuildContext context, AppLocalizations l10n, int diaSemana) {
    final colors = context.colors;
    final dia = controllers.dias[diaSemana];
    final errorHoraInicio = _tieneError(diaSemana, CodigoErrorHorario.horaInicioRequerida)
        ? l10n.horarioErrorHoraInicioRequerida
        : null;
    final errorHoraFin = _tieneError(diaSemana, CodigoErrorHorario.horaFinRequerida)
        ? l10n.horarioErrorHoraFinRequerida
        : _tieneError(diaSemana, CodigoErrorHorario.horasIguales)
            ? l10n.horarioErrorHorasIguales
            : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(_nombreDia(l10n, diaSemana), style: AppTypography.body.copyWith(color: colors.textPrimary)),
              ),
              Text(l10n.horarioAbierto, style: AppTypography.caption.copyWith(color: colors.textMuted)),
              Switch(
                value: dia.abierto,
                onChanged: habilitado
                    ? (valor) => onDiaCambiado(
                          diaSemana,
                          HorarioDiaControlador(abierto: valor, horaInicio: dia.horaInicio, horaFin: dia.horaFin),
                        )
                    : null,
              ),
            ],
          ),
          if (dia.abierto)
            Row(
              children: [
                Expanded(
                  child: RisegTimeField(
                    label: l10n.horarioCampoHoraInicio,
                    value: dia.horaInicio,
                    enabled: habilitado,
                    errorText: errorHoraInicio,
                    onChanged: (valor) => onDiaCambiado(
                      diaSemana,
                      HorarioDiaControlador(abierto: true, horaInicio: valor, horaFin: dia.horaFin),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: RisegTimeField(
                    label: l10n.horarioCampoHoraFin,
                    value: dia.horaFin,
                    enabled: habilitado,
                    errorText: errorHoraFin,
                    onChanged: (valor) => onDiaCambiado(
                      diaSemana,
                      HorarioDiaControlador(abierto: true, horaInicio: dia.horaInicio, horaFin: valor),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  bool _tieneError(int diaSemana, CodigoErrorHorario codigo) {
    return errores.any((error) => error.dia.index == diaSemana && error.codigo == codigo);
  }
}

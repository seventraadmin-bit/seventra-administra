import 'package:flutter/material.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/domain/shared/horario_input.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/sucursal_expediente_input.dart';

/// Controles de "Datos generales" — `tipoSucursalId` no es un
/// `TextEditingController` (lo maneja `RisegSelect`, no un campo de
/// texto), así que vive como un campo mutable simple; el widget de
/// pantalla decide cuándo reconstruirse (`setState`) al cambiarlo.
class SucursalDatosGeneralesControllers {
  SucursalDatosGeneralesControllers() : nombre = TextEditingController();

  final TextEditingController nombre;
  String? tipoSucursalId;

  void poblar(SucursalData sucursal) {
    nombre.text = sucursal.nombre;
    tipoSucursalId = sucursal.tipoSucursalId;
  }

  SucursalDatosGeneralesInput capturar() =>
      SucursalDatosGeneralesInput(nombre: nombre.text, tipoSucursalId: tipoSucursalId ?? '');

  void dispose() => nombre.dispose();
}

/// Borrador mutable de un día de Horario — igual razón que
/// `tipoSucursalId`: ni el toggle "Abierto" ni `RisegTimeField` usan
/// `TextEditingController`.
class HorarioDiaControlador {
  HorarioDiaControlador({this.abierto = false, this.horaInicio, this.horaFin});

  bool abierto;
  TimeOfDay? horaInicio;
  TimeOfDay? horaFin;
}

/// Los 7 días (índice 0 = lunes ... 6 = domingo), siempre presentes.
class HorarioControllers {
  HorarioControllers() : dias = List.generate(7, (_) => HorarioDiaControlador());

  final List<HorarioDiaControlador> dias;

  void poblar(List<HorarioDetalleData>? horario) {
    for (final dia in dias) {
      dia.abierto = false;
      dia.horaInicio = null;
      dia.horaFin = null;
    }
    if (horario == null) return;

    for (final detalle in horario) {
      final dia = dias[detalle.diaSemana];
      dia.abierto = detalle.activo;
      if (dia.abierto) {
        dia.horaInicio = _minutosATimeOfDay(detalle.horaInicio);
        dia.horaFin = _minutosATimeOfDay(detalle.horaFin);
      }
    }
  }

  HorarioSemanalBorrador capturar() => HorarioSemanalBorrador(
        dias: [
          for (final dia in dias)
            HorarioDiaBorrador(
              abierto: dia.abierto,
              horaInicioMinutos: dia.horaInicio == null ? null : _timeOfDayAMinutos(dia.horaInicio!),
              horaFinMinutos: dia.horaFin == null ? null : _timeOfDayAMinutos(dia.horaFin!),
            ),
        ],
      );

  static TimeOfDay _minutosATimeOfDay(int minutos) => TimeOfDay(hour: minutos ~/ 60, minute: minutos % 60);

  static int _timeOfDayAMinutos(TimeOfDay hora) => hora.hour * 60 + hora.minute;
}

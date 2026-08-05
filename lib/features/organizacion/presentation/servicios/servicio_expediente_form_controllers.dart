import 'package:flutter/widgets.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';

/// Controles de "Datos generales" de Servicio — nombre y observaciones
/// son `TextEditingController` (mismo patrón que
/// `ClienteDatosGeneralesControllers`); Tipo de Servicio y fecha de
/// inicio no son texto libre, así que viven como valores simples, no
/// controllers.
class ServicioDatosGeneralesControllers {
  ServicioDatosGeneralesControllers()
      : nombre = TextEditingController(),
        observaciones = TextEditingController();

  final TextEditingController nombre;
  final TextEditingController observaciones;
  String tipoServicioId = '';
  DateTime? fechaInicio;

  void poblar(ServicioData servicio) {
    nombre.text = servicio.nombre;
    observaciones.text = servicio.observaciones ?? '';
    tipoServicioId = servicio.tipoServicioId;
    fechaInicio = servicio.fechaInicio;
  }

  ServicioBorrador capturar() => ServicioBorrador(
        nombre: nombre.text,
        tipoServicioId: tipoServicioId,
        fechaInicio: fechaInicio,
        observaciones: observaciones.text,
      );

  void dispose() {
    nombre.dispose();
    observaciones.dispose();
  }
}

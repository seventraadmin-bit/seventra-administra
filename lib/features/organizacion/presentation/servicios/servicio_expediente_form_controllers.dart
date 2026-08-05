import 'package:flutter/widgets.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';

/// Controles del formulario conjunto de "Datos generales" + "Referencias"
/// de Servicio (Etapa 4F.2, resolución B: comparten un solo ciclo de
/// Editar/Guardar, aunque se muestran en dos secciones/widgets
/// separados) — nombre/observaciones/referencia comercial/referencia
/// contractual son `TextEditingController` (mismo patrón que
/// `ClienteDatosGeneralesControllers`); Tipo de Servicio y fecha de
/// inicio no son texto libre, así que viven como valores simples, no
/// controllers.
class ServicioDatosGeneralesControllers {
  ServicioDatosGeneralesControllers()
      : nombre = TextEditingController(),
        observaciones = TextEditingController(),
        referenciaComercial = TextEditingController(),
        referenciaContractual = TextEditingController();

  final TextEditingController nombre;
  final TextEditingController observaciones;
  final TextEditingController referenciaComercial;
  final TextEditingController referenciaContractual;
  String tipoServicioId = '';
  DateTime? fechaInicio;

  void poblar(ServicioData servicio) {
    nombre.text = servicio.nombre;
    observaciones.text = servicio.observaciones ?? '';
    referenciaComercial.text = servicio.referenciaComercial ?? '';
    referenciaContractual.text = servicio.referenciaContractual ?? '';
    tipoServicioId = servicio.tipoServicioId;
    fechaInicio = servicio.fechaInicio;
  }

  ServicioBorrador capturar() => ServicioBorrador(
        nombre: nombre.text,
        tipoServicioId: tipoServicioId,
        fechaInicio: fechaInicio,
        observaciones: observaciones.text,
        referenciaComercial: referenciaComercial.text,
        referenciaContractual: referenciaContractual.text,
      );

  void dispose() {
    nombre.dispose();
    observaciones.dispose();
    referenciaComercial.dispose();
    referenciaContractual.dispose();
  }
}

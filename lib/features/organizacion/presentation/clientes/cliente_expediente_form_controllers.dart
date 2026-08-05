import 'package:flutter/widgets.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cliente_expediente_input.dart';

/// Controles de "Datos generales" de Cliente comercial.
class ClienteDatosGeneralesControllers {
  ClienteDatosGeneralesControllers()
      : nombreComercial = TextEditingController(),
        observaciones = TextEditingController();

  final TextEditingController nombreComercial;
  final TextEditingController observaciones;

  void poblar(ClienteData cliente) {
    nombreComercial.text = cliente.nombreComercial;
    observaciones.text = cliente.observaciones ?? '';
  }

  ClienteDatosGeneralesInput capturar() => ClienteDatosGeneralesInput(
        nombreComercial: nombreComercial.text,
        observaciones: observaciones.text,
      );

  void dispose() {
    nombreComercial.dispose();
    observaciones.dispose();
  }
}

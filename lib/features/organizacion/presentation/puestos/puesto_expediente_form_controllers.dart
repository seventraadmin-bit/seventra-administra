import 'package:flutter/widgets.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/data/tables/puesto_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/puesto_validator.dart';

/// Controles de "Datos generales" de Puesto — `areaId`/`tipo` no son
/// `TextEditingController` (los maneja `RisegSelect`), así que viven
/// como campos mutables simples que la pantalla actualiza vía
/// `setState`, mismo patrón que `SucursalDatosGeneralesControllers`.
class PuestoDatosGeneralesControllers {
  PuestoDatosGeneralesControllers()
      : nombre = TextEditingController(),
        nivelJerarquico = TextEditingController(),
        descripcion = TextEditingController();

  final TextEditingController nombre;
  final TextEditingController nivelJerarquico;
  final TextEditingController descripcion;
  String? areaId;
  TipoPuesto? tipo;

  void poblar(PuestoData puesto) {
    nombre.text = puesto.nombre;
    nivelJerarquico.text = puesto.nivelJerarquico.toString();
    descripcion.text = puesto.descripcion ?? '';
    areaId = puesto.areaId;
    tipo = TipoPuesto.values.byName(puesto.tipo);
  }

  PuestoBorrador capturar() => PuestoBorrador(
        nombre: nombre.text,
        areaId: areaId ?? '',
        tipo: tipo,
        nivelJerarquico: int.tryParse(nivelJerarquico.text.trim()),
        descripcion: descripcion.text,
      );

  void dispose() {
    nombre.dispose();
    nivelJerarquico.dispose();
    descripcion.dispose();
  }
}

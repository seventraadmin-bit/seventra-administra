import 'package:flutter/widgets.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/validation/direccion_validator.dart';

/// Agrupa los `TextEditingController` de una sección de Dirección
/// genérica (10 campos) — reutilizable por cualquier módulo de
/// Organización que administre una dirección (Sucursal en 4C; Empresa
/// sigue usando su propio `DireccionFiscalControllers` de 4B, sin
/// tocarlo, para no arriesgar código ya aprobado).
class DireccionControllers {
  DireccionControllers()
      : calle = TextEditingController(),
        numeroExterior = TextEditingController(),
        numeroInterior = TextEditingController(),
        colonia = TextEditingController(),
        municipioAlcaldia = TextEditingController(),
        ciudadLocalidad = TextEditingController(),
        estado = TextEditingController(),
        codigoPostal = TextEditingController(),
        pais = TextEditingController(),
        referencias = TextEditingController();

  final TextEditingController calle;
  final TextEditingController numeroExterior;
  final TextEditingController numeroInterior;
  final TextEditingController colonia;
  final TextEditingController municipioAlcaldia;
  final TextEditingController ciudadLocalidad;
  final TextEditingController estado;
  final TextEditingController codigoPostal;
  final TextEditingController pais;
  final TextEditingController referencias;

  void poblar(DireccionData? direccion) {
    calle.text = direccion?.calle ?? '';
    numeroExterior.text = direccion?.numeroExterior ?? '';
    numeroInterior.text = direccion?.numeroInterior ?? '';
    colonia.text = direccion?.colonia ?? '';
    municipioAlcaldia.text = direccion?.municipioAlcaldia ?? '';
    ciudadLocalidad.text = direccion?.ciudadLocalidad ?? '';
    estado.text = direccion?.estado ?? '';
    codigoPostal.text = direccion?.codigoPostal ?? '';
    pais.text = direccion?.pais ?? 'México';
    referencias.text = direccion?.referencias ?? '';
  }

  DireccionBorrador capturar() => DireccionBorrador(
        calle: calle.text,
        numeroExterior: numeroExterior.text,
        numeroInterior: numeroInterior.text,
        colonia: colonia.text,
        municipioAlcaldia: municipioAlcaldia.text,
        ciudadLocalidad: ciudadLocalidad.text,
        estado: estado.text,
        codigoPostal: codigoPostal.text,
        pais: pais.text,
        referencias: referencias.text,
      );

  void dispose() {
    calle.dispose();
    numeroExterior.dispose();
    numeroInterior.dispose();
    colonia.dispose();
    municipioAlcaldia.dispose();
    ciudadLocalidad.dispose();
    estado.dispose();
    codigoPostal.dispose();
    pais.dispose();
    referencias.dispose();
  }
}

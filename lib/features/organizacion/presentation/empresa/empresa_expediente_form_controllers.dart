import 'package:flutter/widgets.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/empresa_expediente_input.dart';

/// Agrupa los `TextEditingController` de "Datos generales". Vive en el
/// widget de pantalla (no en el controlador Riverpod) — ver la nota en
/// `EmpresaExpedienteController`.
class DatosGeneralesControllers {
  DatosGeneralesControllers()
      : nombreComercial = TextEditingController(),
        razonSocial = TextEditingController(),
        rfc = TextEditingController(),
        representanteLegal = TextEditingController(),
        eslogan = TextEditingController();

  final TextEditingController nombreComercial;
  final TextEditingController razonSocial;
  final TextEditingController rfc;
  final TextEditingController representanteLegal;
  final TextEditingController eslogan;

  void poblar(EmpresaData empresa) {
    nombreComercial.text = empresa.nombreComercial;
    razonSocial.text = empresa.razonSocial ?? '';
    rfc.text = empresa.rfc ?? '';
    representanteLegal.text = empresa.representanteLegal ?? '';
    eslogan.text = empresa.eslogan ?? '';
  }

  EmpresaDatosGeneralesInput capturar() => EmpresaDatosGeneralesInput(
        nombreComercial: nombreComercial.text,
        razonSocial: razonSocial.text,
        rfc: rfc.text,
        representanteLegal: representanteLegal.text,
        eslogan: eslogan.text,
      );

  void dispose() {
    nombreComercial.dispose();
    razonSocial.dispose();
    rfc.dispose();
    representanteLegal.dispose();
    eslogan.dispose();
  }
}

/// Agrupa los `TextEditingController` de "Dirección fiscal".
class DireccionFiscalControllers {
  DireccionFiscalControllers()
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

  /// `direccion` nulo (nunca se capturó una) puebla los campos vacíos,
  /// con `país` mostrando "México" como punto de partida editable.
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

  DireccionFiscalBorrador capturar() => DireccionFiscalBorrador(
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

/// Agrupa los `TextEditingController` de "Medios de contacto".
class MedioContactoControllers {
  MedioContactoControllers()
      : telefono = TextEditingController(),
        correo = TextEditingController(),
        sitioWeb = TextEditingController();

  final TextEditingController telefono;
  final TextEditingController correo;
  final TextEditingController sitioWeb;

  void poblar(MedioContactoData? contacto) {
    telefono.text = contacto?.telefono ?? '';
    correo.text = contacto?.correo ?? '';
    sitioWeb.text = contacto?.sitioWeb ?? '';
  }

  MedioContactoBorrador capturar() => MedioContactoBorrador(
        telefono: telefono.text,
        correo: correo.text,
        sitioWeb: sitioWeb.text,
      );

  void dispose() {
    telefono.dispose();
    correo.dispose();
    sitioWeb.dispose();
  }
}

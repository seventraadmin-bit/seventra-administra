// Etapa 16 — Tarjeta fiscal de Empresa. `validarDatosFiscalesTarjeta` es
// función pura: no toca BD. Confirma qué se considera indispensable
// (razón social, RFC, domicilio fiscal) y qué NUNCA se exige (correo/
// teléfono/sitio web son de contacto, no fiscales; régimen fiscal/uso
// de CFDI ni siquiera existen como campo en el modelo hoy, así que
// nunca pueden aparecer como requeridos).

import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/empresa_expediente_data.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/validar_datos_fiscales_tarjeta.dart';

EmpresaData _empresa({String? razonSocial, String? rfc}) {
  final ahora = DateTime(2026, 1, 1);
  return EmpresaData(
    id: 'empresa-1',
    codigo: 'RSG-01',
    razonSocial: razonSocial,
    nombreComercial: 'Seguridad Privada RISEG',
    rfc: rfc,
    representanteLegal: null,
    eslogan: null,
    logoAttachmentId: null,
    cicloVidaRegistro: 'activo',
    createdAt: ahora,
    updatedAt: ahora,
  );
}

DireccionData _direccion() {
  final ahora = DateTime(2026, 1, 1);
  return DireccionData(
    id: 'direccion-1',
    empresaId: 'empresa-1',
    sucursalId: null,
    clienteId: null,
    servicioId: null,
    entidadFiscalId: null,
    empleadoId: null,
    tipoDireccion: 'fiscal',
    esPrincipal: true,
    calle: 'Valle de los Reyes',
    numeroExterior: '2',
    numeroInterior: null,
    colonia: 'Valle del Nevado',
    municipioAlcaldia: 'Calimaya',
    ciudadLocalidad: null,
    estado: 'Estado de México',
    codigoPostal: '52224',
    pais: 'México',
    referencias: null,
    cicloVidaRegistro: 'activo',
    createdAt: ahora,
    updatedAt: ahora,
  );
}

void main() {
  test('empresa completa (razón social + RFC + domicilio) → nada falta', () {
    final datos = EmpresaExpedienteData(
      empresa: _empresa(razonSocial: 'CORPORATIVO DE SEGURIDAD PRIVADA RIZEG SAS DE CV', rfc: 'CSP123456AB1'),
      direccionFiscal: _direccion(),
    );

    expect(validarDatosFiscalesTarjeta(datos), isEmpty);
  });

  test('sin razón social → falta reportada', () {
    final datos = EmpresaExpedienteData(empresa: _empresa(razonSocial: null, rfc: 'CSP123456AB1'), direccionFiscal: _direccion());

    expect(validarDatosFiscalesTarjeta(datos), [CampoFiscalFaltante.razonSocial]);
  });

  test('razón social solo espacios en blanco cuenta como faltante', () {
    final datos = EmpresaExpedienteData(empresa: _empresa(razonSocial: '   ', rfc: 'CSP123456AB1'), direccionFiscal: _direccion());

    expect(validarDatosFiscalesTarjeta(datos), [CampoFiscalFaltante.razonSocial]);
  });

  test('sin RFC → falta reportada', () {
    final datos = EmpresaExpedienteData(empresa: _empresa(razonSocial: 'Razón', rfc: null), direccionFiscal: _direccion());

    expect(validarDatosFiscalesTarjeta(datos), [CampoFiscalFaltante.rfc]);
  });

  test('sin domicilio fiscal → falta reportada', () {
    final datos = EmpresaExpedienteData(empresa: _empresa(razonSocial: 'Razón', rfc: 'CSP123456AB1'), direccionFiscal: null);

    expect(validarDatosFiscalesTarjeta(datos), [CampoFiscalFaltante.domicilioFiscal]);
  });

  test('faltan los 3 → los 3 se reportan, en el orden razonSocial/rfc/domicilioFiscal', () {
    final datos = EmpresaExpedienteData(empresa: _empresa(razonSocial: null, rfc: null), direccionFiscal: null);

    expect(validarDatosFiscalesTarjeta(datos), [
      CampoFiscalFaltante.razonSocial,
      CampoFiscalFaltante.rfc,
      CampoFiscalFaltante.domicilioFiscal,
    ]);
  });

  test('sin correo/teléfono/sitio web (medioContacto null): NUNCA bloquea — son de contacto, no fiscales', () {
    final datos = EmpresaExpedienteData(
      empresa: _empresa(razonSocial: 'Razón', rfc: 'CSP123456AB1'),
      direccionFiscal: _direccion(),
      medioContacto: null,
    );

    expect(validarDatosFiscalesTarjeta(datos), isEmpty);
  });
}

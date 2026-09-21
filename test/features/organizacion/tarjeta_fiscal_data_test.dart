// Etapa 16 — Tarjeta fiscal de Empresa. Funciones puras
// `construirLineasDomicilioFiscal`/`construirTarjetaFiscalData`: mismo
// formato para preview, PDF y "Copiar datos" (una sola fuente).

import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/empresa_expediente_data.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/tarjeta_fiscal_data.dart';

DireccionData _direccion({String? numeroInterior, String? ciudadLocalidad}) {
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
    numeroInterior: numeroInterior,
    colonia: 'Valle del Nevado',
    municipioAlcaldia: 'Calimaya',
    ciudadLocalidad: ciudadLocalidad,
    estado: 'Estado de México',
    codigoPostal: '52224',
    pais: 'México',
    referencias: null,
    cicloVidaRegistro: 'activo',
    createdAt: ahora,
    updatedAt: ahora,
  );
}

EmpresaData _empresa() {
  final ahora = DateTime(2026, 1, 1);
  return EmpresaData(
    id: 'empresa-1',
    codigo: 'RSG-01',
    razonSocial: 'CORPORATIVO DE SEGURIDAD PRIVADA RIZEG SAS DE CV',
    nombreComercial: 'Seguridad Privada RISEG',
    rfc: 'CSP123456AB1',
    representanteLegal: null,
    eslogan: null,
    logoAttachmentId: null,
    cicloVidaRegistro: 'activo',
    createdAt: ahora,
    updatedAt: ahora,
  );
}

MedioContactoData _contacto({String? correo, String? telefono, String? sitioWeb}) {
  final ahora = DateTime(2026, 1, 1);
  return MedioContactoData(
    id: 'contacto-1',
    empresaId: 'empresa-1',
    sucursalId: null,
    telefono: telefono,
    correo: correo,
    sitioWeb: sitioWeb,
    etiqueta: 'principal',
    cicloVidaRegistro: 'activo',
    createdAt: ahora,
    updatedAt: ahora,
  );
}

void main() {
  group('construirLineasDomicilioFiscal', () {
    test('sin número interior — la primera línea es "calle numeroExterior"', () {
      final lineas = construirLineasDomicilioFiscal(_direccion());
      expect(lineas[0], 'Valle de los Reyes 2');
    });

    test('con número interior — se agrega "INT. N" a la primera línea', () {
      final lineas = construirLineasDomicilioFiscal(_direccion(numeroInterior: '9'));
      expect(lineas[0], 'Valle de los Reyes 2 INT. 9');
    });

    test('sin ciudad/localidad — la tercera línea es solo "municipio, estado"', () {
      final lineas = construirLineasDomicilioFiscal(_direccion());
      expect(lineas[2], 'Calimaya, Estado de México');
    });

    test('con ciudad/localidad — antecede a municipio/estado', () {
      final lineas = construirLineasDomicilioFiscal(_direccion(ciudadLocalidad: 'Toluca'));
      expect(lineas[2], 'Toluca, Calimaya, Estado de México');
    });

    test('incluye colonia, C.P. y país en el orden esperado', () {
      final lineas = construirLineasDomicilioFiscal(_direccion());
      expect(lineas, ['Valle de los Reyes 2', 'Valle del Nevado', 'Calimaya, Estado de México', 'C.P. 52224', 'México']);
    });
  });

  group('construirTarjetaFiscalData', () {
    test('sin domicilio (direccionFiscal null) — domicilioLineas vacío, nunca lanza', () {
      final data = construirTarjetaFiscalData(EmpresaExpedienteData(empresa: _empresa()));
      expect(data.domicilioLineas, isEmpty);
    });

    test('sin medioContacto — correo/teléfono/sitioWeb quedan null, no placeholders inventados', () {
      final data = construirTarjetaFiscalData(EmpresaExpedienteData(empresa: _empresa(), direccionFiscal: _direccion()));
      expect(data.correo, isNull);
      expect(data.telefono, isNull);
      expect(data.sitioWeb, isNull);
    });

    test('correo en blanco (solo espacios) se normaliza a null', () {
      final data = construirTarjetaFiscalData(
        EmpresaExpedienteData(empresa: _empresa(), direccionFiscal: _direccion(), medioContacto: _contacto(correo: '   ')),
      );
      expect(data.correo, isNull);
    });

    test('con contacto completo, los 3 campos se copian tal cual', () {
      final data = construirTarjetaFiscalData(
        EmpresaExpedienteData(
          empresa: _empresa(),
          direccionFiscal: _direccion(),
          medioContacto: _contacto(correo: 'facturacion@riseg.mx', telefono: '5555555555', sitioWeb: 'https://riseg.mx'),
        ),
      );
      expect(data.correo, 'facturacion@riseg.mx');
      expect(data.telefono, '5555555555');
      expect(data.sitioWeb, 'https://riseg.mx');
    });

    test('generadoEn explícito se respeta (para pruebas deterministas)', () {
      final fecha = DateTime(2026, 8, 21, 10, 30);
      final data = construirTarjetaFiscalData(EmpresaExpedienteData(empresa: _empresa()), generadoEn: fecha);
      expect(data.generadoEn, fecha);
    });
  });
}

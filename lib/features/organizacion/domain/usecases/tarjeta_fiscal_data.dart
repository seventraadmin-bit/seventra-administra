import 'package:riseg_one/core/database/app_database.dart';

import 'empresa_expediente_data.dart';

String? _vacioANull(String? valor) {
  final recortado = valor?.trim();
  return (recortado == null || recortado.isEmpty) ? null : recortado;
}

/// Domicilio fiscal como líneas de texto ya formateadas, en el mismo
/// orden en el que se muestran (preview/PDF/copiar) — función pura,
/// única fuente de este formato para no tener 3 formatos ligeramente
/// distintos entre pantalla, PDF y portapapeles.
List<String> construirLineasDomicilioFiscal(DireccionData direccion) {
  final numeroInterior = _vacioANull(direccion.numeroInterior);
  final calleNumero = numeroInterior == null
      ? '${direccion.calle} ${direccion.numeroExterior}'
      : '${direccion.calle} ${direccion.numeroExterior} INT. $numeroInterior';

  final ciudadLocalidad = _vacioANull(direccion.ciudadLocalidad);
  final tercerLinea = [
    if (ciudadLocalidad != null) ciudadLocalidad,
    direccion.municipioAlcaldia,
    direccion.estado,
  ].join(', ');

  return [calleNumero, direccion.colonia, tercerLinea, 'C.P. ${direccion.codigoPostal}', direccion.pais];
}

/// Datos ya resueltos para la Tarjeta fiscal (Etapa 16) — usados tanto
/// por la previsualización, el PDF, como "Copiar datos": una sola
/// fuente de verdad para lo que se muestra. Solo contiene lo que
/// `validarDatosFiscalesTarjeta` ya confirmó que existe para
/// razonSocial/rfc/domicilio — este constructor NO valida, el llamador
/// decide si procede tras consultar esa función.
class TarjetaFiscalData {
  const TarjetaFiscalData({
    required this.nombreComercial,
    required this.razonSocial,
    required this.rfc,
    required this.domicilioLineas,
    this.correo,
    this.telefono,
    this.sitioWeb,
    required this.generadoEn,
  });

  final String nombreComercial;
  final String razonSocial;
  final String rfc;
  final List<String> domicilioLineas;

  /// Correo/teléfono/sitio web de contacto — `null` si no están
  /// capturados; nunca bloquean la generación (ver
  /// `validarDatosFiscalesTarjeta`).
  final String? correo;
  final String? telefono;
  final String? sitioWeb;

  final DateTime generadoEn;
}

/// Construye [TarjetaFiscalData] a partir del expediente de Empresa ya
/// cargado — función pura. El llamador debe haber verificado antes con
/// `validarDatosFiscalesTarjeta` que no faltan campos indispensables;
/// aquí simplemente se asume esa garantía (razonSocial/rfc no vacíos,
/// direccionFiscal no nula) para no repetir la misma validación dos
/// veces con criterios que podrían divergir.
TarjetaFiscalData construirTarjetaFiscalData(EmpresaExpedienteData datos, {DateTime? generadoEn}) {
  final empresa = datos.empresa;
  final direccion = datos.direccionFiscal;
  return TarjetaFiscalData(
    nombreComercial: empresa.nombreComercial,
    razonSocial: (empresa.razonSocial ?? '').trim(),
    rfc: (empresa.rfc ?? '').trim(),
    domicilioLineas: direccion == null ? const [] : construirLineasDomicilioFiscal(direccion),
    correo: _vacioANull(datos.medioContacto?.correo),
    telefono: _vacioANull(datos.medioContacto?.telefono),
    sitioWeb: _vacioANull(datos.medioContacto?.sitioWeb),
    generadoEn: generadoEn ?? DateTime.now(),
  );
}

import 'dart:io';
import 'dart:typed_data';

import 'package:riseg_one/core/attachments/attachment_repository.dart';
import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/features/reportes/domain/export/exportar_reporte_resultado.dart';
import 'package:riseg_one/features/reportes/domain/export/guardar_y_abrir_reporte.dart';

import '../../data/pdf/tarjeta_fiscal_pdf_renderer.dart';
import 'empresa_expediente_data.dart';
import 'obtener_expediente_empresa_usecase.dart';
import 'tarjeta_fiscal_data.dart';
import 'validar_datos_fiscales_tarjeta.dart';

sealed class GenerarTarjetaFiscalPdfResultado {}

class GenerarTarjetaFiscalPdfExitoso extends GenerarTarjetaFiscalPdfResultado {
  GenerarTarjetaFiscalPdfExitoso(this.rutaArchivo);
  final String rutaArchivo;
}

/// Faltan campos indispensables (ver `validarDatosFiscalesTarjeta`) — el
/// PDF nunca se genera luciendo completo cuando no lo está.
class GenerarTarjetaFiscalPdfDatosIncompletos extends GenerarTarjetaFiscalPdfResultado {
  GenerarTarjetaFiscalPdfDatosIncompletos(this.faltantes);
  final List<CampoFiscalFaltante> faltantes;
}

class GenerarTarjetaFiscalPdfErrorInesperado extends GenerarTarjetaFiscalPdfResultado {
  GenerarTarjetaFiscalPdfErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Genera el PDF de la Tarjeta fiscal de Empresa (Etapa 16). Vuelve a
/// consultar el expediente completo en el momento de generar — nunca
/// reutiliza el estado ya cargado de la pantalla — para que el PDF
/// siempre refleje los datos ACTUALES de Empresa (pedido explícito:
/// "el PDF debe reflejar los datos actuales... en el momento de
/// generarlo"). No se persiste como `Attachment` ni se guarda
/// snapshot/historial: es 100% regenerable desde `Empresa`/
/// `Direccion`/`MedioContacto`, mismo criterio que el Recibo de pago.
class GenerarTarjetaFiscalPdfUseCase {
  GenerarTarjetaFiscalPdfUseCase(
    this._obtenerExpediente,
    this._attachmentRepository,
    this._attachmentStorage,
    this._datosFiscalesDir,
    this._renderer,
  );

  final ObtenerExpedienteEmpresaUseCase _obtenerExpediente;
  final AttachmentRepository _attachmentRepository;
  final AttachmentStorage _attachmentStorage;
  final String _datosFiscalesDir;
  final TarjetaFiscalPdfRenderer _renderer;

  /// LOGOTIPO (Etapa 5B.2): sólo el de la Empresa; sin él, la tarjeta se
  /// emite sin logotipo. Mismo criterio que `GenerarReciboPagoPdfUseCase`,
  /// donde está explicado el porqué.
  Future<GenerarTarjetaFiscalPdfResultado> ejecutar() async {
    final expedienteResult = await _obtenerExpediente.ejecutar();
    return expedienteResult.when(
      ok: (datos) => _generar(datos),
      failure: (f) async => GenerarTarjetaFiscalPdfErrorInesperado(f.message),
    );
  }

  Future<GenerarTarjetaFiscalPdfResultado> _generar(EmpresaExpedienteData datos) async {
    final faltantes = validarDatosFiscalesTarjeta(datos);
    if (faltantes.isNotEmpty) return GenerarTarjetaFiscalPdfDatosIncompletos(faltantes);

    try {
      final logoBytes = await _leerBytesAttachment(datos.empresa.logoAttachmentId);
      final data = construirTarjetaFiscalData(datos);
      final pdfBytes = await _renderer.renderizar(data: data, logoBytes: logoBytes);

      final resultado = await guardarYAbrirReporte(
        bytes: pdfBytes,
        nombreBase: 'RISEG_Datos_Fiscales',
        extension: 'pdf',
        generadoEn: data.generadoEn,
        reportesDir: _datosFiscalesDir,
        attachmentStorage: _attachmentStorage,
      );
      return switch (resultado) {
        ExportarReporteExitoso(:final rutaArchivo) => GenerarTarjetaFiscalPdfExitoso(rutaArchivo),
        ExportarReporteErrorInesperado(:final mensaje) => GenerarTarjetaFiscalPdfErrorInesperado(mensaje),
      };
    } catch (e) {
      return GenerarTarjetaFiscalPdfErrorInesperado(e.toString());
    }
  }

  Future<Uint8List?> _leerBytesAttachment(String? attachmentId) async {
    if (attachmentId == null) return null;
    final attachment = await _attachmentRepository.obtenerPorId(attachmentId);
    if (attachment == null) return null;
    final file = File(attachment.path);
    if (!file.existsSync()) return null;
    return file.readAsBytes();
  }
}

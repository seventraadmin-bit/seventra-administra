import 'dart:io';
import 'dart:typed_data';

import 'package:riseg_one/core/attachments/attachment_repository.dart';
import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/features/reportes/domain/export/exportar_reporte_resultado.dart';
import 'package:riseg_one/features/reportes/domain/export/guardar_y_abrir_reporte.dart';

import '../../data/pdf/recibo_pago_pdf_renderer.dart';
import '../../data/tables/configuracion_cobro_vigencia_table.dart';
import '../repositories/cliente_repository.dart';
import '../repositories/documento_por_emitir_repository.dart';
import '../repositories/empresa_repository.dart';
import '../repositories/servicio_repository.dart';
import 'recibo_pago_pdf_data.dart';

sealed class GenerarReciboPagoPdfResultado {}

class GenerarReciboPagoPdfExitoso extends GenerarReciboPagoPdfResultado {
  GenerarReciboPagoPdfExitoso(this.rutaArchivo);
  final String rutaArchivo;
}

class GenerarReciboPagoPdfNoExiste extends GenerarReciboPagoPdfResultado {}

/// El documento no es un Recibo de pago (`tipoDocumento == cfdi`) — el
/// PDF administrativo de RISEG ONE nunca sustituye ni acompaña a un
/// CFDI: RISEG ONE controla la agenda/emisión/cobro de un CFDI pero
/// nunca timbra ni genera su representación impresa (Etapa 15).
class GenerarReciboPagoPdfTipoDocumentoInvalido extends GenerarReciboPagoPdfResultado {}

class GenerarReciboPagoPdfErrorInesperado extends GenerarReciboPagoPdfResultado {
  GenerarReciboPagoPdfErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Genera el PDF administrativo del Recibo de pago de un
/// `DocumentoPorEmitir` (Etapa 15) — documento entregable al Cliente,
/// nunca un CFDI. Orquesta, en este orden: obtener el detalle del
/// documento → validar que sea Recibo de pago → reunir Cliente/
/// Servicio(s)/Empresa (solo datos ya existentes, nunca inventados) →
/// resolver bytes del logotipo (el de `Empresa.logoAttachmentId` si
/// existe; si no, el asset oficial ya usado en el resto de la app,
/// nunca uno distinto ni duplicado) → renderizar
/// (`ReciboPagoPdfRenderer`, puro) → guardarlo en `recibosDir`
/// (`AppPaths.recibosDir` en producción — se recibe como `String`, no
/// como `AppPaths` completo, mismo criterio que
/// `ExportarReporteGeneralPdfUseCase`: permite probarse con un
/// directorio temporal sin depender de `path_provider`) y abrirlo —
/// mismo mecanismo que Reportes (`guardarYAbrirReporte`): un recibo es
/// 100% regenerable desde la BD, así que nunca se registra como
/// `Attachment`.
class GenerarReciboPagoPdfUseCase {
  GenerarReciboPagoPdfUseCase(
    this._documentoRepository,
    this._clienteRepository,
    this._servicioRepository,
    this._empresaRepository,
    this._attachmentRepository,
    this._attachmentStorage,
    this._recibosDir,
    this._renderer,
  );

  final DocumentoPorEmitirRepository _documentoRepository;
  final ClienteRepository _clienteRepository;
  final ServicioRepository _servicioRepository;
  final EmpresaRepository _empresaRepository;
  final AttachmentRepository _attachmentRepository;
  final AttachmentStorage _attachmentStorage;
  final String _recibosDir;
  final ReciboPagoPdfRenderer _renderer;

  /// `logoFallbackBytes` es el asset oficial de RISEG
  /// (`assets/images/logo.png`, el mismo que ya usa el resto de la
  /// app), ya resuelto por el llamador — este use case es dominio puro
  /// y no conoce `rootBundle`/Flutter. Se usa únicamente si `Empresa`
  /// no tiene `logoAttachmentId` configurado (hoy siempre el caso: no
  /// existe todavía ninguna pantalla que permita subir un logotipo
  /// propio a Empresa) — la prioridad real siempre es el Attachment de
  /// Empresa cuando exista.
  Future<GenerarReciboPagoPdfResultado> ejecutar({
    required String documentoPorEmitirId,
    Uint8List? logoFallbackBytes,
  }) async {
    final detalle = await _documentoRepository.obtenerDetalle(documentoPorEmitirId);
    if (detalle == null) return GenerarReciboPagoPdfNoExiste();

    final documento = detalle.documento;
    if (TipoDocumentoCobro.values.byName(documento.tipoDocumento) != TipoDocumentoCobro.reciboDePago) {
      return GenerarReciboPagoPdfTipoDocumentoInvalido();
    }

    try {
      final cliente = await _clienteRepository.obtenerPorId(documento.clienteId);

      final servicios = <String>[];
      for (final servicioId in detalle.servicioIds) {
        final servicio = await _servicioRepository.obtenerPorId(servicioId);
        // Guion simple, nunca em-dash: el Helvetica base del paquete
        // `pdf` no tiene el glifo de em-dash (Etapa 15, hallazgo real
        // — confirmado por la propia advertencia del paquete al
        // renderizar en pruebas).
        if (servicio != null) servicios.add('${servicio.codigo} - ${servicio.nombre}');
      }

      final empresa = await _empresaRepository.obtenerActiva();
      final logoBytes = await _leerBytesAttachment(empresa.logoAttachmentId) ?? logoFallbackBytes;
      final contacto = await _empresaRepository.obtenerMedioContactoPrincipal(empresa.id);

      final data = construirReciboPagoPdfData(
        detalle: detalle,
        cliente: cliente,
        servicios: servicios,
        empresa: empresa,
        contacto: contacto,
      );

      final pdfBytes = await _renderer.renderizar(data: data, logoBytes: logoBytes);

      final resultado = await guardarYAbrirReporte(
        bytes: pdfBytes,
        nombreBase: 'recibo_${documento.codigo}',
        extension: 'pdf',
        generadoEn: DateTime.now(),
        reportesDir: _recibosDir,
        attachmentStorage: _attachmentStorage,
      );
      return switch (resultado) {
        ExportarReporteExitoso(:final rutaArchivo) => GenerarReciboPagoPdfExitoso(rutaArchivo),
        ExportarReporteErrorInesperado(:final mensaje) => GenerarReciboPagoPdfErrorInesperado(mensaje),
      };
    } catch (e) {
      return GenerarReciboPagoPdfErrorInesperado(e.toString());
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

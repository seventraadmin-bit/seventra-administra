import 'dart:io';
import 'dart:typed_data';

import 'package:riseg_one/core/attachments/attachment_repository.dart';
import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/empresa_repository.dart';
import 'package:riseg_one/features/reportes/domain/export/exportar_reporte_resultado.dart';
import 'package:riseg_one/features/reportes/domain/export/guardar_y_abrir_reporte.dart';

import '../../data/pdf/nomina_dispersion_pdf_renderer.dart';
import '../repositories/nomina_repository.dart';
import 'nomina_dispersion_pdf_data.dart';

sealed class GenerarNominaDispersionPdfResultado {}

class GenerarNominaDispersionPdfExitoso extends GenerarNominaDispersionPdfResultado {
  GenerarNominaDispersionPdfExitoso(this.rutaArchivo);
  final String rutaArchivo;
}

class GenerarNominaDispersionPdfNoExiste extends GenerarNominaDispersionPdfResultado {}

/// Solo se genera como documento definitivo para una Nómina Cerrada o
/// Pagada — en Borrador los renglones todavía pueden cambiar (Actualizar
/// desde Personal, movimientos manuales), así que un PDF de dispersión
/// en ese momento no sería confiable para ejecutar transferencias.
class GenerarNominaDispersionPdfNominaEnBorrador extends GenerarNominaDispersionPdfResultado {}

class GenerarNominaDispersionPdfSinEmpleados extends GenerarNominaDispersionPdfResultado {}

class GenerarNominaDispersionPdfErrorInesperado extends GenerarNominaDispersionPdfResultado {
  GenerarNominaDispersionPdfErrorInesperado(this.mensaje);
  final String mensaje;
}

/// "Generar PDF de dispersión" (Etapa 15) — hoja operativa para
/// ejecutar/verificar transferencias bancarias de una Nómina ya
/// Cerrada o Pagada. Usa EXCLUSIVAMENTE el snapshot ya guardado en
/// `NominaEmpleado` (banco, cuenta/tarjeta, CLABE, nombre, montos) —
/// nunca vuelve a consultar el expediente bancario en vivo del
/// Empleado, para que el documento de una Nómina histórica nunca
/// cambie aunque el Empleado corrija después sus datos en Personal.
///
/// No bloquea la generación si algún renglón tiene datos bancarios
/// incompletos — el propio PDF los marca "REQUIERE VERIFICACIÓN"
/// (Resolución explícita de Marlon: advertir, nunca bloquear en esta
/// versión).
///
/// 100% regenerable desde `Nomina`/`NominaEmpleado`: igual que
/// `GenerarReciboPagoPdfUseCase`, nunca se registra como `Attachment`
/// (se guarda en `AppPaths.nominaDispersionDir`, fuera del respaldo).
class GenerarNominaDispersionPdfUseCase {
  GenerarNominaDispersionPdfUseCase(
    this._nominaRepository,
    this._attachmentStorage,
    this._nominaDispersionDir,
    this._renderer,
    this._empresaRepository,
    this._attachmentRepository,
  );

  final NominaRepository _nominaRepository;
  final AttachmentStorage _attachmentStorage;
  final String _nominaDispersionDir;
  final NominaDispersionPdfRenderer _renderer;

  /// Etapa 5B.2 — el logotipo lo pone la Empresa, no el producto.
  ///
  /// Este documento era el único que **nunca** miraba
  /// `Empresa.logoAttachmentId`: el llamador le pasaba directamente el asset
  /// del producto. Hoy lo resuelve él mismo. Con una sola Empresa, "la
  /// Empresa del documento" es la activa; cuando `Nomina` lleve su propia
  /// Empresa, este es el punto que cambia.
  final EmpresaRepository _empresaRepository;
  final AttachmentRepository _attachmentRepository;

  Future<GenerarNominaDispersionPdfResultado> ejecutar({required String nominaId}) async {
    final nomina = await _nominaRepository.obtenerPorId(nominaId);
    if (nomina == null) return GenerarNominaDispersionPdfNoExiste();
    if (nomina.estatus == 'borrador') return GenerarNominaDispersionPdfNominaEnBorrador();

    try {
      final renglones = await _nominaRepository.listarEmpleados(nominaId);
      if (renglones.isEmpty) return GenerarNominaDispersionPdfSinEmpleados();

      final data = construirNominaDispersionPdfData(nomina: nomina, renglones: renglones, fechaGeneracion: DateTime.now());
      final empresa = await _empresaRepository.obtenerActiva();
      final logoBytes = await _leerLogoEmpresa(empresa.logoAttachmentId);
      final pdfBytes = await _renderer.renderizar(
        data: data,
        logoBytes: logoBytes,
        empresaNombreComercial: empresa.nombreComercial,
      );

      final resultado = await guardarYAbrirReporte(
        bytes: pdfBytes,
        // Etapa 5B.3: el nombre del archivo llevaba el de la empresa
        // piloto. Ahora describe el documento, como el resto del proyecto.
        nombreBase: 'Dispersion_${nomina.folio}_${nomina.anio}-${nomina.mes.toString().padLeft(2, '0')}',
        extension: 'pdf',
        generadoEn: DateTime.now(),
        reportesDir: _nominaDispersionDir,
        attachmentStorage: _attachmentStorage,
      );
      return switch (resultado) {
        ExportarReporteExitoso(:final rutaArchivo) => GenerarNominaDispersionPdfExitoso(rutaArchivo),
        ExportarReporteErrorInesperado(:final mensaje) => GenerarNominaDispersionPdfErrorInesperado(mensaje),
      };
    } catch (e) {
      return GenerarNominaDispersionPdfErrorInesperado(e.toString());
    }
  }

  /// Los bytes del logotipo de la Empresa, o `null` si no tiene o el
  /// archivo ya no está. Sin logotipo el PDF se emite sin él — nunca con
  /// uno de reserva.
  Future<Uint8List?> _leerLogoEmpresa(String? attachmentId) async {
    if (attachmentId == null) return null;
    final adjunto = await _attachmentRepository.obtenerPorId(attachmentId);
    if (adjunto == null) return null;
    final archivo = File(adjunto.path);
    if (!archivo.existsSync()) return null;
    return archivo.readAsBytes();
  }
}

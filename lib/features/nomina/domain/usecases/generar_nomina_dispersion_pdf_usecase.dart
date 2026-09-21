import 'dart:typed_data';

import 'package:riseg_one/core/attachments/attachment_storage.dart';
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
  );

  final NominaRepository _nominaRepository;
  final AttachmentStorage _attachmentStorage;
  final String _nominaDispersionDir;
  final NominaDispersionPdfRenderer _renderer;

  Future<GenerarNominaDispersionPdfResultado> ejecutar({
    required String nominaId,
    Uint8List? logoFallbackBytes,
  }) async {
    final nomina = await _nominaRepository.obtenerPorId(nominaId);
    if (nomina == null) return GenerarNominaDispersionPdfNoExiste();
    if (nomina.estatus == 'borrador') return GenerarNominaDispersionPdfNominaEnBorrador();

    try {
      final renglones = await _nominaRepository.listarEmpleados(nominaId);
      if (renglones.isEmpty) return GenerarNominaDispersionPdfSinEmpleados();

      final data = construirNominaDispersionPdfData(nomina: nomina, renglones: renglones, fechaGeneracion: DateTime.now());
      final pdfBytes = await _renderer.renderizar(data: data, logoBytes: logoFallbackBytes);

      final resultado = await guardarYAbrirReporte(
        bytes: pdfBytes,
        nombreBase: 'RISEG_${nomina.folio}_Dispersion_${nomina.anio}-${nomina.mes.toString().padLeft(2, '0')}',
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
}

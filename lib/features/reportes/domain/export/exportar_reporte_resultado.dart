/// Resultado de cualquier exportación de Reportes (Etapa 12D) — mismo
/// shape para los 9 exports (PDF y XLSX): nunca persisten un
/// `Attachment` (el documento generado no es propiedad de una entidad
/// de negocio, mismo criterio que `GenerarDocumentoResguardoUseCase`),
/// solo escriben el archivo y lo abren con el programa predeterminado.
sealed class ExportarReporteResultado {}

class ExportarReporteExitoso extends ExportarReporteResultado {
  ExportarReporteExitoso(this.rutaArchivo);
  final String rutaArchivo;
}

class ExportarReporteErrorInesperado extends ExportarReporteResultado {
  ExportarReporteErrorInesperado(this.mensaje);
  final String mensaje;
}

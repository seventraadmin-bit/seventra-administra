/// Contexto común a cualquier exportación de Reportes (Etapa 12D) —
/// se arma en la pantalla/controller a partir de datos que YA están en
/// memoria (rango de filtro del propio `state`, sesión activa) sin
/// ninguna consulta nueva. Todo renderer PDF/XLSX de Reportes recibe
/// exactamente este objeto para su encabezado — nunca decide por su
/// cuenta el periodo o el usuario que generó el documento.
class ReporteExportContext {
  const ReporteExportContext({
    required this.nombreReporte,
    required this.rangoInicio,
    required this.rangoFin,
    required this.generadoPor,
    required this.generadoEn,
  });

  final String nombreReporte;
  final DateTime? rangoInicio;
  final DateTime? rangoFin;
  final String generadoPor;
  final DateTime generadoEn;
}

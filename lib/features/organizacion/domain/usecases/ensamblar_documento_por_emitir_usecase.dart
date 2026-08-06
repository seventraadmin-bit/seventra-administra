import '../repositories/configuracion_cobro_repository.dart';
import '../repositories/servicio_comercial_repository.dart';
import 'calcular_importe_proporcional_usecase.dart';
import 'documento_por_emitir_armado.dart';
import 'documento_por_emitir_generation_key.dart';

/// Un Servicio ya resuelto contra un periodo — a qué vigencia de cobro
/// corresponde y qué fechas calculó, insumo mínimo compartido por
/// `GenerarAgendaUseCase` y `CrearDocumentoManualUseCase`.
class ServicioResueltoParaDocumento {
  const ServicioResueltoParaDocumento({
    required this.servicioId,
    required this.configuracionCobroVigenciaId,
    this.fechaEmisionProgramada,
    this.fechaProcesamientoProgramada,
    this.fechaPagoEsperadoProgramada,
  });

  final String servicioId;
  final String configuracionCobroVigenciaId;
  final DateTime? fechaEmisionProgramada;
  final DateTime? fechaProcesamientoProgramada;
  final DateTime? fechaPagoEsperadoProgramada;
}

int _calcularDiasAplicables(DateTime periodoInicio, DateTime periodoFin, DateTime? vigenciaFin) {
  final finEfectivo = (vigenciaFin == null || vigenciaFin.isAfter(periodoFin)) ? periodoFin : vigenciaFin;
  return finEfectivo.difference(periodoInicio).inDays + 1;
}

DateTime? _masProxima(List<DateTime?> fechas) {
  final noNulas = fechas.whereType<DateTime>().toList()..sort();
  return noNulas.isEmpty ? null : noNulas.first;
}

/// Arma el snapshot completo (configuraciones por Servicio, líneas
/// comerciales con su importe proporcional ya redondeado, correos e
/// importe base) para un grupo de Servicios ya validado como compatible
/// (Etapa 4I.1) — la única pieza compartida entre generar
/// automáticamente y crear manualmente, para no duplicar el cálculo.
class EnsamblarDocumentoPorEmitirUseCase {
  EnsamblarDocumentoPorEmitirUseCase(this._servicioComercialRepository, this._configuracionCobroRepository);

  final ServicioComercialRepository _servicioComercialRepository;
  final ConfiguracionCobroRepository _configuracionCobroRepository;

  Future<DocumentoPorEmitirArmado> ejecutar({
    required String clienteId,
    required String tipoDocumento,
    required String agrupacion,
    required String metodo,
    required bool requiereComplemento,
    required DateTime periodoInicio,
    required DateTime periodoFin,
    required List<ServicioResueltoParaDocumento> servicios,
    String? entidadFiscalId,
  }) async {
    final configuraciones = <ConfiguracionServicioArmada>[];
    final lineas = <LineaArmada>[];
    final correos = <String>{};
    var importeBase = 0;

    for (final s in servicios) {
      configuraciones.add(
        ConfiguracionServicioArmada(
          servicioId: s.servicioId,
          configuracionCobroVigenciaId: s.configuracionCobroVigenciaId,
          fechaEmisionProgramada: s.fechaEmisionProgramada,
          fechaProcesamientoProgramada: s.fechaProcesamientoProgramada,
          fechaPagoEsperadoProgramada: s.fechaPagoEsperadoProgramada,
        ),
      );

      correos.addAll(await _configuracionCobroRepository.listarCorreos(s.configuracionCobroVigenciaId));

      final lineasServicio = await _servicioComercialRepository.listarLineasEnFecha(s.servicioId, periodoInicio);
      for (final l in lineasServicio) {
        final vigente = l.vigenciaActual;
        // Sin condición comercial vigente a esa fecha — no aporta
        // importe, pero el documento se sigue creando (nunca se oculta
        // silenciosamente una situación real que alguien deba revisar).
        if (vigente == null) continue;

        final diasAplicables = _calcularDiasAplicables(periodoInicio, periodoFin, vigente.fechaFinVigencia);
        final subtotal = calcularImporteProporcional(
          precioUnitarioCentavos: vigente.precioUnitario,
          diasAplicables: diasAplicables,
          cantidadElementos: vigente.cantidadElementos,
        );

        lineas.add(
          LineaArmada(
            servicioId: s.servicioId,
            lineaComercialVigenciaId: vigente.id,
            puestoNombre: l.puestoNombre,
            modalidadTurnoNombre: l.modalidadTurnoNombre,
            cantidadElementos: vigente.cantidadElementos,
            precioUnitario: vigente.precioUnitario,
            tratamientoIva: vigente.tratamientoIva,
            diasAplicables: diasAplicables,
            subtotalProporcional: subtotal,
          ),
        );
        importeBase += subtotal;
      }
    }

    final servicioIds = [for (final s in servicios) s.servicioId];
    final vigenciaIds = [for (final s in servicios) s.configuracionCobroVigenciaId];

    return DocumentoPorEmitirArmado(
      clienteId: clienteId,
      entidadFiscalId: entidadFiscalId,
      tipoDocumento: tipoDocumento,
      agrupacion: agrupacion,
      metodo: metodo,
      requiereComplemento: requiereComplemento,
      periodoInicio: periodoInicio,
      periodoFin: periodoFin,
      fechaEmisionProgramada: _masProxima([for (final s in servicios) s.fechaEmisionProgramada]),
      fechaProcesamientoProgramada: _masProxima([for (final s in servicios) s.fechaProcesamientoProgramada]),
      fechaPagoEsperadoProgramada: _masProxima([for (final s in servicios) s.fechaPagoEsperadoProgramada]),
      generationKey: calcularGenerationKey(
        agrupacion: agrupacion,
        tipoDocumento: tipoDocumento,
        clienteId: clienteId,
        servicioIds: servicioIds,
        configuracionCobroVigenciaIds: vigenciaIds,
        periodoInicio: periodoInicio,
        periodoFin: periodoFin,
        entidadFiscalId: entidadFiscalId,
      ),
      importeBaseEsperado: importeBase,
      servicioIds: servicioIds,
      configuraciones: configuraciones,
      lineas: lineas,
      correos: correos.toList(),
    );
  }
}

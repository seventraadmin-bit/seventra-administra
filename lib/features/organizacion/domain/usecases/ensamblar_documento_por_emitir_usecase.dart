import '../repositories/configuracion_cobro_repository.dart';
import '../repositories/servicio_comercial_repository.dart';
import 'calcular_fechas_cobro_usecase.dart';
import 'calcular_importe_proporcional_usecase.dart';
import 'documento_por_emitir_armado.dart';
import 'configuracion_cobro_con_vigencia.dart' show soloFechaCobro;
import 'documento_por_emitir_generation_key.dart';
import 'periodo_facturable.dart';

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
    this.hitos = const [],
  });

  final String servicioId;
  final String configuracionCobroVigenciaId;
  final DateTime? fechaEmisionProgramada;
  final DateTime? fechaProcesamientoProgramada;
  final DateTime? fechaPagoEsperadoProgramada;

  /// Hitos planeados de todas las etapas activas con fecha calculable
  /// (Etapa 15) — la fuente completa que alimenta `DocumentoPorEmitirHito`.
  final List<HitoArmado> hitos;
}

/// `true` si `[periodoInicio, periodoFin]` es exactamente un mes
/// calendario completo que arranca en el día de `periodoInicio` — misma
/// construcción exacta que `calcularLimitesPeriodo` (mes siguiente +
/// `diaFijoDelMes`, con el mismo recorte a fin de mes cuando el día no
/// existe en el mes siguiente), para que un periodo mensual real
/// generado por la Agenda automática, o un periodo manual que replica
/// esa misma forma, se reconozcan igual — nunca una coincidencia
/// numérica de días.
bool _esPeriodoMensualCompleto(DateTime periodoInicio, DateTime periodoFin) {
  final mesSiguiente = DateTime(periodoInicio.year, periodoInicio.month + 1, 1);
  final inicioSiguientePeriodo = diaFijoDelMes(mesSiguiente.year, mesSiguiente.month, periodoInicio.day);
  return periodoFin.add(const Duration(days: 1)) == inicioSiguientePeriodo;
}

/// Regla comercial de RISEG (Etapa 15, corrección explícita de Marlon):
/// un periodo mensual completo siempre vale 30 días comerciales, sin
/// importar si el mes calendario real tiene 28, 29, 30 o 31 días. Solo
/// se considera completo cuando (a) `[periodoInicio, periodoFin]` tiene
/// la forma exacta de un mes calendario completo (`_esPeriodoMensualCompleto`)
/// y (b) la vigencia de la línea comercial no lo corta antes de
/// `periodoFin` — un cambio de vigencia que coincide exactamente con el
/// fin del periodo (ej. vigencia truncada el 31 de diciembre para un
/// periodo que termina el 31 de diciembre) NO es un corte real, por eso
/// la comparación es `!isBefore`, no `isAfter`. Cualquier otro caso
/// (periodo parcial capturado manualmente, o vigencia que sí corta a
/// mitad de mes) prorratea con días calendario reales, nunca con el
/// fijo de 30 — un periodo parcial de 15 días nunca se vuelve 30.
/// **Único motor de prorrateo del sistema.** Recibe el periodo ya
/// efectivo del documento (la Agenda se lo entrega recortado a la vida
/// del Servicio) y lo intersecta además con la vigencia de la línea
/// comercial: los días facturables son los del tramo que ambos cubren.
///
/// Antes sólo miraba `fechaFinVigencia` y jamás el inicio, así que una
/// línea que entraba a mitad de periodo cobraba el periodo entero. Ese
/// era el segundo motor implícito que esta función elimina.
///
/// Devuelve `0` si no hay intersección — la línea no aportó nada a este
/// periodo.
int calcularDiasAplicables({
  required DateTime periodoInicio,
  required DateTime periodoFin,
  required DateTime vigenciaInicio,
  DateTime? vigenciaFin,
}) {
  final efectivo = intersectarRangos(
    aInicio: periodoInicio,
    aFin: periodoFin,
    bInicio: vigenciaInicio,
    bFin: vigenciaFin,
  );
  if (efectivo == null) return 0;

  // El fijo de 30 sólo aplica cuando la línea cubre el periodo COMPLETO
  // y ese periodo tiene forma de mes calendario entero. Un periodo ya
  // recortado por el cierre del Servicio (21/07–30/07) no la tiene, así
  // que prorratea con días naturales — exactamente los 10 días y
  // $10,450.00 de DOC-000029 en la base real.
  final cubreTodoElPeriodo = !efectivo.inicio.isAfter(soloFechaCobro(periodoInicio)) &&
      !efectivo.fin.isBefore(soloFechaCobro(periodoFin));
  if (cubreTodoElPeriodo && _esPeriodoMensualCompleto(periodoInicio, periodoFin)) {
    return 30;
  }

  return efectivo.fin.difference(efectivo.inicio).inDays + 1;
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
    String? clientePortalId,
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
          hitos: s.hitos,
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

        final diasAplicables = calcularDiasAplicables(
          periodoInicio: periodoInicio,
          periodoFin: periodoFin,
          vigenciaInicio: vigente.fechaInicioVigencia,
          vigenciaFin: vigente.fechaFinVigencia,
        );
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
      clientePortalId: clientePortalId,
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

import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';

import '../repositories/configuracion_cobro_repository.dart';
import '../repositories/documento_por_emitir_repository.dart';
import '../repositories/servicio_repository.dart';
import 'agrupar_documentos_por_emitir.dart';
import 'calcular_fechas_cobro_usecase.dart';
import 'ensamblar_documento_por_emitir_usecase.dart';

/// Resultado de una corrida de generación — nunca lanza, siempre
/// informa cuántos documentos se crearon y cuántos ya existían (mismo
/// periodo, mismo grupo) para que la pantalla pueda mostrar un mensaje
/// comprensible sin depender solo del índice único de la base.
class GenerarAgendaResultado {
  const GenerarAgendaResultado({required this.creados, required this.yaExistian});

  final List<DocumentoPorEmitirData> creados;
  final int yaExistian;
}

/// Genera la Agenda de documentos por emitir para un rango de fechas
/// (Etapa 4I.1) — nunca interpreta "agosto" como "periodo iniciado en
/// agosto": selecciona los periodos cuya **fecha de emisión calculada**
/// cae dentro del rango pedido (requisito explícito de Marlon,
/// verificado con el caso Sportium: periodo 21 jul-20 ago, emisión 21
/// de agosto, aparece en la Agenda de agosto).
///
/// Configuraciones con agrupación `manual` se omiten por completo (no
/// hay forma de que un algoritmo adivine qué Servicios agrupar) — su
/// única vía es `CrearDocumentoManualUseCase`. Lo mismo aplica a
/// cualquier vigencia de cobro sin una regla de Emisión calculable: sin
/// una fecha de emisión que pueda caer "dentro del rango", no hay forma
/// de que la búsqueda por rango la encuentre — su vía también es la
/// creación manual, indicando el periodo directamente (cubre Toluca 32,
/// Tikal y Mirabilia).
class GenerarAgendaUseCase {
  GenerarAgendaUseCase(
    this._repository,
    this._configuracionCobroRepository,
    this._servicioRepository,
    this._ensamblar,
    this._generarCodigo,
  );

  final DocumentoPorEmitirRepository _repository;
  final ConfiguracionCobroRepository _configuracionCobroRepository;
  final ServicioRepository _servicioRepository;
  final EnsamblarDocumentoPorEmitirUseCase _ensamblar;
  final GenerarCodigoUseCase _generarCodigo;

  static const _calcularFechas = CalcularFechasCobroUseCase();

  Future<GenerarAgendaResultado> ejecutar({
    required DateTime rangoInicio,
    required DateTime rangoFin,
    String? servicioId,
    String? clienteId,
  }) async {
    final configuraciones = await _configuracionCobroRepository.listarConfiguraciones(
      clienteId: clienteId,
      servicioId: servicioId,
    );

    final candidatos = <CandidatoDocumentoPorEmitir>[];
    final resueltosPorClave = <String, ServicioResueltoParaDocumento>{};
    final infoAgrupacionPorClave = <String, ({String agrupacion, String clienteId})>{};

    for (final configuracion in configuraciones) {
      final servicio = await _servicioRepository.obtenerPorId(configuracion.servicioId);
      if (servicio == null) continue;

      // Ventana de búsqueda de meses candidatos: 2 meses de rezago sobre
      // el inicio del rango cubre con margen `mesRelativo = siguiente` (+1
      // mes) más el desplazamiento de días/semana que una regla pueda
      // aplicar — documentado explícitamente, no una heurística oculta.
      var mesCandidato = DateTime(rangoInicio.year, rangoInicio.month - 2, 1);
      final limiteBusqueda = DateTime(rangoFin.year, rangoFin.month, 1);

      while (!mesCandidato.isAfter(limiteBusqueda)) {
        final vigenciaAprox = await _configuracionCobroRepository.obtenerVigenciaEnFecha(
          configuracion.id,
          DateTime(mesCandidato.year, mesCandidato.month, 1),
        );
        if (vigenciaAprox == null) {
          mesCandidato = DateTime(mesCandidato.year, mesCandidato.month + 1, 1);
          continue;
        }

        final limites = calcularLimitesPeriodo(
          diaInicioPeriodo: vigenciaAprox.diaInicioPeriodo,
          mesInicioPeriodo: DateTime(mesCandidato.year, mesCandidato.month, 1),
        );
        final vigencia = await _configuracionCobroRepository.obtenerVigenciaEnFecha(
              configuracion.id,
              limites.periodoInicio,
            ) ??
            vigenciaAprox;

        if (vigencia.agrupacion != 'manual') {
          final reglas = await _configuracionCobroRepository.listarReglas(vigencia.id);
          final fechas = _calcularFechas.ejecutar(
            reglas: reglas,
            mesInicioPeriodo: DateTime(mesCandidato.year, mesCandidato.month, 1),
          );

          final fechaEmision = fechas.fechaEmision;
          if (fechaEmision != null &&
              !fechaEmision.isBefore(rangoInicio) &&
              !fechaEmision.isAfter(rangoFin)) {
            final clave = '${servicio.id}|${limites.periodoInicio.toIso8601String()}';
            if (!resueltosPorClave.containsKey(clave)) {
              resueltosPorClave[clave] = ServicioResueltoParaDocumento(
                servicioId: servicio.id,
                configuracionCobroVigenciaId: vigencia.id,
                fechaEmisionProgramada: fechaEmision,
                fechaProcesamientoProgramada: fechas.fechaProcesamiento,
                fechaPagoEsperadoProgramada: fechas.fechaPagoEsperado,
              );
              infoAgrupacionPorClave[clave] = (agrupacion: vigencia.agrupacion, clienteId: servicio.clienteId);
              candidatos.add(
                CandidatoDocumentoPorEmitir(
                  servicioId: servicio.id,
                  clienteId: servicio.clienteId,
                  entidadFiscalId: vigencia.entidadFiscalId,
                  tipoDocumento: vigencia.tipoDocumento,
                  metodo: vigencia.metodo,
                  requiereComplemento: vigencia.requiereComplemento,
                  periodoInicio: limites.periodoInicio,
                  periodoFin: limites.periodoFin,
                  configuracionCobroVigenciaId: vigencia.id,
                ),
              );
            }
          }
        }

        mesCandidato = DateTime(mesCandidato.year, mesCandidato.month + 1, 1);
      }
    }

    // Agrupa por modo de agrupación: `porServicio` nunca se junta con
    // nada; `porEntidadFiscal`/`porCliente` se particionan primero por
    // su ancla y luego por compatibilidad real (Resolución de
    // agrupaciones compatibles) — nunca se mezclan Servicios solo por
    // compartir Cliente/Entidad fiscal.
    final gruposFinales = <List<CandidatoDocumentoPorEmitir>>[];
    final porServicio = candidatos.where((c) {
      final clave = '${c.servicioId}|${c.periodoInicio.toIso8601String()}';
      return infoAgrupacionPorClave[clave]!.agrupacion == 'porServicio';
    });
    for (final c in porServicio) {
      gruposFinales.add([c]);
    }

    final porEntidadFiscal = candidatos.where((c) {
      final clave = '${c.servicioId}|${c.periodoInicio.toIso8601String()}';
      return infoAgrupacionPorClave[clave]!.agrupacion == 'porEntidadFiscal';
    }).toList();
    gruposFinales.addAll(_agruparPorAncla(porEntidadFiscal, (c) => '${c.clienteId}|${c.entidadFiscalId}'));

    final porCliente = candidatos.where((c) {
      final clave = '${c.servicioId}|${c.periodoInicio.toIso8601String()}';
      return infoAgrupacionPorClave[clave]!.agrupacion == 'porCliente';
    }).toList();
    gruposFinales.addAll(_agruparPorAncla(porCliente, (c) => c.clienteId));

    final creados = <DocumentoPorEmitirData>[];
    var yaExistian = 0;

    for (final grupo in gruposFinales) {
      final servicios = [
        for (final c in grupo) resueltosPorClave['${c.servicioId}|${c.periodoInicio.toIso8601String()}']!,
      ];
      final primero = grupo.first;

      final armado = await _ensamblar.ejecutar(
        clienteId: primero.clienteId,
        entidadFiscalId: primero.entidadFiscalId,
        tipoDocumento: primero.tipoDocumento,
        agrupacion: infoAgrupacionPorClave['${primero.servicioId}|${primero.periodoInicio.toIso8601String()}']!
            .agrupacion,
        metodo: primero.metodo,
        requiereComplemento: primero.requiereComplemento,
        periodoInicio: primero.periodoInicio,
        periodoFin: primero.periodoFin,
        servicios: servicios,
      );

      final existente = await _repository.obtenerPorGenerationKey(armado.generationKey);
      if (existente != null) {
        yaExistian++;
        continue;
      }

      final codigoResultado = await _generarCodigo.ejecutar('documento_por_emitir');
      final codigo = codigoResultado.when(ok: (c) => c, failure: (f) => throw StateError(f.message));
      creados.add(await _repository.crearDocumento(codigo: codigo, armado: armado));
    }

    return GenerarAgendaResultado(creados: creados, yaExistian: yaExistian);
  }

  List<List<CandidatoDocumentoPorEmitir>> _agruparPorAncla(
    List<CandidatoDocumentoPorEmitir> candidatos,
    String Function(CandidatoDocumentoPorEmitir) ancla,
  ) {
    final porAncla = <String, List<CandidatoDocumentoPorEmitir>>{};
    for (final c in candidatos) {
      porAncla.putIfAbsent(ancla(c), () => []).add(c);
    }

    final resultado = <List<CandidatoDocumentoPorEmitir>>[];
    for (final grupo in porAncla.values) {
      resultado.addAll(agruparCompatibles(grupo));
    }
    return resultado;
  }
}

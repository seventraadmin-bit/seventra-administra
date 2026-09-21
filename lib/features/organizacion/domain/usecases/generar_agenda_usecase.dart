import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_etapa_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/documento_por_emitir_table.dart';

import '../repositories/configuracion_cobro_repository.dart';
import '../repositories/documento_por_emitir_repository.dart';
import '../repositories/servicio_repository.dart';
import 'agrupar_documentos_por_emitir.dart';
import 'calcular_fechas_cobro_usecase.dart';
import 'documento_por_emitir_armado.dart';
import 'documento_por_emitir_generation_key.dart';
import 'configuracion_cobro_con_vigencia.dart' show soloFechaCobro;
import 'periodo_facturable.dart';
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

      // Todas las vigencias vivas de la Configuración, una sola vez.
      //
      // La vigencia ya NO se resuelve preguntando por el día 1 del mes
      // candidato. Ese atajo perdía un mes entero cuando la vigencia
      // arrancaba después del día 1: un Servicio dado de alta el 05/09
      // con ciclo 21→20 no generaba ni el tramo 05/09–20/09 ni el
      // periodo completo siguiente 21/09–20/10. Ahora se resuelve por
      // intersección real con el periodo candidato.
      final vigenciasVivas = [
        for (final v in await _configuracionCobroRepository.listarHistorial(configuracion.id))
          if (v.cicloVidaRegistro == 'activo') v,
      ];
      if (vigenciasVivas.isEmpty) continue;

      // Los ciclos posibles (21→20, 1→fin de mes, …). Normalmente uno
      // solo. Si una vigencia cambió el ciclo a mitad de la vida del
      // Servicio, cada forma de periodo se evalúa por separado y sólo
      // sobrevive aquella cuya propia vigencia la gobierna (el
      // `diaInicioPeriodo` coincide) — así un cambio de ciclo nunca
      // factura el mismo mes dos veces con dos cortes distintos.
      final ciclos = {for (final v in vigenciasVivas) v.diaInicioPeriodo};

      // Ventana de búsqueda de meses candidatos: 2 meses de rezago sobre
      // el inicio del rango cubre con margen `mesRelativo = siguiente` (+1
      // mes) más el desplazamiento de días/semana que una regla pueda
      // aplicar — documentado explícitamente, no una heurística oculta.
      var mesCandidato = DateTime(rangoInicio.year, rangoInicio.month - 2, 1);
      final limiteBusqueda = DateTime(rangoFin.year, rangoFin.month, 1);

      while (!mesCandidato.isAfter(limiteBusqueda)) {
        for (final diaInicioPeriodo in ciclos) {
        final limites = calcularLimitesPeriodo(
          diaInicioPeriodo: diaInicioPeriodo,
          mesInicioPeriodo: DateTime(mesCandidato.year, mesCandidato.month, 1),
        );

        // PERIODO FACTURABLE = intersección de tres rangos: el periodo
        // comercial programado, la vida real del Servicio y la vigencia
        // de la Configuración de cobro. Sin intersección no hay
        // documento; con intersección parcial, el documento existe por
        // el tramo realmente prestado y se prorratea sobre él.
        //
        // Se decide contra el periodo facturable y NUNCA contra
        // `Servicio.estatus`: un Servicio terminado el 30/07 conserva su
        // documento del tramo 21/07–30/07, que se emite el 21/08 con el
        // Servicio ya cerrado (caso real DOC-000029).
        final facturablePorServicio = calcularPeriodoFacturable(
          periodoInicio: limites.periodoInicio,
          periodoFin: limites.periodoFin,
          servicioInicio: servicio.fechaInicio,
          servicioTermino: servicio.fechaTermino,
        );
        if (facturablePorServicio == null) continue;

        // La vigencia que gobierna es la que cubre el inicio EFECTIVO,
        // no el nominal: un alta el 05/09 dentro del periodo 21/08–20/09
        // se rige por la vigencia del 05/09, que no existía el 21/08.
        final vigencia = _vigenciaEnFecha(vigenciasVivas, facturablePorServicio.inicio);
        if (vigencia == null || vigencia.diaInicioPeriodo != diaInicioPeriodo) continue;

        final facturable = intersectarRangos(
          aInicio: facturablePorServicio.inicio,
          aFin: facturablePorServicio.fin,
          bInicio: vigencia.fechaInicioVigencia,
          bFin: vigencia.fechaFinVigencia,
        );
        if (facturable == null) continue;

        if (vigencia.agrupacion != 'manual') {
          final etapas = await _configuracionCobroRepository.listarEtapas(vigencia.id);
          // El calendario de cobro es NOMINAL: recortar el tramo
          // facturable no adelanta la emisión. DOC-000029 cubrió
          // 21/07–30/07 y aun así se emitió el 21/08, como cualquier
          // periodo completo — la fecha de emisión es un acuerdo
          // comercial, no una consecuencia de cuándo cerró el Servicio.
          final fechas = _calcularFechas.ejecutar(
            etapas: etapas,
            mesInicioPeriodo: DateTime(mesCandidato.year, mesCandidato.month, 1),
            periodoFin: limites.periodoFin,
          );

          final fechaEmision = fechaDeEtapaSistema(fechas, TipoEventoCobro.emision);
          if (fechaEmision != null &&
              !fechaEmision.isBefore(rangoInicio) &&
              !fechaEmision.isAfter(rangoFin)) {
            final clave = '${servicio.id}|${facturable.inicio.toIso8601String()}';
            if (!resueltosPorClave.containsKey(clave)) {
              resueltosPorClave[clave] = ServicioResueltoParaDocumento(
                servicioId: servicio.id,
                configuracionCobroVigenciaId: vigencia.id,
                fechaEmisionProgramada: fechaEmision,
                fechaProcesamientoProgramada: fechaDeEtapaSistema(fechas, TipoEventoCobro.procesamiento),
                fechaPagoEsperadoProgramada: fechaDeEtapaSistema(fechas, TipoEventoCobro.pagoEsperado),
                hitos: [
                  for (final f in fechas)
                    if (f.fecha != null) HitoArmado(orden: f.orden, fecha: f.fecha!, tipoSistema: f.tipoSistema, nombre: f.nombre),
                ],
              );
              infoAgrupacionPorClave[clave] = (agrupacion: vigencia.agrupacion, clienteId: servicio.clienteId);
              candidatos.add(
                CandidatoDocumentoPorEmitir(
                  servicioId: servicio.id,
                  clienteId: servicio.clienteId,
                  entidadFiscalId: vigencia.entidadFiscalId,
                  clientePortalId: vigencia.clientePortalId,
                  tipoDocumento: vigencia.tipoDocumento,
                  metodo: vigencia.metodo,
                  requiereComplemento: vigencia.requiereComplemento,
                  periodoInicio: facturable.inicio,
                  periodoFin: facturable.fin,
                  configuracionCobroVigenciaId: vigencia.id,
                ),
              );
            }
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
        clientePortalId: primero.clientePortalId,
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

      // Idempotencia COMERCIAL, además de la técnica de arriba.
      //
      // Una vigencia retroactiva produce una `generationKey` distinta
      // para periodos que ya se facturaron bajo la configuración
      // anterior, así que la comprobación de arriba no los reconoce y
      // la Agenda vuelve a pedir emitir un mes ya emitido (caso real:
      // Morgan, DOC-000040 duplicando al procesado DOC-000035).
      //
      // Qué estatus bloquean y cuáles no lo decide
      // `liberaElPeriodoComercial`, compartida con la creación manual.
      final equivalentes = await _repository.listarPorClaveComercial(
        claveComercialDeGenerationKey(armado.generationKey),
      );
      final vigente = equivalentes.where((d) => !liberaElPeriodoComercial(d.estatus));
      if (vigente.isNotEmpty) {
        yaExistian++;
        continue;
      }

      final codigoResultado = await _generarCodigo.ejecutar('documento_por_emitir');
      final codigo = codigoResultado.when(ok: (c) => c, failure: (f) => throw StateError(f.message));
      creados.add(
        await _repository.crearDocumento(
          codigo: codigo,
          armado: armado,
          tipoEventoCreacion: TipoEventoDocumentoPorEmitir.creadoAutomatico,
        ),
      );
    }

    return GenerarAgendaResultado(creados: creados, yaExistian: yaExistian);
  }

  /// La vigencia activa que cubre [fecha], o `null`. Misma regla que
  /// `ConfiguracionCobroRepository.obtenerVigenciaEnFecha`, resuelta en
  /// memoria porque el generador ya tiene la lista completa y la
  /// consulta ocurriría una vez por mes candidato.
  ConfiguracionCobroVigenciaData? _vigenciaEnFecha(
    List<ConfiguracionCobroVigenciaData> vigencias,
    DateTime fecha,
  ) {
    final dia = soloFechaCobro(fecha);
    for (final v in vigencias) {
      final inicio = soloFechaCobro(v.fechaInicioVigencia);
      final fin = v.fechaFinVigencia == null ? null : soloFechaCobro(v.fechaFinVigencia!);
      if (!inicio.isAfter(dia) && (fin == null || !fin.isBefore(dia))) return v;
    }
    return null;
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

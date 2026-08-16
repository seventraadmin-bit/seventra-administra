import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_etapa_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/documento_por_emitir_table.dart';

import '../repositories/configuracion_cobro_repository.dart';
import '../repositories/documento_por_emitir_repository.dart';
import 'agrupar_documentos_por_emitir.dart';
import 'calcular_fechas_cobro_usecase.dart';
import 'documento_por_emitir_armado.dart';
import 'ensamblar_documento_por_emitir_usecase.dart';

sealed class CrearDocumentoManualResultado {}

class CrearDocumentoManualExitoso extends CrearDocumentoManualResultado {
  CrearDocumentoManualExitoso(this.documento);
  final DocumentoPorEmitirData documento;
}

class CrearDocumentoManualSinServicios extends CrearDocumentoManualResultado {}

/// Un Servicio seleccionado no tiene ninguna Configuración de cobro, o
/// ninguna vigencia efectiva para el periodo indicado.
class CrearDocumentoManualSinConfiguracionAplicable extends CrearDocumentoManualResultado {
  CrearDocumentoManualSinConfiguracionAplicable(this.servicioId);
  final String servicioId;
}

/// Los Servicios seleccionados no son compatibles entre sí (Cliente,
/// tipo de documento, Entidad fiscal cuando es CFDI, método o condición
/// de complemento distintos) — nunca se agrupan Servicios con
/// condiciones distintas, tampoco en la creación manual.
class CrearDocumentoManualServiciosIncompatibles extends CrearDocumentoManualResultado {}

class CrearDocumentoManualYaExiste extends CrearDocumentoManualResultado {
  CrearDocumentoManualYaExiste(this.documento);
  final DocumentoPorEmitirData documento;
}

class CrearDocumentoManualErrorInesperado extends CrearDocumentoManualResultado {
  CrearDocumentoManualErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Crea un `DocumentoPorEmitir` indicando el periodo directamente, sin
/// depender de que exista una fecha de emisión calculable (Etapa 4I.1)
/// — la única vía para Configuraciones de cobro con agrupación `manual`
/// (Resolución B) y para cualquier vigencia sin regla de Emisión (cubre
/// Toluca 32, Tikal y Mirabilia, cuyo único evento capturado es Pago
/// esperado). Produce exactamente el mismo snapshot que la generación
/// automática — reutiliza `EnsamblarDocumentoPorEmitirUseCase`.
class CrearDocumentoManualUseCase {
  CrearDocumentoManualUseCase(
    this._repository,
    this._configuracionCobroRepository,
    this._ensamblar,
    this._generarCodigo,
  );

  final DocumentoPorEmitirRepository _repository;
  final ConfiguracionCobroRepository _configuracionCobroRepository;
  final EnsamblarDocumentoPorEmitirUseCase _ensamblar;
  final GenerarCodigoUseCase _generarCodigo;

  static const _calcularFechas = CalcularFechasCobroUseCase();

  Future<CrearDocumentoManualResultado> ejecutar({
    required String clienteId,
    required List<String> servicioIds,
    required DateTime periodoInicio,
    required DateTime periodoFin,
    String? entidadFiscalId,
    String? clientePortalId,
  }) async {
    if (servicioIds.isEmpty) {
      return CrearDocumentoManualSinServicios();
    }

    final candidatos = <CandidatoDocumentoPorEmitir>[];
    final servicios = <ServicioResueltoParaDocumento>[];
    String? agrupacion;

    for (final servicioId in servicioIds) {
      final configuraciones = await _configuracionCobroRepository.listarConfiguraciones(servicioId: servicioId);
      if (configuraciones.isEmpty) {
        return CrearDocumentoManualSinConfiguracionAplicable(servicioId);
      }

      final vigencia = await _configuracionCobroRepository.obtenerVigenciaEnFecha(
        configuraciones.single.id,
        periodoInicio,
      );
      if (vigencia == null) {
        return CrearDocumentoManualSinConfiguracionAplicable(servicioId);
      }

      final etapas = await _configuracionCobroRepository.listarEtapas(vigencia.id);
      final mesInicioPeriodo = DateTime(periodoInicio.year, periodoInicio.month, 1);
      final fechas = _calcularFechas.ejecutar(etapas: etapas, mesInicioPeriodo: mesInicioPeriodo, periodoFin: periodoFin);

      agrupacion ??= vigencia.agrupacion;

      candidatos.add(
        CandidatoDocumentoPorEmitir(
          servicioId: servicioId,
          clienteId: clienteId,
          entidadFiscalId: vigencia.entidadFiscalId,
          clientePortalId: vigencia.clientePortalId,
          tipoDocumento: vigencia.tipoDocumento,
          metodo: vigencia.metodo,
          requiereComplemento: vigencia.requiereComplemento,
          periodoInicio: periodoInicio,
          periodoFin: periodoFin,
          configuracionCobroVigenciaId: vigencia.id,
        ),
      );
      servicios.add(
        ServicioResueltoParaDocumento(
          servicioId: servicioId,
          configuracionCobroVigenciaId: vigencia.id,
          fechaEmisionProgramada: fechaDeEtapaSistema(fechas, TipoEventoCobro.emision),
          fechaProcesamientoProgramada: fechaDeEtapaSistema(fechas, TipoEventoCobro.procesamiento),
          fechaPagoEsperadoProgramada: fechaDeEtapaSistema(fechas, TipoEventoCobro.pagoEsperado),
          hitos: [
            for (final f in fechas)
              if (f.fecha != null) HitoArmado(orden: f.orden, fecha: f.fecha!, tipoSistema: f.tipoSistema, nombre: f.nombre),
          ],
        ),
      );
    }

    final primero = candidatos.first;
    for (final c in candidatos.skip(1)) {
      if (!sonCompatiblesParaAgrupar(primero, c)) {
        return CrearDocumentoManualServiciosIncompatibles();
      }
    }

    try {
      final armado = await _ensamblar.ejecutar(
        clienteId: clienteId,
        entidadFiscalId: entidadFiscalId ?? primero.entidadFiscalId,
        clientePortalId: clientePortalId ?? primero.clientePortalId,
        tipoDocumento: primero.tipoDocumento,
        agrupacion: agrupacion!,
        metodo: primero.metodo,
        requiereComplemento: primero.requiereComplemento,
        periodoInicio: periodoInicio,
        periodoFin: periodoFin,
        servicios: servicios,
      );

      final existente = await _repository.obtenerPorGenerationKey(armado.generationKey);
      if (existente != null) {
        return CrearDocumentoManualYaExiste(existente);
      }

      final codigoResultado = await _generarCodigo.ejecutar('documento_por_emitir');
      final codigo = codigoResultado.when(ok: (c) => c, failure: (f) => throw StateError(f.message));
      final documento = await _repository.crearDocumento(
        codigo: codigo,
        armado: armado,
        tipoEventoCreacion: TipoEventoDocumentoPorEmitir.creadoManual,
      );
      return CrearDocumentoManualExitoso(documento);
    } catch (e) {
      return CrearDocumentoManualErrorInesperado(e.toString());
    }
  }
}

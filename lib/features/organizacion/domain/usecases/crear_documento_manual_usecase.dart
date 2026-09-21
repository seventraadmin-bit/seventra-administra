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

/// El Servicio no existe, o el periodo pedido cae fuera de su vigencia
/// temporal real: `fechaTermino` (si ya terminó) anterior al inicio del
/// periodo, o `fechaInicio` posterior al fin del periodo — corrección
/// Comercial/Agenda, mismo defecto real ya corregido en
/// `GenerarAgendaUseCase` (caso Mirabilia), encontrado también aquí: la
/// creación manual nunca validaba la vigencia del Servicio contra el
/// periodo capturado a mano.
class CrearDocumentoManualServicioFueraDeVigencia extends CrearDocumentoManualResultado {
  CrearDocumentoManualServicioFueraDeVigencia(this.servicioId);
  final String servicioId;
}

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
      final servicio = await _servicioRepository.obtenerPorId(servicioId);
      if (servicio == null) {
        return CrearDocumentoManualServicioFueraDeVigencia(servicioId);
      }
      // Misma regla de vigencia temporal que `GenerarAgendaUseCase`: un
      // Servicio terminado antes de que el periodo capturado a mano
      // empiece, o que arranca después de que termine, nunca genera un
      // documento para él — la creación manual existe para excepciones
      // (Toluca 32, Tikal, Mirabilia) y sigue permitiendo un periodo
      // HISTÓRICO real de un Servicio ya terminado, solo bloquea un
      // periodo fuera de su vigencia real.
      if (servicio.fechaTermino != null && servicio.fechaTermino!.isBefore(periodoInicio)) {
        return CrearDocumentoManualServicioFueraDeVigencia(servicioId);
      }
      if (servicio.fechaInicio.isAfter(periodoFin)) {
        return CrearDocumentoManualServicioFueraDeVigencia(servicioId);
      }

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

      // Idempotencia COMERCIAL, igual que en `GenerarAgendaUseCase`.
      //
      // Ésta es la vía que produjo el duplicado real: DOC-000040 se
      // creó A MANO (`creadoManual`) dos minutos después de registrar
      // una vigencia retroactiva, y la comprobación técnica de arriba
      // no lo reconoció porque la clave llevaba ya la vigencia nueva —
      // aunque agosto estaba emitido y procesado desde DOC-000035.
      //
      // Crear a mano sigue siendo posible para todo lo que el generador
      // no agenda; lo único que deja de ser posible es duplicar un
      // periodo comercial que ya está vivo. Un documento cancelado o
      // marcado como no requerido no bloquea nada.
      final equivalentes = await _repository.listarPorClaveComercial(
        claveComercialDeGenerationKey(armado.generationKey),
      );
      final vigente = equivalentes.where((d) => !liberaElPeriodoComercial(d.estatus));
      if (vigente.isNotEmpty) {
        return CrearDocumentoManualYaExiste(vigente.first);
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

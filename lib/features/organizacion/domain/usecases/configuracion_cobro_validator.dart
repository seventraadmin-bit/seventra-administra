import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_linea_comercial_vigencia_table.dart';

import '../repositories/catalogo_repository.dart';
import '../repositories/cliente_portal_repository.dart';
import '../repositories/entidad_fiscal_repository.dart';
import '../repositories/servicio_comercial_repository.dart';
import '../repositories/servicio_repository.dart';
import 'configuracion_cobro_con_vigencia.dart';
import 'configuracion_cobro_errors.dart';

/// Condiciones de Configuración de cobro tal como llegan del formulario
/// de alta — sin validar. Las reglas temporales de emisión/
/// procesamiento/pago esperado no existen todavía (Etapa 4H.2).
class ConfiguracionCobroBorrador {
  const ConfiguracionCobroBorrador({
    required this.tipoDocumento,
    required this.frecuenciaId,
    required this.diaInicioPeriodo,
    required this.agrupacion,
    required this.metodo,
    required this.requiereComplemento,
    required this.fechaInicioVigencia,
    this.entidadFiscalId,
    this.clientePortalId,
    this.cuentaBancaria,
    this.observaciones,
    this.correos = const [],
  });

  final TipoDocumentoCobro? tipoDocumento;
  final String frecuenciaId;
  final int? diaInicioPeriodo;
  final AgrupacionCobro? agrupacion;
  final MetodoPagoCobro? metodo;
  final bool requiereComplemento;
  final DateTime? fechaInicioVigencia;
  final String? entidadFiscalId;

  /// Qué `ClientePortal` del Cliente usa esta vigencia — referencia,
  /// nunca los datos del portal capturados aquí (Etapa 15, retiro de
  /// `portalNombre`/`portalUrl`/`portalUsuario`/`portalContrasena`/
  /// `portalObservaciones`: ahora viven exclusivamente en
  /// `ClientePortal`, administrados desde el expediente del Cliente).
  final String? clientePortalId;
  final String? cuentaBancaria;
  final String? observaciones;
  final List<String> correos;
}

/// Condiciones ya validadas y normalizadas — listas para persistir.
class ConfiguracionCobroValidada {
  const ConfiguracionCobroValidada({
    required this.tipoDocumento,
    required this.frecuenciaId,
    required this.diaInicioPeriodo,
    required this.agrupacion,
    required this.metodo,
    required this.requiereComplemento,
    required this.fechaInicioVigencia,
    required this.correos,
    this.entidadFiscalId,
    this.clientePortalId,
    this.cuentaBancaria,
    this.observaciones,
  });

  final TipoDocumentoCobro tipoDocumento;
  final String frecuenciaId;
  final int diaInicioPeriodo;
  final AgrupacionCobro agrupacion;
  final MetodoPagoCobro metodo;
  final bool requiereComplemento;
  final DateTime fechaInicioVigencia;
  final List<String> correos;
  final String? entidadFiscalId;
  final String? clientePortalId;
  final String? cuentaBancaria;
  final String? observaciones;
}

/// Validación de una Configuración de cobro — incluye la validación
/// cruzada contra las líneas comerciales vigentes del Servicio (Etapa
/// 4H.1, Resoluciones D y G): CFDI nunca coexiste con una línea vigente
/// en `noAplica`; recibo exige que todas las líneas vigentes estén en
/// `noAplica`. La misma pareja de reglas se aplica en sentido inverso
/// dentro de `LineaComercialValidator` — cualquier cambio a una de las
/// dos debe revisar la otra.
class ConfiguracionCobroValidator {
  ConfiguracionCobroValidator(
    this._servicioRepository,
    this._entidadFiscalRepository,
    this._catalogoRepository,
    this._servicioComercialRepository,
    this._clientePortalRepository,
  );

  final ServicioRepository _servicioRepository;
  final EntidadFiscalRepository _entidadFiscalRepository;
  final CatalogoRepository _catalogoRepository;
  final ServicioComercialRepository _servicioComercialRepository;
  final ClientePortalRepository _clientePortalRepository;

  bool _esCorreoValido(String correo) => correo.contains('@') && correo.contains('.') && !correo.contains(' ');

  /// `vigenciasExistentes` solo se pasa al registrar una nueva vigencia
  /// (Etapa 4H.2) — el alta original (4H.1) nunca tiene vigencias
  /// previas que pudieran colisionar. Mismo criterio que
  /// `LineaComercialValidator.validarNuevaVigencia`.
  Future<({ConfiguracionCobroValidada? resultado, List<ErrorConfiguracionCobro> errores})> validar({
    required String servicioId,
    required ConfiguracionCobroBorrador borrador,
    List<ConfiguracionCobroVigenciaData>? vigenciasExistentes,
  }) async {
    final errores = <ErrorConfiguracionCobro>[];

    final tipoDocumento = borrador.tipoDocumento;
    if (tipoDocumento == null) {
      errores.add(
        const ErrorConfiguracionCobro(
          campo: CampoConfiguracionCobro.tipoDocumento,
          codigo: CodigoErrorConfiguracionCobro.requerido,
        ),
      );
    }

    final frecuenciaId = borrador.frecuenciaId.trim();
    if (frecuenciaId.isEmpty) {
      errores.add(
        const ErrorConfiguracionCobro(
          campo: CampoConfiguracionCobro.frecuencia,
          codigo: CodigoErrorConfiguracionCobro.requerido,
        ),
      );
    } else {
      final frecuencias = await _catalogoRepository.listarFrecuenciasCobro();
      if (!frecuencias.any((f) => f.id == frecuenciaId)) {
        errores.add(
          const ErrorConfiguracionCobro(
            campo: CampoConfiguracionCobro.frecuencia,
            codigo: CodigoErrorConfiguracionCobro.noExiste,
          ),
        );
      }
    }

    final diaInicioPeriodo = borrador.diaInicioPeriodo;
    if (diaInicioPeriodo == null || diaInicioPeriodo < 1 || diaInicioPeriodo > 31) {
      errores.add(
        const ErrorConfiguracionCobro(
          campo: CampoConfiguracionCobro.diaInicioPeriodo,
          codigo: CodigoErrorConfiguracionCobro.requerido,
        ),
      );
    }

    if (borrador.agrupacion == null) {
      errores.add(
        const ErrorConfiguracionCobro(
          campo: CampoConfiguracionCobro.agrupacion,
          codigo: CodigoErrorConfiguracionCobro.requerido,
        ),
      );
    }

    final metodo = borrador.metodo;
    if (metodo == null) {
      errores.add(
        const ErrorConfiguracionCobro(
          campo: CampoConfiguracionCobro.metodo,
          codigo: CodigoErrorConfiguracionCobro.requerido,
        ),
      );
    } else {
      // Recibo no usa PUE/PPD.
      if (tipoDocumento == TipoDocumentoCobro.reciboDePago && metodo != MetodoPagoCobro.noAplica) {
        errores.add(
          const ErrorConfiguracionCobro(
            campo: CampoConfiguracionCobro.metodo,
            codigo: CodigoErrorConfiguracionCobro.metodoInvalidoParaRecibo,
          ),
        );
      }
      // PPD implica complemento requerido.
      if (metodo == MetodoPagoCobro.ppd && !borrador.requiereComplemento) {
        errores.add(
          const ErrorConfiguracionCobro(
            campo: CampoConfiguracionCobro.requiereComplemento,
            codigo: CodigoErrorConfiguracionCobro.complementoRequeridoParaPpd,
          ),
        );
      }
    }

    // CFDI requiere Entidad fiscal válida (activa, del mismo Cliente);
    // recibo la permite nula.
    if (tipoDocumento == TipoDocumentoCobro.cfdi) {
      final entidadFiscalId = borrador.entidadFiscalId;
      if (entidadFiscalId == null || entidadFiscalId.isEmpty) {
        errores.add(
          const ErrorConfiguracionCobro(
            campo: CampoConfiguracionCobro.entidadFiscal,
            codigo: CodigoErrorConfiguracionCobro.entidadFiscalRequeridaParaCfdi,
          ),
        );
      } else {
        final servicio = await _servicioRepository.obtenerPorId(servicioId);
        final entidad = await _entidadFiscalRepository.obtenerPorId(entidadFiscalId);
        if (entidad == null || servicio == null || entidad.clienteId != servicio.clienteId) {
          errores.add(
            const ErrorConfiguracionCobro(
              campo: CampoConfiguracionCobro.entidadFiscal,
              codigo: CodigoErrorConfiguracionCobro.noExiste,
            ),
          );
        } else if (entidad.cicloVidaRegistro != CicloVidaRegistro.activo.name) {
          errores.add(
            const ErrorConfiguracionCobro(
              campo: CampoConfiguracionCobro.entidadFiscal,
              codigo: CodigoErrorConfiguracionCobro.inactivo,
            ),
          );
        }
      }
    }

    // El portal es siempre opcional (a diferencia de Entidad fiscal, que
    // es condicional a `tipoDocumento`) — solo se valida si viene
    // capturado, y solo que exista, pertenezca al mismo Cliente que el
    // Servicio y no esté archivado (mismo criterio que Entidad fiscal).
    final clientePortalId = borrador.clientePortalId;
    if (clientePortalId != null && clientePortalId.isNotEmpty) {
      final servicio = await _servicioRepository.obtenerPorId(servicioId);
      final portal = await _clientePortalRepository.obtenerPorId(clientePortalId);
      if (portal == null || servicio == null || portal.clienteId != servicio.clienteId) {
        errores.add(
          const ErrorConfiguracionCobro(
            campo: CampoConfiguracionCobro.clientePortal,
            codigo: CodigoErrorConfiguracionCobro.noExiste,
          ),
        );
      } else if (portal.cicloVidaRegistro != CicloVidaRegistro.activo.name) {
        errores.add(
          const ErrorConfiguracionCobro(
            campo: CampoConfiguracionCobro.clientePortal,
            codigo: CodigoErrorConfiguracionCobro.inactivo,
          ),
        );
      }
    }

    final fechaInicioVigencia = borrador.fechaInicioVigencia;
    if (fechaInicioVigencia == null) {
      errores.add(
        const ErrorConfiguracionCobro(
          campo: CampoConfiguracionCobro.fechaInicioVigencia,
          codigo: CodigoErrorConfiguracionCobro.requerido,
        ),
      );
    } else {
      final servicio = await _servicioRepository.obtenerPorId(servicioId);
      if (servicio != null && fechaInicioVigencia.isBefore(servicio.fechaInicio)) {
        errores.add(
          const ErrorConfiguracionCobro(
            campo: CampoConfiguracionCobro.fechaInicioVigencia,
            codigo: CodigoErrorConfiguracionCobro.fechaAnteriorInicioServicio,
          ),
        );
      } else if (vigenciasExistentes != null &&
          vigenciasExistentes.any((v) => soloFechaCobro(v.fechaInicioVigencia) == soloFechaCobro(fechaInicioVigencia))) {
        errores.add(
          const ErrorConfiguracionCobro(
            campo: CampoConfiguracionCobro.fechaInicioVigencia,
            codigo: CodigoErrorConfiguracionCobro.fechaDuplicada,
          ),
        );
      }
    }

    for (final correo in borrador.correos) {
      if (!_esCorreoValido(correo)) {
        errores.add(
          const ErrorConfiguracionCobro(
            campo: CampoConfiguracionCobro.correos,
            codigo: CodigoErrorConfiguracionCobro.correoInvalido,
          ),
        );
        break;
      }
    }

    // Validación cruzada contra las líneas comerciales vigentes del
    // Servicio (Resoluciones D y G) — CFDI y `noAplica` nunca coexisten;
    // recibo exige `noAplica` en todas las líneas vigentes.
    if (tipoDocumento != null) {
      final lineas = await _servicioComercialRepository.listarLineas(servicioId);
      final tratamientosVigentes = [
        for (final l in lineas)
          if (l.vigenciaActual != null) l.vigenciaActual!.tratamientoIva,
      ];

      if (tipoDocumento == TipoDocumentoCobro.cfdi &&
          tratamientosVigentes.contains(TratamientoIva.noAplica.name)) {
        errores.add(
          const ErrorConfiguracionCobro(
            campo: CampoConfiguracionCobro.tratamientoIvaLineasComerciales,
            codigo: CodigoErrorConfiguracionCobro.cfdiIncompatibleConIvaNoAplica,
          ),
        );
      }
      if (tipoDocumento == TipoDocumentoCobro.reciboDePago &&
          tratamientosVigentes.any((t) => t != TratamientoIva.noAplica.name)) {
        errores.add(
          const ErrorConfiguracionCobro(
            campo: CampoConfiguracionCobro.tratamientoIvaLineasComerciales,
            codigo: CodigoErrorConfiguracionCobro.reciboRequiereIvaNoAplica,
          ),
        );
      }
    }

    if (errores.isNotEmpty) {
      return (resultado: null, errores: errores);
    }

    String? vacioANull(String? valor) {
      final recortado = valor?.trim();
      return (recortado == null || recortado.isEmpty) ? null : recortado;
    }

    return (
      resultado: ConfiguracionCobroValidada(
        tipoDocumento: tipoDocumento!,
        frecuenciaId: frecuenciaId,
        diaInicioPeriodo: diaInicioPeriodo!,
        agrupacion: borrador.agrupacion!,
        metodo: metodo!,
        // Etapa "Complemento dependiente del Pago real": sólo PPD puede
        // exigir Complemento. Antes la UI dejaba encender el switch con
        // PUE y se persistía un `true` que el resto del sistema ignoraba
        // (`cuentaRequiereComplemento` exige PPD) — una configuración
        // que se veía como "Sí requiere" y funcionalmente era inerte.
        //
        // Se NORMALIZA aquí, no se rechaza con un error: el formulario
        // ya impide capturar la combinación, así que un error nunca
        // llegaría a verse; lo que hace falta es que la combinación sea
        // imposible de PERSISTIR, venga de donde venga. Es la protección
        // de dominio que pidió Marlon, no sólo el switch apagado.
        requiereComplemento: metodo == MetodoPagoCobro.ppd && borrador.requiereComplemento,
        fechaInicioVigencia: fechaInicioVigencia!,
        correos: borrador.correos,
        entidadFiscalId: vacioANull(borrador.entidadFiscalId),
        clientePortalId: vacioANull(borrador.clientePortalId),
        cuentaBancaria: vacioANull(borrador.cuentaBancaria),
        observaciones: vacioANull(borrador.observaciones),
      ),
      errores: const <ErrorConfiguracionCobro>[],
    );
  }
}

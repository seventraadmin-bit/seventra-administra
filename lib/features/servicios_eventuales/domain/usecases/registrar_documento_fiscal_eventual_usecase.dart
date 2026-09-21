import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/validation/uuid_validator.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/cuenta_por_cobrar_repository.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart'
    show MetodoPagoCobro;
import 'package:riseg_one/features/organizacion/domain/repositories/entidad_fiscal_repository.dart';

import '../../data/tables/servicio_eventual_table.dart';
import '../repositories/servicio_eventual_documento_fiscal_repository.dart';
import '../repositories/servicio_eventual_repository.dart';

sealed class RegistrarDocumentoFiscalEventualResultado {}

class RegistrarDocumentoFiscalEventualExitoso extends RegistrarDocumentoFiscalEventualResultado {
  RegistrarDocumentoFiscalEventualExitoso(this.documento);
  final ServicioEventualDocumentoFiscalData documento;
}

class RegistrarDocumentoFiscalEventualNoExiste extends RegistrarDocumentoFiscalEventualResultado {}

/// El eventual se vendió SIN factura — no hay nada que documentar, y
/// forzarlo convertiría un recibo en un CFDI por la puerta de atrás.
class RegistrarDocumentoFiscalEventualNoRequiereFactura extends RegistrarDocumentoFiscalEventualResultado {}

class RegistrarDocumentoFiscalEventualCancelado extends RegistrarDocumentoFiscalEventualResultado {}

/// Ya hay un documento vigente. Para sustituirlo hay que cancelar el
/// anterior primero — el histórico se conserva, pero vigente sólo uno.
class RegistrarDocumentoFiscalEventualYaTieneVigente extends RegistrarDocumentoFiscalEventualResultado {
  RegistrarDocumentoFiscalEventualYaTieneVigente(this.folioVigente);
  final String folioVigente;
}

class RegistrarDocumentoFiscalEventualFolioRequerido extends RegistrarDocumentoFiscalEventualResultado {}

class RegistrarDocumentoFiscalEventualUuidInvalido extends RegistrarDocumentoFiscalEventualResultado {}

/// `noAplica` nunca es un método de documento fiscal.
class RegistrarDocumentoFiscalEventualMetodoInvalido extends RegistrarDocumentoFiscalEventualResultado {}

/// Faltan razón social o RFC — sin ellos no hay snapshot que congelar.
///
/// Desde la schemaVersion 90 esto sólo puede pasarle a un eventual
/// **anterior** a esa versión: los nuevos exigen el receptor fiscal al
/// vender, así que aquí ya no hay nada que capturar.
class RegistrarDocumentoFiscalEventualDatosFiscalesRequeridos
    extends RegistrarDocumentoFiscalEventualResultado {}

/// La Entidad fiscal elegida no existe o no pertenece a este Cliente.
class RegistrarDocumentoFiscalEventualEntidadFiscalInvalida
    extends RegistrarDocumentoFiscalEventualResultado {}

class RegistrarDocumentoFiscalEventualErrorInesperado extends RegistrarDocumentoFiscalEventualResultado {
  RegistrarDocumentoFiscalEventualErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Registra el CFDI que un sistema externo emitió por un eventual.
///
/// El importe **no** se captura: es el de la venta. En v1 el eventual,
/// su documento fiscal y su Cuenta por cobrar representan la misma
/// venta y el mismo número (decisión explícita de Marlon sobre el IVA),
/// así que pedirlo por separado sólo abriría la puerta a que difieran.
///
/// Los datos fiscales se **congelan**: si el Cliente cambia de razón
/// social mañana, este documento sigue diciendo lo que decía.
class RegistrarDocumentoFiscalEventualUseCase {
  RegistrarDocumentoFiscalEventualUseCase(
    this._documentoRepository,
    this._servicioEventualRepository,
    this._cuentaPorCobrarRepository,
    this._entidadFiscalRepository,
  );

  final ServicioEventualDocumentoFiscalRepository _documentoRepository;
  final ServicioEventualRepository _servicioEventualRepository;
  final CuentaPorCobrarRepository _cuentaPorCobrarRepository;
  final EntidadFiscalRepository _entidadFiscalRepository;

  Future<RegistrarDocumentoFiscalEventualResultado> ejecutar({
    required String servicioEventualId,
    required String folio,
    String? uuid,
    required DateTime fechaEmision,
    required MetodoPagoCobro metodo,
    String? entidadFiscalId,
    String? razonSocialManual,
    String? rfcManual,
    String? codigoPostalFiscalManual,
    String? observaciones,
    String? actorUsuarioId,
  }) async {
    final eventual = await _servicioEventualRepository.obtenerPorId(servicioEventualId);
    if (eventual == null) return RegistrarDocumentoFiscalEventualNoExiste();
    if (eventual.estatus == EstatusServicioEventual.cancelado.name) {
      return RegistrarDocumentoFiscalEventualCancelado();
    }
    if (!eventual.requiereFactura) return RegistrarDocumentoFiscalEventualNoRequiereFactura();

    final folioLimpio = folio.trim();
    if (folioLimpio.isEmpty) return RegistrarDocumentoFiscalEventualFolioRequerido();

    final uuidLimpio = uuid?.trim();
    if (uuidLimpio != null && uuidLimpio.isNotEmpty && !esUuidFormatoValido(uuidLimpio)) {
      return RegistrarDocumentoFiscalEventualUuidInvalido();
    }

    if (metodo == MetodoPagoCobro.noAplica) return RegistrarDocumentoFiscalEventualMetodoInvalido();

    final vigente = await _documentoRepository.obtenerVigente(servicioEventualId);
    if (vigente != null) return RegistrarDocumentoFiscalEventualYaTieneVigente(vigente.folio);

    // §1 — el receptor fiscal se decidió AL VENDER, no aquí. Este
    // caso de uso ya no pregunta a nombre de quién se factura: lo lee
    // del eventual y lo congela. Los parámetros manuales sobreviven
    // únicamente para el histórico anterior a la schemaVersion 90, que
    // nunca pudo capturarlo.
    String razonSocial;
    String rfc;
    String? codigoPostalFiscal;
    String? idEntidadFiscal;

    final entidadDelEventual = eventual.entidadFiscalId;
    if (entidadDelEventual != null && entidadDelEventual.isNotEmpty) {
      // Camino de Cliente: la verdad viva está en su Entidad fiscal, y
      // se copia aquí para que el documento de hoy no cambie si mañana
      // el Cliente cambia de razón social o de domicilio.
      final entidades = await _entidadFiscalRepository.listarPorCliente(eventual.clienteId ?? '');
      final entidad = entidades.where((e) => e.entidadFiscal.id == entidadDelEventual).firstOrNull;
      if (entidad == null) return RegistrarDocumentoFiscalEventualEntidadFiscalInvalida();
      razonSocial = entidad.entidadFiscal.razonSocial;
      rfc = entidad.entidadFiscal.rfc;
      codigoPostalFiscal = entidad.domicilioFiscal?.codigoPostal;
      idEntidadFiscal = entidadDelEventual;
    } else if ((eventual.solicitanteRazonSocial ?? '').trim().isNotEmpty) {
      // Camino de solicitante ocasional: el snapshot ya se capturó y
      // validó al vender. No se vuelve a pedir.
      razonSocial = eventual.solicitanteRazonSocial!.trim();
      rfc = (eventual.solicitanteRfc ?? '').trim();
      codigoPostalFiscal = eventual.solicitanteCodigoPostalFiscal;
    } else if (entidadFiscalId != null && entidadFiscalId.isNotEmpty) {
      // Histórico: el eventual no guarda receptor fiscal, así que se
      // acepta el que indique quien registra el CFDI.
      final entidades = await _entidadFiscalRepository.listarPorCliente(eventual.clienteId ?? '');
      final entidad = entidades.where((e) => e.entidadFiscal.id == entidadFiscalId).firstOrNull;
      if (entidad == null) return RegistrarDocumentoFiscalEventualEntidadFiscalInvalida();
      razonSocial = entidad.entidadFiscal.razonSocial;
      rfc = entidad.entidadFiscal.rfc;
      codigoPostalFiscal = entidad.domicilioFiscal?.codigoPostal;
      idEntidadFiscal = entidadFiscalId;
    } else {
      razonSocial = (razonSocialManual ?? '').trim();
      rfc = (rfcManual ?? '').trim();
      codigoPostalFiscal = codigoPostalFiscalManual?.trim();
    }
    if (razonSocial.isEmpty || rfc.isEmpty) {
      return RegistrarDocumentoFiscalEventualDatosFiscalesRequeridos();
    }

    try {
      final documento = await _documentoRepository.registrar(
        servicioEventualId: servicioEventualId,
        folio: folioLimpio,
        uuid: uuidLimpio == null || uuidLimpio.isEmpty ? null : uuidLimpio,
        fechaEmision: fechaEmision,
        // El importe del documento ES el de la venta, tomado de la
        // Cuenta por cobrar para que los tres números no puedan
        // divergir por una captura.
        importe: (await _cuentaPorCobrarRepository.obtenerPorServicioEventualId(servicioEventualId))
                ?.importeEmitido ??
            eventual.importeAcordado,
        metodo: metodo.name,
        requiereComplemento: metodo == MetodoPagoCobro.ppd,
        snapshotRazonSocial: razonSocial,
        snapshotRfc: rfc,
        // Nullable sólo para el histórico: un eventual vendido desde la
        // v90 siempre lo trae.
        snapshotCodigoPostalFiscal:
            (codigoPostalFiscal ?? '').isEmpty ? null : codigoPostalFiscal,
        entidadFiscalId: idEntidadFiscal,
        observaciones: observaciones?.trim().isEmpty ?? true ? null : observaciones!.trim(),
        actorUsuarioId: actorUsuarioId,
      );
      return RegistrarDocumentoFiscalEventualExitoso(documento);
    } catch (e) {
      return RegistrarDocumentoFiscalEventualErrorInesperado(e.toString());
    }
  }
}

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/tables/cuenta_por_cobrar_table.dart' show EstatusCuentaPorCobrar;
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart'
    show MetodoPagoCobro;
import 'package:riseg_one/features/organizacion/domain/repositories/cliente_repository.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/entidad_fiscal_repository.dart';

import '../../data/tables/servicio_eventual_table.dart';
import '../receptor_fiscal_eventual.dart';
import '../repositories/servicio_eventual_repository.dart';
import '../totales_venta_eventual.dart';

sealed class CrearServicioEventualResultado {}

class CrearServicioEventualExitoso extends CrearServicioEventualResultado {
  CrearServicioEventualExitoso({required this.servicioEventual, required this.cuenta, this.pago});

  final ServicioEventualData servicioEventual;

  /// Siempre presente: vender un eventual **es** generar la obligación
  /// de cobro. Nunca hay un eventual exitoso sin su Cuenta.
  final CuentaPorCobrarData cuenta;

  /// Sólo cuando se cobró en el mismo acto.
  final PagoData? pago;
}

class CrearServicioEventualNombreRequerido extends CrearServicioEventualResultado {}

/// El fin nunca puede ser anterior al inicio — misma regla que el
/// `CHECK` del esquema, validada aquí para dar un mensaje útil en vez
/// de una excepción de SQLite.
class CrearServicioEventualRangoInvalido extends CrearServicioEventualResultado {}

class CrearServicioEventualImporteInvalido extends CrearServicioEventualResultado {}

/// Un eventual de Cliente exige `clienteId`; uno externo exige el
/// nombre del solicitante. Nunca los dos, nunca ninguno.
class CrearServicioEventualSolicitanteIncompleto extends CrearServicioEventualResultado {}

class CrearServicioEventualClienteNoExiste extends CrearServicioEventualResultado {}

/// Sin factura, el método SIEMPRE es `noAplica`; con factura, `pue` o
/// `ppd` — nunca al revés. Es lo que hace imposible que un eventual sin
/// factura acabe exigiendo un Complemento de pago.
class CrearServicioEventualMetodoIncoherente extends CrearServicioEventualResultado {}

/// El cobro inmediato no puede ser cero, negativo ni mayor que la venta.
class CrearServicioEventualCobroInvalido extends CrearServicioEventualResultado {}

/// Con factura y un solicitante **ocasional**, faltan o están mal los
/// datos del receptor fiscal (schemaVersion 90). El motivo exacto viaja
/// dentro para que la pantalla señale el campo, no el formulario entero.
class CrearServicioEventualReceptorFiscalInvalido extends CrearServicioEventualResultado {
  CrearServicioEventualReceptorFiscalInvalido(this.motivo);
  final ErrorReceptorFiscalEventual motivo;
}

/// Con factura y un **Cliente**, no se eligió a nombre de qué Entidad
/// fiscal suya se emitirá. No se recaptura razón social ni RFC: se
/// apunta a la que el Cliente ya tiene.
class CrearServicioEventualEntidadFiscalRequerida extends CrearServicioEventualResultado {}

/// La Entidad fiscal elegida no existe o no pertenece a este Cliente.
class CrearServicioEventualEntidadFiscalInvalida extends CrearServicioEventualResultado {}

/// La Entidad fiscal no tiene domicilio fiscal registrado, así que no
/// hay CP que congelar en el CFDI. Se bloquea aquí, al vender, en vez
/// de descubrirlo al facturar: el dato se completa en Comercial.
class CrearServicioEventualEntidadFiscalSinDomicilio extends CrearServicioEventualResultado {
  CrearServicioEventualEntidadFiscalSinDomicilio(this.razonSocial);
  final String razonSocial;
}

class CrearServicioEventualErrorInesperado extends CrearServicioEventualResultado {
  CrearServicioEventualErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Alta de un Servicio Eventual (schemaVersion 88).
///
/// **Vender genera cobranza.** El eventual, su única `CuentaPorCobrar`
/// y —si se cobra en el acto— el `Pago`, su `AplicacionPago` y su
/// `Ingreso` nacen en la misma transacción. No se crea ningún
/// `DocumentoPorEmitir`: la cobranza eventual no pasa por la agenda
/// comercial.
class CrearServicioEventualUseCase {
  CrearServicioEventualUseCase(this._repository, this._clienteRepository, this._entidadFiscalRepository);

  final ServicioEventualRepository _repository;
  final ClienteRepository _clienteRepository;

  /// Sólo para resolver el receptor fiscal del camino de Cliente — este
  /// módulo nunca crea ni modifica una Entidad fiscal.
  final EntidadFiscalRepository _entidadFiscalRepository;

  Future<CrearServicioEventualResultado> ejecutar({
    required String nombre,
    required DateTime fechaHoraInicio,
    required DateTime fechaHoraFin,
    String? ubicacion,
    String? notas,
    required int importeAcordado,
    required TipoSolicitanteServicioEventual tipoSolicitante,
    String? clienteId,
    String? solicitanteNombre,
    String? solicitanteContacto,
    String? solicitanteTelefono,
    String? solicitanteCorreo,
    String? entidadFiscalId,
    String? solicitanteRazonSocial,
    String? solicitanteRfc,
    String? solicitanteCodigoPostalFiscal,
    bool requiereFactura = false,
    TratamientoIva tratamientoIva = TratamientoIva.noAplica,
    MetodoPagoCobro metodoCobro = MetodoPagoCobro.noAplica,
    DateTime? fechaVencimiento,
    CobroInmediatoServicioEventual? cobroInmediato,
    String? actorUsuarioId,
  }) async {
    final nombreLimpio = nombre.trim();
    if (nombreLimpio.isEmpty) return CrearServicioEventualNombreRequerido();
    if (fechaHoraFin.isBefore(fechaHoraInicio)) return CrearServicioEventualRangoInvalido();
    if (importeAcordado <= 0) return CrearServicioEventualImporteInvalido();

    // Sin factura ⇒ noAplica. Con factura ⇒ pue|ppd. La equivalencia se
    // exige en los dos sentidos a propósito: es la compuerta que impide
    // que un recibo termine pidiendo Complemento de pago.
    final esNoAplica = metodoCobro == MetodoPagoCobro.noAplica;
    if (requiereFactura == esNoAplica) return CrearServicioEventualMetodoIncoherente();

    final esCliente = tipoSolicitante == TipoSolicitanteServicioEventual.cliente;
    final idCliente = (clienteId ?? '').trim();
    final nombreSolicitante = (solicitanteNombre ?? '').trim();

    if (esCliente) {
      if (idCliente.isEmpty) return CrearServicioEventualSolicitanteIncompleto();
      if (await _clienteRepository.obtenerPorId(idCliente) == null) {
        return CrearServicioEventualClienteNoExiste();
      }
    } else if (nombreSolicitante.isEmpty) {
      return CrearServicioEventualSolicitanteIncompleto();
    }

    // §1 — el receptor fiscal. Sólo se exige cuando hay factura: un
    // evento sin CFDI no necesita a nombre de quién emitirlo, y pedirlo
    // convertiría un recibo en un trámite.
    DatosFiscalesEventual? fiscalesManuales;
    String? idEntidadFiscal;
    if (requiereFactura) {
      if (esCliente) {
        final id = (entidadFiscalId ?? '').trim();
        if (id.isEmpty) return CrearServicioEventualEntidadFiscalRequerida();
        // Se busca DENTRO de las del Cliente del eventual: así una
        // Entidad fiscal de otro Cliente nunca puede colarse.
        final entidades = await _entidadFiscalRepository.listarPorCliente(idCliente);
        final entidad = entidades.where((e) => e.entidadFiscal.id == id).firstOrNull;
        if (entidad == null) return CrearServicioEventualEntidadFiscalInvalida();
        if (!entidad.datosFiscalesCompletos) {
          return CrearServicioEventualEntidadFiscalSinDomicilio(entidad.entidadFiscal.razonSocial);
        }
        idEntidadFiscal = id;
      } else {
        final validado = validarReceptorFiscalEventual(
          razonSocial: solicitanteRazonSocial,
          rfc: solicitanteRfc,
          codigoPostalFiscal: solicitanteCodigoPostalFiscal,
        );
        if (validado.error != null) {
          return CrearServicioEventualReceptorFiscalInvalido(validado.error!);
        }
        fiscalesManuales = validado.datos;
      }
    }

    // El cobro se valida contra el TOTAL de la venta, no contra lo
    // capturado: con `masIva` el cliente paga 11,600 aunque se haya
    // capturado 10,000, y rechazarlo por "sobrepago" sería un error.
    final totalVenta = totalVentaEventual(
      importeAcordado: importeAcordado,
      tratamientoIva: tratamientoIva,
    );
    if (cobroInmediato != null && (cobroInmediato.monto <= 0 || cobroInmediato.monto > totalVenta)) {
      return CrearServicioEventualCobroInvalido();
    }

    try {
      final venta = await _repository.crear(
        nombre: nombreLimpio,
        fechaHoraInicio: fechaHoraInicio,
        fechaHoraFin: fechaHoraFin,
        ubicacion: _opcional(ubicacion),
        notas: _opcional(notas),
        importeAcordado: importeAcordado,
        tipoSolicitante: tipoSolicitante,
        // El XOR del esquema se respeta escribiendo exactamente un
        // lado: un eventual de Cliente jamás guarda además los datos
        // sueltos del solicitante externo.
        clienteId: esCliente ? idCliente : null,
        solicitanteNombre: esCliente ? null : nombreSolicitante,
        solicitanteContacto: esCliente ? null : _opcional(solicitanteContacto),
        solicitanteTelefono: esCliente ? null : _opcional(solicitanteTelefono),
        solicitanteCorreo: esCliente ? null : _opcional(solicitanteCorreo),
        // Mismo XOR que el solicitante: el receptor fiscal vive de un
        // lado o del otro, nunca a medias en los dos.
        entidadFiscalId: idEntidadFiscal,
        solicitanteRazonSocial: fiscalesManuales?.razonSocial,
        solicitanteRfc: fiscalesManuales?.rfc,
        solicitanteCodigoPostalFiscal: fiscalesManuales?.codigoPostalFiscal,
        requiereFactura: requiereFactura,
        tratamientoIva: tratamientoIva.name,
        metodoCobro: metodoCobro.name,
        // Sólo PPD obliga a Complemento — PUE y noAplica nunca.
        requiereComplemento: metodoCobro == MetodoPagoCobro.ppd,
        fechaVencimiento: fechaVencimiento,
        cobroInmediato: cobroInmediato,
        actorUsuarioId: actorUsuarioId,
      );
      return CrearServicioEventualExitoso(
        servicioEventual: venta.eventual,
        cuenta: venta.cuenta,
        pago: venta.pago,
      );
    } catch (e) {
      return CrearServicioEventualErrorInesperado(e.toString());
    }
  }
}

/// El estatus que deja un cobro inmediato — `pagada` si cubrió toda la
/// venta, `parcial` si no. Lo calcula la Cuenta, no esta función; existe
/// sólo para que las pruebas y la UI nombren lo mismo.
EstatusCuentaPorCobrar estatusEsperadoTrasCobro({required int venta, required int cobrado}) {
  return cobrado >= venta ? EstatusCuentaPorCobrar.pagada : EstatusCuentaPorCobrar.parcial;
}

String? _opcional(String? valor) {
  final limpio = valor?.trim() ?? '';
  return limpio.isEmpty ? null : limpio;
}

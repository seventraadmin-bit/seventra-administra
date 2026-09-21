import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/complemento_pago_repository.dart';

import '../repositories/servicio_eventual_documento_fiscal_repository.dart';
import '../repositories/servicio_eventual_repository.dart';

/// Qué le pasó —o le pasaría— a un eventual en la reconciliación.
sealed class ResultadoReconciliacionEventual {
  const ResultadoReconciliacionEventual(this.servicioEventual);
  final ServicioEventualData servicioEventual;
}

/// Se revirtió su cobranza (o se revertiría, en modo diagnóstico).
class EventualReconciliable extends ResultadoReconciliacionEventual {
  const EventualReconciliable(
    super.servicioEventual, {
    required this.cobros,
    required this.cuenta,
  });

  /// Los cobros que se soltaron: exclusivos (Pago entero, sale del
  /// banco) o compartidos (sólo la aplicación, el dinero se queda).
  final List<CobroDeVentaEventual> cobros;
  final CuentaPorCobrarData cuenta;

  int get montoQueVuelve =>
      cobros.where((c) => c.exclusivoDeEstaVenta).fold(0, (suma, c) => suma + c.pago.montoTotal);
}

/// No se puede reconciliar en automático: hay un CFDI o un Complemento
/// vigente. La anulación nueva se habría **bloqueado** en ese mismo
/// punto, así que reproducirla aquí sería inventar una cancelación
/// fiscal que nadie hizo. Se reporta y se deja intacto: primero se
/// cancela el documento por su propio flujo y después se vuelve a
/// correr esta reconciliación.
class EventualBloqueadoPorFiscal extends ResultadoReconciliacionEventual {
  const EventualBloqueadoPorFiscal(super.servicioEventual, {this.folioDocumento, this.uuidComplemento});
  final String? folioDocumento;
  final String? uuidComplemento;
}

/// Lleva a su estado correcto los Servicios Eventuales que se
/// cancelaron con la implementación anterior a la schemaVersion 90.
///
/// **El hueco que repara.** Antes de la v90 "Cancelar evento" sólo
/// cambiaba el estatus del evento y de sus coberturas/costos
/// programados. La Cuenta por cobrar, el Pago, su Aplicación, el
/// Ingreso automático y —por derivación— el saldo de la cuenta bancaria
/// quedaban vivos. Desde la v90 cancelar el evento **es** anular la
/// venta (decisión de Marlon), y esos registros quedaron contradiciendo
/// esa semántica.
///
/// **Cómo detecta, sin adivinar.** Por FK y estatus, nunca por folio,
/// monto ni texto: evento `cancelado` + su Cuenta por cobrar NO
/// `cancelada`. Ese estado sólo lo pudo dejar la implementación vieja
/// (ver `ServicioEventualRepository.listarCanceladosConCobranzaViva`).
///
/// **Cómo repara.** Con el MISMO código que la anulación nueva
/// (`revertirCobranzaDeLaVenta`), no con una copia: Pago exclusivo →
/// cancelado con su aplicación e Ingreso; Pago compartido → sólo su
/// aplicación; Cuenta → cancelada. El evento ya estaba cancelado, así
/// que no se toca, y las coberturas/costos pagados (gasto real) nunca.
///
/// **Idempotente por construcción.** Un eventual reconciliado deja de
/// cumplir el criterio de detección (su Cuenta queda cancelada), así
/// que la segunda corrida no lo encuentra y no hace nada.
class ReconciliarAnulacionesServicioEventualUseCase {
  ReconciliarAnulacionesServicioEventualUseCase(
    this._repository,
    this._documentoFiscalRepository,
    this._complementoPagoRepository,
  );

  final ServicioEventualRepository _repository;
  final ServicioEventualDocumentoFiscalRepository _documentoFiscalRepository;
  final ComplementoPagoRepository _complementoPagoRepository;

  /// Con [aplicar] en `false` sólo diagnostica: devuelve lo que haría
  /// sin escribir una sola fila.
  Future<List<ResultadoReconciliacionEventual>> ejecutar({
    required bool aplicar,
    String? actorUsuarioId,
  }) async {
    final candidatos = await _repository.listarCanceladosConCobranzaViva();
    final resultados = <ResultadoReconciliacionEventual>[];

    for (final eventual in candidatos) {
      // Los mismos bloqueos que la anulación nueva, en el mismo orden.
      final documento = await _documentoFiscalRepository.obtenerVigente(eventual.id);
      final cobros = await _repository.cobrosDeLaVenta(eventual.id);
      String? uuidComplemento;
      for (final cobro in cobros) {
        final complemento = await _complementoPagoRepository.obtenerVigentePorPagoId(cobro.pago.id);
        if (complemento != null) {
          uuidComplemento = complemento.uuid;
          break;
        }
      }
      if (documento != null || uuidComplemento != null) {
        resultados.add(EventualBloqueadoPorFiscal(
          eventual,
          folioDocumento: documento?.folio,
          uuidComplemento: uuidComplemento,
        ));
        continue;
      }

      final cuenta = (await _repository.obtenerCuentaPorCobrar(eventual.id))!;
      resultados.add(EventualReconciliable(eventual, cobros: cobros, cuenta: cuenta));

      if (aplicar) {
        await _repository.revertirCobranzaDeLaVenta(
          servicioEventualId: eventual.id,
          // El motivo explica POR QUÉ se movió dinero hoy de un evento
          // cancelado ayer, y conserva el motivo original de la
          // cancelación para que nadie tenga que reconstruirlo.
          motivo: 'Reconciliación v90: el evento se canceló antes de que cancelar anulara la '
              'venta; se revierte su cobranza como lo habría hecho la cancelación actual. '
              'Motivo original: ${eventual.motivoCancelacion ?? '(sin motivo)'}',
          actorUsuarioId: actorUsuarioId,
        );
      }
    }
    return resultados;
  }
}

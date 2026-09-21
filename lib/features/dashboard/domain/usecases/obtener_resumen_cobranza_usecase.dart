import 'package:riseg_one/features/finanzas/data/tables/cuenta_por_cobrar_table.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/cuenta_por_cobrar_repository.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cuenta_por_cobrar_antiguedad.dart';
import 'package:riseg_one/features/notificaciones/domain/usecases/obtener_notificaciones_cxc_usecase.dart'
    show umbralDiasCxcProximaAVencer;

/// Cantidad + importe de un renglón de la tabla de Cobranza.
class ClasificacionCobranza {
  const ClasificacionCobranza({this.cantidad = 0, this.importe = 0});

  final int cantidad;
  final int importe;
}

/// Un documento clasificado como `vencido` — la fuente exacta de la
/// bandeja "Requiere atención" (Parte K), nunca una segunda
/// implementación independiente de la misma regla.
class CuentaPorCobrarVencidaResumen {
  const CuentaPorCobrarVencidaResumen({
    required this.cuentaId,
    required this.clienteId,
    required this.folioDocumento,
    required this.saldoPendiente,
    required this.diasVencido,
  });

  final String cuentaId;
  final String clienteId;
  final String? folioDocumento;
  final int saldoPendiente;
  final int diasVencido;
}

/// Resumen de Cobranza (Etapa 15, rediseño del Dashboard) — clasifica
/// cada `CuentaPorCobrar` en EXACTAMENTE una de 4 categorías amigables
/// para la UI, reutilizando las reglas de dominio ya existentes
/// (`estaVencida`/`diasParaVencerCxc`/`umbralDiasCxcProximaAVencer`,
/// ya usadas por Notificaciones) — nunca un estado nuevo, nunca una
/// segunda regla de "vencido"/"próximo a vencer" paralela.
///
/// Clasificación (orden de evaluación, mutuamente excluyente):
/// 1. `estatus == pagada` → **Pagado** (importe = `importeEmitido`, el
///    valor total ya cobrado).
/// 2. `estaVencida` → **Vencido** (importe = `saldoPendiente`).
/// 3. `0 <= diasParaVencerCxc <= umbralDiasCxcProximaAVencer` →
///    **Próximo a vencer** (importe = `saldoPendiente`).
/// 4. Cualquier otro caso no pagado (`pendiente`/`parcial` con tiempo de
///    sobra, o sin `fechaVencimiento` capturada) → **En proceso**
///    (importe = `saldoPendiente`).
///
/// [totalPorCobrar] es la suma de `saldoPendiente` de TODO lo no
/// pagado (en proceso + próximo + vencido) — nunca incluye `pagado`
/// (ya cobrado, no es "por cobrar").
class ResumenCobranza {
  const ResumenCobranza({
    required this.totalPorCobrar,
    required this.pagado,
    required this.enProceso,
    required this.proximoAVencer,
    required this.vencido,
    required this.documentosVencidos,
    this.diasProximoMasCercano,
  });

  final int totalPorCobrar;
  final ClasificacionCobranza pagado;
  final ClasificacionCobranza enProceso;
  final ClasificacionCobranza proximoAVencer;
  final ClasificacionCobranza vencido;

  /// Detalle de cada documento vencido, orden descendente por
  /// `diasVencido` (el más urgente primero) — fuente directa de la
  /// bandeja "Requiere atención".
  final List<CuentaPorCobrarVencidaResumen> documentosVencidos;

  /// Días hasta el vencimiento MÁS CERCANO entre las cuentas "próximo a
  /// vencer" — `null` cuando `proximoAVencer.cantidad == 0` (Etapa 15
  /// v1.1, tabla compacta Estado/Días de Cobranza).
  final int? diasProximoMasCercano;

  /// Antigüedad del documento vencido más urgente (el primero de
  /// [documentosVencidos], ya ordenado desc) — `0` cuando no hay ningún
  /// vencido, nunca `null` (así la UI puede mostrar "Vencido · 0" sin
  /// un branch adicional).
  int get diasVencidoMasUrgente => documentosVencidos.isEmpty ? 0 : documentosVencidos.first.diasVencido;
}

class ObtenerResumenCobranzaUseCase {
  ObtenerResumenCobranzaUseCase(this._repository);

  final CuentaPorCobrarRepository _repository;

  Future<ResumenCobranza> ejecutar({required DateTime hoy}) async {
    final cuentas = await _repository.listar();

    var pagadoCantidad = 0, pagadoImporte = 0;
    var procesoCantidad = 0, procesoImporte = 0;
    var proximoCantidad = 0, proximoImporte = 0;
    var vencidoCantidad = 0, vencidoImporte = 0;
    int? diasProximoMasCercano;
    final vencidos = <CuentaPorCobrarVencidaResumen>[];

    for (final cuenta in cuentas) {
      if (EstatusCuentaPorCobrar.values.byName(cuenta.estatus) == EstatusCuentaPorCobrar.pagada) {
        pagadoCantidad++;
        pagadoImporte += cuenta.importeEmitido;
        continue;
      }

      if (estaVencida(cuenta, hoy)) {
        vencidoCantidad++;
        vencidoImporte += cuenta.saldoPendiente;
        final vencimiento = cuenta.fechaVencimiento!;
        final diasVencido = DateTime(hoy.year, hoy.month, hoy.day)
            .difference(DateTime(vencimiento.year, vencimiento.month, vencimiento.day))
            .inDays;
        vencidos.add(
          CuentaPorCobrarVencidaResumen(
            cuentaId: cuenta.id,
            clienteId: cuenta.clienteId ?? '',
            folioDocumento: cuenta.folioDocumento,
            saldoPendiente: cuenta.saldoPendiente,
            diasVencido: diasVencido,
          ),
        );
        continue;
      }

      final diasParaVencer = diasParaVencerCxc(cuenta, hoy);
      if (diasParaVencer != null && diasParaVencer >= 0 && diasParaVencer <= umbralDiasCxcProximaAVencer) {
        proximoCantidad++;
        proximoImporte += cuenta.saldoPendiente;
        if (diasProximoMasCercano == null || diasParaVencer < diasProximoMasCercano) {
          diasProximoMasCercano = diasParaVencer;
        }
        continue;
      }

      procesoCantidad++;
      procesoImporte += cuenta.saldoPendiente;
    }

    vencidos.sort((a, b) => b.diasVencido.compareTo(a.diasVencido));

    return ResumenCobranza(
      totalPorCobrar: procesoImporte + proximoImporte + vencidoImporte,
      pagado: ClasificacionCobranza(cantidad: pagadoCantidad, importe: pagadoImporte),
      enProceso: ClasificacionCobranza(cantidad: procesoCantidad, importe: procesoImporte),
      proximoAVencer: ClasificacionCobranza(cantidad: proximoCantidad, importe: proximoImporte),
      vencido: ClasificacionCobranza(cantidad: vencidoCantidad, importe: vencidoImporte),
      documentosVencidos: vencidos,
      diasProximoMasCercano: diasProximoMasCercano,
    );
  }
}

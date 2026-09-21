import '../../data/tables/servicio_linea_comercial_vigencia_table.dart' show TratamientoIva;
import 'calcular_importe_proporcional_usecase.dart' show redondearCentavos;

/// Tasa fija de IVA para `masIva` en RISEG ONE v1.0 (Etapa 15,
/// confirmación explícita de Marlon: "para RISEG v1.0, masIva significa
/// específicamente IVA 16%"). Un cambio de tasa (ej. zona fronteriza al
/// 8%) requeriría una nueva vigencia del modelo comercial, no un
/// parámetro aquí.
const tasaIvaMasIva = 0.16;

/// Los tres montos esperados para control comercial/cobranza —
/// deliberadamente NUNCA para timbrar ni emitir un CFDI (eso lo hace un
/// sistema externo); solo para que RISEG sepa cuánto debería cobrarse
/// según la configuración comercial, y pueda comparar contra lo que en
/// realidad se emitió (`DocumentoPorEmitir.importeEmitido`).
class TotalesEsperados {
  const TotalesEsperados({required this.base, required this.ivaEsperado, required this.totalEsperado});

  /// Importe base después de prorrateos y ajuste manual (si existe) —
  /// ya no es el `importeBaseEsperado` crudo cuando hay ajuste.
  final int base;

  /// `0` para `noAplica`/`ivaIncluido` — `ivaIncluido` nunca desglosa un
  /// monto de IVA en esta etapa (Resolución explícita de Marlon: "si
  /// necesitamos mostrar IVA desglosado, NO lo calcules por ahora salvo
  /// que exista un requerimiento real").
  final int ivaEsperado;

  final int totalEsperado;
}

/// Calcula los totales esperados de un documento (o de una línea) para
/// control comercial/cobranza — Etapa 15, corrección estructural sobre
/// el CFDI real de MILUYOLE: antes RISEG comparaba un importe emitido
/// con IVA contra una base sin IVA, produciendo una "diferencia" que en
/// realidad era el IVA mismo.
///
/// `ajusteManualCentavos` se suma a la base ANTES de aplicar el
/// tratamiento de IVA — nunca después (eso duplicaría o ignoraría el
/// ajuste, según el caso): un ajuste comercial cambia el monto que
/// efectivamente se factura, así que el IVA de `masIva` debe calcularse
/// sobre esa base ya ajustada, igual que `importeFinalEsperado` ya se
/// calcula como `importeBaseEsperado + ajusteManual`
/// (`DocumentoPorEmitirRepositoryImpl.actualizarAjusteManual`).
TotalesEsperados calcularTotalesEsperados({
  required int importeBaseCentavos,
  int? ajusteManualCentavos,
  required TratamientoIva tratamientoIva,
}) {
  final baseAjustada = importeBaseCentavos + (ajusteManualCentavos ?? 0);

  return switch (tratamientoIva) {
    TratamientoIva.noAplica || TratamientoIva.ivaIncluido => TotalesEsperados(
        base: baseAjustada,
        ivaEsperado: 0,
        totalEsperado: baseAjustada,
      ),
    TratamientoIva.masIva => () {
        final iva = redondearCentavos(baseAjustada * tasaIvaMasIva);
        return TotalesEsperados(base: baseAjustada, ivaEsperado: iva, totalEsperado: baseAjustada + iva);
      }(),
  };
}

/// Separa un total que YA trae el IVA dentro — la operación inversa de
/// `masIva`, con la misma tasa y el mismo redondeo.
///
/// **No cambia la semántica global**: `calcularTotalesEsperados` sigue
/// devolviendo `ivaEsperado: 0` para `ivaIncluido`, y ningún consumidor
/// existente ve una diferencia. Esta función se agregó para el
/// requerimiento real de Servicios Eventuales (schemaVersion 89), que sí
/// necesita mostrarle al usuario cuánto de lo que va a cobrar es IVA
/// antes de guardar. Vive aquí, junto a la tasa, para que nadie vuelva
/// a escribir 0.16 en otro archivo.
///
/// `base = total / 1.16`, e `iva = total - base` — nunca
/// `base * 0.16` por separado: así `base + iva == total` SIEMPRE, sin
/// que el redondeo pueda dejar un centavo huérfano.
TotalesEsperados desglosarIvaIncluido(int totalCentavos) {
  final base = redondearCentavos(totalCentavos / (1 + tasaIvaMasIva));
  return TotalesEsperados(base: base, ivaEsperado: totalCentavos - base, totalEsperado: totalCentavos);
}

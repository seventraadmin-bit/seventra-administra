import '../../data/tables/servicio_linea_comercial_vigencia_table.dart' show TratamientoIva;
import 'resumen_iva_documento_por_emitir.dart';
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

/// Una línea ya snapshot, reducida a lo único que importa para el IVA.
typedef LineaGravable = ({int subtotalCentavos, TratamientoIva tratamientoIva});

/// Totales de un documento cuyas líneas NO comparten tratamiento fiscal
/// ("mixto").
///
/// Aplicar una sola tasa a un documento mixto sería incorrecto, así que
/// se calcula **línea por línea** y se suma: cada línea aporta su
/// subtotal a la base, y sólo las `masIva` aportan IVA. Es inequívoco
/// porque el snapshot de cada línea ya guarda su propio
/// `tratamientoIva` junto a su `subtotalProporcional`, y la suma de esos
/// subtotales es exactamente `importeBaseEsperado`
/// (`EnsamblarDocumentoPorEmitirUseCase`).
///
/// `ivaIncluido` aporta `0` de IVA desglosado, igual que en el camino
/// homogéneo — no se desglosa aquí lo que allá no se desglosa.
///
/// **Sin ajuste manual a propósito**: el ajuste de un documento mixto no
/// pertenece a ningún tratamiento fiscal en particular, y repartirlo
/// entre líneas sería inventar un dato. Ese caso no llega hasta aquí
/// (ver `DocumentoPorEmitirDetalle.totalesEsperados`).
TotalesEsperados calcularTotalesEsperadosMixto(List<LineaGravable> lineas) {
  var base = 0;
  var iva = 0;
  for (final linea in lineas) {
    base += linea.subtotalCentavos;
    if (linea.tratamientoIva == TratamientoIva.masIva) {
      iva += redondearCentavos(linea.subtotalCentavos * tasaIvaMasIva);
    }
  }
  return TotalesEsperados(base: base, ivaEsperado: iva, totalEsperado: base + iva);
}
/// Lo que la Agenda y el detalle necesitan saber de un documento: su total
/// esperado, o por qué no lo hay.
class TotalesDeDocumento {
  const TotalesDeDocumento(this.totales, {this.noDisponiblePorAjusteEnMixto = false});

  /// `null` cuando no existe un total fiscalmente comparable.
  final TotalesEsperados? totales;

  /// La única razón por la que hoy puede faltar: un ajuste escalar sobre un
  /// documento con tratamientos mezclados. Se expone para poder explicarlo
  /// en pantalla en vez de dejar un hueco mudo.
  final bool noDisponiblePorAjusteEnMixto;
}

/// **La única decisión fiscal del proyecto**, compartida por el detalle del
/// documento y por el renglón/KPI de la Agenda. Existe como función y no
/// duplicada en cada consumidor justamente para que la columna, el KPI y la
/// ficha no puedan discrepar entre sí.
///
/// Tres caminos, ninguno inventado:
///
/// 1. **Homogéneo** — una sola tasa sobre la base ya ajustada. El ajuste se
///    suma ANTES del IVA: un ajuste comercial cambia el monto que se
///    factura, y el IVA se causa sobre ese monto.
/// 2. **Mixto sin ajuste** — línea por línea. Cada línea trae su propio
///    tratamiento junto a su subtotal, y la suma de esos subtotales es
///    exactamente `importeBaseEsperado`, así que es reconstruible.
/// 3. **Mixto con ajuste** — sin total. Un escalar único no pertenece a
///    ningún tratamiento, y repartirlo entre líneas sería inventar un dato
///    fiscal.
TotalesDeDocumento totalesEsperadosDeDocumento({
  required int importeBaseEsperado,
  required int? ajusteManual,
  required List<LineaGravableSnapshot> lineas,
}) {
  final resumen = calcularResumenIva([for (final l in lineas) l.tratamientoIva]);

  final tratamiento = switch (resumen) {
    ResumenIvaDocumento.masIva => TratamientoIva.masIva,
    ResumenIvaDocumento.ivaIncluido => TratamientoIva.ivaIncluido,
    ResumenIvaDocumento.noAplica => TratamientoIva.noAplica,
    ResumenIvaDocumento.mixto => null,
  };

  if (tratamiento != null) {
    return TotalesDeDocumento(
      calcularTotalesEsperados(
        importeBaseCentavos: importeBaseEsperado,
        ajusteManualCentavos: ajusteManual,
        tratamientoIva: tratamiento,
      ),
    );
  }

  if ((ajusteManual ?? 0) != 0) {
    return const TotalesDeDocumento(null, noDisponiblePorAjusteEnMixto: true);
  }

  return TotalesDeDocumento(
    calcularTotalesEsperadosMixto([
      for (final l in lineas)
        (
          subtotalCentavos: l.subtotalCentavos,
          tratamientoIva: TratamientoIva.values.byName(l.tratamientoIva),
        ),
    ]),
  );
}

/// Una línea tal como está persistida: su subtotal y el NOMBRE de su
/// tratamiento (texto en la base, nunca el enum).
typedef LineaGravableSnapshot = ({int subtotalCentavos, String tratamientoIva});

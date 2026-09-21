import 'package:riseg_one/features/organizacion/data/tables/servicio_linea_comercial_vigencia_table.dart'
    show TratamientoIva;
import 'package:riseg_one/features/organizacion/domain/usecases/calcular_totales_esperados_usecase.dart';

export 'package:riseg_one/features/organizacion/data/tables/servicio_linea_comercial_vigencia_table.dart'
    show TratamientoIva;

/// Subtotal, IVA y total de la venta de un Servicio Eventual
/// (schemaVersion 89).
///
/// **Única fuente de verdad del total a cobrar.** Nadie multiplica por
/// la tasa a mano ni vuelve a escribir 0.16: el total sale de
/// `calcularTotalesEsperados` —la misma función, la misma tasa y el
/// mismo redondeo que usa la cobranza recurrente desde la Etapa 15— y
/// el desglose de `ivaIncluido` de `desglosarIvaIncluido`, que vive
/// junto a esa tasa.
///
/// `importeAcordado` es SIEMPRE lo que el usuario capturó; qué
/// significa depende del tratamiento:
///
/// | Tratamiento   | importeAcordado es | total a cobrar        |
/// |---------------|--------------------|-----------------------|
/// | `masIva`      | la base            | base + 16 %           |
/// | `ivaIncluido` | el total           | el mismo importe      |
/// | `noAplica`    | el total           | el mismo importe      |
///
/// Por eso `importeAcordado` **nunca** se usa directo como total: se
/// pasa por aquí. Ver `totalVentaEventual`.
class TotalesVentaEventual {
  const TotalesVentaEventual({required this.subtotal, required this.iva, required this.total});

  /// Base antes de impuestos.
  final int subtotal;

  /// `0` cuando el tratamiento es `noAplica`.
  final int iva;

  /// Lo que se le cobra al cliente. Es el número que viaja a
  /// `CuentaPorCobrar.importeEmitido` y a
  /// `ServicioEventualDocumentoFiscal.importe`.
  final int total;
}

/// Deriva los tres números desde lo capturado.
TotalesVentaEventual calcularTotalesVentaEventual({
  required int importeAcordado,
  required TratamientoIva tratamientoIva,
}) {
  switch (tratamientoIva) {
    case TratamientoIva.masIva:
      // El importe capturado es la BASE: el total lo calcula la misma
      // función que la cobranza recurrente.
      final totales = calcularTotalesEsperados(
        importeBaseCentavos: importeAcordado,
        tratamientoIva: TratamientoIva.masIva,
      );
      return TotalesVentaEventual(
        subtotal: totales.base,
        iva: totales.ivaEsperado,
        total: totales.totalEsperado,
      );
    case TratamientoIva.ivaIncluido:
      // El importe capturado ES el total; el desglose es informativo.
      final desglose = desglosarIvaIncluido(importeAcordado);
      return TotalesVentaEventual(
        subtotal: desglose.base,
        iva: desglose.ivaEsperado,
        total: desglose.totalEsperado,
      );
    case TratamientoIva.noAplica:
      // Sin impuesto que separar: el capturado es base y total a la vez.
      return TotalesVentaEventual(subtotal: importeAcordado, iva: 0, total: importeAcordado);
  }
}

/// Atajo para el único número que la cobranza necesita.
int totalVentaEventual({required int importeAcordado, required TratamientoIva tratamientoIva}) {
  return calcularTotalesVentaEventual(importeAcordado: importeAcordado, tratamientoIva: tratamientoIva).total;
}

/// El tratamiento con el que migran las filas anteriores a la
/// schemaVersion 89.
///
/// En la v88 `importeAcordado` **era** el total. `noAplica` es el único
/// tratamiento que reproduce ese total **sin inventar un desglose**:
/// con `ivaIncluido` el total también se conserva, pero la pantalla
/// empezaría a afirmar que esas ventas históricas contenían un IVA que
/// nadie capturó nunca. Se elige el que no afirma nada de más.
const tratamientoIvaLegacyEventual = TratamientoIva.noAplica;

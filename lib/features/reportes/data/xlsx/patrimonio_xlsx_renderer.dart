import 'package:excel/excel.dart';

import '../../domain/analitica/obtener_analisis_patrimonio_usecase.dart';
import '../../domain/export/reporte_export_context.dart';
import 'reporte_xlsx_utils.dart';

/// Etiquetas de exportación — constantes locales, como el resto de los
/// XLSX del proyecto (un renderizador no tiene `BuildContext`). Los
/// textos coinciden con los de pantalla.
const _resolucionLabel = {
  'devuelto': 'Devuelto',
  'noEntregado': 'No entregado',
  'transferido': 'Transferido',
  'perdido': 'Perdido',
  'desecho': 'Desecho',
};

const _motivoLabel = {
  'abandonoServicio': 'Abandono de servicio',
  'noLocalizado': 'No localizado',
  'seNegoAEntregar': 'Se negó a entregar',
  'entregaAcordadaPosteriormente': 'Entrega acordada después',
  'perdida': 'Pérdida',
  'robo': 'Robo',
  'noSeSolicitoDevolucion': 'No se solicitó devolución',
  'autorizadoAConservarlo': 'Autorizado a conservarlo',
  'otro': 'Otro',
};

/// Servicio historico. Nunca celda vacia: no poder resolverlo y tener
/// el dato roto son cosas distintas, y ambas se dicen.
String _servicioLabel(RenglonPatrimonio r) => switch (r.servicioHistorico.estado) {
      EstadoServicioHistorico.resuelto => r.servicioHistorico.nombre!,
      EstadoServicioHistorico.sinAsignacion => 'Sin servicio histórico resoluble',
      EstadoServicioHistorico.inconsistente => 'Inconsistencia de asignación',
    };

String _servicioRankingLabel(ProblemaPorServicio s) => switch (s.estado) {
      EstadoServicioHistorico.resuelto => s.nombre!,
      EstadoServicioHistorico.sinAsignacion => 'Sin servicio histórico resoluble',
      EstadoServicioHistorico.inconsistente => 'Inconsistencia de asignación',
    };

const _estatusUnidadLabel = {
  'disponible': 'Disponible',
  'asignado': 'Asignada',
  'enLavanderia': 'En lavandería',
  'enReparacion': 'En reparación',
  'pendienteDesecho': 'Pendiente de desecho',
  'danado': 'Dañada',
  'perdido': 'Perdida',
  'baja': 'Dada de baja',
};

/// XLSX de Patrimonio y bajas.
///
/// Recibe el análisis YA filtrado por la pantalla: el archivo contiene
/// exactamente el mismo universo que el usuario está viendo.
///
/// Cada hoja es una proyección del MISMO conjunto de renglones, filtrada
/// por criterio — nunca un join que duplique filas: un bien aparece una
/// vez en "Pendientes" o una vez en "Recuperados", jamás en las dos.
class PatrimonioXlsxRenderer {
  List<int> generar({required ReporteExportContext contexto, required AnalisisPatrimonio analisis}) {
    final excel = crearWorkbookConInfo(contexto);

    _resumen(excel, analisis);
    _pendientes(excel, analisis);
    _recuperados(excel, analisis);
    _descuentos(excel, analisis);
    _servicios(excel, analisis);
    _autorizaciones(excel, analisis);
    _vehiculos(excel, analisis);

    return excel.encode()!;
  }

  void _resumen(Excel excel, AnalisisPatrimonio analisis) {
    final hoja = excel['Resumen'];
    hoja.appendRow([TextCellValue('Indicador'), TextCellValue('Valor')]);

    void fila(String etiqueta, CellValue valor) => hoja.appendRow([TextCellValue(etiqueta), valor]);

    fila('Bajas conciliadas', IntCellValue(analisis.bajasConciliadas));
    fila('Bienes recuperados', IntCellValue(analisis.recuperados));
    fila('Pendientes de recuperar', IntCellValue(analisis.pendientes));
    fila('Bienes perdidos', IntCellValue(analisis.perdidos));
    fila('Transferidos', IntCellValue(analisis.transferidos));
    fila('Descuentos generados', DoubleCellValue(analisis.importeDescuentos / 100));
    fila('Saldo por cobrar', DoubleCellValue(analisis.saldoDescuentos / 100));
    fila('Valor no cobrado', DoubleCellValue(analisis.importeNoCobrado / 100));
    fila('Decisiones sin cobro', IntCellValue(analisis.decisionesSinCobro));
    fila('Valor de bienes pendientes', DoubleCellValue(analisis.valorPendiente / 100));
    fila('Valor de bienes perdidos', DoubleCellValue(analisis.valorPerdido / 100));
    fila('Bienes sin costo capturado', IntCellValue(analisis.bienesSinValorConocido));
    // Sin denominador no hay tasa: se dice, no se exporta un 0 que
    // afirmaría que no se recuperó nada.
    final tasa = analisis.tasaRecuperacion.tasa;
    fila(
      'Tasa de recuperación',
      tasa == null ? TextCellValue('Sin base') : DoubleCellValue(double.parse((tasa * 100).toStringAsFixed(1))),
    );
    fila('Denominador de la tasa', IntCellValue(analisis.tasaRecuperacion.debianRecuperarse));
    fila('Excluidos: transferidos', IntCellValue(analisis.tasaRecuperacion.excluidosTransferidos));
    fila('Excluidos: autorizados a conservar', IntCellValue(analisis.tasaRecuperacion.excluidosAutorizados));

    final estados = excel['Estados físicos'];
    estados.appendRow([TextCellValue('Estado'), TextCellValue('Unidades')]);
    for (final entrada in analisis.unidadesPorEstatus.entries) {
      estados.appendRow([
        TextCellValue(_estatusUnidadLabel[entrada.key] ?? entrada.key),
        IntCellValue(entrada.value),
      ]);
    }
  }

  void _encabezadoBien(Sheet hoja) {
    hoja.appendRow([
      TextCellValue('Ex empleado'),
      TextCellValue('Fecha de baja'),
      TextCellValue('Servicio (a la baja)'),
      TextCellValue('Bien'),
      TextCellValue('Tipo'),
      TextCellValue('Resolución'),
      TextCellValue('Motivo'),
      TextCellValue('Pendiente desde'),
      TextCellValue('Compromiso'),
      TextCellValue('Estado físico'),
      TextCellValue('Autorizó'),
      TextCellValue('Recibió'),
      TextCellValue('Descuento'),
      TextCellValue('Valor aprox.'),
    ]);
  }

  void _filaBien(Sheet hoja, RenglonPatrimonio r) {
    hoja.appendRow([
      TextCellValue(r.empleadoNombre),
      TextCellValue(formatearFechaCortaXlsx(r.fechaBaja)),
      TextCellValue(_servicioLabel(r)),
      TextCellValue(r.bienDescripcion),
      TextCellValue(r.tipo == TipoBienConciliado.vehiculo ? 'Vehículo' : 'Inventario'),
      TextCellValue(_resolucionLabel[r.resolucion.name] ?? r.resolucion.name),
      TextCellValue(r.motivoNoEntrega == null
          ? (r.renglon.motivoNoEntregaOtro ?? '—')
          : (_motivoLabel[r.motivoNoEntrega!.name] ?? r.motivoNoEntrega!.name)),
      TextCellValue(r.pendienteDesde == null ? '—' : formatearFechaCortaXlsx(r.pendienteDesde!)),
      TextCellValue(r.fechaCompromiso == null ? '—' : formatearFechaCortaXlsx(r.fechaCompromiso!)),
      TextCellValue(r.estatusUnidad == null ? '—' : (_estatusUnidadLabel[r.estatusUnidad!] ?? r.estatusUnidad!)),
      TextCellValue(r.autorizadorNombre ?? '—'),
      TextCellValue(r.receptorNombre ?? '—'),
      r.descuento == null ? TextCellValue('—') : DoubleCellValue(r.importeDescuento / 100),
      // Sin costo capturado: guion, nunca 0.
      r.valorAproximado == null ? TextCellValue('—') : DoubleCellValue(r.valorAproximado! / 100),
    ]);
  }

  void _pendientes(Excel excel, AnalisisPatrimonio analisis) {
    final hoja = excel['Pendientes'];
    _encabezadoBien(hoja);
    for (final r in analisis.renglones.where((r) => r.estaPendiente)) {
      _filaBien(hoja, r);
    }
  }

  void _recuperados(Excel excel, AnalisisPatrimonio analisis) {
    final hoja = excel['Recuperados'];
    _encabezadoBien(hoja);
    for (final r in analisis.renglones.where((r) => r.fueRecuperado)) {
      _filaBien(hoja, r);
    }
  }

  void _descuentos(Excel excel, AnalisisPatrimonio analisis) {
    final hoja = excel['Descuentos'];
    hoja.appendRow([
      TextCellValue('Folio'),
      TextCellValue('Ex empleado'),
      TextCellValue('Concepto'),
      TextCellValue('Resguardo'),
      TextCellValue('Importe'),
      TextCellValue('Cuotas'),
      TextCellValue('Aplicado'),
      TextCellValue('Pendiente'),
      TextCellValue('Estatus'),
    ]);
    // Sólo obligaciones vinculadas por FK a un renglón: nunca préstamos
    // personales ni otros descuentos del empleado.
    for (final r in analisis.renglones.where((r) => r.descuento != null)) {
      hoja.appendRow([
        TextCellValue(r.descuento!.folio),
        TextCellValue(r.empleadoNombre),
        TextCellValue(r.descuento!.descripcion ?? '—'),
        TextCellValue(r.bienDescripcion),
        DoubleCellValue(r.importeDescuento / 100),
        IntCellValue(r.cuotasDescuento),
        DoubleCellValue(r.aplicadoDescuento / 100),
        DoubleCellValue(r.saldoDescuento / 100),
        TextCellValue(r.descuento!.estatus),
      ]);
    }
  }

  void _servicios(Excel excel, AnalisisPatrimonio analisis) {
    final hoja = excel['Servicios'];
    hoja.appendRow([
      TextCellValue('Servicio'),
      TextCellValue('Bajas'),
      TextCellValue('Pendientes'),
      TextCellValue('Perdidos'),
      TextCellValue('Descuentos'),
      TextCellValue('Autorizadas'),
      TextCellValue('Sin cobro'),
    ]);
    // Incluye los renglones de dato no resoluble: si se omitieran, la
    // hoja dejaria de sumar lo mismo que el Resumen.
    for (final s in analisis.problemasPorServicio) {
      hoja.appendRow([
        TextCellValue(_servicioRankingLabel(s)),
        IntCellValue(s.bajas),
        IntCellValue(s.pendientes),
        IntCellValue(s.perdidos),
        DoubleCellValue(s.importeDescuentos / 100),
        IntCellValue(s.decisionesAutorizadas),
        IntCellValue(s.decisionesSinCobro),
      ]);
    }
  }

  void _autorizaciones(Excel excel, AnalisisPatrimonio analisis) {
    final hoja = excel['Autorizaciones'];
    hoja.appendRow([
      TextCellValue('Autorizador'),
      TextCellValue('Decisiones'),
      TextCellValue('Sin cobro'),
      TextCellValue('Valor involucrado'),
    ]);
    for (final a in analisis.autorizadores) {
      hoja.appendRow([
        TextCellValue(a.nombre),
        IntCellValue(a.decisiones),
        IntCellValue(a.decisionesSinCobro),
        DoubleCellValue(a.importeInvolucrado / 100),
      ]);
    }
  }

  void _vehiculos(Excel excel, AnalisisPatrimonio analisis) {
    final hoja = excel['Vehículos'];
    hoja.appendRow([
      TextCellValue('Ex empleado'),
      TextCellValue('Fecha de baja'),
      TextCellValue('Servicio (a la baja)'),
      TextCellValue('Vehículo'),
      TextCellValue('Resolución'),
      TextCellValue('Lugar de entrega'),
      TextCellValue('Combustible'),
      TextCellValue('Daños'),
      TextCellValue('Recibió'),
      TextCellValue('Descuento'),
    ]);
    for (final r in analisis.renglones.where((r) => r.tipo == TipoBienConciliado.vehiculo)) {
      hoja.appendRow([
        TextCellValue(r.empleadoNombre),
        TextCellValue(formatearFechaCortaXlsx(r.fechaBaja)),
        TextCellValue(_servicioLabel(r)),
        TextCellValue(r.bienDescripcion),
        TextCellValue(_resolucionLabel[r.resolucion.name] ?? r.resolucion.name),
        TextCellValue(r.renglon.lugarEntrega ?? '—'),
        TextCellValue(r.renglon.combustible ?? '—'),
        TextCellValue(r.renglon.danos ?? '—'),
        TextCellValue(r.receptorNombre ?? '—'),
        r.descuento == null ? TextCellValue('—') : DoubleCellValue(r.importeDescuento / 100),
      ]);
    }
  }
}

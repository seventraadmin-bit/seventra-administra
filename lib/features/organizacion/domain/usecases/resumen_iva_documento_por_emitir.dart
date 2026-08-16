/// Resumen derivado del tratamiento de IVA de un `DocumentoPorEmitir`
/// (Etapa 4I.1, Resolución C) — nunca se almacena: el tratamiento real
/// vive por línea, en `DocumentoPorEmitirLinea`. Este resumen solo sirve
/// para mostrar de un vistazo si el documento es homogéneo o mixto.
enum ResumenIvaDocumento { masIva, ivaIncluido, noAplica, mixto }

/// Calcula el resumen a partir de los `tratamientoIva` (valores de
/// `TratamientoIva.name`) de todas las líneas de un documento — `mixto`
/// en cuanto aparece más de un valor distinto, sin importar cuáles.
ResumenIvaDocumento calcularResumenIva(List<String> tratamientosIva) {
  final distintos = tratamientosIva.toSet();
  // Un documento sin líneas comerciales (servicio recién incorporado,
  // sin condición comercial vigente todavía) no tiene nada que gravar
  // — mismo criterio que `noAplica`, nunca un error.
  if (distintos.isEmpty) return ResumenIvaDocumento.noAplica;
  if (distintos.length > 1) return ResumenIvaDocumento.mixto;

  final unico = distintos.single;
  return switch (unico) {
    'masIva' => ResumenIvaDocumento.masIva,
    'ivaIncluido' => ResumenIvaDocumento.ivaIncluido,
    'noAplica' => ResumenIvaDocumento.noAplica,
    _ => throw ArgumentError('tratamientoIva desconocido: $unico'),
  };
}

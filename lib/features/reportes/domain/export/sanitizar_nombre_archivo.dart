const _acentos = {
  'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ñ': 'n', 'ü': 'u',
  'Á': 'a', 'É': 'e', 'Í': 'i', 'Ó': 'o', 'Ú': 'u', 'Ñ': 'n', 'Ü': 'u',
};

/// Genera un nombre de archivo seguro para un reporte exportado (Etapa
/// 12D): sin acentos, espacios ni caracteres fuera de
/// `[a-z0-9._-]`, con fecha/hora de generación para evitar
/// colisiones entre exportaciones sucesivas del mismo reporte.
String sanitizarNombreArchivo({required String base, required DateTime generadoEn, required String extension}) {
  var normalizado = base;
  for (final entrada in _acentos.entries) {
    normalizado = normalizado.replaceAll(entrada.key, entrada.value);
  }
  normalizado = normalizado
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');

  final marcaTiempo = '${generadoEn.year.toString().padLeft(4, '0')}'
      '${generadoEn.month.toString().padLeft(2, '0')}'
      '${generadoEn.day.toString().padLeft(2, '0')}'
      '-${generadoEn.hour.toString().padLeft(2, '0')}'
      '${generadoEn.minute.toString().padLeft(2, '0')}'
      '${generadoEn.second.toString().padLeft(2, '0')}';

  return '${normalizado}_$marcaTiempo.$extension';
}

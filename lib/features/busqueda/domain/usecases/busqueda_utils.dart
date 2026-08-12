const maximoResultadosPorGrupo = 5;

/// Coincidencia insensible a mayúsculas contra cualquiera de [campos]
/// — compartida por los 8 `Buscar*UseCase` (Etapa 14A) para no repetir
/// la misma comparación 8 veces. `null` en un campo simplemente no
/// participa (no revienta la búsqueda).
bool coincideBusqueda(String texto, List<String?> campos) {
  final termino = texto.toLowerCase();
  return campos.any((campo) => campo != null && campo.toLowerCase().contains(termino));
}

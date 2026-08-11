/// Acciones auditables del expediente de un teléfono físico (Etapa 9D,
/// punto 11) — persistidas como texto libre en
/// `EquipoTelefonicoEvento.tipoEvento` (mismo criterio que
/// `TipoEventoUsuario`: el enum vive en el dominio, la columna es
/// texto).
enum TipoEventoEquipoTelefonico {
  equipoConfigurado,
  correoActualizado,
  contrasenaActualizada,
  contrasenaRevelada,
  contrasenaCopiada,
}

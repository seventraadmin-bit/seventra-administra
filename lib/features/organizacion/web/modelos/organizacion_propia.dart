/// Una Organization donde esta persona tiene **membresía activa**.
///
/// Dos campos y ninguno más, a propósito: es todo lo que `GET /organizations`
/// entrega y todo lo que E3 necesita —decir dónde va a nacer la primera empresa—.
///
/// ⚠️ **NO TRAE EL ROL, y por eso no sabe si quien mira puede crear nada.** Eso se
/// resuelve con una lectura aparte por Organization —`GET
/// /organizations/{id}/membership`—, que es la única fuente de la autoridad. Guardar
/// aquí un `puedeCrear` invitaría a rellenarlo con una suposición el día que la lista
/// venga de otro sitio.
class OrganizacionPropia {
  const OrganizacionPropia({
    required this.organizationId,
    required this.nombre,
  });

  final String organizationId;
  final String nombre;
}

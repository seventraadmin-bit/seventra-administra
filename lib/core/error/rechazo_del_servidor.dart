import 'package:flutter/widgets.dart';

import '../design_system/design_system_web.dart';
import 'failure.dart';
import 'mensajes_humanos.dart';

/// El rechazo del servidor al guardar, al borrar o al desactivar, **mostrado donde se
/// lee**.
///
/// ## Por qué vive en `core/error/` y no en la pantalla que lo usa
///
/// Nació dentro de `eliminar_estructura.dart`, en Organización, porque las cuatro
/// pantallas de la estructura fueron las primeras que mutaban algo. Desde C1 lo
/// necesitan dos features, y con el archivo dentro de una la segunda sólo tenía dos
/// salidas: importar de la primera —«Comercial importa de Organización»— o escribir su
/// propia versión. La segunda es la mala de verdad: **la web no escuchaba el 402 en
/// ninguna de sus dieciséis mutaciones** hasta D-46 precisamente porque cada pantalla
/// mostraba lo que llegara, y una copia nueva reabriría ese hueco en el módulo nuevo.
///
/// ## Por qué no es un `errorText` de campo
///
/// Porque **no es un error de ningún campo**. «Tiene 3 puesto(s) registrado(s)» no se
/// arregla cambiando lo que está escrito en el formulario; se arregla en otra pantalla.
/// Ponerlo bajo el campo del código —que es donde acababa antes de M3, porque todo 409
/// se trataba como código duplicado— mandaba a la persona a cambiar un código que
/// estaba perfectamente bien.
///
/// ## Por qué el texto llega del servidor y no se reescribe
///
/// Porque el servidor es el único que sabe **el conteo**, y el conteo es lo que cambia
/// qué hace la persona: a un puesto lo mueve, a doscientos los deja y desactiva. Un
/// mensaje local tendría que decir «tiene puestos» sin número, que es la versión
/// inútil.
///
/// **No existe una constante con la lista de códigos**, y es deliberado: las pantallas
/// sólo necesitan distinguir `code_conflict` —que sí va a un campo— de todo lo demás.
/// Una lista de los otros sería una segunda fuente de verdad que habría que mantener al
/// día con el backend sin que nada lo exija.
///
/// ## Por qué recibe el FALLO y no un texto (D-46)
///
/// Porque hay un rechazo que el servidor **no** explica bien: el de autorización. «La
/// suscripción de la organización no permite la operación normal» es exacto y no le dice
/// a nadie qué hacer, y lo mismo pasa con un módulo apagado o un permiso que falta. Con
/// el fallo entero, [MensajesHumanos.deMutacion] decide en UN SITIO cuándo el texto del
/// servidor es el bueno —siempre que sea de negocio— y cuándo hay que traducirlo.
void mostrarRechazoDelServidor(BuildContext context, Failure fallo) =>
    RisegFeedback.showError(context, MensajesHumanos.deMutacion(fallo));

/// Cuántos caracteres admite un motivo. **Lo fija el servidor**, no la pantalla: su
/// `AuditPayload` lanza por encima de 512, y 500 deja margen.
///
/// Vale para **todos** los motivos y no sólo para el de eliminar: corregir un cliente,
/// cambiar su estatus y retirar una entidad fiscal pasan por el mismo `AuditPayload`.
const int motivoMaximo = 500;

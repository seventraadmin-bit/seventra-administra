# D-56 — el trabajo sin guardar no se tira por tres caminos

**Qué deuda paga:** **D-56**, etapa **C1**, y **C1 no cierra sin ella**. Nada de esto llega al
ensayo con el hueco abierto.

**Qué está mal hoy, en una frase.** Salir del formulario de Empresa *desde dentro* pregunta
—`_seguroDeSalir`—, pero con la dirección como estado **cambiarla ya no pasa por la pantalla**: el
botón «atrás» del navegador, recargar y cerrar la pestaña tiran lo escrito sin decir nada.

---

## 0. ✅ APROBADO POR EL DUEÑO EL 26 DE OCTUBRE DE 2026

Las tres decisiones quedaron así, y **dos vinieron con más de lo que pedí**:

| | Qué se decidió |
|---|---|
| **A** | **Una sola pregunta: `onExit` es el único dueño** y la pantalla deja de preguntar. Pero el mensaje **no queda genérico**: tiene que **nombrar qué tiene cambios** —«Tienes cambios sin guardar en el expediente de la sucursal Centro. ¿Salir sin guardar?»—, con los botones **«Seguir editando»** y **«Salir sin guardar»**. Así que **cada formulario registra su nombre** en el `GuardiaDeSalida` |
| **B** | **B2**: Empresa **y** el expediente de sucursal, con su detección de cambios y el cambio de empresa. Y una **regla permanente**: **toda pantalla con «Guardar» se registra en el guardia**, escrita en el diseño de pantallas y **con un candado** que falle si un formulario de guardado no se registra. Clientes, Servicios y lo que venga entran con eso **desde el primer día** |
| **C** | Una prueba del mecanismo —sucio frena, limpio no— y **las dos situaciones en pantalla**, que entran en **la lista de pruebas en pantalla del cierre de C1** |

### A.1 · Cómo se parte el mensaje entre el título y el cuerpo

`RisegDialog.showConfirmation` recibe **título y mensaje**, y el texto aprobado son dos frases.
Se reparten sin cambiar ninguna palabra, en vez de repetir el título dentro del cuerpo:

```
título   → ¿Salir sin guardar?
mensaje  → Tienes cambios sin guardar en el expediente de la sucursal Centro.
confirmar → Salir sin guardar        cancelar → Seguir editando
```

**Y la frase del medio la pone el formulario, no el diálogo** —«el expediente de la empresa», «el
expediente de la sucursal Centro»—, porque es lo único que el router no puede saber. Si un
formulario no la diera, o su cálculo fallara, la pregunta **sigue saliendo** con una frase
genérica: el nombre adorna, la pregunta protege.

### A.2 · ⚠️ Lo que la decisión A destapó: el guardia guardaba UNO solo

Con la regla permanente eso se rompe en el **primer** caso real: **un panel de alta abierto encima
de una pantalla**. Los dos están montados y los dos tienen algo que perder; con un solo hueco, el
panel sobrescribía a la pantalla y **al cerrarse la dejaba sin protección**, en silencio.

Así que `GuardiaDeSalida` **guarda todos los que estén montados**: `hayCambiosSinGuardar` es
«alguno», y `queSePierde` nombra **el de encima de los que tienen cambios** —el que la persona
está mirando—, saltándose los que están limpios: un panel abierto y vacío no es lo que se
perdería. Lo demás no cambia: `liberar` sigue exigiendo la misma función, por el mismo orden de
Flutter que ya estaba documentado.

---

## 0-bis. NECESITO TU DECISIÓN — los cuatro paneles modales

La regla permanente toca **seis** formularios, no dos, y **cuatro son hojas modales**
(`showModalBottomSheet`): el alta/edición de **área**, **puesto**, **sucursal** y **tipo de
sucursal**. No viven en una dirección, y eso cambia qué las protege:

| Camino | ¿Protegido con sólo registrarlas? |
|---|---|
| recargar · cerrar la pestaña | **sí**, `beforeunload` no mira direcciones |
| cambiar de empresa | **sí**, el portón pregunta igual |
| botón «atrás» | **pregunta bien**, pero al confirmar **la hoja se queda encima de la pantalla nueva**: una hoja abierta con `showModalBottomSheet` no vive en el historial del router, así que un cambio de dirección no se la lleva |

1. ✅ **(recomiendo)** Entran al guardia **y** se cierran cuando cambia la dirección — una pieza
   más con su prueba. La regla queda limpia hoy y el candado pasa.
2. Entran al guardia tal cual, y la hoja que queda encima se arregla aparte, **con deuda numerada**.
3. El candado exige el registro **sólo a los formularios que viven en una dirección** —Empresa, el
   expediente de sucursal, y los de Clientes que vienen— y los cuatro paneles quedan **con deuda
   numerada y etapa**.

**Mientras se decide, el trabajo no se detiene:** el mecanismo, Empresa y el expediente de
sucursal no dependen de esta respuesta, y van primero.

---

## 0-ter. Lo que se propuso, y que quedó aprobado con los cambios de arriba

### A · ¿Una pregunta o dos? (se propuso: una, con mensaje genérico)

Si `onExit` pregunta y la pantalla sigue preguntando, **cancelar el expediente preguntaría dos
veces**: la pantalla, y luego el router cuando la pantalla navegue. Hay que quitar una.

Propongo **quitar la de la pantalla** y dejar `onExit` como el único que pregunta por un cambio de
dirección. El costo está medido y es un mensaje menos preciso: hoy dice *«Si eliges administrar las
empresas se perderá lo que escribiste en el expediente»*, y `onExit` **no puede saber a dónde
vas** —go_router le entrega el estado de la ruta que se abandona, no la de destino—, así que el
texto queda en *«Si sales de aquí se perderá lo que escribiste en el expediente.»*

A cambio, la pregunta cubre **todos** los caminos con un solo sitio donde mirar: atrás, pestaña,
apartado, cancelar, cambiar de vista y un enlace pegado.

### B · ¿Hasta dónde llega el guardia? (se propuso: los dos formularios que ya existen)

⚠️ **Medido hoy: sólo `EmpresasWebScreen` se registra en el `GuardiaDeSalida`.** El **expediente de
una sucursal** es un formulario con «Guardar expediente» y **no tiene detección de cambios**:
`_compararCon` existe, pero compara **versiones del servidor** para el 409 de M3, no el formulario
contra lo cargado.

Así que hay dos alcances posibles:

| | Alcance | Qué cuesta | Qué queda fuera |
|---|---|---|---|
| **B1** | Sólo Empresa | el mecanismo, nada más | el expediente de sucursal sigue perdiendo lo escrito por los tres caminos, **y por el cambio de empresa también** |
| **B2** ✅ | Empresa **y** el expediente de sucursal | además, **escribir su detección de cambios** —comparar el formulario contra el expediente cargado, como ya hace Empresa— y registrarlo en el guardia | nada de lo que existe hoy |

**Recomiendo B2**, y la razón no es simetría: con B1 quedaría un guardia que **protege uno de los
dos formularios de la web y desde fuera no hay forma de saber cuál**. Eso es peor que no tenerlo,
porque enseña a confiar. Si decides B1, la parte de la sucursal **tiene que quedar como deuda con
número y etapa**, no como «ya veremos».

**Lo aprobado fue B2**, y con ella la regla permanente del §0. La parte de la sucursal entra en
esta misma deuda, no como «ya veremos».

### C · Recargar y cerrar la pestaña son **el mismo evento**, y no se pueden distinguir

Pediste una prueba por camino. Las dos últimas comparten mecanismo: el navegador manda
**`beforeunload`** y **no dice** si vas a recargar, a cerrar la pestaña o a navegar fuera. Desde
dentro de la página **no hay forma de saberlo**, y tampoco se puede poner texto propio: el
navegador enseña **su** diálogo genérico.

Tres opciones, y escojo la primera:

1. ✅ **Una prueba del mecanismo** —«con trabajo sin guardar se frena la salida; sin él, no»— y
   **las dos situaciones se comprueban en pantalla contigo**, recargando y cerrando la pestaña.
2. Dos pruebas con nombres distintos sobre el mismo código. Suman un nombre y cero cobertura: la
   segunda no puede fallar sin que falle la primera.
3. Dejarlo sólo para la prueba en pantalla. No, porque entonces nada en la suite recuerda que
   existe.

---

## 1. Lo que ya está verificado contra el código, y no supuesto

Cuatro cosas que decidí comprobar en la fuente antes de diseñar, porque las cuatro cambian el
diseño si salen al revés.

### 1.1 `onExit` SÍ se dispara con el botón «atrás» del navegador

El «atrás» de la web no es un `pop`: el navegador mueve su historial y la plataforma le dice a
Flutter la dirección nueva, que termina en `setNewRoutePath` del delegado. Y **ése es justamente
el sitio donde go_router consulta `onExit`**: compara los `RouteMatch` de antes con los de ahora,
toma los que salen y llama a su `onExit` **de dentro hacia fuera**; con un `false`, **no adopta la
configuración nueva** (`go_router-14.8.1/lib/src/delegate.dart:212-265`).

### 1.2 Si se cancela, la URL **vuelve** — y hay que decir a qué costo

Es lo que más me preocupaba: el navegador ya se movió cuando nos pregunta. Lo que pasa al cancelar,
siguiendo el código de Flutter (`widgets/router.dart`):

1. `setNewRoutePath` devuelve sin adoptar, así que `currentConfiguration` sigue siendo la de antes;
2. `Router` llama a `_rebuild()` **siempre**, pase lo que pase (`router.dart:782-794`);
3. `_rebuild` reporta la configuración **actual** con tipo `none`, y `none` decide
   `replace: _equals(_valueInEngine.uri, …)` (`router.dart:1536`). Tras un «atrás» lo que el motor
   tiene es la URL **anterior**, que no coincide, así que **`replace: false`**: el navegador
   **empuja** la dirección en la que te quedaste.

**Resultado:** la barra del navegador vuelve a decir la verdad. **El costo:** el historial se queda
con una entrada más, así que volver a pulsar «atrás» vuelve a preguntar. Es recuperable y es
honesto; lo contrario —una URL que miente— no lo sería. **Esto se comprueba en pantalla**, porque
una prueba de widgets no lleva el historial de un navegador de verdad.

### 1.3 Guardar **no** dispara una pregunta falsa

Me preocupaba que guardar navegara a la ficha y `onExit` preguntara «¿descartar?» justo después de
un guardado correcto. No pasa: el formulario hace `_volcarEnElFormulario(e)` y `_expediente = e`
**antes** de avisar al llamador (`empresa_web_screen.dart:453-467`), así que cuando llega la
navegación ya está limpio y `onExit` dice «sí» **sin diálogo y sin un frame de espera**
—`FutureOr<bool>` devuelto como `bool` se resuelve de forma síncrona (`delegate.dart:299-304`)—.

### 1.4 `onExit` en una `ShellRoute` **se ignora en silencio**

Es una trampa que conviene dejar escrita: `setNewRoutePath` recoge sólo los `RouteMatch` de
`GoRoute` y el recorrido descarta lo que no sea `GoRoute` (`delegate.dart:139`). Poner `onExit` en
la `ShellRoute` compilaría, no haría nada y no avisaría. **Tiene que ser un `GoRoute`.**

---

## 2. Quién pregunta, y por qué cada uno

Un solo sitio sabe si hay trabajo que perder —el **`GuardiaDeSalida`**, que ya existe— y **tres
caminos distintos preguntan**, porque los tres ocurren en capas distintas:

| Qué pasa | Quién pregunta | Por qué ahí |
|---|---|---|
| **cambia la dirección**: atrás, pestaña, apartado, cancelar, cambiar de vista, enlace pegado | **`onExit` del router** | es el único punto por el que pasan **todos** los cambios de dirección, vengan de la aplicación o del navegador |
| **cambiar de empresa** | el **portón**, como hoy | **no cambia la URL**: cambia el contexto. `onExit` no se enteraría |
| **recargar / cerrar la pestaña** | **`beforeunload`** del navegador | es lo único que el navegador consulta antes de tirar la página; ningún código de Dart corre después |

**El guardia no cambia.** Sigue siendo «quién tiene trabajo sin guardar ahora mismo», con su regla
de que **sin nadie registrado no hay cambios** y su `liberar` que exige la misma función —lo que
evita que una pantalla que se desmonta después borre el guardia de la que acaba de montarse—.

### Lo que esto NO es

**No es un estado sobre la pregunta.** No se guarda «ya pregunté» en ninguna parte, y es
deliberado: un `bool` así es exactamente la forma del defecto que D-39 vino a quitar —un dato
sobre dónde estuviste que se queda pegado cuando alguien olvida limpiarlo—. Cada camino pregunta
al guardia **en el momento**, y la respuesta sale del formulario que está montado.

---

## 3. El cambio en el router: partir la ruta única, y por la razón correcta

En `diseno-router-web.md` escribí que D-56 «pide partir la ruta única». **Eso era verdad a medias y
lo corrijo**: `matchedLocation` entra en la igualdad de `RouteMatch` (`match.dart:303-311`), así que
**la ruta comodín también dispararía `onExit`** — en **cada** cambio de dirección de toda la
aplicación.

Y por eso se parte igual, pero el motivo es otro: un `onExit` que se dispara en cada navegación y
tiene que decidir «¿esta importa?» es peor que uno **que sólo existe donde hay algo que perder**.

```dart
ShellRoute(
  builder: (_, _, _) => porton,
  routes: [
    GoRoute(path: '/', builder: (_, _) => const SizedBox.shrink()),

    // LAS RUTAS CON UN FORMULARIO DENTRO, Y SON LAS ÚNICAS CON `onExit`.
    // Van ANTES del comodín: go_router casa en orden.
    GoRoute(
      path: '/organizacion/empresa/editar',
      builder: (_, _) => const SizedBox.shrink(),
      onExit: (context, _) => seguroDeSalir(context, guardia),
    ),
    GoRoute(
      path: '/organizacion/sucursales/:id/expediente',   // ← sólo con B2
      builder: (_, _) => const SizedBox.shrink(),
      onExit: (context, _) => seguroDeSalir(context, guardia),
    ),

    GoRoute(path: '/:resto(.*)', builder: (_, _) => const SizedBox.shrink()),
  ],
)
```

**La `ShellRoute` se queda y su builder sigue ignorando el `child`**: es lo que conserva el `State`
del portón —la caché de logotipos, la autoridad ya leída, el «ya pedí la empresa» y el oyente del
ciclo de vida—, y costó un fallo medido descubrirlo.

**Y la regla que esto deja escrita:** **cada formulario nuevo añade su ruta con `onExit`**. Las
pantallas de Clientes de C1 traen formularios, así que traen las suyas. No es una lista que alguien
tenga que recordar actualizar: una ruta sin `onExit` **no pregunta**, y eso se ve en su prueba.

### La decisión que sale de la dirección, aparte y pura

```dart
/// Qué se perdería, dicho para la pregunta. **La frase genérica es el respaldo**, no el
/// caso normal: un formulario que no dé su nombre —o cuyo nombre falle— no puede
/// tragarse la pregunta.
String _loQueSePierde(GuardiaDeSalida guardia) =>
    guardia.queSePierde ?? 'este formulario';

/// ¿Hay que preguntar antes de salir de aquí?
Future<bool> seguroDeSalir(BuildContext context, GuardiaDeSalida guardia) async {
  if (!guardia.hayCambiosSinGuardar) return true;   // el caso frecuente, sin diálogo

  final confirmado = await RisegDialog.showConfirmation(
    context: context,
    title: '¿Salir sin guardar?',
    message: 'Tienes cambios sin guardar en ${_loQueSePierde(guardia)}.',
    confirmLabel: 'Salir sin guardar',
    cancelLabel: 'Seguir editando',
  );

  return confirmado ?? false;   // cerrar el diálogo con Esc es «no salgo»
}
```

### Y el guardia tiene que llegar al router

Hoy el `GuardiaDeSalida` **nace dentro del portón**, y el router lo necesita — pero el router es
quien construye el portón. Se rompe el círculo donde ya vive la composición: **lo crea
`main_web.dart`** y se lo pasa a los dos, igual que los siete repositorios. Un campo más en
`PortonWeb` y un argumento más en `construirRouterWeb`.

---

## 4. `beforeunload`: la parte que no se puede probar y la que sí

Se sigue **el patrón que ya existe** en este repositorio para el candado entre pestañas: la
implementación con `dart:js_interop` en un archivo `_web.dart`, un `_io.dart` que no hace nada, y
una importación condicional. Windows compila igual, y la suite —que corre en la VM— se queda con el
`_io`.

```
lib/core/company/aviso_de_salida_web.dart   ← addEventListener('beforeunload', …)
lib/core/company/aviso_de_salida_io.dart    ← en el escritorio no hay pestaña que cerrar
```

**La decisión se saca del archivo con interop**, para que la suite la alcance:

```dart
/// ¿Debe el navegador frenar la salida? Es lo único que decide, y es puro.
bool hayQueFrenarLaSalida(GuardiaDeSalida guardia) => guardia.hayCambiosSinGuardar;
```

El archivo `_web.dart` sólo cablea: si devuelve `true`, `preventDefault()` y `returnValue = ''`.

**Tres cosas que el navegador manda y no se negocian:**

- **El texto es suyo**, genérico, y no se puede cambiar. Nuestro mensaje no aparece.
- **Hace falta que la persona haya interactuado** con la página para que el diálogo salga. Quien
  escribió en un formulario cumple, así que en nuestro caso se da siempre.
- **No es cancelable por nosotros**: si dice «salir», la página se va y no corre nada más.

**Quién lo registra:** el portón, en `initState`, con `() => _guardia.hayCambiosSinGuardar`, y lo
suelta en `dispose`. Mismo dueño que el guardia, un solo sitio.

---

## 5. Las pruebas

| | Qué afirma | Cómo, y por qué así |
|---|---|---|
| 1 | **Atrás con trabajo sin guardar pregunta** | `tester.binding.handlePushRoute('/organizacion/empresa')` estando en `…/editar`. Es **el mismo canal que usa el navegador** al moverse —la plataforma avisa de la dirección nueva—, así que prueba nuestra capa de verdad y no un `go` disfrazado |
| 2 | **Cancelar deja la dirección donde estaba** | tras el diálogo, `router.state.uri.path` sigue en `…/editar`. Es el corazón del asunto: sin esto, cancelar perdería el trabajo igual |
| 3 | **Confirmar sale** | el contrapunto, y no sobra: un `onExit` que devolviera siempre `false` pasaría la prueba 2 y dejaría la aplicación **encerrada en el formulario** |
| 4 | **Sin trabajo sin guardar no hay diálogo** | el caso frecuente. Una pregunta que sale siempre se contesta sin leerla |
| 5 | **Una ruta sin formulario no pregunta** | moverse entre pestañas con el guardia sucio **no** pregunta si no se sale del formulario: es lo que fija que `onExit` está sólo donde debe |
| 6 | **`hayQueFrenarLaSalida` con el guardia sucio y limpio** | la decisión de `beforeunload`, en la VM. Lo que no se puede probar —el diálogo del navegador— se comprueba **en pantalla contigo**, recargando y cerrando la pestaña |
| 7 | **Guardar no pregunta** | §1.3 dice que no debería; una prueba lo sostiene, porque una pregunta falsa después de guardar bien parecería un error de guardado |
| 8 | **La pregunta NOMBRA lo que tiene cambios** | «…en el expediente de la sucursal Centro», con el nombre saliendo de la fila cargada. Y su contrapunto: sin nombre, la pregunta **sigue saliendo** con la frase genérica |
| 9 | **El candado de la regla permanente** | un formulario de guardado que no se registra en el guardia **pone la suite roja**. Es lo que hace que Clientes y Servicios entren con esto desde el primer día, en vez de depender de que alguien se acuerde |

**Y lo que NO se prueba en la suite, dicho aquí para que no se confunda con cobertura:** la entrada
de más en el historial al cancelar un «atrás» (§1.2) y el diálogo del navegador. Las dos son del
navegador, y las dos van a la **verificación en pantalla** del cierre de C1, que no se automatiza
ni se fabrica:

- **recargar** con el expediente a medio escribir avisa, y «cancelar» deja lo escrito intacto;
- **cerrar la pestaña** con el expediente a medio escribir avisa;
- **«atrás»** con el expediente a medio escribir pregunta, y al cancelar **la barra del navegador
  vuelve a decir la dirección correcta**.

### El candado, y cómo está escrito para no fijarse a una lista

La regla es **de propiedad y no de censo**: por cada archivo de `lib/features/*/web/` que ofrezca
un botón de guardado, se exige que **participe del guardia** —que llame a `registrar`, o que
exponga la pregunta hacia arriba como ya hace `alVigilarCambios`—. No hay lista de archivos
permitidos ni un total que cuadrar, porque **una prueba fijada a una lista exacta se rompió once
veces en este proyecto**: lo que se afirma es que ninguno se queda fuera, y eso sigue siendo cierto
cuando Clientes añada los suyos.

---

## 6. Lo que toca, y en qué commit

**Cada uno es un tema y cada uno sale verde**, en este orden:

| | Commit | Qué entra |
|---|---|---|
| **A** | el guardia con varios registrados y el nombre | `guardia_de_salida.dart` y su prueba, más la llamada de Empresa. **Va primero porque todo lo demás se apoya en él**, y porque es donde vivía el defecto del anidamiento (§0 A.2) |
| **B** | el mecanismo | `main_web.dart` dueño del guardia · `porton_web.dart` lo recibe y cablea `beforeunload` · `router_web.dart` con las rutas de formulario, su `onExit` y `seguroDeSalir` · `aviso_de_salida_web.dart` / `_io.dart` · `empresas_web_screen.dart` deja de preguntar · pruebas 1–8 · mover la prueba de «pasar a Administración editando» al nivel del router · una línea en `primera_empresa_test.dart` |
| **C** | el expediente de sucursal | su detección de cambios —comparando el formulario contra lo cargado, como ya hace Empresa— y su registro con el nombre de la sucursal |
| **D** | los cuatro paneles y el candado | prueba 9 y la regla permanente. **Pendiente de la decisión del §0-bis** |
| **E** | documentación | la regla permanente en `diseno-pantallas-clientes.md`, D-56 en `deudas-conocidas.md`, y las tres comprobaciones en pantalla en la checklist de cierre de C1 |

# Diseño de E1 de Empresa — el logotipo, y el transporte de archivos que lo hace posible

> **Estado: PROPUESTA, sin programar.** Escrito el 21 de octubre de 2026 para aprobación
> previa, según el método: diseño → aprobación → implementación → revisión → cierre.

---

## 0 · NECESITO TU DECISIÓN

**Dos preguntas, y las dos cambian el tamaño de E1.** El resto del documento asume la
respuesta que propongo, para que puedas corregirla en una línea en vez de rehacerlo.

### Pregunta 1 — ¿E1 es el logotipo?

«E1 de Empresa» no está escrito en ningún documento, así que lo deduje del **hueco real**
entre lo que la pestaña Empresa tiene en el escritorio y lo que tiene en la web (§1). Lo
que falta son tres cosas, y propongo este reparto:

| | Qué | Por qué en ese orden |
|---|---|---|
| **E1** | **El logotipo** | Es lo único que necesita **transporte de archivos**, y ese transporte lo heredan Personal, Clientes y Contratos. Desbloquea más que ninguna otra pieza de Empresa |
| **E2** | La tarjeta fiscal en PDF | Necesita decidir cómo se entrega un PDF en el navegador, que es un problema distinto y aislado |
| **E3** | El nombre comercial editable | Hoy no se edita en la web, y hay que decidir **dónde** se edita (pregunta 2) |

**Si tu E1 era otra cosa, dime cuál y lo reescribo.** Lo que no cambia es el §2: el
servidor del logotipo ya está hecho.

### Pregunta 2 — El nombre comercial, ¿se edita en Administra o sólo en Console?

En el escritorio el nombre comercial **es un campo del expediente**, junto a la razón
social. En la web, la pantalla dice literalmente «el nombre comercial se cambia en otro
sitio»… y ese otro sitio **no existe en Administra**: el nombre viene de la Company, que
se da de alta desde Console.

Así que hoy un cliente **no puede corregir su propio nombre comercial**, y eso es una
función del escritorio que se perdió sin que nadie lo decidiera. Las tres salidas:

- **(a)** se edita en Administra, en el expediente, como en el escritorio;
- **(b)** no se edita nunca: lo cambia SEVENTRA desde Console a pedido;
- **(c)** se edita en Administra pero **exige el rol Maestro**, por ser la identidad de
  la empresa.

**No lo decido yo**: es de producto, y el nombre comercial sale impreso en documentos.
No bloquea E1 —el logotipo no lo toca— así que si prefieres, contéstala cuando llegue E3.

---

## 1 · El hueco real, medido contra el escritorio

Lo que la pestaña Empresa tiene en cada lado. No es una lista de deseos: sale de leer
`empresa_expediente_screen.dart` y sus widgets, y `empresa_web_screen.dart`.

| Renglón del escritorio | Dónde vive allá | En la web hoy |
|---|---|---|
| Razón social, RFC, representante legal, eslogan | `datos_generales_section.dart` | ✅ Hecho |
| Domicilio fiscal | `direccion_fiscal_section.dart` | ✅ Hecho |
| Teléfono, correo, sitio | `medios_contacto_section.dart` | ✅ Hecho |
| **Régimen fiscal del catálogo del SAT** | 🚫 no existe: era texto libre | ✅ Hecho, y **mejora** sobre el escritorio |
| **Logotipo**: subir, reemplazar, quitar, vista previa | `logo_empresa_dialog.dart` | ❌ **No existe** |
| **El logotipo en el encabezado** de la ficha | `ficha_corporativa_header.dart` | ❌ No existe |
| **Tarjeta fiscal en PDF** | `tarjeta_fiscal_dialog.dart` | 🟡 El servidor ya dice si **se puede** generar (`fiscalCardReady`) y la pantalla lo avisa; **generarla, no** |
| **Nombre comercial editable** | `datos_generales_section.dart` | ❌ Se muestra, no se edita (pregunta 2) |

> **Y una función del escritorio que NO se trae, ya decidida:** el **código humano de la
> empresa**. Decisión del dueño del 19 de octubre; en la nube la identidad es el
> `company_id`. No se reinterpreta.

---

## 2 · Lo que el servidor YA tiene — **E1 no lleva backend**

**Esto es lo que hace de E1 una buena primera etapa: cero migraciones, cero rutas
nuevas.** Todo está desde la 0010 (etapa 5D.8) y se puede comprobar hoy.

### El uso del archivo, sembrado y único

```sql
-- 0010_file_foundation.sql
INSERT INTO app.platform_file_purpose
  (code, description, allowed_content_types, max_bytes, singleton)
VALUES
  ('company.logo', '…', ARRAY['image/png', 'image/jpeg'], 5242880, true);
```

**`company.logo` es el ÚNICO uso real sembrado**, con el comentario que explica por qué:
«no se siembran purposes de dominios que todavía no existen: una fila de catálogo sin
consumidor es una promesa que nadie verifica». E1 es ese consumidor.

| Política | Valor | De dónde sale |
|---|---|---|
| Tipos admitidos | `image/png`, `image/jpeg` | la fila del catálogo |
| Tamaño máximo | **5 MiB** | la fila del catálogo |
| ¿Uno solo? | **sí**, `singleton` — uno **por RECURSO** | la fila del catálogo |
| Tope duro de la petición | **32 MiB** | `CompanySettingsEndpoints.TopeDuroDeSubida` |

**Y las dos cosas del modelo que la pantalla tiene que respetar sin reinterpretar:**
«el slot es tabla, `ready` **no** es seleccionado», y **sólo desvincular libera
capacidad**. Es decir: quitar el logotipo **libera en el acto** la capacidad contractual,
aunque el archivo siga guardado hasta la purga. El mensaje de la pantalla no puede decir
«se borró»: dice que se quitó y que la capacidad se liberó.

### Las tres rutas, con su contrato

| Verbo | Ruta | Cuerpo | Respuesta |
|---|---|---|---|
| `POST` | `/companies/{id}/logo` | **`multipart/form-data`**, campo `file` | **201** con `LogoResponse` |
| `GET` | `/companies/{id}/logo` | — | **200** con los **bytes** del archivo |
| `DELETE` | `/companies/{id}/logo` | — | **204** la primera vez, **404** la segunda |
| `GET` | `/companies/{id}/storage` | — | **200** con uso y capacidad |

```
LogoResponse: fileId · contentType · sizeBytes · sha256 · originalFileName · uploadedAt
StorageResponse: contractualUsedBytes · reservedBytes · capacityBytes · availableBytes
```

**El `POST` es una llamada y tres pasos internos**, y su garantía está escrita en la
ruta: «el logotipo anterior sigue vigente hasta que el nuevo está validado, así que un
fallo nunca deja a la Company sin logotipo». La pantalla **no tiene que compensar nada**:
no hay que quitar antes de subir.

**El `DELETE` contesta 404 la segunda vez a propósito** —«el recurso logotipo deja de
existir, y decirlo es más útil que fingir que se borró algo»—. La pantalla lo trata como
éxito silencioso si ya no había logotipo: no es un error que la persona pueda arreglar.

### Los errores, cada uno con su salida en pantalla

| Código | HTTP | Qué pasó | Qué ofrece la pantalla |
|---|---|---|---|
| `content_type_rejected` | 415 | no es PNG ni JPEG | «Elige un PNG o un JPEG» y vuelve al selector |
| `content_mismatch` | 422 | **se llama `.png` y no lo es** | lo mismo, con el motivo dicho: el archivo no es lo que su nombre dice |
| `file_too_large` | 413 | pasa de 5 MiB *(o de 32 MiB, el tope duro)* | el tamaño máximo, en MB |
| `storage_capacity_exceeded` | 409 | **la Organization se quedó sin capacidad** | **las dos cifras** y «habla con SEVENTRA»: no hay autoservicio |
| `subscription_restricted` | 402 | suscripción `restricted` | sólo lectura: el botón de subir no se ofrece |
| `logo_missing` | 404 | no hay logotipo | **no es un error**: es el estado «sin logotipo» |
| `permission_missing` | 403 | falta `company.settings.manage` | no debería verse: los botones no se ofrecen |

⚠️ **La capacidad es de la ORGANIZATION, no de la Company.** El mensaje no puede decir
«tu empresa se quedó sin espacio»: en una Organization con varias empresas, la que se
quedó sin espacio es la organización entera. El texto lo dirá así.

---

## 3 · Lo que falta en la WEB, y es infraestructura: **IF-5**

**Aquí está el trabajo de E1, y no es la pantalla.** El cliente HTTP de la web **no sabe
de binarios**, y eso no es un descuido: está anotado desde que se escribió.

```dart
// api_client.dart, hoy
/// … trabajar con `BaseRequest` deja la puerta abierta a `MultipartRequest` y a
/// `Client.send` con respuesta en flujo cuando IF-5 traiga los archivos.
```

Dos huecos, los dos medidos leyendo el código:

**1 · La respuesta sólo lleva texto.** `ApiRespuesta` tiene `final String cuerpo` y nada
más. Un PNG decodificado como cadena **se corrompe**: no es que se vea mal, es que los
bytes ya no son los que llegaron.

**2 · No hay `multipart`.** Los cinco verbos mandan JSON. El `POST` del logotipo exige
`multipart/form-data` con un campo `file`.

### Lo que propongo construir, una sola vez

| Pieza | Qué | Por qué así |
|---|---|---|
| `ApiRespuesta.bytes` | Los bytes crudos, **nulos salvo que se pidan** | Guardarlos siempre duplicaría en memoria cada respuesta JSON del producto |
| `ApiClient.getBytes(ruta)` | Un `GET` que conserva los bytes | Es el camino de **toda** descarga futura: foto de empleado, documento de contrato |
| `ApiClient.postMultipart(ruta, campo, nombre, bytes, tipo)` | La subida | Un `MultipartRequest` sobre el mismo camino único de `_enviar`, para que el trato de errores siga existiendo **una sola vez** |

⚠️ **Y la trampa que hay que resolver en el diseño, no al programar.**
`ApiClientAutenticado` **reintenta la petición** cuando el token caducó: pide uno nuevo y
vuelve a mandarla. Un `http.MultipartRequest` **no se puede reenviar** —su cuerpo es un
flujo que ya se consumió— así que el reintento mandaría un cuerpo vacío y el servidor
contestaría «no llegó ningún archivo» por un problema de token.

**La salida: los bytes se guardan en memoria y la petición se CONSTRUYE de nuevo en cada
intento.** Caben: el máximo del uso son 5 MiB y el tope duro 32 MiB, y en la web el
archivo ya viene entero en memoria de todas formas (§4). Lo que no se puede hacer es
reenviar el mismo objeto.

> **Esto es lo que convierte E1 en una etapa con diseño previo y no en una pantalla
> más.** El transporte lo heredan: los documentos de Personal, la foto del empleado, el
> logotipo del cliente —`ClientFileEndpoints` ya existe en el servidor— y los documentos
> de contrato. Hacerlo mal una vez se paga cuatro veces.

---

## 4 · La pantalla

### Dónde vive el logotipo

**En el encabezado del expediente de la empresa**, como en el escritorio
(`ficha_corporativa_header.dart`), y **no en un apartado propio**. La razón es la del
escritorio, literal: «es el mismo problema y no merece una pantalla propia: cabe dentro
del expediente».

```
┌─────────────────────────────────────────────────────────────┐
│  ┌────────┐   RISEG                                          │
│  │ logo   │   Seguridad Privada RISEG S.A. de C.V.           │
│  │ 96×96  │   SPR950101AB1                                   │
│  └────────┘   [ Cambiar logotipo ]  [ Quitar ]               │
└─────────────────────────────────────────────────────────────┘
```

### Los cuatro estados, y ninguno es un hueco

| Estado | Qué se ve |
|---|---|
| **Cargando** | el sitio del logotipo con un indicador, no un salto de maquetación |
| **Con logotipo** | la imagen, con «Cambiar logotipo» y «Quitar» |
| **Sin logotipo** (404 `logo_missing`) | **presentación tipográfica**: las iniciales de la empresa en su sitio, y «Subir logotipo». **No es un error y no se dice como tal** |
| **No se pudo cargar** | el sitio tipográfico **y** un aviso discreto con «volver a intentar». Distinto de «no hay»: confundirlos haría pensar que el logotipo se perdió |

### El selector, y la trampa de la web

```dart
// LO QUE EL ESCRITORIO HACE Y LA WEB NO PUEDE COPIAR
final seleccion = await FilePicker.platform.pickFiles(...);
widget.seleccionada.value = archivo!.path;   // ⚠️ en WEB `path` es SIEMPRE null
```

En el navegador no hay sistema de archivos: `file_picker` devuelve **`bytes`** y `path`
nulo. Así que el código del escritorio **no se reutiliza**, y hay que pedir
`withData: true` explícitamente o `bytes` también llega nulo.

**La validación del cliente es un AVISO TEMPRANO, nunca la garantía.** Se comprueban las
mismas dos cosas que el servidor —tipo por los **primeros bytes** y tamaño— por la razón
que el escritorio ya tiene escrita: «un archivo puede llamarse `.png` sin serlo».

⚠️ **Y la parte reutilizable hay que SEPARARLA primero.** `LogoEmpresaValidacion.tipoReal`
es lógica pura sobre un `Uint8List` —sirve tal cual— pero su archivo **importa
`dart:io`** para otra función que vive al lado, `revisarLogo(String rutaArchivo)`, que
abre un `File`. Un solo `import` de ese archivo **rompe la build web**, y lo rompe sin
que nada en la pantalla parezca estar mal: es exactamente el problema que obligó a crear
`design_system_web.dart`.

Así que E1 empieza **moviendo `tipoReal` y las dos constantes a un archivo sin
`dart:io`**, que los dos productos importan. El escritorio no cambia de comportamiento;
sólo deja de ser el dueño de la pieza.

Quien decide sigue siendo el servidor: si el cliente acepta algo que el servidor rechaza,
se muestra el motivo del servidor.

### Vista previa antes de subir

**Se conserva del escritorio.** Se elige el archivo, se ve cómo quedará, y **entonces**
se confirma. Subir en cuanto se elige quitaría el único momento en que la persona puede
darse cuenta de que escogió el archivo equivocado.

### Dos trampas más de la pantalla

**1 · La imagen vieja se queda pegada.** `Image.memory` con los mismos bytes en memoria y
un widget sin `key` **no se repinta** al reemplazar el logotipo: se ve el anterior y
parece que no se guardó. La `key` sale del `fileId` o del `sha256` que devuelve
`LogoResponse` —no de un contador— porque es lo único que cambia cuando el archivo cambia
de verdad.

**2 · `Image.network` NO sirve, y conviene decirlo antes de que alguien lo intente.** Dos
razones independientes: el `Authorization: Bearer` **no viaja** en la petición que hace
`<img>`, y la ruta contesta con `Content-Disposition: attachment` a propósito —«nada
inline»—. El logotipo se descarga con el cliente autenticado y se pinta con
`Image.memory`.

---

## 5 · El mapa de permisos por acción

Según el método, el inventario de cada módulo incluye su mapa de permisos **antes** de
programar. Éste sale de leer las rutas, no de suponerlas:

| Acción | Permiso | Nota |
|---|---|---|
| **Ver** el logotipo | **acceso a la Company**, sin permiso propio | «es su identidad visual, no un dato reservado, y inventar un permiso para mirarlo habría sido ruido» |
| **Subir / reemplazar** | `company.settings.manage` | |
| **Quitar** | `company.settings.manage` | |
| **Ver uso de almacenamiento** | `company.settings.manage` | la ruta lo exige aunque sea una lectura |

**En pantalla se aplica la regla de siempre**, en la misma forma que acabamos de cerrar en
el expediente de la sucursal: quien no puede administrar **ve el logotipo** y no ve los
botones; si además es `restricted`, tampoco. **Ningún permiso nuevo**, ninguna migración.

---

## 6 · Lo que NO entra en E1

Dicho para que no se cuele por simetría:

- **La tarjeta fiscal en PDF** → E2. Es otro problema: generar o recibir un PDF y
  entregarlo en el navegador.
- **El nombre comercial editable** → E3, y depende de la pregunta 2.
- **El logotipo en los documentos** —recibos, tarjeta fiscal—: no hay documentos en la
  web todavía.
- **La bóveda y el respaldo**: fuera de la v1, ya decidido.
- **Las plantillas de documentos por empresa**: pendiente a la espera de un cliente que
  lo pida, ya anotado.
- **Un apartado de «Archivos»**: no existe `/files/{id}` ni URL firmadas a propósito —«la
  autorización sale del recurso de dominio»—. El logotipo se administra desde la empresa
  y nada más.

---

## 7 · Las pruebas que lo fijarían

**Del transporte (IF-5), que es lo que más se reutiliza:**

1. `getBytes` devuelve los bytes **intactos** —se compara un PNG byte a byte, no su
   longitud— y una petición normal **sigue sin guardarlos**.
2. `postMultipart` manda `multipart/form-data` con el campo **`file`**, el nombre y el
   tipo declarados.
3. **El reintento por token caducado vuelve a mandar el cuerpo COMPLETO.** Es la trampa
   del §3: la prueba cuenta los bytes del segundo intento y falla si llegan cero.

**De la pantalla:**

4. Sin logotipo (404) → presentación tipográfica, **sin mensaje de error**, con «Subir».
5. Con logotipo → la imagen, y **cambia** cuando se reemplaza (la trampa de la `key`).
6. Un fallo de red al descargar → aviso con «volver a intentar», **distinto** de «no
   hay».
7. Sin `company.settings.manage` → se ve el logotipo, **no** los botones.
8. Un archivo que no es imagen → se rechaza **antes de subir**, por su firma.
9. El 409 de capacidad → se muestran **las dos cifras** y el texto habla de la
   **organización**, no de la empresa.
10. Quitar → confirmación primero, y el resultado dice que **se liberó capacidad**, no
    que se borró.

---

## 8 · Lo que cuesta, para que decidas con el número delante

| Parte | Tamaño |
|---|---|
| IF-5: bytes y multipart en el cliente, con su reintento | **el grueso** — es infraestructura y se hace una vez |
| La pieza del logotipo en el encabezado | mediano |
| Validación por firma | **ya está escrita**, pero hay que separarla de su `dart:io` antes de poder importarla (§4) |
| Backend | **nada** |
| Migración | **ninguna** |

**Nada de E1 toca el servidor**, así que no hay despliegue ni esquema nuevo: se puede
construir y probar contra la API que ya está en `dev`.

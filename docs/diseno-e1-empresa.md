# Diseño de E1 de Empresa — lista, ficha y editar

> **Estado: PROPUESTA, sin programar.** Reescrito el 21 de octubre de 2026 sobre la
> definición del dueño del 19 de octubre. Sustituye a `diseno-e1-empresa-logotipo.md`,
> que describía E1 como «el logotipo» por haberlo deducido mal.

---

## 0 · Antes de nada: la definición de E1 y E2 **no estaba escrita**

Busqué «E1» y «E2» en `docs/requisitos-nuevos-del-dueno.md`, en `docs/mudanza-a-la-nube.md`,
en el inventario de Organización y en los seis commits del 19 de octubre. **No aparecen en
ningún archivo del repositorio.** Lo que sí quedó escrito ese día son los dos expedientes,
el catálogo del SAT y la atomicidad del expediente de sucursal.

Así que el reparto vivía sólo en la conversación, y por eso lo deduje mal: propuse
«E1 = el logotipo» cuando E1 es el **rediseño de Empresa** y el logotipo es una parte.

**Es justo el riesgo que `requisitos-nuevos-del-dueno.md` existe para evitar** —«un
requisito nuevo no se nota contra nada»—, aplicado a un plan de etapas en vez de a un
requisito. Este documento lo arregla para E1 y E2, y queda el apunte: **un reparto de
etapas se anota el día que se decide**, igual que un requisito.

### Lo que E1 es, según tu definición

1. **Lista de empresas.**
2. **Ficha tipo tarjeta fiscal.**
3. **Editar**, con el logotipo, que **cierra al guardar y vuelve a la ficha**.
4. **Nombre comercial editable** en el expediente — opción (a) —, con
   `company.settings.manage` y **auditado**. Va en E1 porque es la misma pantalla.
5. El transporte de archivos (**IF-5**) y el logotipo, de la investigación anterior.

### Lo que E2 es, y no se mezcla

**Crear, desactivar, reactivar y eliminar empresas**, respetando la capacidad del plan
**incluyendo los adicionales**, con **permiso nuevo y migración**. El §7 trae lo que medí
del servidor para E2 —incluida **una trampa que hay que resolver en su diseño**— porque
lo encontré mirando E1 y perderlo costaría caro.

---

## 1 · Lo que hay hoy, y los dos hechos que cambian el diseño

### La pantalla de hoy

`empresa_web_screen.dart` **es un formulario, siempre abierto**: identidad fiscal,
domicilio, contacto, y «Guardar expediente» al final. No hay lista, no hay ficha, no hay
logotipo, y el nombre comercial se muestra sin poder editarse.

### Hecho 1 · La lista ya existe en el servidor, y **sólo trae activas**

`GET /companies` → «Companies que la Identity puede abrir, de todas sus Organizations».
Devuelve `AccessibleCompany(companyId, organizationId, companyName, organizationName,
role)`, y su consulta es ésta:

```sql
WHERE a.identity_id = @identity_id
  AND a.status = 'activa' AND c.status = 'activa' AND o.status = 'activa'
ORDER BY o.name, c.name
```

**Dos consecuencias que el diseño no puede ignorar:**

- **La lista de E1 no necesita `status`:** por construcción, toda fila está activa. Una
  columna «Activa» que siempre dijera lo mismo invitaría a ramificar sobre nada.
- La web **ya consume esta ruta** para el selector de empresa (`CompanyDisponible`), así
  que el modelo ya está escrito. E1 **no añade repositorio ni ruta** para la lista.

### Hecho 2 · El nombre comercial **no se puede cambiar hoy por ninguna ruta**

Busqué un `UPDATE app.company SET name`: **no existe**. `POST /organizations/{id}/companies`
crea, y nada renombra. Así que la opción (a) —editable en el expediente— **sí lleva
backend**, aunque sea pequeño.

**Y hay precedente de dos días atrás:** el nombre y el tipo de una sucursal se mudaron al
`PUT` de su expediente, en una transacción con el domicilio y el horario. Propongo lo
mismo: **`name` entra en el `PUT /companies/{id}/profile`**, que ya bloquea la fila, ya
tiene candado optimista, ya reúne todos los errores antes de fallar y ya audita.

| | |
|---|---|
| Migración | **ninguna**: `app.company.name` existe, `NOT NULL`, desde la 0004 |
| Permiso | `company.settings.manage`, el que ya exige ese `PUT`. **Ninguno nuevo** |
| Auditoría | `name` se añade al payload de `company_profile`, que ya se escribe en la misma transacción |

⚠️ **Y la auditoría lo exigirá sola:** `AuditPayloadVocabularyTests` falla si una clave
auditada no tiene etiqueta en español. `name` ya la tiene —se audita en áreas, puestos y
sucursales— así que no hay que añadir nada; lo que no se puede es escribir la clave con
otro nombre.

---

## 2 · El recorrido completo

```
            ┌──────────────────┐
            │ LISTA de empresas│   GET /companies   (ya existe)
            └────────┬─────────┘
                     │ tocar una fila
                     ▼
            ┌──────────────────┐
            │ FICHA            │   GET …/profile · GET …/logo
            │ tipo tarjeta     │
            │ fiscal           │
            └────────┬─────────┘
                     │ «Editar»          (sólo con company.settings.manage)
                     ▼
            ┌──────────────────┐
            │ EDITAR           │   PUT …/profile · POST/DELETE …/logo
            │ el formulario    │
            └────────┬─────────┘
                     │ Guardar → cierra
                     ▼
                  la FICHA, con lo guardado
```

**Con una sola empresa la lista no se pinta y se abre su ficha directamente.** Es la misma
regla que ya aplica la barra de pestañas —«un rótulo que no lleva a ninguna parte ocupa
espacio y no dice nada»— y el caso frecuente: la mayoría de los clientes tendrán una.

---

## 3 · La lista

```
┌─────────────────────────────────────────────────────────────────────────┐
│  Empresas                                                               │
│  Las empresas que puedes abrir. Toca una para ver su ficha.             │
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────────┐ │
│  │  RISEG                                            ⟨Maestro⟩     ›  │ │
│  │  Seguridad Privada RISEG · Organización RISEG                      │ │
│  ├────────────────────────────────────────────────────────────────────┤ │
│  │  RISEG Servicios                                  ⟨Usuario⟩     ›  │ │
│  │  Organización RISEG                                                │ │
│  └────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────┘
```

**Qué lleva cada fila, y de dónde sale cada dato:**

| Dato | De dónde | Nota |
|---|---|---|
| Nombre comercial | `companyName` | el título de la fila |
| Organización | `organizationName` | **sólo si hay más de una organización** en la lista: repetir «Organización RISEG» en cinco filas de la misma es ruido |
| Rol | `role` | pastilla, como en la lista de usuarios. Dice **dónde** eres Maestro, que no es obvio con varias empresas |
| Razón social | `GET …/profile` de cada una | ⚠️ **ver abajo** |

⚠️ **La razón social en la lista costaría una petición por empresa.** La lista no la trae,
y pedir el expediente de cada fila para enseñarla sería N+1 peticiones por abrir una
pantalla. **Propongo no mostrarla**: el nombre comercial es el que la persona reconoce, y
la razón social está a un toque, en la ficha. Si la quieres en la lista, lo honesto es
añadirla a `AccessibleCompany` —un `LEFT JOIN` a la misma consulta— y lo digo como
decisión, no lo cuelo.

### ⚠️ Tocar una fila **cambia la empresa activa**

**Y esto hay que decidirlo a sabiendas.** El shell entero —el menú, los permisos, el
rastro— se construye desde la **empresa activa**. Si la ficha de la empresa B se abriera
dejando activa la A:

- el menú seguiría enseñando los apartados de A;
- **la regla «lo que no puedes hacer no se muestra» se calcularía contra la empresa
  equivocada**: el botón «Editar» aparecería o no según tus permisos en A, mientras el
  `PUT` iría contra B. Y el servidor contestaría 403 correctamente, pero la pantalla
  habría prometido algo que no podía cumplir.

Así que **tocar una fila selecciona esa empresa** —el mismo acto que el selector de
empresa ya hace— y después abre su ficha. Es más que navegar, y la pantalla lo dirá si la
empresa cambia.

---

## 4 · La ficha, con la forma de la tarjeta fiscal

```
┌─────────────────────────────────────────────────────────────────────────┐
│  ‹ Empresas                                                             │
│                                                                          │
│  ┌──────────┐   RISEG                                   [ Editar ]      │
│  │          │   Seguridad Privada RISEG S.A. de C.V.                    │
│  │   logo   │   SPR950101AB1                                            │
│  │  96×96   │   601 · General de Ley Personas Morales                   │
│  └──────────┘                                                            │
│                                                                          │
│  ┌─ Datos fiscales ──────────────────────────────── [ Copiar datos ] ─┐ │
│  │  Razón social   Seguridad Privada RISEG S.A. de C.V.          ⧉    │ │
│  │  RFC            SPR950101AB1                                  ⧉    │ │
│  │  Régimen        601 · General de Ley Personas Morales         ⧉    │ │
│  │  Domicilio      Hidalgo 10                                    ⧉    │ │
│  │                 Centro                                             │ │
│  │                 Toluca, Estado de México                           │ │
│  │                 C.P. 50000                                         │ │
│  │                 México                                             │ │
│  └────────────────────────────────────────────────────────────────────┘ │
│                                                                          │
│  ┌─ Contacto ─────────────────────────────────────────────────────────┐ │
│  │  Teléfono  722 123 4567   ⧉     Correo  pagos@riseg.mx       ⧉    │ │
│  └────────────────────────────────────────────────────────────────────┘ │
│                                                                          │
│  ┌─ Representante legal y eslogan ────────────────────────────────────┐ │
│  │  Representante  Juan Pérez            Eslogan  Tu seguridad…      │ │
│  └────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────┘
```

### Las cinco decisiones de la ficha

**1 · El orden y el formato son los de la tarjeta fiscal del escritorio, no unos nuevos.**
El domicilio se arma con las mismas cinco líneas —calle y número, colonia, ciudad ·
municipio · estado, C.P., país— que `construirLineasDomicilioFiscal` ya produce, y que el
escritorio declara «**única fuente de este formato** para no tener 3 formatos ligeramente
distintos entre pantalla, PDF y portapapeles».

⚠️ **Y esa función no se puede importar tal cual:** su archivo importa
`app_database.dart` (Drift). **Es el mismo problema que el logotipo** (§6) y la misma
salida: separar la parte pura a un archivo sin Drift, que los dos productos importan. Es
un patrón, no dos casos: **las funciones puras del escritorio son reutilizables; sus
archivos, no.**

**2 · «Copiar datos» entra aquí, y era un requisito ya anotado.** En
`requisitos-nuevos-del-dueno.md` §1: «Ícono por dato en la tarjeta de la empresa → **con
el expediente de Empresa**». Así que E1 lo trae: el bloque completo con el botón de
arriba, y **el ⧉ por dato**, que es lo que faltaba del escritorio.

> **Lo que E1 NO hace de ese requisito:** la *pieza común* para Cliente y Personal. Esos
> consumidores llegan al mudar Comercial y Personal, y el requisito dice que la pieza se
> diseña «pensando en los tres, **antes del primer consumidor nuevo**». La Empresa **ya
> es** consumidor en el escritorio, así que E1 reutiliza su formato sin inventar la pieza
> común — y cuando llegue el segundo consumidor, se extrae. **Lo digo para que no se lea
> como que E1 la resolvió.**

**3 · Si falta algo para la tarjeta fiscal, se dice QUÉ falta.** El servidor ya manda
`fiscalCardReady` y la pantalla de hoy ya nombra lo que está vacío. Eso se conserva, en la
ficha, como un aviso sobre el bloque:

```
⚠ Para entregar la tarjeta fiscal faltan: el RFC y el domicilio fiscal.
```

**4 · Sin logotipo, presentación tipográfica.** Las iniciales en el sitio del logo, igual
que el logotipo de SEVENTRA en el login es «texto compuesto y no una imagen». **No es un
error y no se dice como tal.**

**5 · La ficha es de SÓLO LECTURA, y «Editar» sólo aparece con
`company.settings.manage`.** Quien no puede editar ve la ficha completa: es la identidad
de su empresa, no un dato reservado. **Sin nota de permiso en la ficha** —no está
intentando editar— a diferencia del formulario, donde la nota sí tiene sentido porque los
campos están ahí.

---

## 5 · Editar — y por qué cerrar al guardar cambia cosas

```
┌─────────────────────────────────────────────────────────────────────────┐
│  Editar RISEG                                        [Cancelar] [Guardar]│
│                                                                          │
│  ┌─ Logotipo ─────────────────────────────────────────────────────────┐ │
│  │   ┌──────────┐                                                     │ │
│  │   │   logo   │   [ Cambiar logotipo ]   [ Quitar ]                 │ │
│  │   └──────────┘   PNG o JPEG, hasta 5 MB                            │ │
│  └────────────────────────────────────────────────────────────────────┘ │
│  ┌─ Identidad ────────────────────────────────────────────────────────┐ │
│  │  Nombre comercial [RISEG                    ]  ← NUEVO en E1       │ │
│  │  Razón social     [Seguridad Privada RISEG …]                      │ │
│  │  RFC              [SPR950101AB1   ]  Régimen [601 · General ▾]     │ │
│  │  Representante    [Juan Pérez     ]  Eslogan [Tu seguridad…  ]     │ │
│  └────────────────────────────────────────────────────────────────────┘ │
│  ┌─ Domicilio fiscal ─────────────────────────────────────────────────┐ │
│  │  … los diez campos de siempre …                                    │ │
│  └────────────────────────────────────────────────────────────────────┘ │
│  ┌─ Contacto ─────────────────────────────────────────────────────────┐ │
│  │  Teléfono [            ]  Correo [            ]  Sitio [         ] │ │
│  └────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────┘
```

### Las decisiones de «Editar»

**1 · Guardar CIERRA y vuelve a la ficha, con lo guardado ya pintado.** No se recarga: el
`PUT` devuelve el expediente completo, así que la ficha se pinta con la respuesta. Pedirlo
otra vez sería una petición que no puede traer nada nuevo.

**2 · Y si el guardado FALLA, no se cierra.** Es lo que la regla implica y conviene
escribirlo: cerrar con un error pendiente dejaría a la persona en la ficha sin saber que su
cambio no entró. Se queda en el formulario, con los campos señalados y **la vista llevada
al primero** —ya construido el 21 de octubre, `riseg_foco_y_vista.dart`—.

**3 · El 409 de otra persona sigue preguntando campo por campo.** El diálogo de choque ya
está hecho y cableado en este expediente. Al resolverse, se guarda y **entonces** cierra.

**4 · Cancelar con cambios sin guardar pregunta antes.** Hoy el formulario está siempre
abierto y «cancelar» no existe; al convertirlo en modo, salir **puede perder trabajo**. El
escritorio ya confirma al cancelar el expediente de empresa (`empresaCancelarConfirmacionTitulo`),
así que se copia ese recorrido.

**5 · El logotipo se administra DENTRO de editar**, como pediste, y **se aplica de
inmediato** —no al guardar—. Es la misma distinción que en la sucursal: subir un archivo es
una operación con su propia ruta, su propio permiso y su propio evento; mezclarla con el
`PUT` del expediente obligaría a mandar los bytes en cada guardado. La pantalla lo dice:
*«El logotipo se guarda al momento.»*

**6 · El nombre comercial es un campo normal del formulario**, con la misma nota de
permiso que el resto. No lleva confirmación propia: cambia con el expediente, en la misma
transacción, y queda en auditoría.

---

## 6 · El logotipo y el transporte — lo que ya investigué, puesto donde va

### El servidor está hecho: sin migración y sin rutas nuevas

La 0010 sembró **`company.logo` como único uso real** —PNG/JPEG, **5 MiB**, `singleton`—
con el comentario que lo explica: «no se siembran purposes de dominios que todavía no
existen: una fila de catálogo sin consumidor es una promesa que nadie verifica». **E1 es
ese consumidor.**

| Verbo | Ruta | Cuerpo | Respuesta |
|---|---|---|---|
| `POST` | `/companies/{id}/logo` | `multipart/form-data`, campo `file` | **201** `LogoResponse` |
| `GET` | `/companies/{id}/logo` | — | **200**, los **bytes** |
| `DELETE` | `/companies/{id}/logo` | — | **204**, y **404** la segunda vez |
| `GET` | `/companies/{id}/storage` | — | uso y capacidad |

**El `POST` es una llamada y tres pasos internos**, y su garantía está en la ruta: «el
logotipo anterior sigue vigente hasta que el nuevo está validado, así que un fallo nunca
deja a la Company sin logotipo». **La pantalla no tiene que quitar antes de subir.**

**Quitar libera capacidad EN EL ACTO** aunque el archivo siga guardado hasta la purga. El
texto no puede decir «se borró»: dice que se quitó y que la capacidad quedó libre.

| Código | HTTP | Qué ofrece la pantalla |
|---|---|---|
| `content_type_rejected` | 415 | «Elige un PNG o un JPEG» |
| `content_mismatch` | 422 | **se llama `.png` y no lo es**: se dice así |
| `file_too_large` | 413 | el máximo, en MB |
| `storage_capacity_exceeded` | 409 | **las dos cifras** y «habla con SEVENTRA» |
| `logo_missing` | 404 | **no es error**: es «sin logotipo» |

⚠️ **La capacidad es de la ORGANIZATION.** El mensaje no puede decir «tu empresa se quedó
sin espacio»: con varias empresas, la que se quedó sin espacio es la organización.

### IF-5: el transporte, que es el grueso de E1

El cliente HTTP de la web **no sabe de binarios**, y está anotado desde que se escribió:
«deja la puerta abierta a `MultipartRequest` … **cuando IF-5 traiga los archivos**».

- `ApiRespuesta` sólo tiene `final String cuerpo`. **Un PNG decodificado como cadena se
  corrompe**: no se ve mal, es que los bytes ya no son los que llegaron.
- No hay `multipart`: los cinco verbos mandan JSON.

| Pieza | Por qué así |
|---|---|
| `ApiRespuesta.bytes`, **nulos salvo que se pidan** | guardarlos siempre duplicaría en memoria cada respuesta JSON del producto |
| `ApiClient.getBytes(ruta)` | el camino de **toda** descarga futura: foto de empleado, documento de contrato |
| `ApiClient.postMultipart(...)` | un `MultipartRequest` sobre el **mismo camino único** de `_enviar`, para que el trato de errores siga existiendo una sola vez |

⚠️ **La trampa que hay que resolver en el diseño:** `ApiClientAutenticado` «ante un **401**,
refresca y reintenta **exactamente una vez**». Un `MultipartRequest` **no se puede
reenviar** —su cuerpo es un flujo ya consumido—, así que el reintento mandaría un cuerpo
vacío y el servidor contestaría «no llegó ningún archivo» **por un problema de token**. La
salida: los bytes se guardan y **la petición se construye de nuevo en cada intento**. Caben
—5 MiB el uso, 32 MiB el tope duro— y en la web el archivo ya viene entero en memoria.

### Las tres trampas de pantalla del logotipo

1. **En web `file_picker` devuelve `bytes` y `path` SIEMPRE nulo**, y `bytes` sólo llega
   con `withData: true`. El código del escritorio lee `path`: **no se reutiliza**.
2. **`Image.network` no sirve**, por dos razones independientes: el `Authorization: Bearer`
   no viaja en un `<img>`, y la ruta responde `Content-Disposition: attachment` a propósito
   —«nada inline»—. Se descarga con el cliente autenticado y se pinta con `Image.memory`.
3. **`Image.memory` sin `key` deja la imagen vieja pegada** al reemplazar: parece que no se
   guardó. La `key` sale del `sha256` o del `fileId` de `LogoResponse`, no de un contador.

### Y la validación por firma

Se comprueban tipo **por los primeros bytes** y tamaño, como **aviso temprano, nunca como
garantía**: «un archivo puede llamarse `.png` sin serlo». `LogoEmpresaValidacion.tipoReal`
ya lo hace, pero **su archivo importa `dart:io`** para `revisarLogo(String rutaArchivo)`,
que vive al lado — el mismo patrón del §4. Se separa la parte pura primero.

---

## 7 · E2, lo que medí — con una trampa que hay que resolver en su diseño

No es el diseño de E2; es lo que encontré del servidor mirando E1, para que no se pierda.

### Lo que YA está hecho

- **La capacidad de empresas existe y está implementada:** el medidor
  `administra.companies` —«Empresas activas», unidad `empresa`, **scope `organization`**—
  está sembrado desde la 0024 con `source_state = 'implemented'`.
- **Es una capacidad DURA**, y está escrito: «Companies → **DURA**. No se excede sin
  capacidad adicional», frente a los empleados activos, que son medidos y **no bloquean**.
- **Crear una empresa ya reserva capacidad** dentro de su propia transacción
  (`TenancyRepository` llama a `ReserveAsync`), y **los adicionales ya cuentan**:
  `adds_company_capacity` → `administra.companies`.
- `GetSnapshotAsync` da capacidad y consumo para informar, así que **la lista de E1 podría
  enseñar «2 de 5 empresas»** cuando E2 llegue.

### Lo que NO existe

**Nada que desactive, reactive o elimine una empresa.** Busqué un `UPDATE app.company SET
status` y no hay ninguno. Eso es el trabajo de E2, con su permiso nuevo y su migración.

### ⚠️ La trampa: desactivar una empresa la hace **invisible para quien la reactivaría**

Está en dos sitios a la vez y los dos la filtran igual:

```sql
-- el autorizador de Company
AND a.status = 'activa' AND c.status = 'activa' AND o.status = 'activa'
-- y GET /companies, la lista
AND a.status = 'activa' AND c.status = 'activa' AND o.status = 'activa'
```

Así que una empresa inactiva **desaparece de la lista de todos y nadie puede abrirla**. Si
«Reactivar» viviera detrás de esa lista, **sería inalcanzable**: la empresa que hay que
reactivar es justo la que no sale.

**Las tres salidas, para decidir en E2:**

| | Qué | Coste |
|---|---|---|
| **(a)** | Una ruta que liste **también las inactivas**, para quien tenga el permiso nuevo | la lista de E1 gana un filtro «mostrar inactivas», como Áreas y Sucursales |
| **(b)** | Reactivar vive en **Console**, no en Administra | el cliente no puede deshacer su propio error sin llamarnos |
| **(c)** | Desactivar **no** cierra el acceso de los administradores | cambia qué significa «inactiva» en el autorizador, que es defensa estructural: **no lo recomiendo** |

**Mi recomendación es (a)**, y nótese lo que implica: entonces **la lista de E1 sí necesita
`status`**, porque tendría que distinguir las inactivas. Hoy no lo necesita (§1). Es la
clase de cosa que conviene saber **antes** de construir la lista, aunque E2 venga después:
el campo se añade a `AccessibleCompany` en E2, y la lista de E1 se escribe sabiendo que va
a llegar.

---

## 8 · La tarjeta fiscal en PDF — propuesta aparte, como pediste

**No está decidida, y creo que hace falta, pero no en E1.**

El escritorio la genera y la abre (`tarjeta_fiscal_dialog.dart` +
`GenerarTarjetaFiscalPdfUseCase`), así que **es una función que se perdería**, y la regla
de la mudanza es que no se pierde ninguna.

**Pero la ficha de E1 cubre la mayor parte de su propósito**: entregar los datos fiscales a
quien va a emitir. Con «Copiar datos» se pegan en un correo, que es como se usan el 90 % de
las veces. El PDF añade **un documento con el logotipo**, que es otra cosa: se adjunta, se
imprime, se archiva.

Y es un problema **técnicamente distinto**, no una pantalla más: hay que decidir **quién lo
compone**, y las dos salidas no se parecen —el cliente con el paquete `pdf` y una descarga
del navegador, o el servidor con una ruta nueva que lo devuelva—. Esa decisión arrastra
dónde vivirá la composición de **todos** los documentos de Administra, que son muchos más
que éste: recibos de pago, constancias, reportes.

**Propongo tratarla como E4, con su propio diseño**, y decidir ahí la pregunta grande
—cliente o servidor— una vez para todos los documentos. Si prefieres que vaya antes, dilo
y la subo; lo que no recomiendo es resolverla dentro de E1 en una tarde, porque la
respuesta compromete los demás módulos.

---

## 9 · Mapa de permisos por acción

| Acción | Permiso | ¿Nuevo? |
|---|---|---|
| **Ver la lista** de empresas | acceso a la Company (la ruta lista lo que puedes abrir) | no |
| **Ver la ficha** y el expediente | `company.settings.read` | no — llegó con la 0052 |
| **Ver el logotipo** | **acceso a la Company**, sin permiso propio | no — «es su identidad visual, no un dato reservado» |
| **Editar** el expediente, incluido el **nombre comercial** | `company.settings.manage` | no |
| **Subir / quitar** el logotipo | `company.settings.manage` | no |
| **Ver uso de almacenamiento** | `company.settings.manage` | no |

**Ningún permiso nuevo y ninguna migración en todo E1.** El permiso nuevo es de E2.

---

## 10 · Las pruebas que lo fijarían

**Del transporte (IF-5), que es lo que más se reutiliza:**

1. `getBytes` devuelve los bytes **intactos** —un PNG comparado byte a byte, no su
   longitud— y una petición normal **sigue sin guardarlos**.
2. `postMultipart` manda `multipart/form-data` con el campo **`file`**, su nombre y su tipo.
3. **El reintento por 401 vuelve a mandar el cuerpo COMPLETO**: la prueba cuenta los bytes
   del segundo intento y falla si llegan cero.

**Del recorrido, que es lo que E1 estrena:**

4. Con **una** empresa no se pinta la lista: se abre su ficha.
5. Con **dos**, la lista las enseña y tocar una abre su ficha **y cambia la empresa activa**.
6. «Editar» **no aparece** sin `company.settings.manage`, y la ficha **sí** se ve completa.
7. Guardar **cierra y vuelve a la ficha**, con lo guardado pintado **sin volver a pedirlo**.
8. Un guardado que **falla NO cierra**, y la vista va al campo señalado.
9. Cancelar **con cambios** pregunta; sin cambios, cierra directo.
10. El 409 de otra persona abre el diálogo de choque, y al resolverlo guarda **y entonces**
    cierra.

**Del logotipo:**

11. Sin logotipo (404) → iniciales, **sin mensaje de error**, con «Subir».
12. Al reemplazar, **la imagen cambia** (la trampa de la `key`).
13. Un archivo que no es imagen se rechaza **antes de subir**, por su firma.
14. El 409 de capacidad enseña **las dos cifras** y habla de la **organización**.
15. Quitar confirma primero, y dice que **se liberó capacidad**, no que se borró.

**De la ficha:**

16. El domicilio se pinta con **las cinco líneas** de la tarjeta fiscal del escritorio, en
    su orden.
17. Si falta algo indispensable, el aviso **nombra qué falta**.
18. «Copiar datos» copia el bloque, y el ⧉ de un dato copia **ese** dato.

---

## 11 · Lo que cuesta

| Parte | Tamaño | Backend |
|---|---|---|
| **IF-5**: bytes y multipart con su reintento | **el grueso**, y se hace una vez | — |
| Lista, ficha y el modo editar | mediano | — |
| El logotipo en la ficha y en editar | mediano | **nada: ya existe** |
| **`name` en el `PUT` del expediente** | pequeño | **sí**, sin migración |
| Separar las dos funciones puras de su `dart:io` / Drift | pequeño | — |

**Lo único que toca el servidor es `name` en el `PUT`.** Sin migración, sin permiso nuevo y
sin esquema: se puede construir y probar contra la API que ya está en `dev`.

⚠️ **Y las dos mitades van juntas al ensayo**, como el expediente de la sucursal: una web
que manda `name` contra un servidor que lo descarta guardaría en silencio nada.

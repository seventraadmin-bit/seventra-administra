# E2 · Administración de empresas

**Diseño para aprobar antes de programar.** Pedido el 22 de octubre de 2026, al cerrar
E1-B. Cubre: la lista de todas las empresas, crear respetando la capacidad del plan,
desactivar con motivo, reactivar, eliminar, el permiso nuevo y la migración **0053**.

---

## 1. Para quién es E2, y es lo primero porque cambia el permiso

Administrar empresas **no es una operación dentro de una empresa**: es una operación
**sobre la Organization**. Y eso tiene una consecuencia que hay que decidir antes de
escribir una línea:

> 🚫 **El permiso nuevo NO puede ser un permiso de Company.** Los permisos de Company se
> conceden **por CompanyAccess**, o sea empresa por empresa. Un permiso concedido en la
> empresa A **no puede autorizar crear la empresa B** — eso sería inferir la pertenencia
> desde donde no está, que es justamente lo que toda la arquitectura impide.

El plano correcto ya existe y ya tiene una pieza dentro:

```
  app.platform_organization_permission        catálogo de SEVENTRA (sólo lectura)
    └── 'subscription.manage'                 el único de hoy
    └── 'companies.manage'                    ← lo que trae la 0053

  app.organization_membership_permission      concedido a UN PERIODO de membresía
    └── el Owner NO tiene filas: su autoridad es intrínseca al rol
```

Así que la autoridad de E2 es: **Owner de la Organization**, o **Admin con
`companies.manage`**. Es la misma forma que `subscription.manage`, incluida la parte que
importa: una membresía revocada y vuelta a conceder **nace sin permisos**, así que nadie
recupera por accidente la autoridad de crear empresas.

**No se ensancha `subscription.manage`**, y la frontera es nítida: crear una empresa
**dentro** de la capacidad contratada no compromete gasto; contratar un adicional para
poder crearla, sí. Son dos autoridades distintas y se quedan distintas.

### ⚠️ La consecuencia de producto, dicha en voz alta

**Un Maestro que no sea miembro de la Organization NO verá esta pantalla.** Beto, que es
Maestro de la empresa, administra *su* empresa; no da de alta empresas nuevas. Tú la ves
porque eres **Owner**.

Y eso descubre un hueco: **hoy la web no sabe nada de la autoridad de Organization.** El
contexto que resuelve la empresa activa trae el rol **de Company** (`maestro`/`user`) y
el nombre de la Organization, y nada más. La ruta que falta **ya existe** —
`GET /organizations/{id}/membership`, «la autoridad propia sobre la Organization, con sus
permisos»—; lo que falta es **pedirla y guardarla**. Es trabajo de E2 y está en el
reparto.

---

## 2. Lo que YA existe y no se reescribe

Lo medí antes de diseñar, y es bastante más de lo que esperaba:

| Qué | Dónde | Estado |
|---|---|---|
| Crear empresa **comprobando capacidad** | `TenancyService.CreateCompanyAsync` → `CapacityCheck` | ✅ con su `CapacidadExcedida` y su mensaje «Tu plan permite N empresas y ya tienes M» |
| Crear con **su primer Maestro en la misma transacción** | la misma | ✅ y el Maestro es **explícito**, puede no ser quien crea |
| La ruta | `POST /organizations/{id}/companies` | ✅ existe, en el plano de Organization |
| **Los tres medidores** cuentan sólo lo `activa` | `company`, `company_access`, `fn_active_employee_usage` | ✅ los tres, y es coherente |
| El **motivo** de una acción auditada | `audit_event.reason`, columna de primera clase | ✅ no hace falta inventar nada |
| «Cambió de estado» en la auditoría | `AuditAction.StatusChanged` | ✅ **no se inventa `deactivated`** |
| Que una empresa con datos **no se pueda borrar** | **58 FK `ON DELETE RESTRICT`** contra `app.company` | ✅ lo impone el motor, no un `if` |
| El patrón de «no la última» | `RevokeCompanyAccessAsync`: bloqueo explícito + conteo dentro de la transacción | ✅ es el precedente del último Maestro |

**Así que E2 no construye el motor de crear: lo expone y añade los otros cuatro verbos.**

---

## 3. Tres hallazgos que cambian el alcance

### 3.1 🔴 `seventra_app` NO PUEDE BORRAR una empresa

La 0004 concede `SELECT, INSERT, UPDATE` sobre `app.company` y **no `DELETE`**. No es un
descuido del proyecto: hay migraciones que lo dicen con todas las letras —«NINGÚN
`DELETE`, y no es una omisión»— porque el rol de la API no debe poder destruir historia.

Así que **«eliminar» no es programar una ruta: es decidir si se amplía un privilegio de
base de datos.** Es la decisión D1 de §7.

Lo que sí acota el riesgo, y es mucho: **las 58 FK `RESTRICT`**. Con el `GRANT` puesto,
un `DELETE` sobre una empresa que tenga **una sola fila de datos** —un empleado, un
cliente, un área, un archivo— **lo rechaza el motor**. El privilegio no abre «borrar
empresas»: abre «borrar una empresa vacía».

### 3.2 Reactivar tiene que comprobar **las tres** capacidades, no una

Desactivar **libera** plaza de empresa, licencias de acceso y cuenta de empleados, porque
los tres medidores filtran `status = 'activa'`. Eso es coherente y es lo que se quiere
— pero abre un camino que hay que cerrar:

```
  plan con 1 empresa, y 1 empresa activa con 8 empleados
    desactivar A        →  0 empresas, 0 accesos, 0 empleados   (plaza libre)
    crear B             →  1 empresa                             ✅ permitido
    reactivar A         →  2 empresas  ❌ por encima del plan
                           y 8 empleados que nadie contó
```

**Reactivar es, en capacidad, exactamente igual que crear.** Así que comprueba lo mismo
—y las tres cosas, no sólo empresas—, con el mismo error y el mismo mensaje. El diseño
aprobado no lo mencionaba; sin esto, reactivar sería la puerta de atrás de la capacidad.

### 3.3 La única lista que existe **no puede ver** lo que E2 desactiva

`ListCompaniesOfOrganizationAsync` filtra `status = 'activa'`. Si E2 desactivara una
empresa sin tocar esa consulta, **la empresa quedaría inalcanzable**: desaparece de la
lista *y* del autorizador a la vez, y no habría ninguna pantalla desde la que
reactivarla.

Es la razón por la que E1 metió `status` en la lista de empresas accesibles «para no
rehacerla en E2». Aquí toca la otra consulta: **la lista de la Organization pasa a
devolver activas e inactivas**, con el estado, y la pantalla filtra.

---

## 4. Las cinco operaciones

Todas en el plano `/organizations/{organizationId}/companies`, todas con la misma puerta
—Owner o `companies.manage`— y todas auditadas en la misma transacción que la mutación.

### 4.1 Listar

`GET /organizations/{id}/companies?incluirInactivas=true`

- **requiere membresía**, como hoy, y el parámetro exige la autoridad de E2: ver las
  inactivas es parte de administrarlas;
- devuelve por empresa: `id`, `name`, `legalName`, `status`, `createdAt`, y **cuántos
  accesos activos tiene**. Lo último no es adorno: es lo que permite decir, antes de
  desactivar, a cuánta gente va a dejar fuera;
- orden: el de hoy —`created_at`—, para no cambiar dos cosas a la vez.

### 4.2 Crear

`POST /organizations/{id}/companies` — **la ruta que ya existe**, con dos cambios:

- la puerta pasa a ser la de E2 (hoy basta la autoridad de Organization; con el permiso
  nuevo, un Admin **sin** `companies.manage` deja de poder crear). Es un
  **estrechamiento**, y hay que decirlo: es intencionado;
- acepta la **razón social** opcional, para no obligar a entrar al expediente después.

Lo demás se conserva: capacidad comprobada, primer Maestro explícito y en la misma
transacción, `409 capacidad_excedida` con las dos cifras.

### 4.3 Desactivar

`POST /organizations/{id}/companies/{companyId}/deactivation` con `{ "reason": "..." }`

Las reglas, en el orden en que se comprueban:

1. **el motivo es obligatorio** y no vacío: va a `audit_event.reason`, que ya existe. Sin
   motivo, un `422`; inventarle un «sin motivo» sería guardar una firma en blanco;
2. **no la última activa.** Se bloquea la fila de la **Organization** primero —el orden
   global de bloqueos es `organization → subscription → company → …`— y se cuentan las
   activas dentro de la transacción. Con una sola, `409 ultima_empresa_activa`;
3. ya inactiva → **`409 sin_cambio`**, no un éxito silencioso;
4. se escribe `status = 'inactiva'` y **un** evento `StatusChanged` con el motivo.

**Lo que NO hace, y es deliberado:**

- **no revoca los accesos.** Las filas de `company_access` se quedan como están, activas.
  No hace falta tocarlas —la empresa desaparece del autorizador por su `status`, así que
  nadie entra— y **conservarlas es lo que hace que reactivar devuelva el equipo
  intacto**. Revocarlas obligaría a reconstruir a mano quién trabajaba ahí;
- **no toca los datos.** Desactivar es dejar de operar, no borrar;
- **no exige que no haya nadie dentro.** La sesión de quien esté trabajando en esa
  empresa dejará de autorizar en la siguiente petición. Eso ya pasa hoy con una
  suscripción vencida y tiene su mensaje.

> ⚠️ Y hay una interacción con el último Maestro que **ya está resuelta en el código** y
> conviene no «arreglar»: `RevokeCompanyAccessAsync` protege al último Maestro **sólo si
> la Company está activa** —«una Company inactiva puede quedarse sin Maestro sin que eso
> rompa nada: ya no se opera»—. Desactivar una empresa con un solo Maestro es legítimo.

### 4.4 Reactivar

`DELETE /organizations/{id}/companies/{companyId}/deactivation`

- **comprueba las tres capacidades**, como crear (§3.2). Sin plaza,
  `409 capacidad_excedida` **con las cifras y diciendo cuál de las tres faltó**: «tu plan
  permite 10 empleados activos y reactivar esta empresa sumaría 14» es accionable;
  «capacidad excedida» no lo es;
- ya activa → `409 sin_cambio`;
- **el motivo es opcional** aquí. Desactivar quita algo a alguien y eso se explica;
  reactivar lo devuelve. Exigir un motivo para arreglar algo es burocracia;
- un evento `StatusChanged`.

### 4.5 Eliminar

`DELETE /organizations/{id}/companies/{companyId}` — **la única que necesita una decisión
de privilegios** (§3.1, D1).

1. **sólo una empresa vacía.** Y no lo decide un `if` que enumere tablas —esa lista se
   queda corta el día que alguien añada una— **lo decide el motor**: se intenta el
   `DELETE` y una violación de FK se traduce a `409 empresa_con_datos`, con el nombre de
   lo que la retiene cuando PostgreSQL lo dice;
2. **no la última activa**, igual que desactivar: borrar la única empresa dejaría la
   Organization sin nada que operar;
3. **no exige desactivar primero.** El caso real es «la creé con el nombre mal»: obligar
   a desactivarla para borrarla sería un trámite sin beneficio;
4. el evento `Deleted` se escribe **antes** del `DELETE` en la misma transacción —con el
   nombre dentro, porque después no habrá fila que consultar—, y lleva motivo obligatorio;
5. 🚫 **ESTE PUNTO ERA FALSO Y SE CORRIGE AQUÍ** (22 de octubre de 2026, al programar
   las pruebas). Decía: «`company_access` cae con ella (`ON DELETE CASCADE`), y es la
   única FK en cascada de las 59».

   **La única FK en cascada es `company_access_permission → company_access`.** La de
   `company_access → company` es **RESTRICT**, como las otras 57. Y la consecuencia no
   es un detalle: **toda empresa nace imposible de eliminar**, porque crearla inserta
   el acceso de su primer Maestro. No existe ninguna empresa «vacía» que borrar, ni
   siquiera una recién creada por error — que es justo el caso que «Eliminar» venía a
   resolver.

   Lo demás del borrado está programado y funciona: la autoridad de Owner, el motivo
   obligatorio, la regla de la última activa —que se evalúa **antes** de tocar la
   base— y el rechazo del motor. Lo que falta es **una decisión más**, la D3 de §7.

**Por qué no basta con desactivar:** una empresa desactivada **sigue ocupando una fila con
un nombre** en la lista de administración y en los informes. Un error de dedo tiene que
poder desaparecer; lo que no puede desaparecer es el trabajo.

---

## 5. La migración 0053

**Es pequeña**, y conviene que se vea lo pequeña que es:

```sql
-- 1 · El permiso de organización, en el catálogo de SEVENTRA.
INSERT INTO app.platform_organization_permission (code, name) VALUES
  ('companies.manage', 'Dar de alta, desactivar y eliminar empresas')
ON CONFLICT (code) DO NOTHING;

-- 2 · El privilegio de borrado, SÓLO si D1 se aprueba.
GRANT DELETE ON app.company TO seventra_app;
```

**Y nada más.** En concreto, lo que **no** trae y podría parecer que sí:

- **ninguna columna para el motivo ni la fecha de desactivación.** `audit_event` ya tiene
  `reason`, es append-only y guarda quién y cuándo. Una columna
  `deactivation_reason` en `company` sería una **segunda fuente de verdad** del mismo
  hecho, y se desincronizaría en el primer camino que alguien olvide actualizar — además
  de guardar sólo el último motivo, perdiendo las desactivaciones anteriores;
- **ningún estado nuevo.** `company.status` ya admite `activa` e `inactiva` con su `CHECK`
  desde la 0004. Lo que faltaba era un camino para escribirlo;
- **ningún `AuditAction` nuevo.** `StatusChanged` y `Deleted` ya existen.

Como toda migración, **necesita prueba del camino incremental 52→53**, no sólo desde cero.

---

## 6. Las pantallas

Organización › Empresa gana una segunda pestaña —**Administración**— visible sólo con la
autoridad de E2. La ficha de la empresa activa (E1) **no se toca**.

```
  Organización › Empresa                    [ Ficha ] [ Administración ]
  ┌──────────────────────────────────────────────────────────────────────┐
  │  Empresas de Cliente de prueba            2 de 5 del plan  [+ Nueva]│
  │  ────────────────────────────────────────────────────────────────── │
  │  ┌────┐ SEGURIDAD PRIVADA RISEG                         Activa  ⋮  │
  │  │ 🏢 │ Seguridad Privada RISEG S.A. de C.V. · 3 accesos           │
  │  └────┘                                                            │
  │  ┌────┐ RISEG Servicios (prueba)                        Activa  ⋮  │
  │  │ RS │ sin razón social · 1 acceso                                │
  │  └────┘                                                            │
  │  ┌────┐ Vigilancia del Valle                          Inactiva  ⋮  │
  │  │ VV │ desactivada el 3 de octubre · 0 accesos                    │
  │  └────┘                                                            │
  │                                      ☐ Mostrar las inactivas       │
  └──────────────────────────────────────────────────────────────────────┘
```

- **la misma tarjeta de E1-B**, con su logotipo o iniciales. Tercera vez que se usa y
  tercera vez que no se duplica;
- **«2 de 5 del plan»** arriba, con las cifras del medidor. Es la respuesta a «¿puedo
  crear otra?» antes de intentarlo — y si no se puede, el botón lo dice en vez de
  descubrirlo con un 409;
- **`⋮` por fila:** Desactivar · Reactivar · Eliminar, cada una sólo cuando aplica. La
  última empresa activa **no ofrece** Desactivar ni Eliminar, y el menú dice por qué;
- **las inactivas se ocultan por omisión** y se piden con la casilla: en el caso normal
  son ruido;
- **desactivar pide el motivo en un diálogo**, con el número de accesos que van a quedar
  fuera a la vista. Con el motivo vacío el botón no se habilita;
- **eliminar pide escribir el nombre de la empresa**, como cualquier borrado
  irreversible, y dice que **sólo funciona si está vacía**.

**Crear** abre un formulario corto: nombre comercial, razón social (opcional) y **quién
será su Maestro**, que es obligatorio y explícito — el servidor lo exige y la pantalla no
lo esconde eligiendo a quien crea.

---

## 7. 🔴 NECESITO TU DECISIÓN

### D1 · ¿Se concede `DELETE` sobre `app.company` al rol de la API?

Es la única pieza de E2 que no se puede programar sin tu aprobación, porque **cambia los
privilegios de base de datos** del rol con el que corre toda la API.

| | Qué | Qué significa |
|---|---|---|
| **(a)** | **`GRANT DELETE ON app.company`**, y eliminar queda como se diseñó | el motor sigue impidiendo borrar cualquier empresa con **una sola fila** de datos (58 FK `RESTRICT`), así que lo que se abre es «borrar una empresa vacía». **Recomendada** |
| **(b)** | **Sin `GRANT`**: «Eliminar» desaparece de E2 y una empresa creada por error **se desactiva y se queda ahí para siempre** | cero cambios de privilegios; el precio es una lista que acumula errores de dedo con nombre propio |
| **(c)** | El borrado lo hace una **ruta de plataforma** (Console, con el rol del migrador) | el cliente no borra; tú sí, desde Console. Más seguro y **más lento para el cliente**, y Console todavía no tiene esa pantalla |

**Recomiendo (a).** El privilegio suena más grande de lo que es: las 58 `RESTRICT` ya
convierten «borrar una empresa» en «borrar una empresa que no tiene nada», y eso es
exactamente la operación que pediste. Y lo que de verdad protege la historia no es la
ausencia del `GRANT`, son esas FK.

### D2 · ¿«Eliminar» exige que la empresa esté vacía, o también sin historia?

Una empresa **vacía de datos** puede tener **auditoría** —se creó, se renombró, se
desactivó—. Esos eventos **no** la retienen: `audit_event` no tiene FK a `company`.

- **(a)** **borrar la empresa y conservar sus eventos** (la auditoría es append-only y
  sobrevive al objeto; es lo que ya pasa con un archivo purgado). **Recomendada**;
- **(b)** no permitir borrar nada que tenga eventos → en la práctica **nada se puede
  borrar nunca**, porque crearla ya dejó uno.

**Recomiendo (a)**, y que el evento `Deleted` lleve el nombre dentro, para que la traza
siga siendo legible cuando la fila ya no exista. **Aprobada así el 22 de octubre.**

---

### D3 · 🔴 El bloqueo de `company_access`, descubierto al programar

Afirmé que `company_access` caía con la empresa en cascada. **Era falso**, y sin eso
«Eliminar» **no puede funcionar nunca**: crear una empresa inserta el acceso de su
Maestro, así que ninguna empresa está vacía jamás.

| | Qué | Qué significa |
|---|---|---|
| **(a)** | **`company_access → company` pasa a `ON DELETE CASCADE`** en una migración **(recomendada)** | un acceso a una empresa que ya no existe no significa nada, y los permisos de ese acceso ya caen en cascada detrás. El historial de quién entró **no se pierde**: vive en `audit_event`, que no tiene FK a `company` |
| **(b)** | `GRANT DELETE ON app.company_access` y borrarlos a mano antes | 🚫 **peor**: el rol de la API podría destruir filas de acceso **en cualquier parte**, y revocar está diseñado para ser un cambio de estado que conserva los periodos. Abre mucho más de lo que resuelve |
| **(c)** | Dejar «Eliminar» como imposible | la lista acumula errores de dedo con nombre propio, que es lo que (b) de D1 ya descartaste |

**Recomiendo (a)**, y acotada: cambiar **esa** clave y ninguna otra, en su propia
migración, con la prueba del camino incremental. Las otras 57 `RESTRICT` siguen siendo
lo que protege los datos del negocio — y lo que esta cambia no es un dato del negocio,
es la relación con un objeto que desaparece.

---

## 8. Reparto y orden

| | Qué | Dónde |
|---|---|---|
| **E2.1** | **0053**: el permiso de organización y, con D1, el `GRANT`. Con prueba del camino **52→53** | backend · migración |
| **E2.2** | La puerta: `companies.manage` en el autorizador de Organization, y el estrechamiento de `POST /companies` | backend |
| **E2.3** | Listar con inactivas, accesos por empresa y razón social | backend |
| **E2.4** | Desactivar, reactivar y eliminar, con sus reglas y sus cuatro errores | backend |
| **E2.5** | La web sabe su autoridad de Organization (`GET /organizations/{id}/membership`) | web |
| **E2.6** | La pestaña Administración: lista, crear, y los tres diálogos | web |

**E2.5 va antes que E2.6** porque sin ella la pestaña no sabe si debe existir. Y **E2.1
va primero** porque todo lo demás necesita el permiso en el catálogo: el `INSERT` de un
permiso que no existe lo rechaza una FK, no un `if`.

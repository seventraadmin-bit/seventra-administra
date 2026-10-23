# E3 · Crear tu primera empresa

**Para aprobar antes de programar.** Cierra Organización: es el único camino que hoy no
tiene salida.

El hueco se encontró el **22 de octubre de 2026**, probando la web contra el ensayo. La
cuenta de «Cliente de Prueba Piloto» entra, es **Owner con membresía activa**, tiene su
plan **`administra_esencial` vigente**… y la organización tiene **cero empresas**. El
portón llega a «Todavía no tienes ninguna empresa» y **para ahí**.

No fue un defecto del despliegue. Se midió por el túnel, en sólo lectura: esquema **54**
con la `0050`–`0054` aplicadas, la `0054` correcta —`descartada` en el `CHECK`,
`seventra_app` sin `DELETE`, `fn_company_has_data` existente—, **cero empresas en toda la
base** y **cero eventos de auditoría** sobre `company`. Nunca hubo empresa que perder: es
el estado que el diseño de M1 dejó escrito, y la propia mudanza lo describía como
«comportamiento correcto, no un fallo».

**Lo que sí es un defecto es que no haya salida.** La pantalla de administración de E2
—la que sabe crear empresas— vive detrás de un `CompanyContext` confirmado: `_pantallaDe`
sólo se construye desde `_conMarco`. Sin empresa no hay contexto, sin contexto no hay
pestañas, y sin pestañas no hay forma de crear la primera. Un cliente nuevo queda
esperando a que SEVENTRA le cree la empresa por la API, y **eso es exactamente lo que el
producto no debe necesitar**.

---

## 1. La frontera, y es la decisión que manda

**El mensaje de hoy NO cambia para quien no tiene autoridad.** Sigue diciendo «Tu cuenta
está lista, pero nadie te ha dado acceso a una empresa. Pídelo a quien administra la
tuya», y sigue sin sonar a fallo, porque no lo es: es el primer día de un empleado al que
todavía no le dieron acceso, y es el caso **normal**.

**El botón es la excepción.** Aparece sólo para quien puede crear una empresa de verdad:
**Owner de la Organization, o miembro con `companies.manage`** — la misma puerta que E2
estrechó, ni más ancha ni más estrecha.

Dicho al revés, que es como se va a leer en el código: esta etapa **no añade un permiso,
no añade una ruta y no añade una migración**. Expone, en la antesala, la autoridad que ya
existe.

---

## 2. El problema de orden: con cero empresas, la web no sabe en qué Organization está

Y es el núcleo del diseño, no un detalle de implementación.

`GET /companies` devuelve `[]`. Esa respuesta **no trae ningún `organizationId`**, porque
el id de la Organization viaja dentro de cada empresa. Así que la pantalla que hoy decide
qué pintar no tiene con qué preguntar por la autoridad: `leerAutoridad(organizationId)`
necesita un id que nadie le dio.

Hace falta una lectura más, y **ya existe**: `GET /organizations` devuelve las
Organizations donde la Identity tiene **membresía activa** (`id`, `name`, `status`,
`createdAt`). Lo que **no** devuelve es el rol, así que la autoridad se sigue leyendo
donde ya se lee, una por Organization: `GET /organizations/{id}/membership`.

La secuencia completa, y son tres lecturas en el peor caso con una Organization:

| # | Lectura | Para qué |
|---|---|---|
| 1 | `GET /companies` → `[]` | lo que ya pasa hoy; es lo que abre esta rama |
| 2 | `GET /organizations` | **nueva en el cliente**; la ruta existe desde siempre y la web nunca la llamó |
| 3 | `GET /organizations/{id}/membership` | rol y permisos → `AutoridadDeOrganizacion` |
| 4 | `POST /organizations/{id}/companies` | crear, con la puerta de E2 |

Ninguna es nueva en el servidor.

### Dónde vive ese estado: en el portón, no en el gestor

**Recomiendo (A): el portón.** `GestorDeCompany` responde una sola pregunta —«¿qué empresa
está abierta?»— y la responde igual que hoy; sus estados y sus pruebas no se tocan. El
portón ya sostiene `_autoridad`/`_autoridadDe`, `_logotipos` y `_guardia`, y ya hace
trabajo asíncrono propio en `_refrescarTrasAdministrar`. La rama
`SinAccesoACompanies` dispara **una vez** la averiguación y la cachea mientras esa rama
siga viva.

La alternativa **(B)** era que el gestor publicara `SinAccesoACompanies(organizaciones:
…)`. Deja el portón más tonto, y a cambio mete el plano de Organization dentro de la
puerta de Company y cambia un contrato que hoy tiene pruebas. **No lo recomiendo**, pero
es tu decisión si prefieres la simetría.

---

## 3. La pantalla

**Es una ANTESALA, no una pestaña**, así que lleva la estética del login y de «Elige una
empresa» —panel oscuro a la izquierda con el logotipo y el saludo, tarjeta a la derecha— y
**no** el marco de la aplicación: no hay empresa, así que no hay barra inferior, no hay
rastro y no hay pestañas. Cuarta vez que se usa esa plantilla, y es deliberado: quien
llega aquí viene de la misma secuencia visual.

Vive en `lib/features/organizacion/web/presentation/primera_empresa_screen.dart`, al lado
de la de administración, porque **comparte su formulario**.

```
┌──────────────────────┬────────────────────────────────────────────┐
│                      │  Crea tu primera empresa                   │
│      SEVENTRA        │                                            │
│                      │  Tu cuenta y tu plan ya están listos.      │
│   Hola, Marlon       │  Administra organiza el personal, las      │
│                      │  sucursales y los clientes DENTRO de una   │
│   Cliente de         │  empresa, así que lo primero es darla de   │
│   Prueba Piloto      │  alta.                                     │
│                      │                                            │
│                      │  Nombre comercial ·········                │
│                      │  Razón social (opcional) ·········         │
│                      │                                            │
│                      │  Tú serás su Maestro. Después puedes dar   │
│                      │  acceso a otras personas desde             │
│                      │  Configuración › Usuarios.                 │
│                      │                                            │
│                      │        [ Crear empresa y entrar ]          │
│   Cerrar sesión      │                                            │
└──────────────────────┴────────────────────────────────────────────┘
```

**El formulario se EXTRAE, no se duplica.** Hoy el alta de E2 vive en un widget privado de
`empresas_administracion_screen.dart` con sus claves `alta_nombre` y `alta_razon_social`.
Se saca a su propio archivo y lo usan las dos pantallas: **una validación, unas claves,
una lista de campos**. Duplicarlo garantizaría que el día que se añada un campo sólo se
añada en una.

**Lo que esta pantalla NO dice: cuánto incluye el plan.** Nada de «tu plan incluye 1
empresa». Esa cifra necesita el lector de capacidad que Administra **no tiene** —es la
deuda del contador «2 de 5 del plan», anotada antes del piloto— y escribirla a mano sería
inventarla. Si el servidor niega por capacidad, se muestra **su** mensaje, que trae las
dos cifras de verdad.

### Con varias Organizations se pregunta, con una sola no

La misma regla que E1-B aplicó al selector de empresas, por la misma razón: elegir por
omisión dónde nace una empresa es una decisión demasiado grande para tomarla en silencio.

Con dos o más Organizations **donde haya autoridad**, primero se eligen —nombre y «Crear
aquí»—; con una, se va directo al formulario. Las Organizations donde la persona es
miembro **sin** `companies.manage` no se listan: ofrecerlas para que el servidor diga 403
sería enseñar una puerta cerrada.

---

## 4. Las cuatro respuestas del servidor, y ninguna se inventa

| Respuesta | Qué se ve |
|---|---|
| **201** | entra sola en la empresa nueva (§5) |
| **409 `capacity_exceeded`** | el mensaje del servidor **tal cual**: trae el límite del plan y lo que quedaría. Reescribirlo perdería las cifras |
| **402 `subscription_restricted`** | «Tu suscripción no permite escribir ahora mismo.» Y el formulario se queda, no se cierra |
| **404 `organizacion_no_disponible`** | la Organization dejó de estar disponible entre la lectura y el envío: se vuelve a leer la lista desde el paso 2 |

Y **el fallo de red no se convierte en «no puedes»**: si la lectura 2 o la 3 falla, se
muestra el mensaje de hoy **más** un «Volver a intentar», nunca un botón de crear que no va
a funcionar ni un «no tienes autoridad» que sería mentira. *Ausencia nunca es cero.*

---

## 5. Después de crear: entra sola

Se llama a `resolver()`. Con **una sola** empresa el gestor carga su contexto y entra
directo —no pregunta, que es la regla de E1-B—, así que la persona pasa del formulario al
escritorio de su empresa sin un clic de más.

Dos desenlaces que hay que respetar:

- **La empresa se creó y el contexto falla** (por ejemplo `402` de una suscripción
  restringida): se representa el fallo con «No se pudo abrir tu empresa» y su «Volver a
  intentar». **La empresa creada no se pierde ni se vuelve a ofrecer crear otra**, porque
  ya existe y un segundo intento gastaría capacidad.
- **La creación responde 201 y la lista sigue vacía**: imposible por construcción, y si
  pasara, el gestor cae en `SinAccesoACompanies` otra vez. Se registra en el log y se deja
  el mensaje de hoy; no se reintenta en bucle.

---

## 6. ⚠️ Dos defectos de E2 que esta etapa destapa, y que hay que arreglar aquí

Los dos están en `POST /organizations/{organizationId}/companies`, que es justo la ruta de
la que depende esta pantalla. **Los dos son míos**, y ninguno lo cazó la suite.

### 6.1 La razón social que se escribe al crear **se tira en silencio**

`EmpresasRepositorioHttp.crear` manda `legalName` en el cuerpo. El contrato del servidor
es `record CrearEmpresaRequest(string? Name, Guid? MaestroIdentityId)`: **no tiene ese
campo**, y `System.Text.Json` ignora las propiedades que le sobran sin decir nada. El
`INSERT` escribe `(id, organization_id, name, status)` y `legal_name` se queda **NULL**.

O sea: desde E2, el campo «Razón social (opcional)» del alta **existe, se escribe, se
envía y no se guarda**. No falla, no avisa, y sólo se nota al abrir el expediente y
encontrarlo vacío.

**Por qué no lo vio la suite:** las pruebas del alta afirman el `Outcome` y el nombre; que
`legal_name` quedara nulo era el estado esperado desde la `0050` —«ya existen empresas
creadas sin ninguno de estos datos»— así que no hay nada que contradiga.

**Arreglo propuesto, y es pequeño:** `CrearEmpresaRequest` gana `string? LegalName`, el
servicio lo valida como el expediente —nulo, o 1..250 tras recortar, que es lo que el
`CHECK company_legal_name_acotado` ya exige— y el `INSERT` lo escribe **en la misma
transacción** que la empresa y su Maestro. El evento de auditoría de la creación añade
`.Set("legalName", …)` **sólo cuando viene**; el máximo de 250 lo deja lejos del límite de
512 de `AuditPayload`, que es una deuda conocida y aquí no se roza.

**Lo que NO se hace:** ensanchar el record `Company` ni la respuesta del `POST`. La razón
social ya viaja en `GET /companies` y en el expediente; añadirla a un tercer sitio sería
una cuarta fuente del mismo dato.

### 6.2 Sin autoridad responde **400**, y tiene que ser **403**

E2 estrechó la puerta de esta ruta: ya no basta pertenecer a la Organization, hace falta
ser Owner o tener `companies.manage`. El servicio devuelve
`TenancyOutcome.AutoridadInsuficiente`… y el `switch` del endpoint no lo contempla, así
que cae en el `_ =>` y sale como **`400 entrada_invalida`**.

Rompe la norma de que **los motivos de denegación no se colapsan** —sin acceso 404, sin
permiso 403, módulo apagado 403, `restricted` 402— y además el cliente web espera el
código `autoridad_insuficiente`, que nunca llega: hoy acierta de casualidad, porque su
rama final muestra el mensaje del servidor y el mensaje sí es el correcto.

**Por qué no lo vio la suite:** la prueba que cubre este caso afirma
`TenancyOutcome.AutoridadInsuficiente` **en el servicio** y nunca cruza el endpoint. Las
rutas nuevas de E2 —desactivar, reactivar, descartar— sí mapean el outcome a 403; la vieja
de crear se quedó sin él.

**Arreglo:** la rama que faltaba, `403` con código `autoridad_insuficiente`, y una prueba
**de extremo a extremo** que pida la ruta con un miembro sin permiso y lea el **código de
estado**, no el outcome.

---

## 7. Lo que se programa

**Servidor** (sin migración):

1. `CrearEmpresaRequest` + servicio + `INSERT` + auditoría: `legalName` (§6.1).
2. El `403 autoridad_insuficiente` que falta (§6.2).

**Web:**

3. `EmpresasRepositorioHttp.listarOrganizaciones()` → `GET /organizations`. Va en ese
   repositorio y no en uno nuevo: es la lectura que responde «dónde puedo crear una
   empresa», y un archivo por método haría más ruido que orden.
4. El formulario de alta, extraído a su propio widget y compartido con E2.
5. `PrimeraEmpresaScreen`, con la estética de la antesala.
6. El portón: la averiguación de una sola vez en la rama `SinAccesoACompanies`, y las tres
   salidas —mensaje de hoy / formulario / mensaje + reintentar—.

**Pruebas:**

| # | Qué fija |
|---|---|
| 1 | Sin autoridad → el mensaje de hoy, **y ningún botón de crear** |
| 2 | Con autoridad de Owner → el formulario |
| 3 | Con `companies.manage` sin ser Owner → el formulario |
| 4 | **Falla la lectura de autoridad** → mensaje + «Volver a intentar», sin botón de crear |
| 5 | Nombre vacío → no se llama al servidor |
| 6 | Crear bien → el `POST` lleva `name` **y** `legalName`, y luego se pide `resolver()` |
| 7 | `409` → se muestra el mensaje del servidor **sin reescribirlo** |
| 8 | `402` → su mensaje, y el formulario sigue abierto |
| 9 | Dos Organizations con autoridad → se pregunta en cuál; una sola → no se pregunta |
| 10 | Una Organization sin `companies.manage` **no se lista** |
| 11 | **Servidor:** crear con `legalName` lo PERSISTE, y sale en `GET /companies` y en el expediente |
| 12 | **Servidor:** crear con `legalName` de 251 caracteres → 400, y con 250 → 201 |
| 13 | **Servidor:** miembro sin permiso → **403** y código `autoridad_insuficiente`, leyendo el `StatusCode` |
| 14 | **Servidor:** el evento `company.created` lleva `legalName` cuando se dio, y no la clave cuando no |

---

## 8. Lo que esta etapa NO hace

- **No crea Organizations.** Dar de alta un cliente es de SEVENTRA y vive en
  `POST /platform/organizations`, detrás de `platform_administrator`. Esta pantalla crea
  **empresas** dentro de una Organization que ya existe y ya está vendida.
- **No muestra el margen del plan** (§3), hasta que exista el lector de capacidad.
- **No elige al Maestro.** Lo será quien crea, como en E2: el servidor acepta otro, y
  resolver un correo a una identidad es una ruta que Administra no tiene.
- **No toca la ficha ni el expediente** (E1), ni la administración (E2) más allá de
  compartir el formulario.
- **No añade permisos ni migraciones**, así que el próximo despliegue al ensayo es
  **imagen sola**: sin respaldo-como-reversa, sin túnel y sin la ventana de riesgo entre
  migrar y desplegar.

---

## 9. Y una pregunta que dejo abierta a propósito

Cuando esta pantalla exista, el ensayo seguirá teniendo **cero empresas** hasta que alguien
la use. **¿La primera empresa del ensayo la creas tú desde esta pantalla, en cuanto esté
desplegada?** Es la mejor prueba que se le puede hacer —es literalmente su único caso de
uso— y de paso deja el ensayo en condiciones de probar el ciclo completo de E2 el día que
el plan dé para dos empresas.

---

## 10. Aprobado y construido — 22 de octubre de 2026

**Las tres decisiones, tal como se tomaron:**

- **(A) El estado vive en el portón.** `GestorDeCompany` responde lo mismo que antes y
  sus pruebas no se tocaron. El portón tiene un estado nuevo de cuatro casos
  —`_Buscando`, `_SinAutoridad`, `_SePuedeCrear`, `_NoSePudoPreguntar`— y no un par de
  banderas, porque «no sé todavía» no se puede confundir con «no puedes».
- **(a) El servidor acepta `legalName` al crear**, validado 1..250 y escrito en la misma
  transacción que la empresa y su Maestro. El evento de auditoría lleva la clave **sólo
  cuando se dio**: la ausencia es la ausencia de la clave, no un nulo que alguien lea
  después como «se la quitaron».
- **Sí**, la primera empresa del ensayo la crea el dueño desde esta pantalla.

**Y un detalle del camino feliz que conviene que conste:** al crear bien, el botón **se
queda girando** a propósito. La empresa ya existe y el portón está a punto de desmontar
la pantalla; devolver los campos a su estado editable durante ese instante invitaría a un
segundo clic, y un segundo clic crearía una segunda empresa. La consecuencia es que las
pruebas de ese camino avanzan **cuadro a cuadro** en vez de con `pumpAndSettle`, que
nunca termina frente a una animación infinita.

### Los dos defectos, arreglados y medidos

| Defecto | Arreglo | Lo que lo fija |
|---|---|---|
| `legalName` se tiraba en silencio | `CrearEmpresaRequest.LegalName` → servicio → `INSERT` → auditoría | Se crea con razón social y se vuelve a **leer** en las dos consultas que la pintan: la lista de accesibles y el expediente |
| Sin autoridad respondía `400` | La rama que faltaba: `403 autoridad_insuficiente` | Prueba por HTTP que lee el **código de estado**, con las dos mitades: niega sin el permiso y **crea** cuando el Owner lo concede |

**Por qué ninguna prueba los veía:** las de E2 afirman el `TenancyOutcome` que devuelve
el *servicio* y nunca cruzan el endpoint, así que el `switch` que traduce ese outcome a
un código HTTP no estaba cubierto por nada. La prueba vieja que cubría este caso tiene
ahora un aviso que apunta a la nueva, para que nadie vuelva a creer que el 403 está
probado ahí.

### La auditoría de los otros `_ =>`, que el dueño pidió

Se miraron los **veinte** `_ => Results.BadRequest` de la API, y para cada uno **qué
outcomes puede devolver de verdad el método que llama** —no qué miembros tiene el enum—.
**Diecinueve están bien**: a su rama final sólo le cae `EntradaInvalida` o
`InvalidInput`. El único hallazgo es **latente**:
`PlatformOutcome.NotPlatformAdministrator`, declarado y documentado como «hacia fuera,
403», **que nadie produce** y que saldría 400 el día que alguien lo devolviera. Queda
anotado en las deudas del backend con el arreglo estructural —el patrón de Gobierno, que
devuelve la autoridad por un canal propio y la traduce **antes** del `switch`—.

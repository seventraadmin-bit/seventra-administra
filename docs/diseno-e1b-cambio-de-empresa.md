# E1-B · Elegir y cambiar de empresa

**Diseño para aprobar antes de programar.** Pedido el 21 de octubre de 2026, al probar
E1 con dos empresas en `dev` por primera vez.

---

## 1. Qué pasó, y por qué el cambio es correcto

E1 se aprobó con **la lista de empresas como entrada** de Organización › Empresa: con
varias, se veía la lista; al tocar una fila se abría su expediente **y se cambiaba la
empresa activa**. Se programó así y funciona así.

Y en cuanto hubo una segunda empresa, apareció el problema de verdad: **consultar no es
cambiar.** Mirar la ficha de otra empresa movía el contexto de trabajo entero —menú,
permisos, barra inferior— sin que nadie lo hubiera pedido. El siguiente guardado habría
ido a la empresa que se estaba *mirando*, no a la que se estaba *usando*.

Esto no es un defecto de implementación: **es la decisión de E1 la que estaba mal.**
Juntaba dos verbos distintos en un gesto:

| Verbo | Qué espera quien lo hace | Dónde vive ahora |
|---|---|---|
| **consultar** una empresa | que no cambie nada | administración de empresas (**E2**) |
| **cambiar** de empresa | que cambie todo | la barra inferior, y sólo ahí |

Cambiar de empresa pasa a tener **un solo gesto en toda la aplicación**, y ese gesto
dice en voz alta lo que hace. El principio es el mismo que ya rige el resto del
producto: *la pertenencia manda el `company_id` real de la fila, nunca lo que la
interfaz insinúe.* Un selector que se mueve al pasear por una lista insinuaba.

> ⚠️ **Esto deshace trabajo de hace tres días, y hay que decirlo así.** La lista de
> E1, su paso `_Paso.lista` y las pruebas de pantalla que la cubren **se retiran** de
> esa pantalla y se rehacen en E2 con otro propósito. El documento de E1 no se reescribe
> para que parezca que siempre dijo esto: se le añade una nota de corrección con la
> fecha y el motivo.

---

## 2. Las tres superficies

```
                         ┌──────────────────────────────┐
  al entrar ────────────►│  A · «Elige una empresa»     │  pantalla completa
                         └──────────────────────────────┘
                                      │ elige
                                      ▼
                         ┌──────────────────────────────┐
                         │      la aplicación           │
                         │  ...                         │
                         │  ┌────────────────────────┐  │
                         │  │ C · Organización ›     │  │  sólo la ficha de
                         │  │     Empresa            │  │  LA ACTIVA
                         │  └────────────────────────┘  │
                         │  🏢 SEGURIDAD PRIVADA ⇅     │◄─ B · el menú, el
                         └──────────────────────────────┘    único cambio
```

---

## 3. A · «Elige una empresa», con la estética del login

**No «parecida» al login: la misma pieza.** `AuthIdentityPanel` es un
`StatelessWidget` puro que recibe dos textos, y ya lo comparten el login de la web y el
arranque del primer Maestro. Aquí se reutiliza con su propio mensaje de bienvenida.
Misma proporción **4 : 5**, mismo umbral de **900 px** para pasar a una zona.

### Ancho (≥ 900 px)

```
┌───────────────────────────────┬──────────────────────────────────────────────┐
│                               │                                              │
│  ▐▀▀▌ SEVENTRA                │   Hola, Marlon                               │
│  ▐▄▄▌ Administra              │   Elige una empresa                          │
│                               │   Tienes acceso a 2. Podrás cambiar después.  │
│                               │                                              │
│                               │  ┌────────────────────────────────────────┐  │
│                               │  │ ┌────┐ SEGURIDAD PRIVADA RISEG  ╭────╮ │  │
│         (palomita            │  │ │ 🏢 │ Riseg Seguridad Privada  │Últ.│ │  │
│          enorme y             │  │ └────┘ Cliente de prueba · Maestro vez│ │  │
│          tenue, cortada       │  │                                  ╰────╯ │  │
│          por el borde)        │  └────────────────────────────────────────┘  │
│                               │  ┌────────────────────────────────────────┐  │
│   Bienvenido a                │  │ ┌────┐ RISEG Servicios (prueba)        │  │
│   Seventra Administra         │  │ │ RS │ ·                            →  │  │
│                               │  │ └────┘ Cliente de prueba · Usuario     │  │
│   Elige con qué empresa       │  └────────────────────────────────────────┘  │
│   quieres trabajar.           │                                              │
│                               │          Entrar con otra cuenta              │
└───────────────────────────────┴──────────────────────────────────────────────┘
      flex 4, AppColors.tinta              flex 5, tarjetas máx. 440
```

**El saludo sale del nombre, y el nombre puede no venir.** `/auth/refresh` responde con
`displayName` nulo, así que una sesión restaurada no lo trae. Sin nombre **no hay línea
de saludo** — ni «Hola, » colgando, ni el correo de relleno.

**440 y no 380 como el login.** La tarjeta lleva un recuadro de logotipo de 44, tres
líneas de texto y una insignia; a 380 la razón social se parte en dos renglones en el
caso más común.

### Angosto (< 900 px)

El panel se va **entero**, no se encoge: igual que el login y por el mismo motivo —una
zona decorativa estrecha no dice nada—. Queda el logotipo arriba, el saludo, el título y
las mismas tarjetas.

---

## 4. La tarjeta de empresa: **una sola pieza**, dos tamaños

Se programa **una vez** y se usa en A y en B. Dos tarjetas distintas que se parecen
divergen en el primer arreglo.

```
  ┌────┐  Nombre comercial            ← AppTypography.body, w600, tinta
  │ 🏢 │  Razón social                ← caption, textMuted — SE OMITE si no hay
  └────┘  Organización · Rol          ← caption, textMuted
   44px
```

| Dato | De dónde sale | Hoy |
|---|---|---|
| Nombre comercial | `companyName` de `GET /companies` | ✅ ya viene |
| **Razón social** | `legal_name` de `app.company` | ❌ **falta en la respuesta** (§6) |
| Rol | `role` de `GET /companies` | ✅ ya viene (`maestro` \| `user`) |
| Organización | `organizationName` | ✅ ya viene |
| Logotipo | `GET /companies/{id}/logo` | ✅ ruta existente (§6) |

**La razón social no se rellena cuando falta.** Empresas creadas por Tenancy tienen
nombre y nada más, y la 0050 dejó `legal_name` nullable justamente por eso. Sin razón
social la tarjeta tiene **dos líneas**, no dos líneas y un hueco con «sin registrar»:
*ausencia nunca es cero*, y tampoco es un texto de disculpa en una pantalla de
bienvenida.

**El rol se escribe en palabras, no en vocabulario del modelo:** `maestro` → **Maestro**,
`user` → **Usuario**. El Maestro va en verde de marca, porque es el único que cambia lo
que se puede hacer ahí.

> 🔖 **Esto revierte una decisión escrita.** El selector actual dice en su comentario:
> «Lo que **no** se muestra es el rol —`maestro` o `user`—: es vocabulario del modelo de
> permisos, no algo que ayude a elegir». Con **una sola** empresa era cierto. Con dos en
> las que la misma persona es Maestra en una y usuaria en la otra, el rol **es** lo que
> distingue qué se puede hacer al entrar. El comentario se corrige con el motivo, no se
> borra.

### Las iniciales, cuando no hay logotipo

Dos letras de las dos primeras palabras del nombre comercial —«RISEG Servicios» → `RS`,
«Administración» → `AD`—, en blanco sobre un color **derivado del `companyId`** de una
paleta corta de la marca. Derivado del id y no del nombre: así renombrar una empresa no
le cambia el color, que es justo lo que la hace reconocible de un vistazo.

---

## 5. B · El menú de la barra inferior

La barra ya existe, ya tiene el icono `unfold_more` y ya tiene una acción enganchada.
**Lo que cambia es qué hace esa acción.**

Hoy llama a `olvidarSeleccion()`: borra la memoria y devuelve a la pantalla de
selección, desmontando la aplicación entera. Funciona, y es un portazo para algo que
debería ser un gesto pequeño.

```
                                 ┌─────────────────────────────────────┐
                                 │  TUS EMPRESAS                       │
                                 ├─────────────────────────────────────┤
                                 │ ┌──┐ SEGURIDAD PRIVADA RISEG     ✓ │
                                 │ │🏢│ Maestro                       │
                                 │ └──┘                               │
                                 │ ┌──┐ RISEG Servicios (prueba)      │
                                 │ │RS│ Usuario                       │
                                 │ └──┘                               │
                                 └─────────────────────────────────────┘
                                                  ▲ se abre HACIA ARRIBA
  ┌──────────────────────────────────────────────────────────────────────┐
  │ 🏢 SEGURIDAD PRIVADA RISEG  ⇅                                        │
  └──────────────────────────────────────────────────────────────────────┘
```

- **la misma tarjeta, en dos líneas:** logotipo o iniciales, nombre comercial y rol. Sin
  razón social: aquí no se está eligiendo entre desconocidas, se está cambiando entre
  las propias;
- **la activa se marca con ✓ y no se puede pulsar.** Cambiar a la que ya está sería un
  viaje al servidor y un aviso para no mover nada;
- **se abre hacia arriba**, porque la barra vive al pie del área de contenido;
- **con una sola empresa no hay menú**, igual que hoy: la barra es texto plano. El
  `unfold_more` sólo aparece cuando hay a dónde ir.

### Al elegir

```
  ¿hay cambios sin guardar en la pantalla de ahora?
        │
        ├── sí  ─► «Hay cambios sin guardar. ¿Cambiar de empresa y perderlos?»
        │            └── cancelar ─► no pasa NADA: ni menú abierto, ni cambio
        │
        └── no  ─► cambiarA(id)
                     ├── falla ─► la empresa anterior sigue activa, con el motivo
                     └── ok    ─► se publica el contexto nuevo, se RECUERDA,
                                  y sale «Ahora trabajas en SEGURIDAD PRIVADA RISEG»
```

El aviso es `RisegFeedback.showSuccess`, que ya existe y ya está en el barrel web.

### El guardia de cambios sin guardar

Hoy esa pregunta vive **dentro** de la pantalla de Empresa (`_seguroDeSalir`), y el
marco no sabe nada de ella. Para que la barra pueda preguntar hace falta una pieza
pequeña y explícita:

```
  GuardiaDeSalida            el marco lo crea y lo pasa hacia abajo
    ├─ registrar(bool Function() hayCambios) → se llama en initState
    └─ liberar()                              → se llama en dispose
```

**Sin nadie registrado, no hay cambios.** Es la postura segura en el sentido correcto:
una pantalla que olvide registrarse deja de proteger su formulario —se nota y se
arregla—, mientras que un guardia que se quede pegado tras un `dispose` bloquearía el
cambio de empresa para siempre y parecería un cuelgue. Es la misma forma que E1 ya usa
con `alVigilarCambios`, subida un nivel.

---

## 6. C · Organización › Empresa: sólo la ficha de la activa

```
  ANTES (E1)                           AHORA
  ┌─────────────────────────┐          ┌─────────────────────────┐
  │ Empresas (2)            │          │ SEGURIDAD PRIVADA RISEG │
  │  ▸ SEGURIDAD PRIVADA ●  │          │  ─────────────────────  │
  │  ▸ RISEG Servicios      │   ──►    │  RFC   XAXX010101000    │
  └─────────────────────────┘          │  Razón social   ...     │
         │ toca una                    │  Régimen  601 · General │
         ▼ CAMBIABA LA ACTIVA          │                         │
  ┌─────────────────────────┐          │     [Editar]  [Copiar]  │
  │ la ficha                │          └─────────────────────────┘
  └─────────────────────────┘           la ficha, directa, siempre
```

- **entra directo a la ficha**, con una empresa o con veinte;
- **desaparecen** el paso de lista, la fila que cambiaba de empresa y la pregunta «hay
  cambios sin guardar» *asociada a cambiar de empresa desde aquí* — esa pregunta se
  conserva, pero ahora la hace el guardia del marco;
- **se conserva entero** todo lo demás de E1: ficha fiscal, Copiar datos, ⧉ por dato,
  Editar con el logotipo y la vista previa, el 409 con `current`, la vista que sigue al
  foco;
- el título de la ficha ya dice qué empresa es, y ahora **no puede mentir**: es siempre
  la activa.

### Lo que se va a E2

| Qué | Dónde queda |
|---|---|
| lista de todas las empresas, con su estado | **E2 · Administración de empresas** |
| crear, desactivar, reactivar, eliminar | **E2** (ya aprobado, con permiso nuevo y migración) |
| ver la ficha de una empresa **sin** cambiar la activa | **E2** — y es trabajo nuevo: hoy no existe ningún camino que lea el expediente de otra empresa sin activarla |

El `estado` que E1 añadió a `CompanyDisponible` **se queda donde está**: nació
precisamente para no rehacer la lista en E2, y ese argumento no cambia porque la lista
se mude de pantalla.

---

## 7. Lo que falta en el servidor

Una sola cosa, y es pequeña:

**`GET /companies` no devuelve la razón social.** La consulta ya trae
`c.id, c.organization_id, c.name, o.name, a.role, c.status` de las mismas tres tablas;
`legal_name` es **otra columna de `app.company`**, la misma fila del `JOIN` que ya
está. Es una columna en el `SELECT`, un campo en la respuesta y un campo nullable en el
modelo del cliente.

- **sin migración.** La 0050 ya creó la columna;
- **sin permiso nuevo.** Quien recibe la lista ya tiene acceso a esas empresas;
- **nullable en el contrato**, porque lo es en la base. Exigirlo rompería el login contra
  un servidor viejo, que es exactamente el precio que no se pagó con `status`.

**El logotipo no necesita nada nuevo.** `GET /companies/{id}/logo` existe y se autoriza
**por acceso, no por permiso de módulo** —su propio código lo argumenta: «es visual, no
un dato reservado, y inventar un permiso para mirarlo habría sido [excesivo]»—. Así que
el selector puede pedirlo para cualquier empresa de su lista, incluso antes de entrar en
ella.

- **una petición por empresa, en paralelo, y la tarjeta no espera:** nace con las
  iniciales y cambia al logotipo cuando llega. Nada parpadea vacío;
- **404 `logo_missing` no es un fallo**, igual que en E1: es «no tiene», y se queda con
  las iniciales;
- **se guardan en memoria mientras la sesión viva**, para que abrir el menú de la barra
  cinco veces no sean cinco rondas de descargas.

---

## 8. ✅ DECIDIDO: se pregunta siempre con varias empresas

**El dueño aprobó la opción (a) el 21 de octubre de 2026:** con varias empresas se
pregunta siempre, la recordada marcada «Última vez» y de primera; **con una sola no se
pregunta**. Queda abajo el razonamiento completo, incluido lo que costó, porque es lo
que explica por qué la pantalla se ve en cada inicio de sesión.

### El choque que lo hizo necesario

Pediste marcar la última empresa usada y recordarla. **Recordarla ya funciona.** Lo que
choca es lo otro, y lo descubrí leyendo el motor:

> Con varias empresas, si hay una recordada **y sigue en la lista, se entra directo a
> ella**. La pantalla «Elige una empresa» no se muestra.

Así que, tal como está hoy, la insignia «Última vez» **no se vería nunca**: cuando hay
memoria no hay pantalla, y cuando hay pantalla no hay memoria. La viste aparecer esta
vez porque acababas de crear la segunda empresa y todavía no había nada recordado; en
cuanto elijas una, el próximo inicio de sesión entrará solo.

| | Qué | Qué se gana | Qué cuesta |
|---|---|---|---|
| **(a)** | **Preguntar siempre** con varias empresas, con la recordada marcada «Última vez» y primera | entrar es siempre deliberado, la insignia tiene sentido, y es coherente con lo que acabas de pedir: que nada cambie de empresa sin que lo busques | **un toque más en cada inicio de sesión** para quien tiene más de una |
| **(b)** | Dejar la entrada automática y mostrar «Última vez» sólo cuando la pantalla aparezca | nada cambia en tu rutina diaria | la insignia es casi decorativa; la pantalla rediseñada casi no se ve |
| **(c)** | Entrada automática, pero con un aviso «Entraste en X · Cambiar» los primeros segundos | rápido **y** visible | una cosa más que aparece y se va; y si no se alcanza a leer, no sirve |

**Recomendé (a) y es la aprobada.** Un toque al día contra la certeza de saber dónde
estás escribiendo, en un producto donde el `company_id` equivocado es un dato en la
empresa del cliente ajeno. Y con una sola empresa **nada cambia**: se entra directo,
como hoy.

---

## 9. Reparto y orden

| | Qué | Dónde |
|---|---|---|
| **E1-B.1** | `legalName` en `GET /companies` | backend · sin migración |
| **E1-B.2** | la tarjeta de empresa, el recuadro de logotipo y las iniciales | web · pieza compartida |
| **E1-B.3** | «Elige una empresa» en dos zonas, con saludo y «Última vez» | web |
| **E1-B.4** | el menú de la barra inferior, el guardia de salida y «Ahora trabajas en X» | web |
| **E1-B.5** | Organización › Empresa: sólo la ficha; retirar la lista y sus pruebas | web |
| **E2** | administración de empresas: la lista, crear, desactivar, reactivar, eliminar | backend + web, con permiso y migración |

**E1-B.1 va primero** porque las tarjetas sin razón social se verían a medias, y
programar la pantalla contra un campo que no existe obligaría a tocarla dos veces.
Ningún paso deja la aplicación sin poder cambiar de empresa: el camino viejo
—`olvidarSeleccion()`— sigue en pie hasta que E1-B.4 lo sustituye.

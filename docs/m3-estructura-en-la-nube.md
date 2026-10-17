# M3 — Áreas, puestos y sucursales contra la API

**Las tres pantallas más pequeñas de Administra, leyendo y escribiendo en la nube.** Son la
dependencia de todo Personal, y por eso van primero: prueban la plomería completa —sesión,
empresa, permisos, 402, auditoría— con datos de verdad y con el dominio más simple que hay.

**Orden: la migración primero, las pantallas después.** Lo que falta en el motor no se
suple en la pantalla.

---

## 0 · Lo que se midió en los datos reales de RISEG, antes de decidir nada

Se leyó una **copia** de `RISEGONE/riseg_one.sqlite` —nunca la base viva— para que la
importación no pierda nada y para que los nombres que se pongan en pantalla no mientan.

### 🔴 La numeración de niveles está AL REVÉS de lo que se supuso

La propuesta inicial era «1 Dirección … 7 Operativo». **En RISEG es lo contrario: 1 es el
más bajo y 10 el más alto.**

| Nivel | Puesto real | Tipo |
|---|---|---|
| **1** | Elemento Operativo | operativo |
| **2** | Jefe de Turno | operativo |
| **3** | Jefe de Servicio | operativo |
| **4** | Auxiliar *(en Recursos Humanos)* | administrativo |
| **4** | Auxiliar *(en Administración)* | administrativo |
| **5** | Monitorista | operativo |
| **5** | Supervisor de Zona | operativo |
| **6** | Coordinador Operativo | operativo |
| **7** | Gerente Operativo | operativo |
| **7** | Gerente en Recursos Humanos | administrativo |
| **10** | DIRECCION GENERAL | administrativo |

**Si se hubieran aplicado los nombres propuestos, los once puestos habrían quedado mal
etiquetados**: «Elemento Operativo» se mostraría como «Dirección», y «DIRECCION GENERAL» se
quedaría sin nombre porque 8–10 iban libres. Por eso la pregunta se contestó mirando los
datos y no la memoria.

### Tres cosas más que los datos dicen y conviene saber

- **El 8 y el 9 están vacíos**, y el 10 salta directo a Dirección General. El salto es
  deliberado de quien capturó: deja hueco para crecer.
- **La escala no es una jerarquía limpia.** «Auxiliar» (4, administrativo) está **por debajo**
  de «Monitorista» y «Supervisor de Zona» (5, operativos). Conviven dos carreras —la
  administrativa y la operativa— en una sola recta numérica.
- **«Auxiliar» aparece dos veces con el mismo nombre**, en Recursos Humanos y en
  Administración. El nombre **no identifica** el puesto; hace falta el área al lado. Es el
  mismo defecto que los adicionales duplicados de Console.

### Sucursales: hay UNA, y no hay ninguna Bodega

| Sucursal | Tipo | Estado operativo |
|---|---|---|
| Toluca | Base Operativa | operando |

**Retirar «Bodega» de los tipos recomendados no cuesta nada**: la fila existe en el catálogo
sembrado, pero **ninguna sucursal la usa**. No hay nada que reasignar al importar.

### Áreas: hay SEIS, y dos no tienen puestos

`Administración` · `Dirección` · **`Monitoreo`** · `Operaciones` · **`Reclutamiento`** ·
`Recursos Humanos`

Monitoreo y Reclutamiento existen sin ningún puesto colgando. No es un error: un área puede
existir antes de tener plazas.

### ⚠️ El código de un área hoy NO lo escribe el cliente

Se decidió que «el código lo escribe el cliente y se muestra pequeño y en gris». **En RISEG
el código del área es un folio generado**: `ARE-0001`, `ARE-0002`… Encaja en el formato que
la nube exige (`^[A-Z0-9_-]{1,32}$`), así que **la importación los trae intactos**, pero hay
que decidir qué pasa en la nube:

- **A** — el cliente lo escribe (`OPERACIONES`), y los importados conservan su `ARE-0001`.
- **B** — se sigue generando como folio, y el cliente no lo ve ni lo escribe.

### ✅ DECIDIDO el 17 de octubre de 2026 — opción A

**El cliente escribe el código, y las áreas importadas conservan su `ARE-xxxx`.** La nube ya
trata el código como dato del cliente —la ruta lo exige en el `POST`— y un folio generado por
área no aporta nada que el nombre no diga.

**Los importados NO se renombran:** un código es una identidad, y reescribirla rompería
cualquier referencia en papel.

**Único por empresa**, y el mensaje de choque va en lenguaje simple: *«Ya existe un área con
el código OPERACIONES. Los códigos no se repiten dentro de una empresa.»* No «violación de
restricción única», que es lo que diría el motor si nadie lo traduce.

---

## 1 · La migración (0048), antes de cualquier pantalla

Tres huecos medidos entre lo que el producto local guarda y lo que la nube tiene.

### 1.1 El puesto gana descripción y nivel

```sql
ALTER TABLE app.position
  ADD COLUMN description     text,
  ADD COLUMN hierarchy_level int;
```

- `description` acotada a 500 y opcional — en los datos reales está **vacía en todas las
  filas**, así que es un campo que existe y nadie usa todavía. Se conserva porque se decidió
  conservarlo, no porque los datos lo pidan.
- `hierarchy_level` **1–10** por `CHECK`, el mismo rango que el validador local.

**`hierarchy_level` entra NULLABLE y eso hay que justificarlo.** En el producto local es
obligatorio, pero en la nube ya existen puestos creados por las pruebas y por el ensayo sin
ese dato. Ponerlo `NOT NULL` exigiría inventarles un nivel, y **ausencia nunca es cero** —ni
uno—. Lo que sí se hace es exigirlo **en la ruta** para todo puesto nuevo: el dato es
obligatorio hacia adelante y desconocido hacia atrás, que es la verdad.

### 1.2 El catálogo de tipos de sucursal, por EMPRESA

Tabla nueva, Company-owned con todo lo que eso implica en este motor: `company_id` +
`organization_id`, **FK compuesta** a `company (id, organization_id)`, ancla
`UNIQUE (company_id, id)` y **RLS con `USING` y `WITH CHECK`**.

```sql
CREATE TABLE app.branch_type (
  id              uuid NOT NULL PRIMARY KEY,
  company_id      uuid NOT NULL,
  organization_id uuid NOT NULL,
  code            text NOT NULL,
  name            text NOT NULL,
  status          text NOT NULL DEFAULT 'activa',
  ...
);
```

**NADA SE SIEMBRA.** Es la misma decisión que las modalidades de turno de la 5D.10D:
sembrar al crear la empresa obligaría a Tenancy a conocer un catálogo de Personal. Una
empresa nueva nace con **cero tipos**, y la pantalla ofrece **«Agregar tipos
recomendados»** — tres de un clic:

| Código | Nombre |
|---|---|
| `OFICINA_ADMIN` | Oficina administrativa |
| `BASE_OPERATIVA` | Base operativa |
| `ZONA_SUPERVISION` | Zona de supervisión |

**«Bodega» no va**, y los datos respaldan la decisión: ninguna sucursal la usa. ✅ Decidido el
17 de octubre de 2026: **no se crea**.
**«Zona de supervisión» es nueva** —no existe en el local— y por eso ninguna sucursal
importada caerá en ella; se añade porque describe algo que la operación sí tiene.

**Lo que el botón crea es de la empresa desde el primer minuto.** Una fila sembrada por el
sistema invita a preguntarse si se puede borrar; una que alguien creó con un clic, no.

### 1.3 La sucursal gana tipo y estado operativo

```sql
ALTER TABLE app.branch
  ADD COLUMN branch_type_id     uuid,
  ADD COLUMN operational_status text NOT NULL DEFAULT 'operando';
```

**La FK es de DOS columnas** —`(company_id, branch_type_id)`— contra el ancla del catálogo:
una sucursal no puede apuntar a un tipo de otra empresa ni conociendo su UUID, y eso no lo
comprueba ningún `if`.

```sql
CONSTRAINT branch_operational_status_valido
  CHECK (operational_status IN ('operando', 'cerrada_temporalmente'))
```

**DOS valores, no tres.** El `enum` del producto local tiene exactamente éstos
(`EstadoOperativoSucursal { operando, cerradaTemporalmente }`), y **una sucursal cerrada
para siempre se marca `status = 'inactiva'`**, no con un tercer estado operativo.

#### Por qué los dos datos no se colapsan

| | Qué responde |
|---|---|
| `status` activa/inactiva | **¿se puede usar en el sistema?** Una inactiva no aparece en los selectores |
| `operational_status` | **¿está abierta hoy?** Una activa puede estar cerrada por obra y seguir siendo elegible mañana |

Meterlos en una sola columna obligaría a elegir entre perder «esta sucursal existe pero hoy
no opera» o inventar un estado que signifique las dos cosas.

**`branch_type_id` entra NULLABLE** por el mismo motivo que el nivel: hay sucursales ya
creadas sin tipo, y el catálogo del que elegirlo todavía no existe en ninguna empresa.
Obligatorio en la ruta para toda sucursal nueva.

### 1.4 Lo que la migración NO hace

- **No siembra tipos.** Ver 1.2.
- **No rellena niveles.** Ver 1.1.
- **No añade `orden` ni `descripcion` al área.** El local las tiene y están **vacías en las
  seis filas reales**. Traer una columna que nadie llena es deuda, no previsión.

### 1.5 Pruebas

Estructurales en crudo, como M1 y M2: el rango 1–10 rechazado por fuera, el estado operativo
fuera de catálogo rechazado, un tipo de **otra empresa** rechazado por la FK de dos
columnas, RLS en la tabla nueva, y los tipos recomendados **no** sembrados por la migración.
Más las mutaciones de cada regla, y la suite completa en verde antes de un solo commit.

---

## 2 · La app web, junto a la de escritorio

**El repositorio sólo tiene la plataforma `windows`.** No existe carpeta `web/`, así que el
primer paso de M3 es crearla.

**Dos puntos de entrada, una sola `lib/`:**

| | |
|---|---|
| `lib/main.dart` | el escritorio, **intacto**. Ya no está en uso diario |
| `lib/main_web.dart` | la app nueva. Entra, elige empresa, y por ahora **sólo** estructura |

### ⚠️ CORREGIDO el 17 de octubre de 2026 — el motivo real, y no es el que estaba escrito

Aquí decía que los dos puntos de entrada existían para no romper el escritorio del cliente
piloto. **Las dos mitades de esa frase eran falsas.**

**El escritorio NO está en uso diario.** Se usó como prueba —con datos reales de la
operación, que siguen cargados— y se dejó al empezar SEVENTRA; en paralelo la operación se
lleva en Excel. No necesita protección: basta con que no estorbe a la web.

**Y el motivo técnico es otro, medido:** `flutter build web` falla con **`dart:ffi`**, no con
`dart:io`. Viene del **SQLite nativo** a través del grafo de `lib/main.dart`, así que ese
archivo **nunca** compilará para web mientras Drift esté dentro. Eso sería verdad aunque el
escritorio no existiera.

**`dart:io` es el problema de DESPUÉS**, y es más pequeño: está en 43 archivos, la mayoría de
`respaldo`, `reportes` y PDF. De todo `lib/core`, la web sólo tropezaba con **uno** —
`api_client.dart`, y sólo por una pregunta de tipo—. Ya está resuelto con importación
condicional, sin cambiar nada en escritorio.

**Lo que sigue en pie es la decisión**, no su justificación: convertir todo de golpe
obligaría a M3 a arrastrar una limpieza que no le toca.

**La prueba de arquitectura dirige esto**, y es el mecanismo que ya existe: una prueba que
prohíbe `dart:io` **en los archivos que la app web alcanza**, apretada etapa a etapa. El día
que la lista de excepciones esté vacía, la mudanza terminó y el escritorio se retira.

> ⚠️ **`flutter create --platforms=web` REEMPLAZA la lista de plataformas, no la amplía.**
> Dejó `.metadata` con `web` en lugar de `windows`, y hubo que devolver las dos. El
> escritorio habría seguido compilando —así que nadie lo nota— pero `flutter migrate`
> dejaría de saber que existe. También crea `test/widget_test.dart`, la prueba del contador
> de la plantilla: se borra.

---

## 3 · Las pantallas

### 3.1 Cómo se ven

Lo aprobado en Console, porque ya está probado: **verde de marca `#1E7F45`**, **una sola
etiqueta de estado** con sus cuatro familias y su ícono, y las reglas de redacción —ningún
código interno a la vista, frases cortas de negocio, lo que se elige de una lista no se
escribe a mano—.

**Pero Administra no es Console, y la diferencia manda.** Console la usa una persona que
conoce la plataforma. Administra la usa el **personal administrativo de un cliente de
seguridad privada**. De ahí:

- **Listas, no tablas densas.** Nombre grande; debajo, **el código pequeño y en gris** —lo
  decidido— y lo secundario.
- **Un botón principal por pantalla**, arriba a la derecha: «Nueva área».
- **Formularios en panel lateral**, no en diálogo modal centrado: el modal se siente viejo
  en web y se rompe en pantallas pequeñas.
- **Vacíos que explican.** Nunca una tabla vacía con encabezados.
- **Errores en el campo**, no en una barra roja arriba.

> ⚠️ **Y una regla que viene del propio producto:** en los formularios, **liberar los
> controllers** al cerrar. `Future.delayed(300ms)` está **prohibido** — ya costó una vez.

### 3.2 Áreas

Lo más simple: nombre, código en gris, estado. Alta y edición en panel lateral.

**Vacío:** «Todavía no hay áreas. Un área agrupa puestos, por ejemplo Operaciones o
Administración.»

### 3.3 Puestos

**El nivel se muestra con NOMBRE, no con `N3`.** Hoy la pantalla pinta una píldora gris que
dice `N3` y nadie sabe qué significa.

**El catálogo de niveles es por empresa**, igual que los tipos de sucursal, con su botón
**«Agregar niveles recomendados»**. La lista propuesta sale de los datos reales, con la
numeración **en el sentido correcto**:

| Nivel | Nombre propuesto | Puestos reales que caen aquí |
|---|---|---|
| 1 | Operativo | Elemento Operativo |
| 2 | Jefatura de turno | Jefe de Turno |
| 3 | Jefatura de servicio | Jefe de Servicio |
| 4 | Administrativo | Auxiliar (×2) |
| 5 | Supervisión | Monitorista · Supervisor de Zona |
| 6 | Coordinación | Coordinador Operativo |
| 7 | Gerencia | Gerente Operativo · Gerente en Recursos Humanos |
| 8 | *libre* | — |
| 9 | *libre* | — |
| 10 | Dirección | DIRECCION GENERAL |

**Cada puesto real queda con un nombre que le corresponde, y 8 y 9 quedan libres** como
están hoy.

> ✅ **APROBADA el 17 de octubre de 2026**, con la numeración en este sentido: **1 es el más
> bajo y 10 el más alto**, como está en los datos. Y porque «Auxiliar» aparece dos veces,
> **junto al puesto se muestra SIEMPRE el área**.

**El área va SIEMPRE al lado del nombre del puesto**, y no es decoración: hay dos
«Auxiliar», y sin el área no se distinguen.

**Vacío:** «Todavía no hay puestos. Un puesto es el cargo de una persona, por ejemplo
Guardia de seguridad o Jefe de turno.»

### 3.4 Sucursales

Nombre, código en gris, **tipo**, y **dos estados** que se ven distintos porque responden
cosas distintas:

| | Cómo se ve |
|---|---|
| Activa | verde con palomita · Inactiva en gris |
| Operando / Cerrada temporalmente | **ámbar** cuando está cerrada, porque es temporal y alguien tiene que volver a abrirla |

**Vacío:** «Todavía no hay sucursales. Una sucursal es un destino administrativo: una
oficina, una base. El destino operativo de una persona es un servicio, no una sucursal.»

Esa última frase está ahí a propósito: es **la regla que no se reinterpreta**, dicha donde
alguien podría equivocarse.

---

## 4 · Lo que M3 NO es

- **No toca Personal**: ni empleados, ni asignaciones, ni sueldos. Eso es M4 y M5.
- **No importa datos de RISEG.** La importación es etapa propia, antes del piloto. Aquí se
  **leyeron** los datos locales para decidir bien, y nada se escribió en ninguna parte.
- **No retira el escritorio.** Se queda compilando y funcionando mientras la web crece
  módulo a módulo, pero **no porque alguien lo use a diario** —no lo usa nadie—: porque
  retirarlo antes de que la web cubra los catorce módulos dejaría sin acceso a los datos
  reales que tiene cargados.
- **No crea pantalla de servicios.** Un servicio es el destino **operativo** y vive en
  Comercial, no en estructura.

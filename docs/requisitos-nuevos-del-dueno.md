# Requisitos nuevos del dueño — lo que RISEG ONE **no** hacía

**Qué es este documento.** La mudanza tiene una regla: *no se pierde ninguna función del
escritorio*. Este archivo es la otra mitad — **lo que el dueño pide y el escritorio nunca
tuvo**, anotado el día que se pide y no el día que toca construirlo.

Existe porque un requisito nuevo es más fácil de perder que una función vieja: una función
que falta se nota al comparar contra el escritorio, y **un requisito nuevo no se nota
contra nada**.

> Cada renglón dice **qué**, **por qué**, **quién lo consume** y **cuándo se construye**.
> Lo que no diga «✅ hecho» está pendiente, y el inventario de su apartado lo recoge
> cuando le toca.

---

## 1 · COPIAR DATOS — la pieza común, tres consumidores

**Pedido el 19 de octubre de 2026.** El escritorio tiene **un** «Copiar datos»: el de la
tarjeta fiscal de la Empresa. El dueño quiere lo mismo para el **Cliente** y para el
**Personal**, y **con la misma función de formato**.

### Por qué es una pieza común y no tres botones

Porque el escritorio ya aprendió esta lección en pequeño y la dejó escrita en
`tarjeta_fiscal_data.dart`:

> «función pura, **única fuente de este formato** para no tener 3 formatos ligeramente
> distintos entre pantalla, PDF y portapapeles.»

Eso fue por **tres salidas de un mismo dato**. Ahora serían **tres consumidores**, cada
uno con sus salidas: si cada apartado escribe su propio formato, el RFC de la empresa, el
del cliente y el del empleado se pegarían distinto, y quien los recibe no sabría que son
el mismo sistema.

### Los tres consumidores, y qué pide cada uno

| Consumidor | En bloque | Dato por dato |
|---|---|---|
| **Empresa** · tarjeta fiscal | ✅ **ya existe** | ⏳ falta el ícono por dato |
| **Cliente** y cada **entidad fiscal** | razón social · RFC · **régimen fiscal** · domicilio fiscal con CP · **uso de CFDI** · correo de facturación · teléfono | RFC, CP y cada campo suelto |
| **Personal** · expediente del empleado | CURP · RFC · NSS · CLABE · nº de cuenta · banco · dirección · teléfono | cada uno |
| **Nómina** · dispersión | **varios empleados a la vez**: nombre · banco · CLABE · importe, **en formato que se pegue en Excel o en el portal del banco** | — |

### 🚫 LO QUE NO SE PUEDE REINTERPRETAR

**1 · Los permisos protegidos valen también para copiar.**

> «Quien no puede **ver** datos bancarios o el expediente sensible, **tampoco puede
> copiarlos**, ni le aparece el botón para esos campos.»

No es una regla de pantalla: copiar es **leer**, y leer un dato protegido exige su permiso
protegido. Esconder el botón es cortesía; **la autorización la decide el servidor**, igual
que en la eliminación física. Un «Copiar datos» que arme el bloque en el cliente a partir
de lo que ya cargó la pantalla **se salta la regla sin querer** — así que el bloque de
datos protegidos lo tiene que armar quien autoriza.

**2 · Copiar un dato bancario o sensible queda en AUDITORÍA.**

Quién, **de qué empleado**, qué dato y cuándo — y en lenguaje simple, como el resto de la
auditoría. Es el único caso del proyecto donde **leer** se audita, y tiene su razón: un
dato bancario copiado sale del sistema y ya no hay rastro de dónde fue.

⚠️ **Esto necesita un verbo nuevo** —del orden de `copied`— y su traducción, **y su prueba
de cobertura de verbos**: es exactamente el hueco por el que se colaron «Closed» y
«Reopened» en inglés.

**3 · La dispersión es otro formato, no el mismo.**

El bloque de la tarjeta fiscal se pega en un correo; el de la dispersión se pega en
**Excel o en el portal del banco**, que quiere columnas separadas por tabulador y sin
adornos. **Son dos salidas de la misma pieza**, no dos piezas — igual que la tarjeta
fiscal tiene pantalla, PDF y portapapeles con un solo formateador.

### Cuándo se construye

| Parte | Cuándo |
|---|---|
| La **pieza común** | Se diseña **una vez**, pensando en los tres, antes del primer consumidor nuevo |
| Cliente y entidad fiscal | Al mudar **Comercial** |
| Empleado | Al mudar **Personal** |
| Dispersión en bloque | Al mudar **Nómina** |
| Ícono por dato en la tarjeta de la empresa | Con el expediente de Empresa |

---

## 2 · ⚠️ RÉGIMEN FISCAL Y USO DE CFDI DEL CLIENTE — **choca con una decisión congelada**

**Esto no es un hueco: es una colisión, y hay que decidirla a sabiendas.**

El dueño pide que del Cliente **sí** se guarden `régimen fiscal` y `uso de CFDI`, porque
son los datos con los que se le factura.

**Y el servidor ya decidió lo contrario, por escrito**, en la 0018 (5D.10C):

> `COMMENT ON TABLE app.fiscal_entity` — «Razon social con la que se factura a un Cliente.
> N:1 con Client. **Sin regimen ni uso de CFDI: eso es Facturacion.**»

Lo que `fiscal_entity` tiene hoy, medido: `legal_name`, `tax_id` (el RFC, **nullable**),
`status`, `notes`, su domicilio 1:1 en `fiscal_entity_address` y sus documentos.

### Las dos salidas, y qué cuesta cada una

| | |
|---|---|
| **Añadirlos a `fiscal_entity`** | Revierte la decisión de 5D.10C, igual que la 0049 revirtió el `DELETE` de la 0011 — **se puede, con argumento escrito**. El argumento existe y es el mismo que el dueño usó para la empresa: con **CFDI 4.0** el emisor necesita del receptor RFC, razón social, régimen y CP del domicilio fiscal. Si nosotros facturamos al cliente, nosotros somos el emisor |
| **Esperar a 5D.11** | Respeta la frontera, pero deja el «Copiar datos fiscales del cliente» **incompleto** hasta entonces — y el requisito nace precisamente para poder facturar |

**Se decide al mudar Comercial, no antes**, y con las dos cosas delante. Lo que no puede
pasar es que se añadan las columnas sin que nadie note que había una decisión en contra.

### Y una asimetría deliberada, para que no se lea como incoherencia

| | Régimen fiscal | Uso de CFDI |
|---|---|---|
| **Empresa** (nos facturan) | **SÍ** | **NO** — «eso lo elige quien factura» |
| **Cliente** (le facturamos) | **SÍ** | **SÍ** |

No es un descuido: la tarjeta fiscal de la empresa se **entrega** para que otro emita, y
quien emite elige el uso. Del cliente lo necesitamos **nosotros** para emitir.

---

## 3 · El catálogo del régimen fiscal es el del SAT, no texto libre

Decidido el 19 de octubre de 2026, junto con el régimen de la Empresa: **selección del
`c_RegimenFiscal` del SAT**, nunca un campo de texto.

Y un dato medido que lo hace más fácil: **el RFC ya dice si es persona física o moral**
—12 caracteres = moral, 13 = física— así que la lista se puede filtrar **sin preguntar
nada nuevo**.

> **Filtro y aviso, NO regla que bloquee.** Es la filosofía que el propio validador del
> escritorio declara: «validación conservadora… **no sustituye la validación fiscal del
> SAT**». Bloquear por longitud rechazaría un caso legítimo raro; filtrar con un aviso, no.

⏳ **Pendiente de decidir: dónde vive el catálogo.** No es per-empresa —la lista del SAT es
la misma para todos—, así que **no** puede ser una tabla Company-owned como `branch_type`.

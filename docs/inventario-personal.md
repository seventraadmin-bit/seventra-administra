# Inventario de Personal — abierto

**Estado: PENDIENTE.** Existe porque hay requisitos anotados **antes** de que al apartado
le toque, y un requisito sin archivo donde vivir es un requisito que se pierde.

> **Personal SaaS está CERRADO en el backend** —`Person`, `Employee`,
> `EmploymentPeriod`, `EmployeeAssignment`, estructura, historial, documentos, expediente
> sensible, ficha técnica y ciclo laboral— y **no se reabre**. Lo que falta es la
> **pantalla web**, y es el apartado más cruzado del producto: su baja escribe en cinco
> módulos en una sola transacción.

---

## Renglones ya decididos

### 1 · 🆕 Copiar los datos del empleado

**Requisito nuevo del dueño, 19 de octubre de 2026. No existe en el escritorio** — hoy
las cuentas se anotan a mano, que es exactamente de donde salen los errores de dispersión.

| | |
|---|---|
| **En bloque** | Un botón «Copiar datos» en el expediente |
| **Dato por dato** | Ícono junto a CURP · RFC · NSS · **CLABE** · nº de cuenta · banco · dirección · teléfono |
| **El formato** | **La misma función** que la tarjeta fiscal de la Empresa y los datos fiscales del Cliente |

### 2 · 🚫 LOS PERMISOS PROTEGIDOS VALEN TAMBIÉN PARA COPIAR

> «Quien no puede **ver** datos bancarios o el expediente sensible, **tampoco puede
> copiarlos**, ni le aparece el botón para esos campos.»

**Copiar es LEER.** Y eso tiene una consecuencia de arquitectura que conviene escribir
antes de programar: **el bloque no se puede armar en el cliente** con lo que la pantalla
ya cargó, porque entonces la regla la impondría la pantalla y no el servidor. Lo arma
quien autoriza.

Es el mismo criterio que la eliminación física: esconder el botón es **cortesía**, la
autorización la decide el servidor.

### 3 · 🚫 COPIAR UN DATO BANCARIO O SENSIBLE QUEDA EN AUDITORÍA

Quién · **de qué empleado** · qué dato · cuándo. Y en lenguaje simple, como el resto.

**Es el único caso del proyecto donde LEER se audita**, y tiene su razón: un dato bancario
copiado sale del sistema y ya no hay rastro de dónde fue.

> ⚠️ Necesita **un verbo nuevo** —del orden de `copied`—, su traducción y **su renglón en
> la prueba de cobertura de verbos**. Es exactamente el hueco por el que «Closed» y
> «Reopened» llegaron a pantalla en inglés.

### 4 · Lo que el inventario tendrá que respetar cuando le toque

Las invariantes del dominio, ya cerradas y **no reinterpretables**:

- **`Branch` = destino administrativo, `Service` = destino operativo.** Personal **NO**
  usa Branch como sustituto de Service.
- **«Activo» se DERIVA de un periodo abierto**, nunca de una columna de estado.
- La antigüedad **no acumula**; un periodo cerrado **no se reabre**; una asignación
  invalidada no participa en la exclusión de solapes.
- **La baja escribe en cinco módulos en UNA transacción**, y sus cuatro reglas que no son
  de la pantalla están medidas en
  [funciones que cruzan apartados](funciones-que-cruzan-apartados.md) — incluida que se
  **bloquea entera** si la persona tiene la única cuenta Maestra activa.
- **Las cuatro puertas** de `EmployeeAssignment` ← empleado · servicio · sucursal.
- `codigoPostalFiscal` del empleado es **independiente** del CP de su domicilio: «son dos
  datos distintos que pueden no coincidir», y su consumidor es Nómina.

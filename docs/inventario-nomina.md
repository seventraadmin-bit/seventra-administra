# Inventario de Nómina — abierto

**Estado: PENDIENTE(D-48).** Existe porque hay un requisito anotado **antes** de que al apartado
le toque.

> Nómina es, en el escritorio, un **cálculo interno**: no genera CFDI de nómina ni timbra.
> Y es el segundo apartado más cruzado — lee de Personal y de Organización, cobra los
> descuentos programados y paga en Finanzas.

---

## Renglones ya decididos

### 1 · 🆕 Copiar en bloque las cuentas para la DISPERSIÓN

**Requisito nuevo del dueño, 19 de octubre de 2026. No existe en el escritorio** — hoy las
cuentas se anotan a mano, que es de donde salen los errores de dispersión.

| | |
|---|---|
| **Qué copia** | **Varios empleados a la vez**: nombre · banco · **CLABE** · importe |
| **En qué formato** | Listo para **pegar en Excel o en el portal del banco** — columnas por tabulador, sin adornos |
| **De dónde sale** | De la **misma pieza común** que la tarjeta fiscal de la Empresa y los datos del Cliente y del empleado |

**Es otra SALIDA de la pieza, no otra pieza.** El bloque de la tarjeta fiscal se pega en un
correo; éste se pega en una hoja de cálculo. Igual que la tarjeta fiscal tiene pantalla,
PDF y portapapeles con un solo formateador.

### 2 · 🚫 Y arrastra las dos reglas de Personal

Porque lo que se copia **son datos bancarios de varias personas a la vez**:

- **Sólo copia quien puede VER.** Copiar es leer, y la CLABE está detrás de un permiso
  protegido. Un bloque de cien empleados armado en el cliente **se salta la regla sin
  querer**: lo arma quien autoriza.
- **Queda en auditoría.** Y aquí con un matiz que Personal no tiene: el evento es de
  **varios empleados**, y la norma del proyecto dice que **ningún evento lleva una
  colección** — uno por fila, y las operaciones en lote registran **cuentas**. Así que hay
  que decidir si se escribe un evento por empleado copiado o uno por dispersión con su
  conteo. **Eso se decide al construir**, no ahora.

### 3 · Lo que el inventario tendrá que medir cuando le toque

- **La ESPINA de los egresos.** Nómina es uno de los ocho orígenes automáticos, y un
  módulo que gasta dinero **no se cierra** sin su alta en los dos registros de Finanzas y
  Reportes, con prueba. El escritorio se equivocó ahí **tres veces** y lo dejó escrito; el
  detalle, en [funciones que cruzan apartados](funciones-que-cruzan-apartados.md).
- **`ActualizarNominaDesdePersonal`**: el sueldo puede cambiar después de generar la
  nómina, y hay un caso de uso dedicado a eso. No se pierde.
- **Las cuatro puertas** de la cuota ← descuento programado.
- Y el renombre ya decidido: **«Nómina registrada» / «Pago complementario»**, y la
  etiqueta de IMSS como **«Con alta en IMSS / Sin alta en IMSS»**.

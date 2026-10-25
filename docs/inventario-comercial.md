# Comercial — decisiones del dueño

> ## ✅ EL INVENTARIO YA NO SE ESCRIBE AQUÍ
>
> **La referencia del apartado es
> `seventra-backend/docs/inventario-riseg-one/02-comercial-clientes-servicios.md`**, uno de
> los nueve inventarios funcionales que el dueño entregó el 22 de octubre de 2026. Es
> obligatorio leerlo completo antes de construir: sus «Reglas clave» se respetan tal como
> están y sus «Dudas o cosas raras» **no se copian**, se presentan para decidir.
>
> **Este archivo conserva lo que ese inventario no puede saber:** las decisiones y
> requisitos que el dueño anotó *antes* de que al apartado le tocara. Eso no se pierde, y
> por eso el archivo no se borra.
>
> Cerrado así el 25 de octubre de 2026, al cerrar la deuda **D-48**.

Lo de abajo **ya está decidido** y se incorpora como renglones: no se vuelve a discutir.

> Comercial es grande: en el escritorio son Clientes, Servicios, Entidades fiscales,
> Portales, Agenda, Configuración de cobro y Líneas comerciales — la segunda mitad de
> `features/organizacion`, que tiene 326 archivos. El diseño del dominio está
> **congelado** en el backend (5D.10A–E cerradas; 5D.10F y 5D.10G pendientes).

---

## Renglones ya decididos

### 1 · 🆕 «Copiar datos fiscales» del cliente y de cada entidad fiscal

**Requisito nuevo del dueño, 19 de octubre de 2026. No existe en el escritorio.**

| | |
|---|---|
| **En bloque** | Un botón que copia todo ordenado: razón social · RFC · **régimen fiscal** · domicilio fiscal con CP · **uso de CFDI** · correo de facturación · teléfono |
| **Dato por dato** | Ícono de copiar junto a cada uno —RFC, CP, cada campo suelto— |
| **El formato** | **La misma función** que el «Copiar datos» de la tarjeta fiscal de la Empresa. Una sola pieza, tres consumidores |

El detalle, los permisos y la auditoría del copiado están en
[requisitos nuevos del dueño](requisitos-nuevos-del-dueno.md), y por qué cruza apartados
en [funciones que cruzan apartados](funciones-que-cruzan-apartados.md).

### 2 · ⚠️ Régimen fiscal y uso de CFDI del cliente — **colisión, no hueco**

El dueño decidió que del cliente **sí** se guardan los dos, porque son los datos con los
que se le factura.

**Y la 0018 decidió lo contrario, por escrito:**

> `COMMENT ON TABLE app.fiscal_entity` — «Razon social con la que se factura a un Cliente
> (5D.10C). N:1 con Client. **Sin regimen ni uso de CFDI: eso es Facturacion.**»

Lo que `fiscal_entity` tiene hoy, medido: `legal_name`, `tax_id` —el RFC, **nullable**—,
`status`, `notes`, su domicilio 1:1 en `fiscal_entity_address` y sus documentos.

**Se decide al construir, con las dos cosas delante**, y el argumento a favor de añadirlos
ya existe: con **CFDI 4.0**, quien emite necesita del receptor RFC, razón social, régimen
y CP del domicilio fiscal. Si nosotros facturamos al cliente, nosotros somos quien emite.
Revertir una decisión escrita se puede —la 0049 revirtió el `DELETE` de la 0011— **con el
argumento escrito también**.

Lo que no puede pasar es que las columnas aparezcan sin que nadie note que había una
decisión en contra.

### 3 · Lo que el inventario tendrá que medir cuando le toque

Anotado para no redescubrirlo:

- **Las cuatro puertas** de todo lo que cuelga: `CommercialLine` ← `Service`,
  `CommercialLineTerm` ← línea y puesto, `FiscalEntity` ← `Client`, `ServicioEventual` ←
  `Client` *(opcional)*. Ver el apartado 4 ter de funciones que cruzan apartados.
- **Las fronteras congeladas que no se colapsan:** `Client != Prospect` ·
  `Service != Quote` · `Eventual != Service` · `Client != FiscalEntity` ·
  `Branch != Service`. Y `Service` del plano Company **!=** servicio profesional del
  catálogo de SEVENTRA.
- **Los códigos humanos, lista cerrada:** `CLI` · `SRV` · `COT` · `CTR` · `EVT`. **Sin
  código** para Prospect, Opportunity, QuoteLine, FiscalEntity, CommercialLine, Term,
  Schedule y Contact. **No se inventan códigos por simetría.**
- **Los minutos:** `start_minute` 0..1439, `end_minute` 1..1440, cruce de medianoche
  **derivado**. No existen minutos > 1440.
- **La frontera con Facturación (5D.11):** `Terms → BillingConfiguration →
  BillingPreparation → documento emitido → AccountReceivable → Payment`. La CxC nace
  **únicamente** al registrar el documento emitido.

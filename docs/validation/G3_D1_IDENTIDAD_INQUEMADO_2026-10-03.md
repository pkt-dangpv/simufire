# G3-D1 — identidad física del combustible no quemado

Estado (2026-10-03): **decisión pendiente del usuario**. Este gate no cambia
física ni activa CO/FED. G3-4A quedó en el commit `a4ee6ff` como cuenta
energética en MJ, marcada `physical_inventory: false`; no es masa de gas.

## Lo que sabemos

- En la opción `explicit_objects`, el motor descuenta `burn_MJ` del objeto
  cuando confirma el paso, incluso si una parte de la pirólisis no libera
  calor. G3-4A registra esa diferencia como energía no quemada del objeto,
  sin alterar el descuento (`CombustionSystem.gd`, `_g3_apply_owned`).
- La mayoría de los objetos no declara un calor de combustión utilizable:
  el valor por defecto es `-1`; solo cuatro objetos en dos casos de
  validación lo declaran (§16.4 del diseño). La conversión global de
  backdraft a 10 000 kJ/kg no tiene fuente material. Un MJ no determina kg
  ni composición del combustible.
- CFAST **prescribe** la tasa de pirólisis; no la predice. Cuando limita el
  oxígeno, asume que esa tasa no cambia, sigue el combustible no quemado y
  lo transporta por la pluma y las aberturas. Es un precedente de modelado,
  **no una medición que demuestre que cada mueble de SimuFire se comporta así**:
  [NIST TN 1889v1, §3.2, ecuaciones 3.12–3.14, p. 12–13](https://nvlpubs.nist.gov/nistpubs/TechnicalNotes/NIST.TN.1889v1.pdf).

## Decisión D1

| Alternativa | Significado de la energía U | Consecuencia mínima |
|---|---|---|
| A. Gas pirolizado | El combustible ya abandonó el sólido y no se oxidó. | Conservar masa y composición de gas por objeto y zona; transportar lo que salga de la fuente. El débito actual al sólido mantiene su significado, pero la cuenta en MJ **no** sustituye ese inventario. |
| B. Sólido no pirolizado | Esa fracción permanece en el objeto. | No descontarla del combustible del objeto; redefinir la tasa de pirólisis y el débito actual. No llamar gas a la cuenta en MJ. |

**Recomendación provisional: A**, porque coincide con el significado del
débito actual y con el precedente de CFAST. Es una inferencia de coherencia
interna, no una validación experimental ni una autorización para implementar
la masa o el transporte. B sigue siendo una alternativa física posible que
exigiría revisar la ley de pirólisis.

## Criterio de cierre y siguiente gate

El usuario debe escoger A, B o pedir evidencia adicional. Hasta entonces,
D1 permanece abierto y no se implementa ninguna de las dos rutas. Si se elige
A, antes de física nueva quedan por resolver separadamente D2 (kg/MJ por
material), D3 (zona de entrada y transporte), D4 (ignición) y D5 (límite de
O₂), según §16.4 del [diseño G3](G3_ENERGY_DELAY_DESIGN_2026-09-29.md).
Elegir A no aprueba por sí solo los valores ni las reglas de D2–D5.

La prueba futura debe cerrar por paso masa de sólido, masa de gas no quemado,
especies, carbono y O₂ en casos ventilados y cerrados, y comprobar transporte
entre zonas y recintos. Mantener identidad byte a byte con el interruptor OFF
y referencia 346/346; CO/FED siguen en NO-GO hasta contrastarlos con datos
experimentales. No usar la reducción de U en MJ como sustituto de esas
comprobaciones.

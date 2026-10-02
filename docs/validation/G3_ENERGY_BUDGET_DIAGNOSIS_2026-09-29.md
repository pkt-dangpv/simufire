# G3 — diagnóstico del presupuesto energético, antes de nueva física

Fecha: 2026-09-29. Alcance: nueve controles de 90 s ya capturados en
`runs/g3_fuel_ledger_off_20260929_092817/` y
`runs/g3_fuel_ledger_on_20260929_093110/`. **No** se ha modificado la ley
de combustión en esta pasada.

## Identidad contable por paso

Para cada paso: `C` = MJ debitados a combustible sólido = pirólisis;
`T` = objetivos de llama más combustión latente integrados; `B` = calor
sólido aplicado; `G` = MJ añadidos al pool de gas inquemado. Entonces:

```text
C − B − G = (C − T − G) + (T − B)
  no liberado     diferencia de         retraso/exceso del
  ni retenido     objetivos/pool         suavizado de HRR
```

Es una descomposición algebraica, **no** una declaración de que `C−B−G`
sea gas almacenado o una pérdida física calibrada. El analizador puro
[`analyze_g3_energy_budget.py`](../../scripts/simulation/analyze_g3_energy_budget.py)
la calcula desde el libro G3-3; sus tests fijan signos, unidades y entradas
no finitas.

| Caso | Modo | C MJ | B MJ | G MJ | C−T−G MJ | T−B MJ |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| Sofá solo | OFF | 2,999863 | 3,405765 | 0 | 0 | −0,405902 |
| Sofá solo | ON | 2,999013 | 2,065228 | 0 | 0 | +0,933784 |
| Sofá y silla fría | OFF | 5,996351 | 6,137992 | 0 | 0 | −0,141641 |
| Sofá y silla fría | ON | 2,999013 | 2,065228 | 0 | 0 | +0,933784 |
| Dos objetos activos | OFF | 5,738884 | 5,003335 | 0 | 0 | +0,735549 |
| Dos objetos activos | ON | 5,698013 | 4,637314 | 0 | 0 | +1,060699 |
| Objeto de potencia baja | OFF | 5,845985 | 5,254885 | 0 | 0 | +0,591100 |
| Objeto de potencia baja | ON | 3,568255 | 2,498333 | 0 | 0 | +1,069922 |
| Fuente adicional nombrada | ON | 2,999003 | 2,040218 | 0 | 0 | +0,958785 |
| Solo agregado de sala | OFF = ON | 2,999863 | 3,405768 | 0 | 0 | −0,405905 |

Los demás controles de carga de sala también mantienen `G=0` y
`C−T−G=0`. En los nueve, `C` coincide con la pirólisis integrada y el
pool empieza y termina en 0. Los residuos de la identidad son numéricos,
no un mecanismo físico nuevo.

## Causa localizada y límite

El código debita `C` antes de suavizar `room.hrr_kw` hacia `T`. En la rama
legacy, la cola suavizada puede liberar calor una vez agotado el combustible
del paso: de ahí el exceso neto de 0,405902 MJ del sofá solo. En la rama
experimental ON, el calor sólido se limita a la pirólisis **del mismo
paso**. Evita calor sin propietario, pero no conserva el déficit anterior
para una liberación posterior: 0,933784 MJ del sofá solo quedan sin estado
físico de destino. El cociente 0,689 es por tanto un **límite físico real**
de esa rama, aunque la contabilidad del propietario de combustible cierre.

La afirmación general «30 % al pool y 70 % no registrado» describe otra
ruta posible del código, pero **no explica estos nueve resultados**: `G=0`
en todos. Esa ruta requiere controles específicos de ventilación limitada
antes de atribuirle una pérdida medida o decidir cómo corregirla.

No se debe forzar `B=C` en cada paso: el retraso puede ser legítimo si
existe un inventario transitorio de combustible pirolizado con dueño,
balance y reglas de oxidación/extinción. Hoy ese inventario no existe para
el desfase del suavizado. Convertir todo el déficit en calor inmediato,
gas retenido o pérdida definitiva serían **tres físicas distintas** y
afectarían HRR, O₂ y especies. Falta diseñar y falsar esa transición con
controles ventilados/subventilados y agotamiento antes de implementarla.

Decisión: **GO al diagnóstico numérico del presupuesto; NO-GO a cerrar la
física energética de `explicit_objects` ni a activar ese modo en producto**.
G3-4 química, CO y FED continúan NO-GO. El interruptor permanece OFF.

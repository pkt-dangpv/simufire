# Diagnóstico de O₂ — casa simple, 24 de septiembre de 2026

> **Pregunta:** ¿por qué el fuego sigue creciendo cuando el O₂ medio del Salón
> cae a 0,37 % y el O₂ de la capa baja vuelve a 20,9 %?
>
> **Base:** [auditoría FDS](AUDITORIA_FDS_CASA_SIMPLE_2026-09-24.md) ·
> caso `sim/validation/cases/fds_simple_house_default.json`
>
> **No se ha implementado ninguna corrección.** Este documento diagnostica y
> propone; no arregla. No se ha cambiado física, interruptores, perfiles,
> parámetros, escenarios, casos FDS, baselines ni tolerancias.
>
> **Instrumentación:** `sim/core/OxygenExchangeSystem.gd` y
> `sim/fire/CombustionSystem.gd` se instrumentaron temporalmente **solo con
> `print`** y se restauraron desde copia; `sha256sum -c` confirma que ambos
> vuelven a su contenido exacto (`c6693034…` y `a616b996…`). Los tres casos de
> control se escribieron **fuera del árbol versionado**.

---

## 1. Resumen en una frase

El limitador de combustión y el sumidero de oxígeno **leen y escriben depósitos
distintos**: `CombustionSystem` decide que el penacho respira de la capa baja y
lee `room.o2_lower`, mientras `OxygenExchangeSystem` carga el consumo a
`room.o2` porque la sala tiene una puerta interior abierta. `room.o2_lower`
queda como una concentración flotante que nadie descuenta y que además otro
escritor eleva por encima de su propia fuente.

---

## 2. Trayectoria medida del Salón

Traza por segundo, caso `fds_simple_house_default` sin modificar:

| t (s) | `plume_lower_mode` | `effective_plume_lower` | factor int. abierto | h interfaz (m) | `room.o2` | `o2_lower` | ACH Δ | HRR (kW) | `o2_hrr_factor` | `fire_o2_mode_used` |
|---:|---|---|---:|---:|---:|---:|---:|---:|---:|---|
| 60 | false | **false** | 0,750 | 2,00 | 0,2065 | 0,20882 | 0,000000 | 122 | 1,0000 | `plume_lower` |
| 120 | false | **false** | 0,750 | 2,12 | 0,1865 | 0,20560 | 0,000000 | 645 | 1,0000 | `plume_lower` |
| 150 | false | **false** | 0,750 | 1,65 | 0,1621 | 0,19784 | 0,000000 | 1030 | 1,0000 | `plume_lower` |
| 180 | false | **false** | 0,750 | 1,34 | 0,1230 | 0,18864 | 0,000000 | 1526 | 1,0000 | `plume_lower` |
| 200 | false | **false** | 0,750 | 1,22 | 0,0915 | 0,18935 | 0,000000 | 1921 | 1,0000 | `plume_lower` |
| 220 | false | **false** | 0,750 | 1,04 | 0,0594 | **0,20734** | 0,000000 | 2340 | 1,0000 | `plume_lower` |
| 240 | false | **false** | 0,750 | 0,87 | 0,0249 | **0,20897** | 0,000000 | 2808 | 1,0000 | `plume_lower` |
| 260 | false | **false** | 0,750 | 0,70 | 0,0035 | **0,20900** | 0,000000 | 3276 | 1,0000 | `plume_lower` |

Dos cosas saltan a la vista:

1. **`effective_plume_lower` es `false` toda la corrida**, mientras
   `fire_o2_mode_used` dice `plume_lower`. Son dos decisiones distintas tomadas
   por dos sistemas distintos, y **no coinciden nunca**.
2. **El ACH no es el repositor.** `ach_lower_dt = 0,000000` en cada paso. Con
   0,5 ren/h y `dt = 1/12 s` el término vale 2·10⁻⁷: despreciable. La hipótesis
   «la infiltración repone la capa baja» queda **descartada por medida**.

`o2_lower` baja hasta 0,1887 en t ≈ 180 s y **vuelve a subir** hasta 0,209000
exactos. La subida ocurre **fuera** del bloque de O₂: dentro de él `o2_lower`
sale en 0,208965, y reentra al segundo siguiente en 0,209000.

---

## 3. El escritor exacto que eleva la capa baja

`sim/core/OxygenExchangeSystem.gd`, en el contraflujo por vano interior:

```gdscript
_apply_room_o2_mass_delta(hot_room, hot_room_delta_o2_kg, air_density_kg_m3)   # → bulk
…
if lower_replenish_scale > 0.0:
    hot_room.o2_lower = clampf(
        hot_room.o2_lower + hot_room_delta_o2_kg * lower_replenish_scale / lower_mass_hr,
        0.0, o2_nominal)
```

Los **mismos** `hot_room_delta_o2_kg` se aplican dos veces: primero al bulk
contra la masa de aire de **toda la sala**, y después a `o2_lower` contra la
masa de la **capa baja**. Medido en la traza (226 eventos):

| t (s) | Δ O₂ contraflujo (kg) | masa sala (kg) | masa capa baja (kg) | amplificación | `o2` sala fría | `o2_lower` antes → después |
|---:|---:|---:|---:|---:|---:|---|
| 60 | 0,0000918 | 57,60 | 48,01 | ×1,20 | 0,2088 | 0,208817 → 0,208819 |
| 180 | 0,0005314 | 57,60 | 32,16 | ×1,79 | 0,1938 | 0,188641 → 0,188657 |
| 220 | 0,0037234 | 57,60 | 25,02 | ×2,30 | 0,1708 | 0,207344 → **0,207493** |
| 260 | 0,0066935 | 57,60 | 16,71 | **×3,45** | **0,1398** | 0,208965 → **0,209000** |

La amplificación es exactamente `1 / lower_frac` y **crece según se adelgaza la
capa baja**: cuanto más caliente la sala, más se amplifica la reposición. El
`clampf(…, 0.0, o2_nominal)` recorta el exceso, y por eso `o2_lower` se clava en
**0,209000**, que es `o2_nominal`.

**La prueba que no necesita a FDS:** a t = 260 s la sala fría que alimenta el
contraflujo (el Pasillo) está en **0,1398**, y la capa baja del Salón se
mantiene en **0,2090**. Mezclando aire de una sala al 14 % no se puede sostener
una capa al 20,9 %. Esa operación **crea** oxígeno.

---

## 4. Lo que falsa la hipótesis: quitar la reposición no apaga el fuego

Mutación diagnóstica temporal (`lower_replenish_scale = 0.0`), restaurada
después con hash verificado:

| t (s) | base `o2_lower` | mutado `o2_lower` | base HRR | mutado HRR | base `o2f` | mutado `o2f` |
|---:|---:|---:|---:|---:|---:|---:|
| 180 | 0,18864 | 0,17866 | 1525,5 | 1525,5 | 1,0000 | 1,0000 |
| 220 | 0,20734 | 0,16518 | 2340,3 | 2340,3 | 1,0000 | 1,0000 |
| 260 | **0,20900** | **0,15280** | 3275,6 | **3275,6** | 1,0000 | 1,0000 |

La reposición **sí** es el escritor que devuelve `o2_lower` a 20,9 % —al
quitarla, decae a 15,3 %—, pero el HRR sale **idéntico bit a bit** y
`o2_hrr_factor` sigue en 1,0000. **La reposición no es la causa del fuego que no
se apaga.** A 15,3 % el limitador tampoco actúa.

---

## 5. La causa demostrada: dos condiciones que no coinciden

**`CombustionSystem._resolve_fire_o2_selection`** elige el depósito **solo por
la altura de la interfaz**:

```gdscript
if interface_m >= fire_base_m + transition_m:   # 0,0 + 0,3 m
    o2_ref = room.o2_lower
    mode = "plume_lower"
```

**`OxygenExchangeSystem`** encamina el sumidero a la capa baja solo si:

```gdscript
plume_lower_mode = … and _estimate_room_outside_open_factor(...) <= 0.01
                     and _estimate_room_interior_open_factor(...) <= 0.01
canonical_plume_lower = fire_o2_canonical_enabled and …      # por defecto false
effective_plume_lower = plume_lower_mode or canonical_plume_lower
```

El Salón tiene la puerta al Pasillo abierta: **factor interior 0,750**, muy por
encima de 0,01. Luego `plume_lower_mode` no puede ser cierto, y
`fire_o2_canonical_enabled` está apagado por defecto. Resultado:

- el fuego **lee** `room.o2_lower`;
- el consumo se **carga** a `room.o2` por la vía bulk;
- `room.o2` cae a 0,0035 y el limitador no la mira;
- `room.o2_lower` no se descuenta nunca y además se eleva (§3);
- `o2_hrr_factor = 1` durante 260 s y el HRR sigue la curva de crecimiento.

En esta configuración `room.o2_lower` es un **canal de solo escritura**: la
recomposición `room.o2 = o2_upper·upper_frac + o2_lower·lower_frac` **solo corre
dentro de `effective_plume_lower`**, que es falso. Nada devuelve `o2_lower` al
inventario de la sala.

---

## 6. Controles

Tres controles fuera del árbol versionado, ejecutados secuencialmente:

| control | qué cambia | HRR pico | HRR 260 s | `o2_lower` 260 s | `room.o2` 260 s | `o2_hrr_factor` 260 s |
|---|---|---:|---:|---:|---:|---:|
| **base** | nada | 3275,6 | **3275,6** | 0,2090 | 0,0037 | **1,0000** |
| **C1** | `fire_o2_canonical_enabled = true` (interruptor que ya existe) | 1409,3 | **457,1** | 0,1067 | 0,1069 | **0,5497** |
| **C2** | puerta Salón↔Pasillo cerrada (`open_fraction = 0`) | 1475,9 | **0,0** | 0,0787 | 0,0791 | **0,0002** |
| **C3** | sin ignición | 0,0 | 0,0 | 0,2090 | 0,2090 | 1,0000 |

- **C1 confirma la causa.** Basta con que el sumidero siga al depósito que el
  limitador lee para que el fuego se vuelva limitado por ventilación: el HRR
  hace pico en 1409 kW y decae a 457 kW, el factor baja a 0,55, y las dos capas
  dejan de divergir (0,1067 frente a 0,1069, en vez de 0,2090 frente a 0,0037).
- **C2** cierra la puerta, con lo que `plume_lower_mode` pasa a cierto por la vía
  de sala sellada: el fuego **se apaga por completo**.
- **C3** descarta deriva espuria: sin fuego no hay contraflujo, y `o2_lower` se
  queda en 0,2090 porque nadie consume. La reposición **no inventa oxígeno por
  sí sola**; solo cuando el fuego la dispara.

**Mecanismo, no configuración:** C1 no toca la ventilación —mismo recinto,
mismas aberturas, mismo fuego— y cambia el resultado por un factor de 7. Lo que
cambia es a qué depósito se carga el consumo.

---

## 7. Balance de O₂ y residual

Inventario = Σ(`room.o2` × volumen × 1,2 kg/m³) sobre las seis salas.

| corrida | quemado | demanda O₂ | inventario inicial → final | retirado | **residual** |
|---|---:|---:|---|---:|---:|
| base | 310,8 MJ | 23,62 kg | 42,13 → 24,67 kg | 17,47 kg | **+6,15 kg (+26,0 %)** |
| sin reposición | 310,8 MJ | 23,62 kg | 42,13 → 24,67 kg | 17,47 kg | **+6,15 kg (+26,0 %)** |
| C1 canonical | 121,2 MJ | 9,21 kg | 42,13 → 31,93 kg | 10,21 kg | −1,00 kg (−10,8 %) |
| C2 puerta cerrada | 113,5 MJ | 8,62 kg | 42,13 → 34,65 kg | 7,48 kg | +1,14 kg (+13,2 %) |

**El balance global NO se cierra.** El residual es **idéntico** con y sin
reposición, así que **no lo causa el escritor de §3**: ese escritor solo toca
`o2_lower`, que no forma parte de este inventario.

> **Corregido en la fase O2-A.** La cifra de +6,15 kg salía de una
> reconstrucción propia del inventario. Rehecho el balance con los
> **acumuladores del propio motor** (`o2_consumed_kg_total_all`,
> `o2_net_transport_kg_total`, `o2_exterior_net_kg_total`,
> `o2_zone_sync_kg_total`), el residual del Salón es **+9,263 kg (31,7 % de la
> demanda)** y las otras cinco salas cierran por debajo de 1,4·10⁻⁴ kg. Además
> ese residual **coincide exactamente** con la diferencia entre el O₂ declarado
> como consumido (29,261 kg) y el descontado por la vía bulk (19,998 kg). El
> contrato, las tolerancias medidas y las pruebas que lo detectan están en
> [el contrato de O₂](CONTRATO_O2_2026-09-24.md).

**Mecanismo del residual, por aritmética sobre la vía bulk:**

```gdscript
consumed = minf(consumed, o2_mass_kg * 0.05)   # tope del 5 % por paso
```

A t = 260 s: `o2_mass_kg` = 57,6 × 0,0037 = 0,213 kg, luego el tope deja pasar
0,0107 kg por paso, mientras la demanda del paso es 0,249 kg/s × 0,0833 s =
0,0207 kg. **Solo se descuenta el 52 % de lo que el fuego quema.** Cuando el O₂
es alto el tope no muerde; según se agota, muerde cada vez más. Acumulado: los
6,15 kg.

**Ruta de presión/volumen: descartada por construcción.**
`_compute_room_air_mass_kg()` devuelve `volumen × 1,2` — densidad constante, sin
dependencia de temperatura ni de presión. Los inventarios de O₂ de esta ruta
están **estructuralmente desacoplados** del camino presión/volumen, así que no
puede contribuir. Las rendijas experimentales están apagadas (0/5 interruptores)
y `overpressure_pa` hace pico en 314 Pa.

---

## 8. El limitador solo mira concentración

`_resolve_fire_o2_selection` devuelve **una fracción** (`o2_ref`), y
`_compute_o2_factor(o2, nominal, min_o2)` opera solo con fracciones. **Ni
inventario ni caudal entran en la decisión.** Medido a t = 260 s:

| magnitud | valor |
|---|---:|
| Inventario de O₂ de la capa baja | **3,49 kg** |
| Demanda instantánea del fuego | **0,249 kg/s** |
| **Autonomía de la capa baja sin reposición** | **14,0 s** |
| Aporte físico real (0,5 ren/h de infiltración) | 0,00167 kg/s |
| **Cobertura de ese aporte sobre la demanda** | **0,67 %** |

La capa baja podría sostener el fuego **catorce segundos**, y el único
reabastecimiento físico cubre **menos del 1 %** de lo que pide. El limitador no
puede ver ninguna de esas dos cifras: solo ve «20,9 %», y concluye que sobra
aire.

---

## 9. Los tres defectos, separados

| # | defecto | demostrado por | efecto |
|---|---|---|---|
| **O2-1** | **El sumidero y el limitador usan depósitos distintos.** `CombustionSystem` elige `plume_lower` solo por altura de interfaz; `OxygenExchangeSystem` solo encamina a la capa baja si la sala está sellada por dentro **y** por fuera, o con `fire_o2_canonical_enabled`. Con puerta interior abierta discrepan siempre | C1, C2, traza §2 | **Causa demostrada del HRR desbocado.** El fuego respira de un depósito que nadie descuenta |
| **O2-2** | **La reposición de capa baja por contraflujo cuenta dos veces y con la base de masa equivocada.** `hot_room_delta_o2_kg` se aplica al bulk y otra vez a `o2_lower` dividido por `lower_mass_hr`, amplificando ×1/`lower_frac` y recortando en `o2_nominal` | DIAGB §3, mutación §4 | Clava `o2_lower` en 0,209 **por encima de su fuente** (0,1398). **No** causa el HRR |
| **O2-3** | **El sumidero bulk está topado al 5 % del O₂ de la sala por paso**, así que a O₂ bajo se quema oxígeno que no se descuenta | balance §7 | **+9,263 kg, 31,7 % de la demanda, sin conservar** |

**O2-1 es la causa demostrada.** O2-2 y O2-3 son defectos reales e
independientes que agravan el cuadro y explican por qué la traza *parecía* un
depósito infinito.

---

## 10. Qué queda abierto

- **El residual de 9,263 kg ya no es solo aritmética.** Coincide exactamente con
  `o2_consumed_kg_total_all − o2_consumed_bulk_kg_total`, así que queda
  **demostrado** que es combustión aceptada cuyo O₂ no se descuenta. Lo que
  sigue sin aislar por control es qué fracción la aporta el tope del 5 % frente
  a otros recortes del mismo camino.
- **No se ha comprobado si O2-1 afecta a otros escenarios.** La condición que
  falla —puerta interior abierta— es la normal en vivienda, así que es
  previsible que afecte a los cinco escenarios del ámbito G0, pero solo se ha
  medido la casa simple.
- **`fire_o2_canonical_enabled` no está auditado como arreglo.** C1 demuestra el
  mecanismo; no demuestra que ese interruptor sea correcto en todos los casos.

---

## 11. Propuesta de arreglo (no implementada)

**Principio:** el depósito del que el limitador lee debe ser el mismo del que el
sumidero descuenta, y ningún escritor puede elevar una capa por encima de su
fuente.

1. **O2-1 — unificar la decisión.** Que `OxygenExchangeSystem` encamine el
   sumidero según `room.fire_o2_mode_used` (lo que `CombustionSystem` ya
   decidió), en vez de reevaluar condiciones propias. Es lo que hace
   `canonical_plume_lower`; el trabajo es decidir si se activa por defecto y
   auditar su efecto en los 108 casos, no escribir código nuevo.
2. **O2-2 — una sola acreditación y una sola base.** Repartir
   `hot_room_delta_o2_kg` entre capas **una vez**, con el mismo criterio de masa
   con el que se aplicó al bulk, y acotar la capa destino por la concentración
   de la **sala de origen**, no por `o2_nominal`.
3. **O2-3 — que el tope no borre masa.** Si el tope del 5 % recorta el consumo,
   el déficit debe quedar registrado o cobrarse en otro depósito, no
   desaparecer.
4. **Limitador con inventario.** Añadir al limitador el caudal de O₂ que el
   depósito elegido puede entregar en el paso sin hacerse negativo, no solo su
   concentración.

### Pruebas de aceptación propuestas

| # | prueba | criterio |
|---|---|---|
| A1 | Balance global de O₂ en `fds_simple_house_default` | residual ≤ **2 %** de la demanda (hoy: 26 %) |
| A2 | Ningún escritor eleva una capa por encima de su fuente | para todo paso y sala, `o2_lower` ≤ máx(`o2_lower` previo, O₂ de la sala origen del contraflujo) |
| A3 | Coherencia sumidero/limitador | el depósito leído por `_resolve_fire_o2_selection` es el descontado en el mismo paso, en el **100 %** de los pasos con `hrr_kw > 0` |
| A4 | Recinto sellado con fuego | el HRR **decae** antes de t = 260 s; hoy termina en su máximo |
| A5 | Autonomía respetada | el fuego no consume de una capa más O₂ del que esa capa contiene, en ningún paso |
| A6 | No regresión de los 5 escenarios G0 | 0 errores de validación y los 5 interruptores experimentales apagados |
| A7 | Corpus de referencia | 346/346 y 78 gaps tras regenerar, **una sola vez y con memoria suficiente** |

---

## 12. Estado y límites

**R2-1 sigue en rojo** por los cambios pendientes de `sim/templates/` de fases
anteriores. **No se ha ejecutado la suite de referencia completa**: la memoria
libre osciló entre **4,56 y 4,59 GB**, por debajo del umbral operativo de
6–8 GB. Seis ejecuciones de Godot, **secuenciales**, sin fallos nativos y sin
procesos residuales.

Los dos ficheros instrumentados se restauraron y su SHA-256 coincide con el
original. `git status` no muestra cambios en `sim/core/` ni en `sim/fire/`.

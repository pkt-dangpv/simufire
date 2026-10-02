# G3-0 — CO con puerta, ventana y hueco vertical (2026-09-28)

Estado: **baseline diagnóstico; no valida FED ni transporte de especies**.
Cuatro controles generados por
[`run_g3_transport_baseline.py`](../../scripts/simulation/run_g3_transport_baseline.py)
y ejecutados secuencialmente por el monitor de Godot. Tienen el mismo sofá
artificial de 200 MJ/100 kW, ignición en sala 0, 90 s, propagación de fuego
desactivada y transporte interior activado. No se ha cambiado `sim/core`,
`sim/fire`, escenarios distribuidos ni física. Las series completas y los
hashes de escenarios están en el artefacto **ignorado por Git**
`runs/g3_transport_topology_baseline_20260928_080739/` del worktree G3.
La tanda anterior `..._080002/` es idéntica byte a byte en `sim_log.csv` y
`events.json` para los cuatro casos: sólo se añadió un snapshot opt-in del
CO en parcelas pendientes.

## Controles y resultado a 90,1 s

En los tres primeros casos se usa `simple_house`: las cuatro puertas del
pasillo a otras salas permanecen cerradas, las ventanas cerradas salvo el
evento declarado y la puerta salón–pasillo es la única ruta interior.
`door_then_window` abre esa puerta a 30 s y la ventana del salón a 60 s.
`two_storey_open` usa la plantilla de dos plantas con su camino abierto
salón PB → recibidor → escalera PB → hueco vertical → escalera P1 → distribuidor.

| Caso | CO generado, kg | CO en salas, kg | CO al exterior, kg | CO en tránsito, kg / parcelas | CO pasillo PB, kg / ppm | CO escalera P1, kg |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Puerta cerrada | 0,00204561 | 0,00203743 | 0,00000818 | 0 / 0 | 0 / 0 | — |
| Puerta abierta | 0,00204107 | 0,00181099 | 0,00000631 | 0,000223762 / 308 | 0,00047711 / 16 | — |
| Puerta a 30 s, ventana a 60 s | 0,00202928 | 0,00094813 | 0,00102290 | 0,000058204 / 308 | 0,00028935 / 10 | — |
| Dos plantas abiertas | 0,00200418 | 0,00154145 | 0,00000592 | 0,000456815 / 200 | 0,00031757 / 5 | 0,00000022 |

El pasillo permanece en **0 kg** con la puerta cerrada. En el caso
escalonado aún tiene 0 kg a 30,1 s y llega a 0,00011831 kg a 60 s;
el caso abierto desde el inicio alcanza 0,00047711 kg a 90,1 s. Abrir
la ventana aumenta mucho la retirada exterior registrada, pero las
pequeñas diferencias en CO generado entre casos muestran que cambiar
aberturas también modifica ligeramente la combustión: no se debe atribuir
toda diferencia de concentración únicamente al transporte. En dos plantas
llegan 0,00000022 kg a la escalera P1 a 90,1 s; el CSV redondea su ppm a
cero y el distribuidor P1 aún marca cero. Este horizonte **no demuestra**
una predicción útil de exposición en la planta alta.

## Balance con tránsito medido

Para cada sala, con las cifras CSV a ocho decimales, se cumple
`CO generado + CO neto transportado − CO retirado exterior − CO inventario
= 0` con residuo máximo `1e-8 kg`. En cambio, la suma de
`co_net_transport_kg_total` de **todas** las salas no es cero en los tres
casos con camino interior abierto: −0,00022376, −0,00005824 y
−0,00045681 kg. El nuevo snapshot opt-in lee por separado las parcelas
pendientes de entrega y el registro por destino de
`GasExchangeSystem._inflight_species_kg`: las dos cuentas de CO coinciden
a menos de `1e-9 kg`. La masa pendiente de la tabla explica el CO que
todavía no está en una sala ni ha salido al exterior.

El cierre **global final** `CO generado − CO en salas − CO exterior − CO
en tránsito` deja residuos −`6,8e-21`, `8,1e-9`, `4,6e-8` y
−`4,6e-9 kg` en los cuatro controles, respectivamente. La cota de
aceptación predeclarada en el arnés fue `2e-7 kg`, derivada del redondeo
CSV a ocho decimales en hasta 13 salas; no se ajustó tras ver el resultado.
Queda así resuelta la **atribución de ese residuo final concreto**: es CO
en tránsito, no una pérdida. No implica cierre por paso, de CO oxidado, de
CO₂/HCN ni del presupuesto zonal. G3-5 debe exigir ese cierre más amplio
antes de validar concentraciones y FED.

## Calidad de corrida y decisión

Cuatro monitores con exit 0, sin timeout, cuadros de error ni procesos
Godot residuales; `process_quiescent = true` en todos. Memoria libre antes
de cada caso: 6,40–6,45 GiB en la tanda con snapshot. Los tests focalizados
del runner y sus predecesores pasan. `git diff --check` limpio. No se ejecutó la
referencia completa porque no se modificó física ni `sim/core`.

**Decisión:** G3-0 amplía su corpus con puerta, ventana y edificio de dos
plantas y cierra la atribución del CO final en tránsito, pero permanece
**parcial**. G3-4/5/6 siguen NO-GO: el rendimiento de CO del sofá es un
estímulo artificial; no hay todavía presupuesto simultáneo por paso/zona,
validación experimental de transporte ni curva de fuente por combustible.

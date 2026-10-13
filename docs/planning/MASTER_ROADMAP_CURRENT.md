# Hoja de ruta activa de SimuFire

Fecha base: 2026-07-25
Ultima actualizacion parcial: 2026-10-13 (minimapa corregido; jugabilidad/FP pendientes)
Estado: fuente de verdad operativa para continuar trabajo
Alcance: credibilidad fisica del motor, balances de conservacion, validacion CFAST restante y limites de cambios globales.

Prioridad inmediata: [hotfix del minimapa y límites de jugabilidad](../validation/PRODUCT_MINIMAP_LAYOUT_THRASH_2026-10-13.md).
Ventana real reproduce 3D 60 FPS pausa / 6,64 Play. El minimapa abreviaba
fichas, expulsando la caché compartida: 606 misses en ocho segundos. Corregido
sin ocultarlo ni cambiar física/calidad: 46,22 FPS y cero misses.
730 checks / 12 mutantes válidos; producto 168 y global 5 090 aprobados
(80 skipped, 2 xfailed, 42 subtests), guardarraíles/R2-1 y referencia intactos.
GO sólo al hotfix, NO-GO a cerrar jugabilidad: FP tiene cuatro corridas
rechazadas por dos avisos GL al salir; 24,65 FPS sólo provisional.
Siguiente: rendimiento sostenido de FP y causa de las texturas no liberadas.
Registrar también el popup técnico fuera del árbol al salir del usuario.
No tocar nueva física ni asumir que el problema restante es la GPU; CO/FED OFF.

Primer checkpoint de producto: [corrección visual de mobiliario](../validation/PRODUCT_FURNITURE_LAYOUT_CACHE_FIX_2026-10-13.md).
Diagnóstico y arreglo CPU cerrados: poses reutilizadas con fichas dinámicas
frescas e invalidación acotada; cuatro GD visuales, sin cambios de física,
calidad, transforms de autor ni escenarios. 560 checks nativos y 11/11
mutantes GD válidos; diez viviendas idénticas al algoritmo original.
Refresco 3D 317,33 -> 7,11 ms; FP 316,19 -> 6,16 ms; ventana FP
648,35 -> 10,62 ms. Paso físico ~5 ms. Producto 168 PASS; global
5 078 passed / 78 skipped / 2 xfailed / 42 subtests, monitor sano;
ALL GUARDRAILS PASS/R2-1, referencia 346/346/78 intacta, sin regenerar.
No FPS/GPU medidos y p95 de callback real aún ~48-52 ms. Siguiente:
probar Casa simple renderizada en 3D/FP con Play y puertas/ventanas.
El gate gas/energía/EOS viene después; CO/FED siguen OFF/NO-GO.

Avance M4-P1: [núcleo de parcelas físicas aislado](../validation/G3_O2_M4_PHYSICAL_PARCEL_P1_2026-10-12.md).
GD implementado sin consumidor: gas/energía/O2 pareados, calor sin masa,
donaciones desde snapshot, sin entrada futura financiando salida. 5 920
checks, 20/20 mutantes GD y 315 focales offline PASS. No calibración de ley.
Cadena final: referencia 18/18 y 346/346, 78 gaps; solo generated_at cambia
en 494 archivos. Producto 168 PASS, guardarraíles/R2-1 PASS; global repetida
5 061 passed / 74 skipped / 2 xfailed / 42 subtests, monitor limpio.
Dos falsos positivos iniciales del inventario documental corregidos con una
excepción exacta probada, sin cambiar el módulo/fixture/auditor.
Motor vivo, M1/M2-T/M2-V/M3 y activación intactos. CO/FED OFF/NO-GO.
Siguiente: diseñar autoridad gas/energía/EOS y calentador sin combustible,
cerrando energía interna/entalpía/trabajo antes de integración M4-C/D.

Avance M4-B3: [compatibilidad física](../validation/G3_O2_M4_PHYSICAL_COMPATIBILITY_2026-10-12.md).
Diseño: referencia fija no equivale a gas caliente; calor/interfaz no son
transporte de O2. Testigos analíticos, revisión TN 1889v1/CFAST-7.7.7;
sin ensayo externo ni cambio de sim/. Recomendado contrato experimental
gas/O2 zonal con paquetes físicos, no remap geométrico del penacho.
Siguiente M4-P1, especificación/prototipo puro antes de decidir autoridad
gaseosa de producto y selección M4-C/D. Conectar red también exige contrato
de semántica O2; no autorizado por este diseño. CO/FED y producto OFF/NO-GO.
14 testigos nuevos / 255 focales offline PASS, enlaces/AST y R2-1 verdes;
sin referencia/producto/global nuevos ni campaña de mutación GD.

Avance M4-B2: [captura pasiva del motor real](../validation/G3_O2_M4_PASSIVE_CAPTURE_2026-10-12.md).
Cuatro pares sintéticos, 3 844 checks y estados idénticos con/sin observador;
penacho, puertas y M2-V medidos, sin modificar sim/ ni tasas.
15 nuevas / 241 focales PASS, monitor final sano, referencia/R2-1 intactos.
NO-GO a adaptador físico: no hay donante O2 zonal ni conversión de gas aprobada,
ni petición interior pre-cap. Siguiente contrato de compatibilidad física
con M2-T/M2-V antes de M4-C/D. CO/FED y producto siguen OFF/NO-GO.

Avance M4-B1: [contrato de eventos offline](../validation/G3_O2_M4_EVENT_CONTRACT_2026-10-12.md).
Donantes, unidades, participantes e identidad; propuesta inmutable y auditor
independiente. 115 nuevas / 226 focales PASS, 12/12 mutantes Python en memoria.
No consumidores de sim/, Godot ni política M2-T/M2-V elegida; R2-1 verde
sin regenerar referencia. Siguiente M4-B2, captura pasiva de rutas reales
y elegibilidad; NO-GO a M4-C/D o producto hasta resolver los límites físicos.
CO/FED OFF/NO-GO. El cierre de este contrato no es calibración de incendio.

Avance M4-B: [diagnóstico del adaptador](../validation/G3_O2_M4_ADAPTER_DIAGNOSIS_2026-10-12.md).
35 escrituras directas en cinco módulos, instantánea de 64 .gd y testigos
offline. El neto de sala no determina capas; donante estratificado cambia
la ley M2-T y penacho/remap exige evitar doble paquete. NO-GO a M4-C/D;
siguiente propuesto M4-B1, contrato offline de eventos, no wiring físico.
No cambios en sim/, Godot ni activación; CO/FED sigue OFF/NO-GO.

Avance posterior del 12-10: [M4-A1 puro](../validation/G3_O2_M4_PURE_PARTITION_2026-10-12.md).
Nuevo .gd aislado, 160 304 checks, 18 contrastes Python y 14/14 mutantes
validos. Focal final 227 PASS. Referencia 346/346 y 78 gaps, 493/494 archivos
brutos iguales (solo generated_at); producto 168/168, guardarrailes/R2-1 PASS.
Global final 4 830 passed, 70 skipped, 2 xfailed, 42 subtests; todos los monitores
sanos. GO tecnico aislado, publicacion autorizada tras revision, sin wiring.
M3 y producto intactos, CO/FED OFF/NO-GO. Siguiente: diagnostico M4-B del adaptador.
Revisión staged corrigió el inventario del arnés para admitir el módulo tracked;
histórico intacto, prueba añadida y global repetida. Primera global 4 829 PASS
conservada como historial; no se repitió física con fuentes sin cambios.

Continuacion del 12-10: [M4-A, contrato de reparto](../validation/G3_O2_M4_PARTITION_CONTRACT_2026-10-12.md).
Un total de O2 y un reparto subordinado; oraculo offline, sin Godot ni cambios
en sim/. M4 significa reparto entre capas, no soporte general de varios fuegos.
GO al siguiente nucleo GDScript puro aislado; NO-GO al wiring de fuego,
transporte y exposicion sin bases y adaptador. Producto/CO/FED OFF/NO-GO.
66 pruebas nuevas / 200 focales PASS (no sumables), guardarrailes y R2-1 PASS.
Entrega offline, sin cambio en los 1 010 archivos versionados de sim/;
sin commit/push de M4-A, main intacto.

Actualizacion operativa del 12-10: [M3 cerrado tecnicamente](../validation/G3_O2_M3_IMPLEMENTATION_2026-10-11.md).
Aceptacion post-filtro, reserva y debito exacto, fraccion comun y flashover
diferido implementados en cuatro `.gd`. 477 checks de integracion, 126 del
propietario; falsacion valida 14/14 en cada campana. OFF 9/9 y ON sin limitacion
4/4 identicos byte a byte a M2-T; regresion de transporte 3 650 checks PASS.
Casas intactas completas, 10 800 ticks cada una, sin deuda, enriquecimiento
ni recorte tardio; fraccion limitada juzgada en controles sinteticos.
Referencia 346/346 y 78 gaps, 493/494 archivos brutos iguales (solo timestamp).
Producto 168/168; guardarrailes R2-1/ALL PASS. Global repetida 4 735 passed,
68 skipped, 2 xfailed, 42 subtests, monitor limpio. Nueve fallos estaticos de
la primera global corregidos sin mover motor ni informes; historial conservado.
Publicacion autorizada tras revisar el diff. No confundir cierre contable con realismo:
producto, CO/FED y M4 siguen OFF/NO-GO. La nota M2-T de abajo es historica.

Actualizacion operativa del 11-10: [M2-T](../validation/G3_O2_TRANSPORT_M2T_2026-10-11.md)
opcion D autorizada: O2 experimental inmediato y conservativo, implementado
en dos `.gd`, sin modificar caudal ni retardos de otras especies. 3 650 checks
Godot por monitor seguro y 199 pruebas offline PASS. Retomado con 7,697 GiB:
12/12 mutantes muertos, base anterior con 712 fallos válidos de comprobación,
M1/M2/M2-V 281/102/126 PASS e identidad OFF 9/9 byte a byte.
Casas sin deuda ni enriquecimiento, repetidas con temporales externos.
Referencia regenerada 18/18, 346/346 y 78 gaps; corpus 493/494 hashes LF
identicos, solo generated_at, sin manifiesto bruto previo. R2-1 y
guardarrailes PASS; producto 168/168. Dos fallos de decodificacion del
arnes, no nativos, documentados; ajuste limitado a tres decodificadores.
Primera global: tres fallos de contratos estaticos / 4 626 passed;
corregidos con 78 focalizadas PASS. Global repetida: 4 635 passed,
60 skipped, 2 xfailed, 42 subtests, exit 0 y monitor limpio. Cierre tecnico
completo y publicacion autorizada, sin activar producto. Estilo/enlaces/diff
PASS; 79 `.gd.uid` y cuatro stashes intactos, fuera del commit con `runs/`.
Revisar M3 con el transporte nuevo antes
de implementarlo; no usar deuda sintetica como defecto vivo.
M3/M4 y CO/FED siguen pendientes y el producto no se activa. Los avances
detallados posteriores al baseline historico de abajo estan en el
[subplan G3](G3_CO_END_TO_END_CLOSURE_PLAN_2026-09-27.md).

Avance G3 sin promocion de fisica: el gate de propiedad confirma que la
carga positiva de estancia gobierna el incendio aunque difiera de los
objetos; 23 diferencias distribuidas carecen de significado material
declarado. Se fijo una primera ficha NIST FCD para dos sofas completos,
alfombra con cojines y mesa bajo deteccion, pero faltan CSV temporales y
regimenes subventilados. G3-1 y G3-2 continuan NO-GO para migracion y
calibracion automatica; [subplan](G3_CO_END_TO_END_CLOSURE_PLAN_2026-09-27.md).
Cuatro controles adicionales de topologia reproducen la entrada de CO al
pasillo al abrir la puerta y la retirada al abrir la ventana; el paso a la
planta alta es minimo a 90 s. El snapshot opt-in verifica que el CO no
presente aun en salas ni expulsado esta en parcelas en transito. El cierre
global final deja residuo maximo `4,6e-8 kg`.
G3-5 mantiene pendiente el balance por paso y zona con oxidacion y
validacion experimental.

## Decision operativa vigente - 2026-09-24

El 30 de octubre deja de ser fecha objetivo. La publicacion depende de
estabilidad y credibilidad fisica en un ambito declarado, no de acabar una
lista de fases ni de mantener una suite en verde. El plan con gates G0-G6 esta
en [PLAN_PUBLICACION_2026-10-30.md](../PLAN_PUBLICACION_2026-10-30.md);
el nombre conserva la estimacion historica, no una promesa vigente.

Siguiente trabajo: fijar el ambito G0 y construir la matriz experimental G2
para fuga fria, envolvente, deformacion y vidrio; en paralelo preparar los
recorridos visuales/estabilidad y la exportacion Windows. La fisica de puertas
y envolvente sigue experimental, con product_activation=false en los 15
perfiles; no promocionarla por el mero hecho de estar implementada. FED/CO y
SVV siguen siendo un gate cientifico independiente. Ninguna fecha nueva hasta
estimar con evidencia estos bloques.

La seccion «Estado actual conocido» y las recomendaciones M5/F3.3 de abajo
conservan el historial de esa linea: sus recuentos y prioridad no sustituyen
esta decision. La matriz vigente de referencia es 346/346 requeridos PASS con
78 gaps no bloqueantes (informe del 2026-09-23); no se compara directamente
con los seis VALID_GAP de la matriz anterior.

## Regla principal

La prioridad actual es que el motor sea fisicamente auditable. No perseguir un baseline bonito si eso conserva datos incoherentes.

Cada cambio debe estar ligado a una de estas lineas:

1. Cerrar incoherencias fisicas con auditoria reproducible.
2. Mejorar instrumentacion y balances sin cambiar fisica accidentalmente.
3. Mantener validacion CFAST sin tocar tolerancias para esconder fallos.
4. Documentar explicitamente lo que queda como `VALID_GAP`, caso legacy/control o deuda Phase 3+.

Antes de tocar motor:

- confirmar `git status --short --branch`;
- revisar `docs/HANDOFF_CURRENT_STATE.md`;
- revisar `docs/validation/MOTOR_PHYSICS_VALIDATION_CHECKLIST.md`;
- ejecutar o justificar por que no se ejecuta `python scripts\simulation\validation_guardrails.py --verbose`;
- no modificar reports, baselines ni tolerancias para forzar PASS.

## Estado actual conocido

- Rama esperada: `main`; antes de esta nota estaba local ahead de `origin/main`.
- Handoff vigente: `docs/HANDOFF_CURRENT_STATE.md` rev 21.
- Ultimo estado documentado: C1 backdraft/pool-release path exercised, pero no clean promotion evidence; M5 post-backdraft HRR cut queda como proximo experimento de motor.
- Suite referencia: **347/353 PASS**.
- Los 6 FAIL restantes son los `VALID_GAP` conocidos:
  - Grupo A: O2 en `cfast_r0_window_360`.
  - Grupo C: temperatura y O2 upper en `cfast_corridor_chain`.
- F3.3l corrigió la topología real de `cfast_corridor_chain`.
- F3.3m cerró la correspondencia temporal R0→Hall: el caudal pasa de déficit
  temprano a superávit tardío y el aporte convectivo queda muy por debajo de
  CFAST.
- F3.3n valida el reparto receptor `flogo` sobre la topología corregida:
  forma las capas altas de Hall/R2 y acerca las cuatro direcciones a CFAST
  con conservación exacta. Queda default OFF y no autoriza el shadow.
- F3.3o descarta cambiar solo la fracción radiativa: duplica casi el calor
  sin aumentar el plume, sobrecalienta R0/Hall/R2 y empeora la masa upper.
- F3.3p reconstruye el balance lower y autoriza solo un experimento
  escalonado: a 600 s faltan 109.1 kg de plume frente a CFAST y las rutas
  pierden 123.4 kg de margen lower. F3.3n ayuda, pero no prueba por si solo
  que el colapso antiguo este cerrado.
- F3.3p1 reintrodujo temporalmente el contrato unificado
  `Q aceptado -> Qc -> calor + plume` con routing F3.3n. A 180 s cerro masa,
  interfaz y plume, pero sobrecalento R0 (`200.75 C` frente a `159.82 C`) y
  tambien Hall/R2. Fue NO-GO y se retiro sin ejecutar 300/600 s.
- F3.3q localiza un deficit de perdida de frontera de `3.414 MJ` hasta 180 s.
  El balance canonico cierra, pero el caso no transmite el hormigon de CFAST
  y el contrato usa `40.0 m2` de pared frente a `83.2 m2` de envolvente.
- F3.3r0 confirma que el material importa: el hormigon reduce el deficit de
  frontera de `3.414` a `0.730 MJ` y corrige la temperatura upper temprana.
  No es adoptable porque sobreenfria R0/Hall lower y R2 upper a 180 s.
- F3.3r1 cierra la atribucion: CFAST almacena unos `26.993 MJ` en superficies
  a 180 s; `13.392 MJ` son radiacion directa del fuego y `13.601 MJ` vienen
  del gas, frente a `14.163 MJ` inferidos por el balance de sala.
- El shadow material solo conserva `9.009 MJ` en pared y elimina `3.796 MJ`
  por decay ambiente sin superficie. Por eso el sink total puede coincidir
  mientras pared y lower zones quedan frios.
- F3.3r2 cierra el diseno de un shadow multi-superficie default OFF:
  techo, pared upper, pared lower y suelo; radiacion de combustion atomica;
  migracion conservativa al mover la interfaz; y un invariante unico
  gas/superficies/exterior.
- La implementacion se divide en F3.3r2a solver puro y fixtures, F3.3r2b
  estado/transacciones y F3.3r2c gates scratch 60/120/180 s. Solo r2a queda
  autorizado como siguiente paso. El parche de area completa sigue NO-GO.
- F3.3r2a ya entrega el solver puro: respuesta de hormigon a 60 s con error
  `3.07%` frente a la solucion semi-infinita y residual acumulado
  `5.96e-8 kJ` tras 10.000 pasos. No tiene wiring runtime.
- F3.3r2b/b1/b2 ya entregan estado, transaccion atomica, intercambio
  gas-superficie y topologia explicita default OFF.
- F3.3r2c cierra contabilidad multi-superficie pero falla correspondencia
  fisica a 180 s: masa/interfaz, temperaturas y radiacion aceptada.
- F3.3r2d atribuye el deficit radiativo de `4.268 MJ`: `3.814 MJ` vienen del
  throttle de decision O2, `0.454 MJ` de la trayectoria fuente y `0 MJ` del
  commit atomico. La interfaz alta desplaza `1.775 MJ` de pared upper a
  lower sin romper conservacion.
- F3.3s localiza el primer error en el path de solicitud/fuente del plume:
  ya a 10 s faltan `2.64 kg` en la capa superior y `1.07 kg` de transferencia
  acumulada, con O2 aun coherente y sin residual de proyeccion.
- CFAST entra en regimen llama/interfaz a 60 s; el O2 de SimuFire diverge a
  70 s y su `z_eff` queda pinzado cerca de `0.10 m` a 80-90 s.
- F3.3t implementa un plume Heskestad completo default OFF desde HRR/chi_rad
  canonicos aceptados y evita el segundo throttle O2. En 10-180 s mejora las
  nueve familias RMSE, entre `25.9%` y `95.5%`, con residual maximo `8e-8`.
- El mecanismo F3.3t queda GO experimental; autoridad runtime y cierre Grupo C
  siguen NO-GO.
- F3.3u confirma estabilidad hasta 600 s: las nueve familias RMSE mejoran en
  todos los horizontes, inventarios permanecen positivos y el residual maximo
  es `2.8e-7`. Sin embargo, la proyeccion falla los checks t180/t300/t600/O2.
- El owner tardio es la propuesta HRR legacy ya throttleada: a 590 s el
  shadow acepta el 100% de 137 kW aunque CFAST mantiene 300 kW. Siguiente fase
  F3.3v: disenar una propuesta de fuego canonica previa al throttle legacy.
- F3.3v cierra el diseno sin tocar motor: propuesta pura desde estado
  persistente y parametros inmutables, seguida por extincion dura, inventario
  O2, limite Kawagoe y combustible en una unica transaccion atomica.
- Quedan rechazados reconstruir HRR dividiendo por el factor legacy, imponer
  300 kW o usar fallback legacy silencioso. F3.3v1 sera default OFF,
  shadow-only y limitado al fuego t2 simple de Grupos A/C.
- F3.3v1 ya implementa esa propuesta como telemetria default OFF. El gate de
  180 s conserva exactamente 709 columnas compartidas, soporta las 18
  muestras activas de R0 y alcanza el cap t2 de 300 kW con combustible
  monotono y cero llama sin O2.
- F3.3v1 queda GO pasivo, pero autoridad y cierre de Grupo C siguen NO-GO.
  F3.3v2 ya genera productos puros de combustible, O2, siete especies,
  carbono, energia y drivers de plume con una unica fraccion aceptada.
- El gate F3.3v2 conserva las 728 columnas previas, anade 46 campos y cierra
  todos los residuales exportados. Queda GO como telemetria default OFF.
- Autoridad y cierre de Grupo C siguen NO-GO: siete objetos combustibles
  requieren sincronizacion y el bundle aun no alimenta el estado canonico.
  Siguiente fase: F3.3v2b routing atomico shadow; despues, F3.3v3
  correspondencia 180/300/600 s.
- Physics coherence audit: suite con controles intencionales registrados (`v1_backdraft_accumulation`, `v1_m4_pool_release`). Reglas FAIL/gating: B1, C1, C2, A2, A3, D1, E1, S0. WARN: O1, O2E1.
- Tests Python: **157 PASS**.

## Cambio de enfoque

La linea M4/ILV ya no es el unico centro. El proyecto paso a una revalidacion fisica integral:

- HRR, combustible, energia y regimen de combustion.
- O2 por capa/sala y acoplamiento con HRR.
- CO/CO2/HCN, generacion local, transporte y balance de carbono.
- Humo/soot, visibilidad, FED y tenabilidad.
- Temperaturas upper/lower, capas, presion, plano neutro e isoterma 150 C.
- Modelo bizona, ventilacion por puertas/ventanas, flotabilidad y transporte multi-room/multi-planta.
- Paredes, radiacion, almacenamiento termico y reradiacion.

Documento maestro:

- `docs/validation/MOTOR_PHYSICS_VALIDATION_CHECKLIST.md`

## Auditores vigentes

### Auditor fisico general

Archivos:

- `scripts/simulation/check_physics_coherence.py`
- `scripts/simulation/audit_physics_coherence_suite.py`
- `tests/test_check_physics_coherence.py`

Reglas vigentes:

| Regla | Severidad | Estado |
|---|---|---|
| `B1` inversion termica fuerte | FAIL | Gating |
| `C1` FED suma | FAIL | Gating |
| `C2` FED monotonica | FAIL | Gating |
| `A2` HRR sin combustible | FAIL | Gating |
| `A3` regimen vs O2 superior critico | FAIL | Gating |
| `D1` balance CO por sala/paso | FAIL | Gating |
| `E1` balance combustible solido | FAIL | Gating |
| `S0` conservacion humo global | FAIL | Gating |
| `O1` balance masa O2 bulk | WARN | Clean 11/11, no gating |
| `O2E1` cross-check Thornton HRR↔O2 | WARN | Clean 11/11, no gating |

### Auditor ILV por capas

Archivos:

- `scripts/simulation/check_ilv_layer_coherence.py`
- `scripts/simulation/audit_ilv_layer_coherence_suite.py`

Uso:

- Detecta HRR significativo con `o2_upper` critico y throttle/regimen incoherente.
- `fp_ilv_upper_throttle_off` sigue siendo control intencional y puede fallar si se incluye.

## Lineas cerradas

### M4 ILV upper-O2 throttle guard

Estado:

- `fire_o2_upper_throttle_enabled` existe como fix fisico gated.
- Default global: `false`.
- Activacion global: bloqueada hasta migracion coordinada.
- No mezclar con `fire_o2_canonical_enabled` sin plan explicito: ambos mecanismos compiten.
- Casos correctos con M4:
  - `fp_ilv_upper_throttle_on`
  - `layer_interface_single_room_window`
  - `v5_m4_ventilation_throttle`

Decisiones vigentes:

- `v5_ventilation_hrr_spike` queda como legacy/control pre-M4.
- `v5_m4_ventilation_throttle` es la referencia fisica corregida.
- No usar M4 para intentar cerrar Grupo A sin plan Phase 3+/O2 separado.

### S0 smoke global conservation

Estado: cerrado como `FAIL`/gating.

Cobertura:

- Valida `sum(smoke_kg) + smoke_in_transit_kg` contra generado menos venteado menos depositado.
- Corrigio contabilidad de ACH, purga por ventilacion natural, humo interior diferido y masa sub-threshold.
- Corpus fresco: 11/11 CSVs PASS, 0 findings.

### D1 CO balance

Estado: cerrado como `FAIL`/gating.

Invariante:

```text
delta_co = co_kg[t] - co_kg[t-1]
expected = delta(co_generated_kg_total)
           + delta(co_net_transport_kg_total)
           - delta(co_exterior_removed_kg_total)
residual = abs(delta_co - expected)
```

Correcciones relevantes:

- `GasExchangeSystem._purge_upper_species_to_exterior_direct`
- `ThermalSystem._flush_contaminant_deltas`
- `GasExchangeSystem._release_pending_interior_deliveries`

Nota: `co_net_transport_kg_total` es neto amplio e incluye intercambio, arrastre termico/hot-gas carry y entregas interiores diferidas. Exterior se contabiliza aparte.

### E1 fuel balance

Estado: corregido para usar combustible solido explicito.

Decision:

- E1 valida `solid_fuel_remaining_MJ` contra `fuel_consumed_MJ_total`.
- No usar `fuel_remaining_MJ` legacy visible como fuente principal: puede incluir retained/unburned/object state y dar falsos residuales.

### O2E1 Thornton cross-check HRR↔O2

Estado: **WARN**, no `FAIL`/gating todavia. La regla esta limpia en el corpus base; C1 backdraft/pool-release esta ejercitado pero no aporta evidencia limpia de promocion por zombie A3 post-evento.

Invariante:

```text
expected_o2   = delta(hrr_kj_total) * 7.6e-5   (Thornton: kg O2 / kJ HRR)
delta_o2_fire = delta(o2_consumed_fire_kg_total)
residual      = |delta_o2_fire - expected_o2|
tolerance     = max(1e-5, 0.05 * |expected_o2|)
```

Columnas clave:

- `hrr_kj_total` — acumulado por CombustionSystem como `maxf(0, hrr_kw) * dt`. Tracking-only.
- `o2_consumed_fire_kg_total` — acumulado por OES via path primario (una unidad Thornton por paso). Tracking-only.

Por que `*_fire` y no `*_all`: `o2_consumed_kg_total_all` acumula todas las rutas OES. En modo two-zone estandar (bulk + upper ambos activos), acumula 2× Thornton. El acumulador `*_fire` selecciona solo el path primario: bulk si corrio; de lo contrario lower/plume/upper segun el flag activo.

Resultado actual:

- Corpus base O2E1: PASS limpio.
- C1 backdraft/pool-release: `v1_m4_pool_release` ejercita el path (`backdraft_triggered=1` a t=350 s) pero deja 5 WARN post-evento por zombie A3.
- No cambio de fisica. O1 intacto.
- 157 tests PASS.

Criterios para promover a FAIL:

1. O2E1 PASS limpio en corpus que incluya: backdraft o pool-release, caso largo (≥ 600 s), caso multi-room con intercambio O2, caso con `effective_plume_lower` o `fire_uses_lower_o2` activos.
2. Revision de tolerancias bajo condiciones de O2 bajo y cap activo.
3. Plan explicito de promocion antes de tocar `severity`.

### O1 bulk O2 balance

Estado: **WARN-clean**, no `FAIL`/gating todavia.

Invariante:

```text
delta_bulk = (o2[t] - o2[t-1]) * air_mass_kg
expected   = -delta(o2_consumed_bulk_kg_total)
             + delta(o2_exterior_net_kg_total)
             + delta(o2_net_transport_kg_total)
             + delta(o2_zone_sync_kg_total)
residual   = abs(delta_bulk - expected)
```

Resultado actual:

- 11/11 PASS.
- 0 O1 findings.
- Max residual < `4e-4 kg`.
- Sigue como WARN hasta validarse en corpus mas amplio, largo y multi-planta.

Correcciones importantes:

- `SimulationStateBuilder` exporta `room.o2` real, no valor con correccion molar CO2 aplicada.
- O1 usa `o2_consumed_bulk_kg_total`, no `o2_consumed_kg_total_all`.
- `_apply_room_o2_mass_delta` acumula delta post-clamp real.

## Caveats conocidos

### CO2 upper dual tracking

`co2_upper_ppm` es tracer-derived (`co2_upper * 1e6`), mientras CO upper ppm es mass-derived.

Consecuencia:

- Reglas CO/CO2 ratio quedan bloqueadas.
- No implementar D2 hasta resolver o documentar la semantica dual de `co2_upper` / `co2_upper_kg`.

### O1 no sustituye balance zonal

O1 audita `room.o2` bulk. No cierra todavia la conservacion de `o2_upper` / `o2_lower`.

Pendiente:

- Balance zonal O2 por capa.
- Separacion clara de combustion, transporte y zone-sync.
- Reconciliacion con future two-zone canonico.

Estado E1 del contrato de O2 (2026-09-25, estatico mas seis fixtures pequenos
medidos paso a paso; detalle en
[E1 - base de masa](../validation/E1_O2_BASE_DE_MASA_2026-09-25.md)):

- **NO-GO** a `upper_gas_kg`/`lower_gas_kg` como autoridad de O2 en kg. Red
  OFF (producto): `ZoneFireSolver.gd:360-369` reescribe la masa baja; medido,
  Salon sellado -25,7 % y +22,6 kg de frontera sin propietario. Red ON: masa de
  gas exacta, pero dos propietarios del transporte interior (`Thermal:1505`
  mueve 64,6 kg que la red devuelve) y O2 en kg con -5,10 kg sin propietario
  con la puerta abierta.
- Prerrequisito de la alternativa B: masa baja como estado en la ruta de
  producto. Decision de alcance pendiente.
- Defecto candidato **O2-4**: `OxygenExchangeSystem` no recibe
  `two_zone_solver_enabled`, y su sumidero de capa alta descuenta el consumo
  completo ademas del bulk. Explica los 9,263 kg que O2-A atribuia al tope del
  5 %; el tope recorta 0,943 kg.
- C1, C2, C3, C4 y C5 del contrato O2-A necesitan correcciones antes de ser
  gates; E2 no empieza sin clasificar O2-4 ni reescribir C2.

### FED/SVV pendientes de revision cientifica

**Subplan de cierre G3 (27-09):** el trabajo de CO se secuencia en baseline,
propiedad de combustible, evidencia por material, libro contable pasivo,
fuente por objeto, transporte por zonas, FED/SVV y decisión de promoción por
perfil. Cada fase tiene gate GO/NO-GO/LIMITADA; ninguna fecha o coincidencia
aislada con CFAST sustituye validación experimental. Véase
[G3_CO_END_TO_END_CLOSURE_PLAN_2026-09-27.md](G3_CO_END_TO_END_CLOSURE_PLAN_2026-09-27.md).
G3-0 ya reprodujo en cinco controles que una silla sin arder puede elevar
2,92 veces el CO de un sofá con HRR y consumo prácticamente iguales; no es
un valor calibrado de producto. Ver
[baseline de fuentes G3-0](../validation/G3_FUEL_SOURCE_DYNAMIC_BASELINE_2026-09-27.md).
La traza pasiva G3-3 por paso confirma que esa silla no consume combustible
ni entrega HRR en ninguno de los 1.081 pasos, mientras cambia el CO generado.
La ampliación del libro también muestra un −7,11 % de humo generado por
añadirla, con CO y humo contablemente cerrados por sala y paso en este
corpus. No cierra todavía fuentes por objeto, balance elemental, otras
especies, energía ni transporte por zonas; **NO-GO** sigue vigente.

**Gate previo de propiedad del combustible (27-09):** el escenario amueblado
no tiene una única fuente inequívoca de energía/especies: 23 de 36 salas con
objetos en los JSON distribuidos discrepan de su carga agregada; siete de diez
presets carecen de objetos. Clasificar y dar procedencia a cada carga, preservar
los casos de referencia agregados y cerrar contabilidad pasiva por objeto
antes de calibrar CO, activar G3 o migrar el catálogo. No asumir doble
combustión universal: el proxy se excluye de las sumas de objetos. Véase
[auditoría G3 de fuentes](../validation/G3_FUEL_SOURCE_OWNERSHIP_AUDIT_2026-09-27.md).
El [gate dinámico G3-1](../validation/G3_FUEL_OWNERSHIP_DYNAMIC_GATE_2026-09-27.md)
confirma el límite de estancia: con 3 MJ de sala y 1 MJ en el sofá, el
fuego consume 1,998060 MJ tras agotarse el objeto; con 1 MJ de sala y
3 MJ en el sofá, deja ≈2 MJ sin quemar. Son controles artificiales, no
clasifican las 23 diferencias reales ni autorizan migración automática.
La [matriz G3-1 de procedencia](../validation/G3_FUEL_PROVENANCE_MATRIX_2026-09-27.md)
ubica las 23 declaraciones (17 en JSON de referencia y seis en el preset
de plantilla), pero no su significado material: todas siguen propuestas
como `legacy_unknown` hasta decisión documentada. No se han migrado JSON.

Estado: **ABIERTO**. Prioridad alta antes de la release candidate si el producto
va a presentar estas salidas como magnitudes fisiologicas fiables.

Diagnóstico interno del 26-09: [G3_FED_SVV_DIAGNOSTICO_2026-09-26.md](../validation/G3_FED_SVV_DIAGNOSTICO_2026-09-26.md).
El selector de CO bajo y la propia heurística de `co_lower_ppm` deben medirse
por separado con concentraciones impuestas; no se modifica la física por la
discrepancia de CSV. El log `SVV=%` aún imprime el peor histórico.
El fixture controlado del mismo día confirmó la incoherencia: 100 ppm de CO
impuestos en zona baja se exportan como 0 ppm, mientras FED a 0,9 m integra la
media de 343 ppm (dosis 3,59 veces la de la concentración impuesta). Ver §4 del
diagnóstico. Existe un candidato experimental de CO zonal para FED, apagado por
defecto: reproduce la dosis baja impuesta, conserva la referencia OFF 346/346
con 78 gaps e impacta solo `fed`/`fed_co` en el caso ON medido. **No está
calibrado ni autorizado para producto**; queda pendiente contrastar inventarios
zonales y fisiología antes de cambiar el valor por defecto.
El contraste de inventarios del 26-09 confirma el **NO-GO**: 0,0058 ppm de CO
bajo por masa en la sala del fuego frente a 579 ppm CFAST a 480 s, con interfaz
de capa similar. Dos checks históricos de «CO bajo» consumían en realidad la
media de sala. Ver
[G3_CO_ZONAL_INVENTORY_AUDIT_2026-09-26.md](../validation/G3_CO_ZONAL_INVENTORY_AUDIT_2026-09-26.md).
Ampliación del 27-09: un comparador diagnóstico verificable cubre cinco casos
y 28 puntos. Post-flashover ventado y corredor reproducen los logs físicos
oficiales y muestran de nuevo CO bajo casi nulo frente a 101 y hasta 439 ppm
en CFAST, aunque sus interfaces no son comparables. El contraste de dos salas
a 480 s sigue siendo el punto que mejor aísla el error zonal. No se ha
modificado ningún check oficial ni disposición de gap; el selector sigue OFF.
Antes de activar G3 hay que corregir la observabilidad del comparador y
diagnosticar el transporte intercapas, sin calibrar una tasa a un solo punto.
El control de la corrección contable experimental de CO sube el inventario
inferior en dos salas a 480 s de 0,0058 a 10,47 ppm, todavía lejos de los
579 ppm CFAST. El inventario total de CO de la sala solo permitiría 452,70
ppm abajo aun reubicándolo íntegro: el gap incluye producción o flujos,
no solo mezcla intercapas. NIST TN 1455-1 revisado confirma CO respirable en
ensayos residenciales, y FR 4016 ofrece datos crudos para un fixture, aún sin
auditar.
El siguiente gate es atribución completa de flujos de gas/especies y un caso
experimental reproducible, no una tasa exclusiva de CO. Ver
[G3_CO_CFAST_NIST_TRANSPORT_GATE_2026-09-27.md](../validation/G3_CO_CFAST_NIST_TRANSPORT_GATE_2026-09-27.md).

**Orden refinado el 27-09:** antes de atribuir el déficit al transporte,
cerrar la fuente de CO. Auditar rendimiento por combustible y régimen,
registrar generación por objeto y balance por estancia (CO generado,
oxidado, transportado e inventariado), y contrastar curvas temporales con
NIST TN 2303/1453 y un ensayo de salón amueblado. Los valores de mesa y
alfombra disponibles no permiten una calibración directa sin reservas.
Después vendrán el transporte intercapas y la exposición respiratoria.
[Evidencia y gates de producción G3](../validation/G3_CO_PRODUCCION_COMBUSTIBLES_ESTANCIA_2026-09-27.md).

Decision vigente:

- La correccion de presentacion de la fase 1 esta cerrada: distinguir valor
  actual y peor historico no valida la fisiologia subyacente. La campana de
  CO muestra sensibilidad material del selector zonal (26,2 % en un caso a
  0,9 m); no se activa el candidato por esa sola diferencia.

- La implementacion, observabilidad y regresion basica de FED estan hechas, pero
  su validacion cuantitativa no esta cerrada.
- SVV es un indice heuristico interno; no esta validado como porcentaje o
  probabilidad medica de supervivencia.

Evidencia que obliga a reabrir la revision:

- `room.fed` suma CO, HCN, hipoxia y calor, mientras algunas comparaciones
  externas usan FED asfixiante sin componente termico.
- Los checks FED de Ghanekar siguen siendo no vinculantes y cientificamente no
  cualificados; no deben cerrarse ajustando tolerancias a la salida del motor.
- Bajo la capa superior, CO usa concentracion media de sala, mientras HCN, O2 y
  CO2 usan valores zonales. Hay que justificar o corregir esa asimetria.
- La seleccion upper/lower es casi binaria y puede generar saltos al cruzar el
  plano respiratorio.
- La ruta FED de CO2 basada en masa sigue default OFF por el defecto conocido de
  `co2_upper_kg` post-extincion; produccion usa la ruta tracer.
- El FED de habitacion representa una persona inmovil a 1.8 m desde t=0, no la
  cronologia real del jugador o de una victima movil.
- SVV toma el minimo entre calor, FED y visibilidad. Puede indicar 0 % solo por
  visibilidad menor de 1 m, mezclando evacuacion con supervivencia.
- El peor valor historico `svv_worst_pct` no se recupera al ventilar; la UI ya
  distingue actual y peor historico, pero la interpretacion fisiologica y el
  texto legacy `SVV=%` del log aun requieren revision.

No confundir con defecto: FED es dosis acumulada y no debe disminuir al limpiar
la sala; debe dejar de crecer o crecer mas despacio. Del mismo modo,
`svv_worst_pct` es monotono por diseno, aunque queda por decidir si debe mostrarse
durante la partida.

Trabajo para cerrar:

1. Reproducir el caso observado y registrar escenario, sala, instante, altura y
   componentes `fed_co`, `fed_hcn`, `fed_hypoxia` y `fed_heat`.
2. Separar FED asfixiante, FED termico, tenabilidad instantanea y dosis usada
   para incapacitar a una victima.
3. Auditar el muestreo por altura/zona de CO, HCN, CO2, O2 y calor, incluida la
   transicion entre capas.
4. Resolver la dualidad tracer/masa de CO2 antes de promover esa ruta.
5. Validar primero con concentraciones impuestas y resultados analiticos, y
   despues con un benchmark experimental comparable sin rebaseline de runtime.
6. Redisenar o renombrar SVV separando tenabilidad actual, dosis acumulada,
   estado individual de victima y peor tenabilidad historica.
7. Revisar textos, colores y porcentajes de la interfaz para no presentar un
   indice heuristico como probabilidad de supervivencia.
8. Anadir guardarrailes y mutaciones para formulas, seleccion zonal, altura y
   semantica de interfaz; terminar con suites globales en verde.

Dependencia: ejecutar la recalificacion cuantitativa cuando la red de presion y
el transporte de gases de puertas/envolvente esten estables, porque cambian CO,
HCN, CO2 y O2. Si FED/SVV siguen visibles como resultados fiables, el cierre es
obligatorio antes de release candidate.

## Fallos CFAST vivos

Los 5 FAIL restantes siguen siendo estructurales y no pertenecen a D1/S0/O1:

| Grupo | Checks | Estado |
|---|---|---|
| A - `cfast_r0_window_360` | 3 checks O2 | VALID_GAP Phase 2/3+, requiere arquitectura O2/two-zone |
| C - `cfast_corridor_chain` | 2 checks temperatura | VALID_GAP Phase 3+, requiere presion/intercambio two-zone |

No cambiar tolerancias ni reclasificar estos FAIL sin decision cientifica explicita.

## Linea historica recomendada antes de la revision de publicacion

No es el siguiente trabajo de release. Se conserva como backlog del motor,
supeditado a los gates G0-G3 y a la decision de alcance del producto.

### Prioridad 1 - M5 post-backdraft HRR cut

Motivo: C1 backdraft/pool-release ya esta ejercitado, pero el caso no es evidencia limpia para promover O2E1 porque queda un zombie A3 post-evento.

Diagnostico:

- El backdraft principal de `v1_m4_pool_release` ocurre a t=350 s y agota el pool a t=355 s.
- Despues, `hrr_target_kw=0` pero `room.hrr_kw` cae con smoothing (`fire_hrr_fall_tau_s=20`), dejando HRR positivo con `o2_upper` critico.
- Esa cola produce A3/O2E1 WARNs post-evento y puede permitir reacumulacion de pool/segundo backdraft artificial.

Implementacion recomendada:

- Nuevo flag `fire_post_bd_hrr_cut_enabled`, default `false`.
- Activarlo primero solo en `v1_m4_pool_release`.
- En `CombustionSystem.gd`, despues de `room.backdraft_active` y antes de consumo/reacumulacion de pool, cortar `room.hrr_kw`, `room.hrr_target_kw` y `retained_generation_kw` cuando: no backdraft activo, no llama viable, no latencia viable, `retained_unburned_MJ < 0.001` y `fire_o2_ref < fire_o2_min_for_flame`.

Criterios de aceptacion:

- Backdraft principal preservado a t≈350 s.
- Sin segundo backdraft artificial.
- A3=0 y O2E1=0 WARN en `v1_m4_pool_release`.
- `check_physics_coherence.py` limpio para el caso.
- Guardrails globales estables por default-off.
- No tocar tolerancias ni `severity` de O2E1.

### Prioridad 1b - O2 + energia/HRR

Corpus diagnostico completado (2026-06-27). Resultados:

| Criterio | Caso | Resultado |
|---|---|---|
| C1 backdraft/pool-release | v1_m4_pool_release | ⚠️ Path ejercitado (CTRL) — O2E1 limpio durante backdraft; zombie A3 post-evento |
| C2 larga duracion ≥ 600 s | cfast_slow_growth_sealed | ✅ PASS total |
| C3 multi-room O2 exchange | cfast_two_room_door_open | O2E1 ✅ PASS; O1 247 WARNs (gap multi-room) |
| C4 effective_plume_lower | fp_ilv_open_partial_window | ✅ Ya en suite, PASS |

**Decision C1 cerrada (2026-06-27):** `v1_m4_pool_release` confirma que el motor ejecuta correctamente el path backdraft/pool-release (`backdraft_triggered=1` a t=350s, pico HRR 21 369 kW, pool agotado en t=355s, O2E1 limpio durante el evento). El zombie A3 que reaparece post-evento es un bug de motor separado — ambos casos marcados CTRL. **O2E1 permanece WARN.**

Bloqueo para O2E1 → FAIL:

- C1 "path exercised" pero no "clean promotion evidence": los 5 O2E1 WARN post-backdraft son consecuencia del zombie A3, no de un fallo de Thornton. La promocion requiere un caso backdraft/pool-release completo sin A3 zombie post-evento, o una politica de exclusion explicita aprobada.
- Requisito minimo para promover: (a) caso C1 que sale exit 0 en check_physics_coherence, o (b) decision documentada de que O2E1 WARN del zombie no bloquea la promocion porque ocurren fuera de la ventana de backdraft.

Proximo experimento para C1 limpio: M5 post-backdraft HRR cut. La politica de exclusion queda como alternativa secundaria, no preferida.

Otras reglas pendientes en el bloque O2/energia:

- HRR x dt vs consumo de combustible solido (ya cubierto parcialmente por E1 en sentido inverso).
- Coherencia entre `solid_pyrolysis_kw`, `fresh_flame_target_kw`, `smolder_hrr_target_kw`, `pool_release_hrr_target_kw` y `hrr_kw` — verificar que la suma de targets no exceda la generacion de pirolisis.
- Balance zonal O2 (`o2_upper`/`o2_lower`) — pendiente, ver caveat "O1 no sustituye balance zonal".

Restricciones vigentes:

- No anadir una segunda ruta fisica de consumo O2: OES ya aplica Thornton rate.
- `o2_consumed_kg_total_all` no es la fuente correcta para reglas de coherencia energetica: usar `o2_consumed_fire_kg_total`.

### Prioridad 2 - Corpus O1 ampliado

Mantener O1 como WARN hasta probar:

- escenarios largos;
- multi-room;
- multi-planta;
- ventilacion exterior con eventos;
- HVAC solo cuando el nucleo este estable.

### Prioridad 3 - CO2 semantics

Resolver/documentar `co2_upper_ppm` vs `co2_upper_kg` antes de reglas CO/CO2 ratio.

### Prioridad 4 - Phase 3+ two-zone canonico

Necesario a largo plazo para cerrar los VALID_GAP:

- `room.o2` derivado, no fuente independiente;
- combustion vinculada a capa fisica correcta;
- presion/doorway ODE;
- recalibracion completa de casos CFAST afectados.

## Criterios de no-regresion

Antes de commit de motor o validacion:

```powershell
python scripts\simulation\validation_guardrails.py --verbose
python scripts\simulation\audit_physics_coherence_suite.py
python scripts\simulation\audit_ilv_layer_coherence_suite.py --allow-findings
git diff --check
```

Para cierre de fase amplia:

```powershell
powershell -ExecutionPolicy Bypass -File sim\validation\run_full_reference_suite.ps1 -TimeoutSeconds 900
python -m unittest
```

Para cambios solo de documentacion:

```powershell
python scripts\check_docs_links.py
git diff --check
```

## Puntos de entrada vivos

- `docs/HANDOFF_CURRENT_STATE.md`: estado operativo actual.
- `docs/validation/MOTOR_PHYSICS_VALIDATION_CHECKLIST.md`: checklist fisico maestro.
- `docs/validation/STATUS_VALIDATION.md`: fuente de verdad de validacion legacy.
- `docs/validation/GAPS_INVENTORY.md`: conteo de gaps non-gating.
- `docs/validation/GUARDRAILS_STATUS.md`: estado de guardrails.
- `docs/architecture/PHASE_5A_O2UPPER_SWEEP_RESULTS.md`: descarte per-case Grupo A.
- `docs/architecture/PHASE_3_DOORWAY_PRESSURE_ODE_PLAN.md`: plan pendiente para corridor_chain.
- `docs/architecture/ILV_COMBUSTION_REGIME_PLAN.md`: diseno ILV.

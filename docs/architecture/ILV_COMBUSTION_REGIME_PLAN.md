# Plan de regimenes de combustion ILV / infraventilado / ventilado

Fecha: 2026-06-17
Estado: propuesta tecnica documentada, sin cambios de motor
Alcance: adaptar la propuesta externa al modelo actual de SimuFire y dejar una base comun para trabajar desde otras maquinas.

## Problema

El comportamiento observado es que, cuando el incendio entra en una zona de oxigeno muy baja, SimuFire puede apagar el fuego directamente. En un escenario real de incendio limitado por ventilacion (ILV), esto no siempre es correcto: si queda combustible, temperatura suficiente y gases no quemados, el incendio puede pasar a un estado latente o infraventilado, acumular productos incompletos y reintensificarse al recibir ventilacion.

La correccion no debe ser una subida artificial de HRR. Debe separar tres conceptos que ahora estan demasiado mezclados en la salida:

- energia potencial por pirolisis o combustible disponible;
- energia realmente quemada por oxigeno disponible;
- energia retenida en gases/productos no quemados que puede participar en crecimiento inducido por ventilacion o riesgo de backdraft.

## Realidad de validacion

CFAST puede seguir siendo util como referencia para escenarios ventilados o razonablemente controlados por combustible, pero no debe ser el patron principal para calibrar ILV. En ILV interesan fenomenos que dependen de viciacion, mezcla, CO, hollin, hidrocarburos, historial termico y ventilacion transitoria. La calibracion debera ser manual, con rangos fisicos y comparacion cualitativa/cuantitativa contra ensayos publicados.

Fuentes externas utiles localizadas:

- NIST TN 1603, "Experimental Study of the Effects of Fuel Type, Fuel Distribution, and Vent Size on Full-Scale Underventilated Compartment Fires in an ISO 9705 Room". Incluye HRR ideal vs medido, temperaturas, O2, CO2, CO, THC, hollin, eficiencia de combustion y efecto de ventilacion.
- NIST TN 1736, "Experimental Study of the Three Dimensional Internal Structure of Underventilated Compartment Fires in an ISO 9705 Room". Aporta datos 3D de temperatura, gases, CO, hollin y eficiencia en fuegos infraventilados con puerta reducida.
- FSRI/UL, "Analysis of the Coordination of Suppression and Ventilation in Single-Family Homes". Es util para comportamiento operativo: la ventilacion puede cambiar rapidamente la intensidad, por lo que el modelo necesita detectar eventos de ventilacion y no solo un nivel estatico de O2.

## Inventario del modelo actual

SimuFire ya contiene muchas piezas que la propuesta original queria introducir desde cero:

- `room.hrr_kw`: HRR real suavizado.
- `room.hrr_target_kw`: objetivo de HRR total.
- `room.pyrolysis_kw`: energia potencial generada por pirolisis.
- `room.flame_hrr_target_kw`: parte que arde como llama.
- `room.smolder_hrr_target_kw`: parte latente/smolder.
- `room.pool_release_hrr_target_kw`: liberacion adicional al reventilar.
- `room.unburned_generation_kw`: energia generada pero no quemada.
- `room.retained_unburned_MJ`: reserva de energia no quemada retenida.
- `room.unburned_gas_vol_frac`: indicador de gases combustibles retenidos.
- `room.o2_hrr_factor`: factor de HRR por disponibilidad de O2.
- `room.ventilation_response_factor`: respuesta transitoria a ventilacion.
- campos de backdraft: riesgo, acumulacion y evento.

Por tanto, la implementacion recomendada no es duplicar `hrr_potential`, `hrr_actual` y `unburned_fuel_mass` como variables nuevas de motor desde el primer paso. Primero deben mapearse a estos campos existentes y exponerse como diagnostico.

## Regimenes propuestos

La propuesta externa hablaba de `FUEL_CONTROLLED`, `ENTERING_VENTILATION_CONTROLLED`, `VENTILATION_CONTROLLED`, `VENTILATION_INDUCED_GROWTH`, `FULLY_DEVELOPED`, `BACKDRAFT_RISK` y `BACKDRAFT_EVENT`. Para SimuFire conviene hacerlos mas explicitos:

1. `FUEL_CONTROLLED`: hay oxigeno suficiente; HRR depende sobre todo del combustible/curva de fuego.
2. `VENTILATION_STRESSED`: empieza la limitacion por ventilacion; baja eficiencia, sube CO/hollin, pero aun hay llama sostenida.
3. `ILV_LATENT`: no hay llama sostenida o es marginal, pero el incendio no esta extinguido porque quedan temperatura, combustible y pirolisis/smolder.
4. `VENTILATION_CONTROLLED_BURNING`: el incendio quema lo que permite la ventilacion; la pirolisis potencial puede ser mayor que la combustion real.
5. `VENTILATION_INDUCED_GROWTH`: al abrir puerta/ventana o aumentar caudal, el fuego puede recuperar HRR rapidamente si habia energia/gases retenidos.
6. `FULLY_DEVELOPED`: alta temperatura/flujo termico y fuego generalizado; no debe usarse solo como sinonimo de HRR alto.
7. `BACKDRAFT_RISK`: mezcla caliente, baja O2, gases combustibles acumulados y ventilacion insuficiente.
8. `BACKDRAFT_EVENT`: evento transitorio limitado por combustible retenido, mezcla y apertura; debe tener duracion y energia acotadas.
9. `EXTINGUISHED`: sin combustible viable, sin temperatura suficiente o sin energia latente mantenida durante el tiempo definido.

## Senales de deteccion

El clasificador debe usar histeresis y tiempo minimo por estado. No debe cambiar de estado cada frame.

Senales principales:

- O2 medio de sala y `room.o2_hrr_factor`.
- relacion entre HRR potencial y HRR real: `pyrolysis_kw / max(hrr_kw, epsilon)`.
- diferencia entre `pyrolysis_kw` y `burned_hrr_kw`.
- `retained_unburned_MJ` y `unburned_gas_vol_frac`.
- temperatura de capa caliente y temperatura baja para viabilidad latente.
- `floor_heat_flux_kw_m2` para continuidad de pirolisis.
- fraccion de llenado de humo.
- caudal y apertura de ventilacion, mas derivada temporal de apertura/caudal.
- combustible restante.

Reglas iniciales orientativas para calibracion manual:

- `FUEL_CONTROLLED`: O2 alto, `o2_hrr_factor` alto y poca energia no quemada retenida.
- `VENTILATION_STRESSED`: O2 en descenso, `o2_hrr_factor` intermedio, CO/hollin en aumento y HRR real por debajo del potencial.
- `ILV_LATENT`: O2 bajo, llama limitada, temperatura por encima del umbral latente, combustible remanente y `pyrolysis_kw` o smolder todavia positivos.
- `VENTILATION_CONTROLLED_BURNING`: HRR real limitado por ventilacion durante varios segundos, no por falta de combustible.
- `VENTILATION_INDUCED_GROWTH`: incremento brusco de ventilacion con reserva no quemada y temperatura suficiente.
- `BACKDRAFT_RISK`: O2 bajo, gases combustibles/energia retenida altos, temperatura alta y ventilacion limitada.

## Cambio clave respecto a la propuesta adjunta

La propuesta original es correcta en direccion, pero para SimuFire debe ajustarse asi:

- No crear un motor paralelo de combustion. El primer objetivo es un `CombustionRegimeClassifier` diagnostico que lea el estado existente.
- No sustituir de golpe `CombustionSystem.step_room_fire`. Primero se debe instrumentar y registrar por que una sala entra en ILV o se extingue.
- La latencia no debe depender solo de O2. En ILV extremo puede no haber llama, pero si hay temperatura, combustible y smolder/pirolisis residual, el estado correcto puede ser `ILV_LATENT`.
- `retained_unburned_MJ` debe ser la reserva inicial de energia no quemada. Solo se anadira otra variable si la calibracion demuestra que hace falta separar energia gaseosa, combustible solido caliente y vapor de combustible.
- Los cambios de HUD deben mostrar regimen y tendencias suavizadas, pero el HUD no debe ser la fuente de verdad del modelo.
- Backdraft debe quedar como riesgo/evento acotado, no como resultado automatico de abrir una ventana.

## Fases recomendadas

### Fase 0 - Resultado de auditoria (2026-06-21, CERRADA)

Artefactos: `sim/validation/cases/cfast_ilv_audit.json`, `scripts/simulation/audit_ilv_phase0.py`.

Secuencia de regimenes (room 2, 36 m³, sellada, 900 s):

```
t=  0s  EXTINGUISHED
t=  1s  FUEL_CONTROLLED
t=186s  VENTILATION_STRESSED
t=274s  VENTILATION_CONTROLLED_BURNING
t=436s  EXTINGUISHED  <-- extincion directa, ILV_LATENT nunca mostrado
```

Condiciones en extincion (t=436 s): o2=10.9%, hrr_kw=0.00, retained_unburned_MJ=0.1497, fire_smoldering=false.

Gap estructural confirmado: con `fire_o2_min_for_flame=0.10`:
- `can_flame=false` cuando o2 < 8.5%
- `latent_viable=false` cuando o2 < 10.8%
- Ventana 8.5-10.8%: ni llama ni latencia posible -> extincion directa

Causa adicional: `fire_smoldering` requiere `hrr_kw > 0.5`, pero el HRR cayo por debajo antes de que `latent_viable` se convirtiera en la condicion limitante. El clasificador no puede mostrar `ILV_LATENT` porque depende de `fire_smoldering`.

Aceptacion verificada: se puede explicar por datos por que el fuego se apaga directamente y que condicion impidio la latencia.

---

### Fase 0 - Auditoria y reproduccion (objetivo original)

No tocar comportamiento. Crear un escenario minimo que reproduzca el apagado directo en ILV y registrar cada segundo:

- O2, CO, CO2, HCN, temperatura.
- HRR real, target, pirolisis, smolder, llama, pool release.
- `o2_hrr_factor`, `retained_unburned_MJ`, `unburned_gas_vol_frac`.
- aperturas y caudal de ventilacion.
- razon de extincion o latencia.

Aceptacion: se puede explicar por datos por que el fuego se apaga y que condicion impidio la latencia.

### Fase 1 - Clasificador solo diagnostico

Anadir un clasificador sin cambiar HRR ni gases. Debe escribir el regimen por sala en logs y, opcionalmente, exponerlo en debug.

Aceptacion: el clasificador identifica transiciones coherentes sin parpadeo: ventilado -> estresado -> ILV latente o ventilacion-controlado.

### Fase 2 - Latencia ILV controlada

Modificar la condicion de latencia para que no requiera siempre O2 suficiente para llama. Debe permitir un estado latente con HRR bajo, acumulacion limitada de no quemados y temperatura decreciente si no hay aporte.

Aceptacion: un fuego ILV no se apaga instantaneamente si queda energia termica y combustible, pero se extingue si la temperatura cae o el combustible se agota.

### Fase 3 - Reventilacion y crecimiento inducido

Usar apertura/caudal y `retained_unburned_MJ` para crecimiento transitorio. La liberacion debe estar acotada por mezcla, O2, combustible retenido y constantes de tiempo.

Aceptacion: abrir una ventana puede recuperar HRR, pero no siempre dispara backdraft ni HRR infinito.

### Fase 4 - Calibracion manual

Comparar curvas contra NIST TN 1603/TN 1736:

- forma de HRR ideal vs HRR medido;
- descenso de O2 y aumento de CO/hollin;
- diferencia entre ubicaciones front/rear y capa alta/baja;
- eficiencia de combustion en infraventilacion.

Aceptacion: tendencias monotonicamente razonables, sin saltos numericos no fisicos y con parametros documentados por preset.

## Riesgos tecnicos

- El modelo two-zone no representa bien la mezcla 3D local. Por eso el clasificador debe usar margenes e histeresis.
- Si la latencia se relaja demasiado, el fuego puede quedar vivo siempre. Deben existir temporizadores de extincion y enfriamiento.
- Si la reventilacion usa solo apertura, generara eventos falsos. Debe mirar reserva no quemada, temperatura y mezcla.
- El HUD de first-person puede amplificar la sensacion de salto si muestra valores instantaneos. La solucion de visualizacion debe ser suavizado/display rate, no alterar la fisica para que el numero se vea bonito.

## Trabajo inmediato recomendado

Antes de tocar core:

1. Preparar escenario reproducible de ILV.
2. Anadir logging diagnostico si se acepta tocar codigo de observabilidad.
3. Confirmar si `_can_sustain_latent_fire` esta descartando ILV por exigir demasiado O2.
4. Definir presets iniciales para madera/solidos y liquidos por separado.
5. Solo despues implementar el clasificador y usarlo para ajustar latencia.

## Enlaces de referencia

- NIST TN 1603: https://tsapps.nist.gov/publication/get_pdf.cfm?pub_id=861620
- NIST TN 1736: https://tsapps.nist.gov/publication/get_pdf.cfm?pub_id=908944
- FSRI/UL single-family ventilation and suppression report: https://fsri.org/resource/analysis-coordination-suppression-and-ventilation-single-family-homes

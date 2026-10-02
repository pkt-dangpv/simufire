# G3 — CO respirable: CFAST, mediciones NIST y gate de transporte (2026-09-27)

Estado: **NO-GO** para activar `fed_co_zonal_enabled` en producto. Esta nota
documenta evidencia y un experimento diagnóstico; no modifica la física, los
casos de referencia ni los 78 gaps.

## Qué representa CFAST

La [guía técnica CFAST, NIST TN 1889v1, §2.2](https://nvlpubs.nist.gov/nistpubs/TechnicalNotes/NIST.TN.1889v1.pdf)
mantiene la masa de cada especie en cada capa; los productos del fuego se
transportan con el caudal gaseoso y se acumulan en la capa receptora. La
concentración se obtiene de la masa de especie y el volumen de esa capa. El
modelo no asigna al CO una velocidad propia de ascenso por su masa molecular.
El penacho arrastra gas de la capa inferior a la superior (§3.3), mientras
los vanos permiten transporte entre recintos (§4). Para reproducir CO bajo
importan conjuntamente la producción, la masa y energía de cada capa, el
caudal por abertura y la zona receptora. Copiar solo un factor de mezcla de
CO no reproduce ese sistema.

En el repositorio ya existen candidatos *experimentales* relacionados:
`phase3_co_zonal_transport_consistency_enabled` corrige un débito de
inventario alto de CO en una ruta; F33N ensaya la deposición por flotabilidad
en sombra; F33G estudia el arrastre del chorro de puerta. Ninguno está
autorizado como física de producto. Véanse
[el experimento F33N](PHASE3_F33N_BUOYANCY_RUNTIME.md) y
[el diseño F33G](PHASE3_F33G_DOORWAY_JET_ENTRAINMENT_DESIGN.md).

## Qué miden los experimentos, y qué no

- [NIST TN 1455-1, revisión de 2008](https://nvlpubs.nist.gov/nistpubs/Legacy/TN/nbstechnicalnote1455-1r2008.pdf)
  documenta ensayos residenciales a escala real. En el ensayo SDC05,
  colchón ardiendo en un dormitorio, la figura 115 informa CO a 900 mm bajo
  el techo, aproximadamente **1,5 m sobre el suelo**: justo antes de iniciar
  la supresión, 0,049 % en el punto próximo al fuego y 0,017 % en uno remoto,
  es decir, **490 y 170 ppm**. Son concentraciones respirables no nulas; no
  prueban que la capa inferior deba igualar la superior ni dan una constante
  universal de mezcla. El informe revisado advierte correcciones de deriva
  de base en analizadores de CO/CO2 y exclusiones por ruido en otros ensayos;
  no se debe usar la primera edición ni un canal excluido como patrón.
- [NIST FR 4016](https://www.nist.gov/el/nist-report-test-fr-4016) ofrece las
  series temporales originales de 27 ensayos en una vivienda prefabricada,
  con CO, CO2, O2, humo y temperatura en varios puntos. SDC02 y SDC05 son
  candidatos para montar un fixture experimental completo. **Pendiente**:
  auditar el mapa de canales/alturas, la corrección de base y el momento de
  supresión antes de importar CSV o fijar tolerancias. En esta sesión se
  localizaron los enlaces oficiales, pero la descarga directa de CSV fue
  denegada por la red y el navegador disponible bloqueó esa URL. No se ha
  importado una serie ni se han inventado valores de canal.
- [NIST TN 1837](https://nvlpubs.nist.gov/nistpubs/TechnicalNotes/NIST.TN.1837.pdf)
  describe 24 ensayos de sillón a escala residencial; en el pasillo se
  muestreó gas a 10 cm del techo y a 1,5 m sobre el suelo (figura 2). Es una
  geometría útil para contraste superior/inferior, pero el informe no
  entrega aquí una tabla temporal emparejada de CO de ambas alturas. No
  atribuirle un cociente de mezcla que no publica.
- [NISTIR 6959](https://nvlpubs.nist.gov/nistpubs/Legacy/IR/nistir6959.pdf)
  muestra CO a alturas bajas en un incendio de almacén. Corrobora la
  posibilidad de CO cerca del suelo, pero su escala y el sesgo previo de un
  canal impiden calibrar una vivienda con esa serie.

Estas mediciones no son los CSV de CFAST del corpus: aquellos son salidas de
otro *modelo*. Una coincidencia SimuFire–CFAST es contraste de modelos; solo
un caso experimental con combustible, HRR, geometría, ventilación y sensor
definidos permite hablar de validación cuantitativa frente a NIST.

## Control experimental de una causa propuesta

Se repitió `cfast_two_room_door_open` con `--fire-o2-mode upper`,
`--co-inventory-trace` y únicamente
`--phase3-co-zonal-transport-consistency`. Corrida opt-in bajo el monitor
seguro de Godot 4.7.1: exit 0, sin timeout, cuadro de error ni proceso
residual. Archivos locales ignorados en
`runs/g3_co_inventory_20260926/cfast_two_room_co_consistency_on/`.

| Sala del fuego, 480 s | Candidato OFF | Candidato ON | CFAST |
|---|---:|---:|---:|
| CO inferior por masa (ppm) | 0,00576575 | 10,47465 | 579 |
| Interfaz (m) | 1,7359237 | 1,7359237 | 1,78 |

El arreglo contable aumenta el CO bajo unas 1 817 veces, pero ON continúa
unas 55 veces por debajo de CFAST en este punto. La interfaz y las variables
térmicas/O2 del CSV no cambiaron; sí cambian CO y FED. **Inferencia**: aquel
débito defectuoso explica parte del síntoma, pero no autoriza activar el
selector ni atribuir el resto a una sola tasa intercapas. Tampoco demuestra
que 579 ppm sea la verdad física del escenario: CFAST es aquí el comparador,
no un ensayo de NIST. El corpus de cinco casos y sus límites están en
[la auditoría G3](G3_CO_ZONAL_INVENTORY_AUDIT_2026-09-26.md).

Hay una cota de inventario más fuerte: a 480 s, la sala contiene
`co_total_kg = 0,01814318` y la zona baja `lower_gas_kg = 41,50863`.
Con la conversión del observable (`ppm = m_CO/m_gas · 29/28 · 10^6`),
poner **todo** ese CO en la zona baja daría como máximo **452,70 ppm**.
Para obtener 579 ppm con la masa baja de SimuFire se necesitarían
`0,02320476 kg` de CO abajo, más que los `0,01814318 kg` de la sala entera.
Así que ningún reparto entre capas, por sí solo, puede igualar ese punto
CFAST. También hay que contrastar generación, entrada y salida de CO y la
masa de gas de cada modelo. Esta cota no extrapola la concentración real de
un ensayo, solo descarta una explicación única de la discrepancia entre
modelos en este estado.

## Gate para cambiar `.gd` y cerrar G3

1. Construir un fixture **experimental** SDC05/SDC02 desde FR 4016 con
   canal, cota, unidad, cronología de HRR, puertas/ventanas y supresión
   auditados. Registrar incertidumbre y excluir muestras no comparables.
2. En un caso de dos salas y en el fixture experimental, medir por paso y
   por propietario: CO generado, CO alto/bajo, caudal de gas alto/bajo por
   vano, especie que sale de cada zona, zona donde se deposita, penacho,
   arrastre de chorro y cualquier proyección o clamp. Exigir cierre de
   `CO_final - CO_inicial = producción + entradas - salidas` por sala y zona.
3. Identificar cuál de las rutas existentes pierde o deposita mal **gas y
   todas sus especies**, no solo CO. Corregir la ruta canónica una vez,
   detrás de un interruptor OFF; no activar `phase2f_co_interlayer_mixing`
   ni ajustar un coeficiente a los 579 ppm.
4. Probar conservación de masa de gas, CO, CO2, O2 y energía; sensibilidad
   a altura de interfaz, puerta y ventilación; identidad OFF byte a byte.
   Si se toca `sim/core`, cumplir R2-1: referencia 346/346, 78 gaps sin
   reclasificación silenciosa, suites de producto/global y guardarraíles.
5. Solo con mejora consistente frente a varios casos CFAST **y** al menos
   un ensayo residencial NIST evaluar `fed_co_zonal_enabled`. SVV no se
   convierte por ello en probabilidad médica validada.

La fuente local llamada `NISTIR_5499_Carbon_Monoxide_Production_Full_Scale.pdf`
no debe emplearse como NISTIR 5499: su metadato/título interno corresponde
a un libro de resúmenes de la conferencia NIST de octubre de 1994, no al
informe nominal. Queda señalada en el índice bibliográfico.

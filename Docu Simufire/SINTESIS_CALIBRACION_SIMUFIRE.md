# Sintesis de calibracion para Simufire

## Alcance

Esta nota resume como aprovechar la biblioteca tecnica reunida en `Docu Simufire` para llevar `Simufire` desde una validacion interna hacia una validacion empirica basada en estudios publicados y ensayos a escala real.

## Lectura rapida

- El corpus reunido cubre cuatro frentes que ahora mismo nos faltaban: `tenabilidad`, `ventilacion`, `transporte de gases/humo` y `fuego subventilado`.
- Los estudios mas utiles para empezar no son los mas teoricos, sino los que dan tiempos, configuraciones de puertas/ventanas y mediciones en pasillos o recintos remotos.
- La comparacion preliminar con nuestro caso actual sigue apuntando al mismo problema: `Simufire` esta demasiado abierto por dentro y demasiado cerrado hacia el exterior.
- El siguiente salto de calidad no es "afinar un numero", sino crear `casos de validacion empirica nuevos` que reproduzcan geometria, ventilacion y puntos de medida de los papers.

## Familias de evidencia y utilidad practica

### 1. Vivienda a escala real - FSRI / ULRI

Documentos clave:

- `Occupant Tenability in Single Family Homes Part I`
- `Occupant Tenability in Single Family Homes Part II`
- `Coordination of Suppression and Ventilation in Single-Family Homes`
- `Coordination of Suppression and Ventilation in Multi-Family Dwellings`
- `Impact of Ventilation on Fire Behavior in Legacy and Contemporary Residential Construction`
- `Positive Pressure Ventilation During Fire Attack in Single Family Homes`
- `Impact of Fire Attack Utilizing Interior and Exterior Streams`
- `Residential Flashover Prevention with Reduced Water Flow`

Lo que aportan:

- Escenarios de vivienda completa y no solo compartimentos idealizados.
- Sensibilidad muy alta a `puerta principal`, `ventanas`, `ventilacion vertical`, `door control` y tactica.
- Benchmarks utiles de `tiempo a deterioro de tenabilidad`, `efecto de apertura/cierre de puertas` y evolucion del incendio tras intervencion.

Traduccion a Simufire:

- Necesitamos modelar mejor `aberturas exteriores iniciales`, `cambios de ventilacion durante el evento` y `estado de puertas interiores`.
- Las validaciones deben medir no solo la habitacion de origen, sino tambien `pasillos`, `dormitorios remotos` y `escaleras`.

### 2. NIST / NBS - humo, compartimentos y fuego subventilado

Documentos clave:

- `Modeling Smoke Movement Through Compartmented Structures`
- `Improvement in Predicting Smoke Movement in Compartmented Structures`
- `Smoke Movement in Rooms of Fire Involvement and Adjacent Spaces`
- `Carbon Monoxide Production in Compartment Fires`
- `Experimental Study ... Under-Ventilated Compartment Fires`
- `Three Dimensional Internal Structure of Underventilated Compartment Fires`
- `Propane Gas Fire Experiments in Residential Scale Structures`
- `Report on Residential Fireground Field Experiments`
- `CFAST Technical Reference Guide`

Lo que aportan:

- Base fisica para transporte entre compartimentos y prediccion de humos.
- Datos para revisar `CO`, `O2`, temperatura y transicion a incendio limitado por ventilacion.
- Referencias claras para contrastar una implementacion propia con un modelo de zonas tipo `CFAST`.

Traduccion a Simufire:

- Hoy necesitamos revisar `yields`, `mezcla entre capas`, `entrainment`, `flujos por aberturas` y la logica de `agotamiento de oxigeno`.
- Un benchmark fuerte seria reproducir al menos un caso tipo `ISO 9705 under-ventilated` antes de seguir tocando coeficientes a ciegas.

### 3. HVAC y transporte de gases

Documentos clave:

- `Effects of HVAC on combustion-gas transport in residential structures`
- `Experimental data from gas burner fires in residential structure with HVAC system`
- `Numerical Simulations of Gas Burner Experiments in a Residential Structure with HVAC System`
- `Air Moving Systems and Fire Protection`

Lo que aportan:

- Sensibilidad de `O2`, `CO2` y `H2O` al estado del HVAC y a la posicion de puertas de dormitorio.
- Datos y un caso de validacion practico para habitaciones remotas conectadas por pasillo.
- Un puente muy util entre `modelo multicompartment` y `caso realista de vivienda`.

Traduccion a Simufire:

- `HVAC off/on`, `rejillas pasivas` y `door open/closed` deberian ser parametros de primer orden.
- El modelo necesita poder colocar `sondas` en ubicaciones concretas, no solo promedios por recinto.

### 4. Dano termico y validacion de superficies

Documentos clave:

- `Impact of Fixed Ventilation on Fire Damage Patterns in Full-Scale Structures`
- `Evaluation of Heat Flux Profiles Through Walls in Support of Fire Model Validation`

Lo que aportan:

- Un puente entre dinamica del incendio y observables de dano en cerramientos.
- Otra via de validacion adicional, util cuando todavia no tengamos todas las especies toxicas completas.

Traduccion a Simufire:

- A medio plazo conviene registrar `flujo termico incidente`, `temperatura de superficie` y algun indicador simple de dano termico.

## Implicaciones directas para el modelo actual

### Mismatch principal ya visible

- Las puertas interiores del escenario actual estan demasiado abiertas desde el inicio.
- La ventilacion exterior esta demasiado limitada para compararla con los estudios residenciales mas usados.
- El incendio parece crecer muy rapido en el origen y luego estrangularse demasiado pronto.
- Eso genera una firma rara: `contaminacion temprana en recintos adyacentes` pero `agotamiento/extincion` antes de lo que sugieren varios benchmarks experimentales.

### Lo que no deberiamos seguir haciendo

- Ajustar un unico coeficiente global de crecimiento sin replicar antes la ventilacion del paper de referencia.
- Dar por buena una validacion solo porque el caso interno hace `PASS`.
- Comparar tiempos a flashover o IDLH usando geometria y aberturas que no se parecen al experimento.

## Hoja de ruta de validacion empirica

### Caso 1 - dormitorio y pasillo

Objetivo:

- Reproducir un caso tipo dormitorio con medicion al final del pasillo y foco en `tiempo a llegada de humo`, `caida de O2`, `CO`, `IDLH` y `flashover`.

Referencias base:

- `Evolution of combustion gas concentrations in full-scale residential fire environments`
- `Occupant Tenability Part I`
- `Smoke Movement in Rooms of Fire Involvement and Adjacent Spaces`

### Caso 2 - cocina/salon y pasillo

Objetivo:

- Capturar un incendio mas lento y ventilado que el dormitorio, con recorrido de gases hacia pasillo y distinta cronologia de tenabilidad.

Referencias base:

- `Evolution of combustion gas concentrations in full-scale residential fire environments`
- `Occupant Tenability Part II`
- `Coordination of Suppression and Ventilation in Single-Family Homes`

### Caso 3 - compartimento subventilado

Objetivo:

- Validar el paso de `fuel-controlled` a `ventilation-controlled`, y revisar `CO`, temperatura y agotamiento de oxigeno.

Referencias base:

- `NIST TN 1603`
- `NIST TN 1736`
- `Carbon Monoxide Production in Compartment Fires`

### Caso 4 - HVAC y puertas

Objetivo:

- Ver si el simulador reproduce el cambio de cronologia y concentraciones cuando `HVAC` esta encendido/apagado y la puerta del dormitorio abierta/cerrada.

Referencias base:

- `Effects of HVAC on combustion-gas transport in residential structures`
- `Experimental data from gas burner fires in residential structure with HVAC system`
- `Numerical Simulations ... HVAC System`

### Caso 5 - legado vs contemporaneo / cambios de ventilacion

Objetivo:

- Medir sensibilidad del modelo a aperturas exteriores, intervencion y configuraciones de vivienda real.

Referencias base:

- `Impact of Ventilation on Fire Behavior in Legacy and Contemporary Residential Construction`
- `Positive Pressure Ventilation`
- `Residential Flashover Prevention with Reduced Water Flow`

## Variables que debemos instrumentar en Simufire

- `time_to_flashover_s`
- `time_to_smoke_arrival_hallway_s`
- `time_to_idlh_s`
- `time_to_extinction_s`
- `O2`, `CO2`, `CO`, `H2O` por sonda
- `temperature` a altura de respiracion y en capa superior
- `smoke layer height`
- `vent flow` por puerta/ventana
- `pressure difference`
- `door state`, `window state`, `HVAC state`

## Cambios de modelo con mayor retorno

### Geometria y ventilacion

- Añadir `puerta principal` y aberturas exteriores configurables en los casos de validacion.
- Permitir `rotura de vidrio` o apertura dinamica cuando el caso experimental lo requiera.
- Distinguir entre `ventilacion exterior` e `interconexion interior`.

### Sondas y comparacion experimental

- Crear un sistema de `probes` con altura y ubicacion explicitas.
- Permitir exportar series temporales por sonda, no solo metricas resumidas por recinto.

### Especies y tenabilidad

- Consolidar `CO2` y preparar hueco para `HCN` y `FED`.
- Separar `condicion interna del fuego` de `tenabilidad en punto remoto`.

### HVAC y flujo interno

- Modelar `on/off`, rejillas y caudales basicos.
- Tratar `door position` como control de primer orden, no como detalle secundario.

## Recomendacion operativa inmediata

1. Crear un caso `ghanekar_bedroom_hallway` con ventilacion exterior realista y sonda a altura de respiracion.
2. Crear un caso `nist_iso9705_under_vent` para revisar yields y agotamiento de oxigeno.
3. Crear un caso `hvac_door_transport` con estados `HVAC on/off` y `door open/closed`.
4. Comparar los tres contra series temporales, no solo contra eventos tipo `PASS/FAIL`.

## Pendientes menores del corpus

- Localizar una URL publica estable para `Search and Rescue Tactics Part I` y `Part II`.
- Si aparece un PDF publico directo para `Measurement of Heat Transfer and Fire Damage Patterns on Walls for Fire Model Validation`, sustituir el reporte relacionado por el articulo final.


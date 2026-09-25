# Proyecto SimuFire AI — Asistente especializado en comportamiento del incendio

**Estado:** propuesta futura / no implementada
**Fecha de creación:** 2026-09-25
**Ubicación prevista en repositorio:** `docs/planning/SIMUFIRE_AI_PROJECT.md`

## 1. Objetivo

Incorporar a SimuFire una IA local, multilingüe y comercializable que explique los fenómenos ocurridos durante una simulación de incendio.

La IA no sustituirá al motor físico ni decidirá por sí sola qué ha ocurrido. Su función será interpretar y explicar resultados generados por SimuFire a partir de datos físicos, eventos y reglas previamente validadas.

Preguntas objetivo:

- ¿Por qué ha aumentado tan rápido la temperatura?
- ¿Qué efecto ha tenido abrir esta puerta?
- ¿Por qué ha aumentado el HRR?
- ¿El incendio estaba limitado por combustible o por ventilación?
- ¿Qué condiciones son compatibles con un flashover?
- ¿Por qué ha descendido el plano de humo?
- ¿Cómo ha afectado la aplicación de agua?
- ¿Qué cambió cuando se rompió una ventana?
- ¿Qué secuencia de acontecimientos explica la evolución del incendio?

El objetivo es crear un **instructor virtual de comportamiento del incendio**, no un chatbot generalista.

## 2. Principio fundamental

```text
Motor físico SimuFire
        ↓
Datos de simulación
        ↓
Fire Event Analyzer
        ↓
Hechos y fenómenos detectados
        ↓
Base de conocimiento
        ↓
LLM local
        ↓
Explicación al usuario
```

El LLM no debe inventar la física.

Siempre que sea posible, las conclusiones físicas deben proceder de:

1. variables calculadas por el motor;
2. eventos registrados por SimuFire;
3. reglas del Fire Event Analyzer;
4. conocimiento documental validado.

## 3. Fire Event Analyzer

Antes del LLM debe existir un módulo propio:

`FireEventAnalyzer`

Debe poder detectar, entre otros:

- crecimiento y decrecimiento del HRR;
- agotamiento de combustible;
- reducción de O₂;
- incendio limitado por combustible;
- incendio limitado por ventilación;
- cambios tras apertura o cierre de puertas;
- cambios tras apertura o rotura de ventanas;
- modificación del flujo de gases;
- propagación entre recintos;
- descenso o ascenso de la capa de humo;
- cambios en temperaturas de capa superior e inferior;
- acumulación de gases calientes;
- condiciones compatibles con rollover;
- condiciones compatibles con flashover;
- condiciones compatibles con backdraft;
- efecto del viento;
- aplicación de agua;
- enfriamiento de gases;
- extinción o decaimiento;
- reignición;
- cambios de presión relevantes;
- transición entre regímenes de combustión.

Los fenómenos con incertidumbre no deben presentarse como hechos absolutos.

```text
NO:
"Ha ocurrido un flashover."

PREFERIDO:
"Los datos muestran condiciones compatibles con una transición a flashover."
```

## 4. Datos para la IA

No se recomienda enviar al LLM todos los valores de todos los pasos temporales.

El Fire Event Analyzer debe resumir los cambios importantes.

```json
{
  "time_s": 195,
  "room": "Bedroom_03",
  "event": "ventilation_change",
  "cause": "door_open",
  "before": {
    "o2_percent": 14.1,
    "hrr_kw": 720,
    "upper_temp_c": 390
  },
  "after": {
    "o2_percent": 16.8,
    "hrr_kw": 1280,
    "upper_temp_c": 475
  },
  "confidence": 0.93
}
```

Ventajas:

- más velocidad;
- menor consumo de memoria;
- más precisión;
- mejor trazabilidad;
- mejor funcionamiento en móvil;
- menos alucinaciones.

## 5. Modelo candidato

### Principal

**Qwen3-1.7B**

Motivos:

- tamaño reducido;
- adecuado para ejecución local;
- soporte multilingüe amplio;
- licencia Apache 2.0;
- cuantizable;
- compatible con runtimes locales como llama.cpp;
- viable para PC, tablet y móvil sin API externa.

La familia Qwen3 declara soporte para 119 idiomas y dialectos.

### Versión ligera

**Qwen3-0.6B**

Pensada para:

- móviles con menos memoria;
- tablets económicas;
- modo de bajo consumo;
- dispositivos donde 1.7B resulte demasiado lento.

### Estrategia

```text
SimuFire AI Lite
Qwen3-0.6B Q4

SimuFire AI Standard
Qwen3-1.7B Q4
```

La selección definitiva debe hacerse con benchmarks propios de SimuFire.

## 6. Licencias y comercialización

### Qwen3

Los modelos Qwen3-0.6B y Qwen3-1.7B se publican bajo **Apache License 2.0**.

Esto permite plantear su uso en un producto comercial respetando las obligaciones de la licencia y conservando los avisos correspondientes.

### Runtime

**llama.cpp** se distribuye bajo licencia **MIT**.

### Regla de proyecto

Antes de cada lanzamiento comercial debe revisarse:

- licencia exacta del modelo;
- licencia de la cuantización;
- tokenizer;
- runtime;
- librerías enlazadas;
- modelos auxiliares;
- LoRA o adaptadores;
- datasets utilizados;
- documentación incluida.

No debe asumirse que futuras versiones mantendrán exactamente las mismas condiciones.

## 7. Ejecución local

Objetivo prioritario:

**SimuFire AI debe funcionar sin conexión a Internet.**

Ventajas:

- coste de API por consulta: 0 €;
- sin dependencia de red;
- menor latencia de red;
- mayor privacidad;
- funcionamiento en formación sin cobertura;
- coste operativo casi independiente del número de usuarios.

La IA debe cargarse solo cuando se utilice.

```text
Simulación normal
        ↓
Evento relevante
        ↓
Fire Event Analyzer
        ↓
Se almacena explicación estructurada
        ↓
El usuario solicita explicación
        ↓
Se activa el LLM
```

## 8. Tamaño previsto

Estimaciones iniciales pendientes de medir con las cuantizaciones definitivas:

| Componente | Tamaño orientativo |
|---|---:|
| Qwen3-0.6B Q4 | ~0,4–0,6 GB |
| Qwen3-1.7B Q4 | ~1,0–1,3 GB |
| Runtime | decenas de MB |
| Reglas FireEventAnalyzer | despreciable frente al modelo |
| Base documental | ~50–500 MB inicialmente |
| LoRA futuro | normalmente mucho menor que el modelo base |

La descarga de la IA debería ser opcional.

## 9. Hardware

### PC

La versión 1.7B cuantizada debería ser viable en equipos actuales de gama media.

Objetivos:

- no competir innecesariamente con Godot por la VRAM;
- inferencia en CPU o aceleración parcial;
- carga del modelo solo cuando sea necesario;
- contextos pequeños;
- respuestas breves.

### Tablet / móvil

**Lite 0.6B**
- dispositivos modestos;
- menos RAM;
- menor latencia;
- menor consumo.

**Standard 1.7B**
- móviles y tablets de gama media/alta.

Los requisitos definitivos se fijarán con pruebas reales.

## 10. Runtime multiplataforma

Primera opción a investigar:

**llama.cpp / GGUF**

Motivos:

- C/C++;
- ejecución local;
- cuantización;
- Android;
- Apple/Metal;
- CPU y distintos backends;
- licencia MIT.

La integración con Godot debe aislarse:

```text
AIProvider
 ├── LocalLlamaCppProvider
 └── FutureProvider
```

Así SimuFire no dependerá directamente de un único runtime.

## 11. Multilingüe

El idioma se definirá desde SimuFire.

Los identificadores internos deben ser neutrales:

```text
ventilation_limited
flashover_conditions
door_opened
water_application
upper_layer_temperature_rise
```

El LLM se encargará de expresarlos en el idioma elegido.

## 12. Niveles de explicación

### Alumno
Explicación sencilla y pedagógica.

### Bombero
Terminología operacional y comportamiento del incendio.

### Instructor
Explicación causal más completa, con variables y secuencia temporal.

### Técnico
Valores, relaciones físicas, limitaciones del modelo y grado de confianza.

## 13. Base de conocimiento

Debe existir una base documental propia y controlada:

- documentación técnica de SimuFire;
- documentación científica usada en la validación;
- bibliografía sobre comportamiento del incendio;
- referencias de CFAST/FDS cuando proceda;
- documentos técnicos reconocidos;
- manual propio de interpretación;
- definiciones validadas.

## 14. Especialización futura

No se propone entrenar un LLM desde cero.

Orden recomendado:

```text
FASE 1
Modelo base + prompts + datos estructurados

FASE 2
RAG / base de conocimiento

FASE 3
Dataset de casos SimuFire

FASE 4
LoRA / fine-tuning si mejora de forma demostrable
```

## 15. Dataset SimuFire

Cada simulación puede producir pares:

```text
Entrada:
estado inicial
+
eventos
+
evolución física

Salida esperada:
explicación validada
```

También deben incluirse casos negativos:

- datos insuficientes;
- fenómeno no confirmado;
- correlación sin causalidad demostrada;
- varias explicaciones posibles.

La IA debe poder responder:

`No hay datos suficientes para afirmar la causa.`

## 16. Seguridad científica

Reglas obligatorias:

1. El LLM nunca modifica el resultado del motor físico.
2. El LLM no crea variables inexistentes.
3. Debe diferenciar dato, inferencia y explicación.
4. Los fenómenos inciertos deben expresarse como compatibles/probables.
5. Debe poder indicar qué datos sostienen una explicación.
6. Si faltan datos, debe indicarlo.
7. Las afirmaciones críticas deben poder reproducirse sin depender del LLM.
8. El sistema debe evaluarse contra casos conocidos.
9. La IA no debe ocultar las limitaciones del modelo bizonal.
10. El objetivo es explicar SimuFire, no simular el incendio por su cuenta.

## 17. Formato de respuesta recomendado

```text
EVENTO
Apertura de puerta a los 182 s.

CAMBIO OBSERVADO
O₂: 14,1 → 16,8 %
HRR: 720 → 1.280 kW
T capa superior: 390 → 475 °C

INTERPRETACIÓN
La apertura creó una nueva vía de ventilación. El aumento de oxígeno permitió
incrementar la tasa de combustión y produjo un aumento rápido del HRR y de la
temperatura de la capa superior.

CONFIANZA
Alta.

LIMITACIÓN
La relación se basa en las variables disponibles en el modelo de SimuFire.
```

## 18. Fases de implementación

### Fase AI-0 — Especificación

- definir eventos;
- definir variables accesibles;
- definir formato JSON;
- seleccionar 20–50 escenarios de prueba;
- fijar idiomas iniciales.

### Fase AI-1 — Fire Event Analyzer

- detector de eventos;
- timeline;
- reglas deterministas;
- confidence score;
- exportación JSON.

### Fase AI-2 — Prototipo LLM PC

- Qwen3-1.7B;
- GGUF Q4;
- llama.cpp;
- comunicación Godot ↔ runtime;
- respuestas en español e inglés.

### Fase AI-3 — Evaluación multilingüe

Idiomas mínimos propuestos:

- español;
- inglés;
- francés;
- alemán;
- italiano;
- portugués.

### Fase AI-4 — Móvil/tablet

- Android;
- iOS/iPadOS;
- perfil Lite;
- perfil Standard;
- benchmarks de RAM;
- latencia;
- batería;
- temperatura.

### Fase AI-5 — Base de conocimiento

- documentos validados;
- retrieval;
- trazabilidad;
- citas internas.

### Fase AI-6 — Especialización

- dataset SimuFire;
- evaluar LoRA;
- comparar contra modelo base;
- mantener LoRA solo si la mejora es medible.

## 19. Criterios de aceptación

Antes de considerar la IA lista para producto:

- explicación causal correcta en escenarios validados;
- no inventar variables;
- no confundir correlación con causalidad;
- no afirmar fenómenos no demostrados;
- funcionamiento offline;
- español e inglés sólidos;
- comportamiento aceptable en el resto de idiomas;
- funcionamiento en PC;
- funcionamiento en una gama definida de Android;
- funcionamiento en iPad/iPhone objetivo si se distribuye allí;
- RAM dentro del presupuesto;
- latencia aceptable;
- licencias auditadas;
- pruebas automatizadas;
- posibilidad de desactivar completamente la IA.

## 20. Decisión inicial propuesta

```text
Modelo:
Qwen3-1.7B Q4

Modelo Lite:
Qwen3-0.6B Q4

Runtime:
llama.cpp / GGUF

Arquitectura:
SimuFire Engine
    ↓
FireEventAnalyzer
    ↓
Structured Fire Context
    ↓
Knowledge Layer
    ↓
Local LLM
    ↓
SimuFire AI UI
```

La decisión no queda cerrada. Antes de integrar el modelo se compararán los modelos pequeños disponibles en ese momento.

## 21. Coste operativo previsto

Para ejecución totalmente local:

- coste de API por consulta: **0 €**;
- conexión a Internet: **no obligatoria**;
- coste por usuario adicional: esencialmente distribución, soporte y consumo del dispositivo;
- coste principal: desarrollo, validación y mantenimiento.

## 22. Riesgos principales

- alucinaciones del LLM;
- consumo excesivo de RAM en móvil;
- latencia;
- calentamiento y batería;
- cambios futuros de modelos/licencias;
- traducciones técnicas incorrectas;
- confusión entre aproximación bizonal y realidad local;
- exceso de confianza del usuario.

Mitigación principal:

**mantener la lógica física y la detección de eventos fuera del LLM.**

## 23. Fuentes iniciales

- Qwen3 oficial: https://qwenlm.github.io/blog/qwen3/
- Qwen3-1.7B: https://huggingface.co/Qwen/Qwen3-1.7B
- Qwen3-0.6B: https://huggingface.co/Qwen/Qwen3-0.6B
- llama.cpp: https://github.com/ggml-org/llama.cpp

## 24. Fuentes de conocimiento y entrenamiento

SimuFire AI puede empezar a desarrollarse antes de que SimuFire esté operativo.

Debe distinguirse entre tres usos distintos de la documentación y de los simuladores externos:

### 24.1 RAG / consulta documental

La documentación técnica no tiene por qué usarse directamente para modificar los pesos del modelo.

Primera opción recomendada:

```text
Documentación validada
        ↓
Indexado / búsqueda semántica
        ↓
Fragmentos relevantes
        ↓
LLM
        ↓
Respuesta fundamentada
```

Fuentes candidatas:

- documentación propia de SimuFire;
- manuales y documentación técnica de CFAST;
- manuales y documentación técnica de FDS;
- documentación de verificación y validación;
- bibliografía científica seleccionada;
- documentos técnicos sobre comportamiento del incendio;
- material formativo propio del proyecto.

Ventajas:

- conocimiento actualizable sin reentrenar;
- trazabilidad;
- posibilidad de citar la fuente utilizada;
- menor riesgo de introducir conocimiento incorrecto en los pesos;
- menor coste de desarrollo.

### 24.2 Dataset sintético generado con CFAST

CFAST puede utilizarse como generador masivo de casos por su bajo coste computacional relativo.

Se pueden variar automáticamente:

- geometría de recintos;
- altura;
- puertas;
- ventanas;
- área de ventilación;
- posición y momento de apertura;
- combustibles;
- curvas HRR;
- ventilación mecánica;
- conexiones entre recintos;
- tiempos de intervención.

Cada ejecución podría producir:

```text
Configuración inicial
        +
Eventos programados
        +
Evolución temporal
        +
Resultados físicos
        =
Caso de entrenamiento/evaluación
```

Los resultados pueden transformarse después en ejemplos explicativos supervisados.

### 24.3 Dataset de referencia con FDS

FDS se utilizará para una selección menor de escenarios.

Su misión no será generar millones de casos sino aportar casos de mayor detalle espacial para:

- contrastar fenómenos;
- estudiar flujos complejos;
- observar efectos locales que un modelo bizonal no representa;
- enriquecer escenarios críticos;
- evaluar cuándo una explicación basada en el modelo de zonas debe incluir limitaciones.

Estrategia propuesta:

```text
Muchos casos:
CFAST

Casos seleccionados y de mayor detalle:
FDS

Casos propios de producto:
SimuFire
```

### 24.4 Fine-tuning / LoRA

Solo debe plantearse después de disponer de un dataset suficientemente grande y validado.

No se recomienda entrenar el modelo desde cero.

Objetivos posibles del ajuste:

- terminología de incendios;
- estructura de respuesta;
- clasificación de fenómenos;
- explicación causal;
- construcción de escenarios;
- mejor obediencia al formato estructurado de SimuFire.

Antes y después de cualquier ajuste debe existir un benchmark fijo para comprobar que realmente mejora el sistema.

---

## 25. Generación automática de escenarios

SimuFire AI tendrá una segunda capacidad independiente del análisis:

**construir escenarios de SimuFire a partir de lenguaje natural.**

Ejemplo de entrada:

```text
Crea un dormitorio de 4 x 3 m con una puerta al pasillo,
una ventana al exterior, una cama y un armario.
El incendio empieza en la cama y la puerta se abre a los 120 s.
```

La IA no deberá crear directamente escenas Godot.

Debe generar un formato intermedio controlado.

Ejemplo:

```json
{
  "rooms": [
    {
      "id": "bedroom",
      "width_m": 4.0,
      "depth_m": 3.0,
      "height_m": 2.5
    }
  ],
  "openings": [
    {
      "type": "door",
      "from": "bedroom",
      "to": "corridor"
    },
    {
      "type": "window",
      "from": "bedroom",
      "to": "outside"
    }
  ],
  "fuels": [
    {
      "type": "bed",
      "room": "bedroom",
      "ignition_time_s": 0
    }
  ],
  "events": [
    {
      "time_s": 120,
      "action": "open_door",
      "target": "bedroom_to_corridor"
    }
  ]
}
```

Después:

```text
Lenguaje natural
        ↓
Scenario AI
        ↓
SimuFire Scenario Schema
        ↓
Validador
        ↓
Constructor de escenario
        ↓
SimuFire
```

El validador debe impedir:

- dimensiones imposibles;
- aperturas sin recinto de destino;
- objetos fuera de la geometría;
- parámetros fuera de límites;
- eventos que referencien objetos inexistentes;
- combinaciones no soportadas por el motor.

---

## 26. Generación de escenarios por objetivo

La IA también podrá recibir un objetivo didáctico.

Ejemplos:

```text
"Crea un escenario que evolucione hacia un incendio limitado por ventilación."

"Crea un ejercicio donde abrir una puerta provoque un aumento claro de HRR."

"Crea dos escenarios iguales salvo por la ventilación para comparar resultados."
```

La arquitectura futura puede ser:

```text
Objetivo didáctico
        ↓
IA propone escenario
        ↓
Validador
        ↓
CFAST / SimuFire
        ↓
Fire Event Analyzer
        ↓
¿Se produjo el fenómeno buscado?
        ↓
Sí → aceptar escenario
No → modificar parámetros y volver a probar
```

Esto permitiría generar ejercicios automáticamente sin depender de que una persona ajuste manualmente cada variable.

---

## 27. Tres funciones de SimuFire AI

El sistema puede dividirse conceptualmente en tres funciones:

### A. Scenario Builder

Convierte lenguaje natural u objetivos didácticos en escenarios válidos.

### B. Fire Analyst

Analiza la evolución del incendio a partir de datos estructurados.

### C. Fire Instructor

Explica al usuario lo ocurrido adaptándose al nivel y al idioma.

Las tres funciones pueden compartir:

- el mismo modelo base;
- la misma base de conocimiento;
- parte del mismo vocabulario;
- el mismo runtime local.

Pero deben tener prompts, validadores y contratos de datos separados.

---

## 28. Arquitectura ampliada

```text
                         ┌──────────────────────┐
Lenguaje natural ──────→ │ Scenario Builder AI  │
                         └──────────┬───────────┘
                                    ↓
                         SimuFire Scenario Schema
                                    ↓
                               Validator
                                    ↓
              ┌─────────────────────┼─────────────────────┐
              ↓                     ↓                     ↓
           SimuFire               CFAST                  FDS
              ↓                     ↓                     ↓
              └────────────── Simulation Data ───────────┘
                                    ↓
                           Fire Event Analyzer
                                    ↓
                           Structured Fire Events
                                    ↓
                 ┌──────────────────┴─────────────────┐
                 ↓                                    ↓
          Fire Analyst AI                      Fire Instructor AI
                 ↓                                    ↓
       análisis técnico                      explicación al usuario
```

---

## 29. Ruta de trabajo para empezar ahora

No es necesario esperar a que SimuFire esté terminado.

### ETAPA 0 — Crear el contrato de datos

**Objetivo:** definir el idioma común entre SimuFire, CFAST, FDS y la IA.

Crear:

```text
simufire_ai/
  schemas/
    scenario.schema.json
    simulation_state.schema.json
    fire_event.schema.json
    explanation.schema.json
```

Definir como mínimo:

- recintos;
- geometría;
- aberturas;
- combustibles;
- HRR;
- O₂;
- CO;
- CO₂;
- temperaturas;
- capas;
- presión;
- flujo entre recintos;
- eventos;
- acciones del usuario;
- resultados.

**Resultado:** la IA podrá desarrollarse sin depender del código de Godot.

### ETAPA 1 — Crear escenarios manuales de referencia

Crear entre 20 y 50 escenarios sencillos.

Primer conjunto recomendado:

1. incendio libre en una habitación;
2. puerta cerrada;
3. puerta abierta;
4. apertura de puerta a mitad de simulación;
5. ventana abierta;
6. apertura de ventana tardía;
7. puerta + ventana;
8. recinto pequeño;
9. recinto grande;
10. fuego de HRR bajo;
11. fuego de HRR alto;
12. caída progresiva de O₂;
13. incendio limitado por ventilación;
14. incendio limitado por combustible;
15. propagación entre dos recintos;
16. aplicación de agua;
17. cierre de una abertura;
18. cambio de ventilación;
19. caso compatible con condiciones de flashover;
20. caso donde no exista evidencia suficiente para diagnosticar un fenómeno.

Formato:

```text
tests/ai/scenarios/
```

### ETAPA 2 — Automatizar CFAST

Crear un generador de entradas CFAST.

Objetivo inicial:

```text
Python
   ↓
genera escenario CFAST
   ↓
ejecuta CFAST
   ↓
lee resultados
   ↓
convierte a schema SimuFire AI
```

Primero producir unas pocas decenas de escenarios.

Después ampliar de forma paramétrica.

Variables iniciales:

- dimensiones;
- HRR;
- puerta;
- ventana;
- tiempo de apertura;
- número de recintos.

### ETAPA 3 — Fire Event Analyzer v0

Construir un analizador determinista, sin IA.

Primeros detectores:

- aumento rápido de HRR;
- descenso de O₂;
- subida de temperatura de capa superior;
- apertura/cierre de puertas;
- apertura/cierre de ventanas;
- cambio de régimen de ventilación;
- propagación entre recintos;
- aplicación de agua;
- enfriamiento.

Salida:

```json
{
  "event": "ventilation_increase",
  "time_s": 180,
  "evidence": [...],
  "confidence": 0.91
}
```

### ETAPA 4 — Primer prototipo LLM

Ejecutar Qwen local fuera de Godot.

Primera prueba:

```text
JSON de simulación
        ↓
Fire Event Analyzer
        ↓
Qwen
        ↓
Explicación
```

Probar:

- español;
- inglés;
- francés;
- alemán;
- italiano;
- portugués.

Medir:

- RAM;
- tiempo hasta primer token;
- tokens/s;
- calidad técnica;
- alucinaciones;
- obediencia al formato.

Comparar al menos:

- Qwen3-0.6B;
- Qwen3-1.7B.

### ETAPA 5 — Scenario Builder v0

Crear prompts para transformar lenguaje natural al schema de escenarios.

Ejemplos:

```text
"Crea una habitación de 4 x 4 m..."
```

↓

```json
scenario
```

Después validar automáticamente el JSON.

No ejecutar todavía Godot.

### ETAPA 6 — Generador de escenarios por objetivo

Añadir objetivos como:

```text
ventilation_limited
rapid_hrr_growth_after_door_open
two_room_smoke_spread
```

La IA genera candidatos y CFAST comprueba si se produce el comportamiento deseado.

### ETAPA 7 — Introducir FDS

Seleccionar los casos más importantes y reproducirlos en FDS.

No intentar hacer al principio generación masiva con FDS.

Objetivo:

- validar patrones;
- enriquecer el dataset;
- identificar diferencias entre modelo de zonas y CFD;
- crear ejemplos donde la IA deba mencionar las limitaciones del modelo.

### ETAPA 8 — Crear dataset supervisado

Formato orientativo:

```text
scenario
simulation_history
detected_events
question
expected_answer
language
difficulty
sources
```

Separar:

- entrenamiento;
- validación;
- test.

El conjunto de test no debe utilizarse durante el ajuste del modelo.

### ETAPA 9 — Evaluar LoRA

Solo después de que el sistema funcione con RAG + prompts.

Comparar:

```text
Qwen base
vs
Qwen + RAG
vs
Qwen + RAG + LoRA
```

Mantener LoRA únicamente si la mejora es clara y reproducible.

### ETAPA 10 — Integración con SimuFire

Cuando el motor esté preparado:

```text
SimuFire
        ↓
exporta el mismo schema
        ↓
todo el sistema AI existente sigue funcionando
```

El objetivo es que la integración sea una sustitución de la fuente de datos, no una reescritura del sistema.

---

## 30. Primer sprint recomendado

Trabajo que puede empezar inmediatamente:

### Sprint AI-001

**Objetivo:** demostrar que el concepto funciona sin depender de SimuFire.

Entregables:

- `scenario.schema.json`;
- `simulation_state.schema.json`;
- `fire_event.schema.json`;
- 20 escenarios de prueba;
- conversor básico de resultados;
- Fire Event Analyzer v0;
- benchmark Qwen3-0.6B;
- benchmark Qwen3-1.7B;
- 50 preguntas técnicas con respuesta esperada;
- evaluación en español e inglés.

Criterio de éxito:

> El sistema recibe un historial de incendio estructurado y produce una explicación técnicamente coherente sin inventar datos que no estén presentes.

---

## 31. Orden de prioridad

```text
1. Schema común
2. Casos de prueba
3. Automatización CFAST
4. Fire Event Analyzer
5. Qwen local
6. Scenario Builder
7. RAG documental
8. Dataset masivo CFAST
9. Casos selectivos FDS
10. LoRA
11. Integración Godot
12. Móvil / tablet
```

No conviene empezar por el fine-tuning ni por la integración con Godot.

El activo más importante al principio será:

**el dataset estructurado + el sistema de eventos + los benchmarks.**

---

## 32. Estado actual actualizado

**El proyecto puede empezar ya de forma independiente a SimuFire.**

No hace falta esperar a que el motor, el editor o la interfaz estén terminados.

Lo que sí debe evitarse por ahora es acoplar la IA directamente a estructuras internas de Godot que todavía puedan cambiar.

La primera implementación debe trabajar únicamente contra schemas externos y datos de prueba.

Cuando SimuFire esté listo, el motor deberá limitarse a exportar datos compatibles con esos schemas.

Esto permite desarrollar desde ahora:

- análisis de incendios;
- generación de escenarios;
- multilingüe;
- RAG;
- CFAST;
- FDS;
- evaluación de modelos;
- dataset propio;
- futura especialización mediante LoRA.

La IA podrá evolucionar de forma paralela al simulador.

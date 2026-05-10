# ISSUE-010: Clasificar overrides fisicos, numericos y empiricos por escenario

Severidad: Media  
Area: validacion, calibracion, uso seguro  
Hallazgo relacionado: SF-AUD-001, SF-AUD-020

## Evidencia

- `sim/validation/cases/cfast_r0_window_360.json` cambia parametros como O2 minimo, taus y releases.
- `sim/validation/cases/ghanekar_bedroom_hallway.json` ajusta multiplicadores de CO, transporte y calor.
- Muchos overrides son legitimos si representan condiciones fisicas del escenario: geometria, combustible, ventilacion, instrumentacion o frontera numerica. Algunos pueden ser ajustes empiricos y deben marcarse como tales.

## Riesgo

Un escenario calibrado puede parecer validacion general si no se distingue entre condicion fisica del caso y ajuste empirico. Para entrenamiento, esto puede crear confianza indebida fuera del dominio calibrado.

## Referencias recomendadas

- ASTM E1355.
- CFAST TN 1889v3.
- FDS SP 1018 validation methodology.

## Criterio de cierre

- Cada caso declara parametros globales, overrides fisicos, overrides numericos y overrides empiricos.
- Cada override empirico incluye motivo, fuente, sensibilidad y dominio de aplicabilidad.
- La UI/documentacion distingue modo cualitativo, semicuantitativo validado y no validado.
- CI falla si un escenario validado deja de pasar tolerancias.

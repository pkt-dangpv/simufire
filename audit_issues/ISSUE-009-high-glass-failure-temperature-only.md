# ISSUE-009: Rotura de ventanas modelada solo por temperatura de capa superior

Severidad: Alta  
Area: ventanas, ventilacion, flashover  
Hallazgo relacionado: SF-AUD-011

## Evidencia

- `sim/core/GlassFailureSystem.gd:17-20`: temperatura 250 C +/- 80 C, apertura 0.15/s, max 0.85.
- `sim/core/GlassFailureSystem.gd:70-79`: apertura cuando `room.temp_upper_c >= break_temp`.

## Riesgo

La rotura de vidrio es un cambio tactico/termico mayor. Si ocurre demasiado pronto o tarde, HRR, O2, CO, humo y flashover quedan desplazados.

## Referencias recomendadas

- SFPE glass breakage correlations.
- UL FSRI/NIST ventilation experiments.

## Criterio de cierre

- Vidrio tiene tipo, espesor, area, marco, temperatura inicial y condicion de radiacion/conveccion.
- Se calcula flujo al vidrio y gradiente termico.
- Tests demuestran sensibilidad a vidrio simple/doble/templado y a fuego cercano/remoto.

# Estructura visual

Esta carpeta contiene solo presentacion e interaccion visual. La simulacion y sus reglas siguen en `sim/`.

- `2d/`: visualizador plano, overlays 2D y escenas auxiliares del mapa.
- `3d/`: escena 3D, geometria visual, humo, fuego, mobiliario y camaras.
  - `3d/smoke/`: mallas y materiales de humo.
  - `3d/fire/`: materiales de llama y fuego de techo.
  - `3d/furniture/`: clasificacion, colocacion, carga, formas procedurales y estados visuales de mobiliario/combustibles.
  - `3d/openings/`: pose y geometria base de puertas/ventanas.
- `fp/`: control de primera persona, raycast de interaccion, postura y luces locales.
  - `fp/FPVisibilityOverlay.gd`: overlay de humo y visibilidad efectiva en FP.
  - `fp/FPOpeningVisuals.gd`: helpers de geometria visual para puertas/ventanas FP.

Regla de mantenimiento: los scripts de `view/` leen el estado publico que entrega el simulador y lo convierten en representacion visual. No deben introducir reglas fisicas, victoria/derrota ni cambios de estado del core.

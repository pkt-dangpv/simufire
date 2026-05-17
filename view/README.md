# Estructura visual

Esta carpeta contiene solo presentacion e interaccion visual. La simulacion y sus reglas siguen en `sim/`.

- `2d/`: visualizador plano, overlays 2D y escenas auxiliares del mapa.
  - `2d/openings/`: geometria de puertas/ventanas y helpers de picking del plano.
  - `2d/rooms/`: calculos puros del estado visual por sala.
- `3d/`: escena 3D, geometria visual, humo, fuego, mobiliario y camaras.
  - `3d/camera/`: camara orbital, zoom y ajuste al modelo.
  - `3d/smoke/`: mallas, materiales, sprites, animacion y puentes de humo entre aberturas.
  - `3d/fire/`: materiales, mallas y animacion de llama y fuego de techo.
  - `3d/furniture/`: clasificacion, colocacion, carga, formas procedurales y estados visuales de mobiliario/combustibles.
  - `3d/geometry/`: geometria base de habitaciones.
  - `3d/interaction/`: picking de raton y conversion pantalla-modelo.
  - `3d/openings/`: pose y geometria base de puertas/ventanas.
- `fp/`: control de primera persona, raycast de interaccion, postura y luces locales.
  - `fp/FPVisibilityOverlay.gd`: overlay de humo y visibilidad efectiva en FP.
  - `fp/FPOpeningVisuals.gd`: helpers de geometria visual para puertas/ventanas FP.

Regla de mantenimiento: los scripts de `view/` leen el estado publico que entrega el simulador y lo convierten en representacion visual. No deben introducir reglas fisicas, victoria/derrota ni cambios de estado del core.

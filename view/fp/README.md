# Primera persona

`FirstPersonController.gd` coordina movimiento, camara, postura, input y escena FP. Las piezas especializadas deben ir saliendo a modulos pequenos:

- `FPVisibilityOverlay.gd`: calculo visual del overlay de humo y visibilidad efectiva en la postura actual.
- `FPOpeningVisuals.gd`: geometria visual de aperturas FP, empezando por la pose de hojas de ventana.

Mantener aqui solo presentacion e interaccion. La fisica de humo, gases, FED y temperatura sigue perteneciendo a `sim/`.

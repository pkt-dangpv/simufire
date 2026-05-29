# Primera persona

`FirstPersonController.gd` coordina movimiento, camara, postura, input y escena FP. Las piezas especializadas deben ir saliendo a modulos pequenos:

- `FPVisibilityOverlay.gd`: calculo visual del overlay de humo y visibilidad efectiva en la postura actual.
- `FPOpeningVisuals.gd`: geometria visual de aperturas FP, empezando por la pose de hojas de ventana.
- `FPOpeningInteraction.gd`: ciclo de fracciones de apertura y texto de prompt de uso.
- `FPPlayerMotion.gd`: lectura WASD, direccion horizontal, velocidades y etiquetas de postura.

Mantener aqui solo presentacion e interaccion. La fisica de humo, gases, FED y temperatura sigue perteneciendo a `sim/`.

SimuFire FP assets
==================

Estas escenas son la base editable del modo primera persona. El generador de `view/fp/FirstPersonController.gd` instancia estos `.tscn` cuando existen y los escala a las medidas del objeto del escenario.

- `furniture/*.tscn`: muebles, textiles y cargas visibles.
- `openings/*.tscn`: paneles de puertas y ventanas.

La posicion exacta y el tamano real de cada objeto se editan en los escenarios de `res://scenarios/*.json` desde el editor de vivienda. La forma visual de cada tipo de objeto se edita abriendo su `.tscn` en Godot.

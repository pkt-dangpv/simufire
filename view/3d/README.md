# Visual 3D

`Visualizer3D.gd` coordina la escena y mantiene el enlace con el estado publico del simulador. Las piezas especializadas se separan por dominio visual:

- `camera/`: calculos de camara orbital, zoom y ajuste al modelo.
- `smoke/`: geometria, materiales, sprites, animacion y puentes de humo entre aberturas.
- `fire/`: materiales, mallas y animacion de llama y extension de fuego bajo techo.
- `furniture/`: clasificacion, colocacion, carga de assets, formas procedurales y estados visuales de mobiliario/combustibles 3D.
- `geometry/`: geometria base de habitaciones, suelos, paredes y etiquetas.
- `interaction/`: picking de raton y conversion pantalla-modelo.
- `openings/`: calculos de pose y geometria base de puertas/ventanas 3D.

Mantener aqui solo representacion visual. Si una logica cambia masa, temperatura, gases, ventilacion, FED o propagacion, pertenece a `sim/`, no a `view/3d/`.

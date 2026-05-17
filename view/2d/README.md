# Visual 2D

`Visualizer.gd` coordina el dibujo en planta y mantiene la API publica usada por `Main.gd`.
Las piezas nuevas deben salir a subcarpetas por dominio visual:

- `openings/`: geometria de puertas/ventanas, segmentos compartidos/exteriores y helpers de picking.
- `rooms/`: calculos puros de estado visual por sala, como SVV, colores y etiquetas compactas.

Mantener aqui solo presentacion e interaccion 2D. Si una logica cambia masa, temperatura, gases, ventilacion, FED o propagacion, pertenece a `sim/`.

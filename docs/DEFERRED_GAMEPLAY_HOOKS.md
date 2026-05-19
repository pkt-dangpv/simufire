# Deferred Gameplay Hooks

Estado: idea conservada fuera del runtime activo.

La antigua UI tactica comentada en `Main.gd` y `ui/hud.gd` no estaba conectada a la
escena activa. Para reactivarla de forma limpia haria falta implementar estas piezas:

- Paneles HUD: `WaterPanel`, `VentPanel`, `RescuePanel` con sus botones.
- Senales HUD para agua, ventilacion y rescate.
- Handlers en `Main.gd` que traduzcan esas acciones a cambios de simulacion.
- Helpers activos en el engine para seleccionar habitaciones con fuego, cancelar
  supresion y detectar extincion.
- Criterios de victoria/derrota cubiertos por validacion o una escena de juego.

No basta con descomentar el codigo antiguo: dependia de nodos inexistentes y de
helpers del engine tambien comentados.

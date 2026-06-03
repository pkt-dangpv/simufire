class_name FPPreset
extends Resource

## Perfil de configuración para FirstPersonController.
## Crear instancias .tres desde el Inspector de Godot y asignar a fp_preset
## en FirstPersonController para cambiar entre perfiles sin tocar la escena.

@export_group("Iluminacion")
## Habilita la luz de relleno ambiental difusa.
@export var ambient_fill_enabled: bool = true
## Habilita las luces de techo por sala.
@export var room_ceiling_lights_enabled: bool = true
## Modo de iluminación exterior.
@export_enum("Dia", "Noche") var exterior_lighting_mode: String = "Dia"
## Activa el contexto exterior (ciudad/fachada visible desde ventanas).
@export var exterior_context_enabled: bool = true

@export_group("Marcadores")
## Muestra los marcadores de detectores en vista FP.
@export var show_fp_detectors: bool = true
## Muestra los marcadores de víctimas en vista FP.
@export var show_fp_victims: bool = true
## Reproduce aviso sonoro procedural cuando un detector visible se activa.
@export var fp_detector_alarm_enabled: bool = true

@export_group("Humo")
## Alpha máximo del overlay de humo (0.0 = sin efecto, 0.97 = casi opaco).
@export_range(0.0, 1.0, 0.01) var smoke_overlay_max_alpha: float = 0.97
## Distancia a la que el campo se considera despejado (sin humo). Metros.
@export var fp_visibility_clear_m: float = 30.0

@export_group("HUD Tecnico")
## Muestra el panel HUD técnico (T, CO, CO₂, O₂, HCN, FED, Vis).
@export var show_technical_overlay: bool = true
## Muestra el readout compacto de visibilidad si el panel técnico está oculto.
@export var show_visibility_readout: bool = true

@export_group("FED Victimas")
## FED mínimo para estado incapacitada (default NFPA 1710: 0.3).
@export var fp_victim_fed_incapacitated_threshold: float = 0.3
## FED mínimo para estado mortal (default FED = 1.0).
@export var fp_victim_fed_fatal_threshold: float = 1.0

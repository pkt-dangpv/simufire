# Checklist de verificación visual — Regresión

**Escenario de referencia:** `scenarios/two_storey_reference.json`
- 2 plantas (PB 0.0 m, P1 2.9 m), 8 habitaciones
- Ignición en Salon PB (room 0)
- 900 s de simulación

**Escenario secundario:** `scenarios/compact_apartment_reference.json` (una planta, para regresión rápida)

---

## Pasada de humo (ejecutar antes y después de cada fase)

### Resolución 1: 1280×720 (viewport nativo)

| # | Paso | OK? | Notas |
|---|------|-----|-------|
| 1 | Cargar `two_storey_reference.json` en el editor | | |
| 2 | Iniciar simulación, esperar ≥60 s (humo visible) | | |
| 3 | **Visor 2D:** selector de planta funciona, humo visible en ambas plantas | | |
| 4 | **Visor 2D:** labels legibles, isoterma 150°C solo si T_upper≥150 | | |
| 5 | **Visor 2D:** SVV/FED badges visibles y coherentes | | |
| 6 | Cambiar a **Visor 3D** orbital | | |
| 7 | **Visor 3D:** seleccionar sala en PB con clic → resalta correcta | | |
| 8 | **Visor 3D:** seleccionar sala en P1 con clic → resalta correcta | | |
| 9 | **Visor 3D:** arrastrar un mueble en P1 → se mantiene bajo el cursor | | |
| 10 | **Visor 3D:** humo volumétrico visible, fuego animado | | |
| 11 | Cambiar a **Visor FP** | | |
| 12 | **FP:** overlay de humo se activa al entrar en la capa | | |
| 13 | **FP:** HUD técnico muestra datos (sin "null" ni "--" inesperados) | | |
| 14 | **FP:** subir escaleras a P1 funciona | | |
| 15 | Salir con **"Salir y guardar + gráficas"** | | |
| 16 | Ventana de gráficas aparece, dimensionada dentro de la pantalla | | |
| 17 | Gráficas: 5 PNGs por sala, orden `hrr, temp, capas, gases, fed_svv` | | |
| 18 | Zoom y pan en las gráficas funcionan | | |
| 19 | Cerrar visor de gráficas → resumen técnico accesible | | |
| 20 | Cerrar todo → vuelve al editor limpiamente | | |

### Resolución 2: 1920×1080 con escala Windows 125%

| # | Paso | OK? | Notas |
|---|------|-----|-------|
| 1–20 | Repetir la pasada completa | | |
| 21 | Verificar que ventanas de gráficas y resumen no se salen de pantalla | | |

### Salida sin gráficas

| # | Paso | OK? | Notas |
|---|------|-----|-------|
| 22 | Iniciar simulación, pausar | | |
| 23 | Menú salir → "Salir sin guardar" | | |
| 24 | Verificar que NO se crea carpeta nueva en `graphs/` | | |
| 25 | Verificar que NO se lanza proceso Python | | |

### Regresión rápida (una planta)

| # | Paso | OK? | Notas |
|---|------|-----|-------|
| 26 | Cargar `compact_apartment_reference.json` | | |
| 27 | Simulación ≥30 s, cambiar 2D→3D→FP→2D | | |
| 28 | Salir con gráficas, verificar PNG generados | | |

---

## Criterios de aceptación por fase

- **Fase 0:** Pasos 1-2 (carga del escenario) funcionan; `.gdignore` impide imports en `graphs/`
- **Fase 1:** Pasos 15-20 y 22-25 pasan
- **Fase 2:** Pasos 7-9 pasan en escenario multi-planta
- **Fase 3:** Pasos 3-5, 10, 13 verifican las correcciones puntuales
- **Fase 4:** Sin regresión en pasos 1-20; mejora de FPS medible en escenarios grandes
- **Fase 5:** Pulido visual confirmado visualmente

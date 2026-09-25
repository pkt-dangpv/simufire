# Plan vivo de publicación de SimuFire

> Decisión vigente: 24 de septiembre de 2026. El nombre del archivo conserva la previsión histórica; **el 30 de octubre ya no es fecha objetivo ni compromiso**. Se publicará cuando exista una versión estable y suficientemente contrastada con la realidad para un ámbito de uso declarado. No se publicará una beta científicamente débil por cumplir calendario.

## Criterio de salida

La primera versión debe funcionar de forma reproducible, comunicar sus límites y no presentar como fiable una magnitud que no se ha contrastado. Una suite en verde demuestra regresión respecto a sus referencias; por sí sola no valida la física nueva ni la seguridad de las decisiones que sugiera al jugador. El ámbito será entrenamiento y comparación de escenarios, no predicción cuantitativa de un incendio real ni soporte operativo para una intervención.

La fecha se fijará **después** de completar el inventario de evidencia y dimensionar el trabajo restante. Se reservará una ventana de release candidate sin cambios de física y margen para corregir defectos. Si un gate científico no cierra, se acota y explica la capacidad afectada o se retrasa la salida; no se activa por calendario. No asignar porcentajes de avance sin denominador y criterios verificables.

## Punto de partida (24-09-2026)

- La referencia actual informa 346/346 comprobaciones requeridas PASS y 78 gaps no bloqueantes en su matriz. No es comparable directamente con la antigua matriz de 347/353 y seis VALID_GAP; conservar ambas como historia, sin declarar resueltos los gaps por cambio de recuento.
- D1 (fuga fría de puerta), R3 (fuga de envolvente), D2 (deformación prescrita), D3 (caída prescrita de vidrio) y su activación experimental están implementados y ensayados en sus contratos. Los 15 perfiles de producto mantienen product_activation=false. **Eso no equivale a calibración ni a autorización de uso ordinario.**
- La presentación de FED/SVV se corrigió; la credibilidad del cálculo de exposición, especialmente CO en zona respiratoria y la semántica de SVV, sigue abierta.
- Las últimas suites reportadas pasan, pero faltan una campaña visual sistemática documentada, ensayos largos de producto y una exportación Windows reproducible. La ausencia de un registro sistemático no niega las pruebas manuales ya realizadas.

## Gates de publicación

| Gate | Entregable verificable | Criterio de cierre |
|---|---|---|
| G0 · Ámbito y evidencia | Lista de escenarios, geometrías, regímenes y salidas que se van a publicar; para cada una, fuente, observables, incertidumbre y límites | Ninguna afirmación de realismo fuera de ese ámbito; vacíos de evidencia visibles antes de calibrar |
| G1 · Integridad del motor | Balances de masa, especies y energía; estabilidad y casos de referencia frescos | Sin pérdidas inexplicadas, pasos descartados ocultos ni regresiones en los escenarios de salida; 346/346 requeridos y gaps revisados, no solo contados |
| G2 · Puertas, vidrio y envolvente | Comparación experimental por familia (ELA y flujo de rendija, deformación, rotura de vidrio, interacción) y sensibilidad de parámetros | Activar cada familia solo si su intervalo y condiciones de aplicación son defendibles; si no, mantenerla experimental y acotar el producto |
| G3 · Exposición y comunicación | Auditoría FED por especie y altura, componente térmico, SVV y trazabilidad UI/log | Las magnitudes visibles significan lo que dice la interfaz y no inducen una lectura de seguridad no demostrada |
| G4 · Producto estable | Matriz reproducible de editor, ejecución, vistas, guardado/carga, escenarios largos, rendimiento y recuperación de errores | Sin bloqueos críticos, crashes recurrentes, corrupción de estado ni divergencia visual grave en plataformas soportadas |
| G5 · Distribución | Exportación Windows reproducible, instalación limpia, arranque, recursos, rutas de escritura y desinstalación | Otra máquina puede instalar y ejecutar la misma versión sin el entorno de desarrollo |
| G6 · Release candidate | Congelación, suites completas, recorrido manual, notas y límites públicos | Todos los gates anteriores cerrados o con una exclusión explícita que no falsee las capacidades anunciadas |

Cada gate requiere artefacto, responsable, fecha de última prueba y resultado PASS/NO-GO. Un resultado provisional no se convierte en valor de producto. La revisión científica debe contrastar observables e incertidumbre con datos experimentales apropiados; CFAST y las pruebas internas son referencias útiles, pero no sustituyen ese contraste.

## Orden de trabajo desde hoy

1. **G0 y auditoría de G2.** Fijar el conjunto mínimo de escenarios residenciales y salidas. Partir de la matriz por familia ya realizada en [el diseño de puertas, §23.2 y §23.10](PROMPT_MOTOR_FUGAS_PUERTA_CERRADA.md): verificar su vigencia, vincularla a los escenarios seleccionados y registrar decisión por familia (candidata a producto, experimental o excluida). No repetir la búsqueda bibliográfica como si esa matriz no existiera.
2. **G1 y G3 en paralelo lógico, sin mezclar cambios.** Revisar los 78 gaps según relevancia del ámbito y cerrar el diagnóstico FED/CO antes de prometer SVV o seguridad de ocupantes. Cambios de motor solo tras hipótesis, medición anterior, fixture y regresión OFF.
3. **G4/G5 temprano.** Montar matriz visual y de estabilidad reproducible y prueba de exportación Windows ahora, para descubrir dependencias de producto mientras avanza la evidencia científica. No esperar al final para probar distribución.
4. Integrar únicamente las capacidades que superen su gate. Después, congelar física, completar G6 y fijar fecha de publicación con margen real.

El próximo trabajo concreto es una **matriz de aplicabilidad G0/G2**, que extienda la matriz científica existente: escenario/observable, rango físico, fuente experimental, valor o intervalo, incertidumbre, correspondencia con el modelo, prueba existente, hueco y decisión. En D1 ya consta que faltan ELA/exponente/reparto medidos en puertas residenciales instaladas; en R3, permeabilidad del marco por longitud; en D2, ley térmica residencial; y en D3, ensayos de compartimento y resolución del templado. Verificar también la interacción con presión y envolvente. No inventar calibraciones para rellenar celdas.

## Seguimiento de plazos

Revisar al cerrar cada gate y al aparecer un defecto estructural. Registrar duración observada, trabajo restante estimado, riesgos y nueva ventana de publicación; no usar un semáforo ligado a una fecha retirada. Si la evidencia obliga a estrechar el ámbito o ampliar el plazo, la decisión se documenta antes de cambiar el producto.

| Fecha | Previsión o decisión | Contexto |
|---|---|---|
| 2026-09-19 | Beta/early access el 2026-10-30; confianza 70 %, semáforo amarillo | Estimación original con R3 en curso y D2–D4 pendientes; supersedida por avances y revisión del criterio de salida |
| 2026-09-24 | Fecha abierta, condicionada a G0–G6 | El usuario prioriza estabilidad y credibilidad física frente al 30-10; no se publicará una versión recortada solo para cumplir esa fecha |

# ISSUE-006: Humo, soot y visibilidad mezclan magnitudes opticas y masa agregada

Severidad: Alta  
Area: humo, visibilidad, soot  
Hallazgo relacionado: SF-AUD-008

## Evidencia

- `sim/smoke/SmokeModel.gd:16-20`: `smoke_density_kg_m3=0.18`, `visibility_extinction_m2_per_kg=8700`, `C=3`.
- `sim/smoke/SmokeModel.gd:135-148`: visibilidad calculada como `C/(K*concentracion)`.
- `smoke_kg` se usa tambien para capa/volumen, no solo soot.

## Riesgo

Si K=8700 m2/kg se aplica a humo total en vez de soot, la visibilidad puede ser fisicamente incorrecta por ordenes de magnitud. Impacta busqueda, supervivencia y lectura del incendio.

## Referencias recomendadas

- ASTM E1354 visible smoke release.
- NIST TN 1603 soot data.
- SFPE visibility/extinction correlations.

## Criterio de cierre

- Separar `soot_kg`, `smoke_aerosol_kg` y gases.
- Validar optical density/extinction contra dataset.
- Tests garantizan unidades correctas y limites de visibilidad por altura.

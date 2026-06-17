# Documentation Link Audit

Fecha: 2026-06-17.

## Alcance

Se añadió `scripts/check_docs_links.py` para validar enlaces Markdown locales.

El modo por defecto revisa documentación vigente y preparada para CI. El modo completo se ejecuta con:

```powershell
python scripts/check_docs_links.py --all
```

## Resultado

- Documentación vigente: preparada para check automático.
- Histórico completo: contiene deuda conocida en auditorías antiguas, sesiones históricas y documentos de `sim/validation/`.

## Deuda Detectada en Histórico

Tipos principales:

- enlaces absolutos antiguos a `F:/OneDrive/Documentos/GitHub/simufire/...`;
- enlaces relativos escritos como si el documento estuviera en la raíz;
- referencias antiguas a líneas concretas que ya no existen o se movieron;
- referencias a rutas históricas previas a la reorganización documental.

## Decisión

No se corrigen masivamente los documentos históricos para evitar alterar evidencia de auditoría o sesiones pasadas. El checker de CI omite esas zonas por defecto y valida la documentación viva.

Zonas tratadas como históricas por defecto:

- `docs/archive/`;
- `docs/audits/`;
- `docs/literature/`;
- `docs/sessions/`;
- `sim/validation/`.

Cuando se promueva un documento histórico a documentación vigente, debe revisarse con `python scripts/check_docs_links.py --all` o moverse fuera de esas zonas y corregir sus enlaces.

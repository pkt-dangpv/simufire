# ADR 0005: Local Literature Library

## Status

Accepted.

## Context

La bibliografía local estaba en una carpeta con espacio en la raíz. Eso era incómodo para scripts, enlaces y presentación del repositorio.

## Decision

Ubicar bibliografía, PDFs y material externo en `docs/literature/`.

## Consequences

Los scripts que descargan bibliografía deben usar `docs/literature/` por defecto. Los documentos que citen fuentes locales deben referenciar la nueva ruta.

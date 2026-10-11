# Migración de equipo — 11 de octubre de 2026

## Alcance y estado

El código publicable se recupera desde GitHub. El trabajo privado y local
necesita además un respaldo separado: no se debe publicar indiscriminadamente
el historial de todas las ramas ni ejecutar `git push --mirror`.

Base de esta migración: `main` en `8e256c97`, que incorpora el cierre técnico
del motor M2-T (`28f74c4d`) y las actualizaciones publicadas de `simufire_ai`.
El avance local a esa base fue por fast-forward. No se cambió física ni se
ejecutó Godot para preparar esta migración.

- Las dos ramas de viviendas ya tienen referencias publicadas:
  `codex/playable-homes` y `codex/playable-homes-isolated`.
- La rama `codex/g3-fed-co-zonal-shareable` conserva el cierre del motor.
- Cuatro commits locales de la rama antigua `codex/g3-fed-co-zonal` contienen
  originales FSRI excluidos de publicación. Se conservan únicamente en el
  respaldo privado; no se fusionan en `main` ni se suben al repositorio público.
- Hay cuatro stashes y diecinueve checkouts registrados, incluidos experimentos
  con cambios sin commit. Estar respaldados no convierte esos cambios en
  implementaciones aprobadas ni verificadas.
- `runs/`, los archivos ignorados, los temporales diagnósticos y los archivos
  nuevos de los checkouts no se recuperan con un simple `git clone`.

El disco autorizado para el respaldo privado es `D:`. El estado final se
certifica en los manifiestos del respaldo, no por la existencia de su carpeta.
No formatear hasta comprobar los certificados y restaurar en el nuevo equipo.

## Recuperar el proyecto público

En el equipo nuevo, instalar Git y clonar en una carpeta nueva:

```powershell
git clone https://github.com/pkt-dangpv/simufire.git
Set-Location simufire
git status --short --branch
git log -1 --oneline
```

Leer [el handoff vigente](../HANDOFF_CURRENT_STATE.md) y el
[informe M2-T](../validation/G3_O2_TRANSPORT_M2T_2026-10-11.md).
M3/M4 no están implementados por esta migración. CO/FED siguen OFF/NO-GO:
no activar física experimental para intentar comprobar que el clon funciona.

Preparar las dependencias según los documentos del proyecto. La cadena del
motor se verificó con Godot `4.7.1.stable.official.a13da4feb`; una versión
diferente exige su propia comprobación. No abrir los checkouts históricos en
Godot ni lanzar suites en paralelo. Las pruebas que necesiten Godot deben usar
el monitor seguro y su guarda de memoria (mínimo 6 GiB disponibles).

## Recuperar trabajo privado

El respaldo contiene una instantánea de archivos, un inventario, un manifiesto
SHA-256 y un bundle de Git sin dependencias del repositorio original. Contiene
material no apto para publicación: mantenerlo en disco o nube privados.

Para restaurar el historial privado en una carpeta distinta del clon público:

```powershell
git clone "D:\RespaldoSimuFire_2026-10-11\simufire-private.bundle" simufire-private
```

La ruta real puede llevar un sufijo para evitar sobrescribir otro respaldo.
Consultar `git_state.json` y `GIT_VERIFIED.json` dentro de esa carpeta: contienen
las referencias y hashes que hay que comprobar. Los stashes históricos y los
HEAD separados deben recuperarse desde sus referencias de respaldo; no asumir
que `git clone` reconstruye automáticamente una lista de stashes.

Los archivos sin commit se encuentran bajo `snapshot/`. Copiar únicamente los
archivos necesarios a un checkout del commit correspondiente, y revisar el
diff. Las rutas `.git` de los worktrees apuntan al ordenador anterior: **no
copiarlas como si fueran checkouts portables**. Crear nuevos worktrees con Git
y restaurar después sus archivos. Nunca sobrescribir el clon público con toda
la instantánea privada.

## Condiciones antes de borrar el equipo anterior

1. `COPY_VERIFIED.json` declara PASS, sin archivos omitidos ni cambios de origen.
2. `GIT_VERIFIED.json` declara PASS para ramas, stashes y HEAD de los worktrees.
3. El bundle se ha restaurado y comprobado en un repositorio independiente.
4. Se ha comprobado en el equipo nuevo la presencia de los archivos locales
   necesarios, no solo que `main` abre correctamente.
5. Se conserva una segunda copia privada si los datos son irremplazables.

El respaldo del proyecto no equivale a una imagen del sistema: no incluye por
sí mismo credenciales, instalación de herramientas, configuración de todas las
aplicaciones ni historial completo de chats. Revisar por separado documentos o
assets de la diseñadora que estén fuera de las carpetas del proyecto.

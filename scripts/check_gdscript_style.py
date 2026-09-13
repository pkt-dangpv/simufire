# -*- coding: utf-8 -*-
"""Guardarrail de estilo y salud del codigo GDScript de la linea visual.

No opina: cuenta. Cada regla dice cuantas veces se rompe y donde, y el proceso
sale con codigo 1 si hay alguna.

Las reglas no son gusto personal: cada una se puso despues de encontrar el fallo
que describe.

  - **Funcion privada que nadie llama.** La auditoria del 2026-09-11 encontro
    nueve, y una de ellas -`_outflow_color`- era *la version vieja y con el
    fallo* de una funcion que si se usa: mezclaba hasta un 58 % hacia el naranja
    y por eso el vano se leia como una caja anaranjada. El codigo muerto no es
    solo peso: es la respuesta equivocada esperando a que alguien la copie.
  - **Parametro sin tipo.** Este repositorio esta tipado; un `building` sin tipo
    deja pasar cualquier cosa hasta que revienta en tiempo de ejecucion.
  - **Dos lineas en blanco entre funciones**, que es como se lee el resto del
    fichero.
  - **print() en codigo de producto.** Una traza olvidada escribe en cada
    fotograma. Los diagnosticos de verdad van en funciones `_log_*` y se
    gobiernan desde el inspector con un `@export`, que es la regla de la casa.
  - Espacios al final, sangrado con espacios, CRLF y comparaciones con
    `== true`.

  python scripts/check_gdscript_style.py [--detail [texto]]
"""
from __future__ import annotations

import os
import re
import sys
from collections import Counter, defaultdict

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# La superficie que vigila: la linea visual, el editor y la interfaz.
SCAN_DIRS = ['editor', 'view', 'ui', 'sim/building']
# Y donde ademas se BUSCAN usos, para no llamar muerta a una funcion que llaman
# las herramientas o una escena.
USE_DIRS = SCAN_DIRS + ['tools', 'scenes', 'scripts', 'tests']
USE_SUFFIXES = ('.gd', '.tscn', '.py')

# Las que llama Godot por su cuenta: nunca aparecen escritas en ningun sitio.
GODOT_CALLBACKS = re.compile(
    r'^_(ready|process|physics_process|input|unhandled_input|unhandled_key_input|'
    r'draw|init|notification|enter_tree|exit_tree|gui_input|to_string|get|set|'
    r'get_property_list|property_can_revert|property_get_revert|validate_property|'
    r'integrate_forces|shortcut_input|iter_init|iter_next|iter_get)$'
)
# Los diagnosticos si pueden imprimir: van gobernados por un @export.
DIAGNOSTIC_FUNC = re.compile(r'^_log_|_diagnostics$|^_dump_|^_report')


def _iter_files(dirs, suffixes=('.gd',)):
    for d in dirs:
        root_dir = os.path.join(REPO_ROOT, d)
        if not os.path.isdir(root_dir):
            continue
        for root, _dirs, files in os.walk(root_dir):
            for name in sorted(files):
                if name.endswith(suffixes):
                    yield os.path.join(root, name)


def _rel(path):
    return os.path.relpath(path, REPO_ROOT).replace('\\', '/')


def _split_params(params: str):
    """Parte por comas de PRIMER nivel: Color(1, 1, 1) lleva comas dentro."""
    depth = 0
    current = ''
    out = []
    for ch in params:
        if ch in '([{':
            depth += 1
        elif ch in ')]}':
            depth -= 1
        if ch == ',' and depth == 0:
            out.append(current)
            current = ''
        else:
            current += ch
    out.append(current)
    return [p.strip() for p in out if p.strip()]


def run():
    findings = defaultdict(list)

    def add(rule, path, line_no, text):
        findings[rule].append((_rel(path), line_no, text))

    defined = defaultdict(list)

    for path in _iter_files(SCAN_DIRS):
        with open(path, encoding='utf-8') as handle:
            src = handle.read()
        lines = src.split('\n')
        blank_run = 0
        current_func = ''

        for i, ln in enumerate(lines, 1):
            if ln.rstrip() != ln and ln.strip() != '':
                add('espacios sobrantes al final de linea', path, i, ln.strip()[:60])
            if ln.startswith('    ') and not ln.lstrip().startswith('#'):
                add('sangrado con espacios en vez de tabulador', path, i, ln.strip()[:60])
            if re.search(r'==\s*(true|false)\b', ln):
                add('comparacion con true/false', path, i, ln.strip()[:60])
            if re.search(r'\b(TODO|FIXME|HACK|XXX)\s*[:()]', ln):
                add('marca de trabajo pendiente', path, i, ln.strip()[:70])

            match = re.match(r'^(?:static )?func ([A-Za-z_]\w*)', ln)
            if match:
                current_func = match.group(1)
                defined[current_func].append((path, i))
                if i > 1 and blank_run < 2:
                    prev = lines[i - 2].strip()
                    if prev != '' and not prev.startswith('#'):
                        add('funcion sin dos lineas en blanco delante', path, i, ln.strip()[:60])
                # Firma completa: puede ocupar varias lineas.
                sig = ln
                j = i - 1
                while sig.count('(') > sig.count(')') and j + 1 < len(lines):
                    j += 1
                    sig += ' ' + lines[j].strip()
                if '->' not in sig:
                    add('funcion sin tipo de retorno', path, i, sig.strip()[:70])
                for prm in _split_params(sig[sig.find('(') + 1:sig.rfind(')')]):
                    base = prm.split('=')[0].strip()
                    if base and ':' not in base:
                        add('parametro sin tipo', path, i, '%s  <- %s' % (current_func, base))

            if (re.search(r'(?<![\w.])print\s*\(', ln)
                    and not ln.strip().startswith('#')
                    and not DIAGNOSTIC_FUNC.search(current_func)):
                add('print() en codigo de producto', path, i, ln.strip()[:60])

            blank_run = blank_run + 1 if ln.strip() == '' else 0

        if src and not src.endswith('\n'):
            add('fichero sin salto de linea final', path, len(lines), '')
        if '\r\n' in src:
            add('fin de linea CRLF', path, 1, '')

    haystack = []
    for path in _iter_files(USE_DIRS, USE_SUFFIXES):
        with open(path, encoding='utf-8', errors='ignore') as handle:
            haystack.append(handle.read())
    tokens = Counter(re.findall(r'[A-Za-z_]\w*', '\n'.join(haystack)))

    for name, places in sorted(defined.items()):
        if not name.startswith('_') or GODOT_CALLBACKS.match(name):
            continue
        # Aparece tantas veces como se declara: nadie mas la nombra.
        if tokens[name] <= len(places):
            for path, line_no in places:
                add('funcion privada que nadie llama', path, line_no, name)

    return findings


def main(argv):
    findings = run()
    order = sorted(findings.items(), key=lambda kv: -len(kv[1]))
    total = sum(len(v) for v in findings.values())

    print('  %-44s %s' % ('regla', 'veces'))
    print('  ' + '-' * 52)
    for rule, hits in order:
        print('  %-44s %5d' % (rule, len(hits)))
    if not order:
        print('  %-44s %5d' % ('(ninguna regla rota)', 0))
    print('  ' + '-' * 52)
    print('  %-44s %5d' % ('TOTAL', total))

    if '--detail' in argv:
        pos = argv.index('--detail')
        which = argv[pos + 1] if len(argv) > pos + 1 else ''
        for rule, hits in order:
            if which and which not in rule:
                continue
            print('\n  == %s (%d)' % (rule, len(hits)))
            for path, line_no, text in hits[:100]:
                print('     %s:%d  %s' % (path, line_no, text))

    if total == 0:
        print('[check_gdscript_style] PASS')
        return 0
    print('[check_gdscript_style] FAIL (%d)' % total)
    return 1


if __name__ == '__main__':
    raise SystemExit(main(sys.argv[1:]))

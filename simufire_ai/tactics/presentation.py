"""Numeric display preferences, independent of hydraulic computation and JSON units."""
import re

from tactics.hydraulics import render_result


def resolve_number_format(*,language='es',number_format='en'):
    # Explicit preference wins. This project's existing English notation remains
    # the default; callers can opt into auto according to the UI language.
    if number_format in ('en','es'): return number_format
    if number_format != 'auto': raise ValueError('Formato numérico no admitido')
    if not isinstance(language,str): raise ValueError('Idioma no admitido para formato automático')
    code = language.replace('_','-').split('-')[0].lower()
    if code not in ('en','es'): raise ValueError('Idioma no admitido para formato automático: '+language)
    return code


def render_hydraulic_answer(result,*,language='es',number_format='en'):
    style = resolve_number_format(language=language,number_format=number_format)
    text = render_result(result)
    if style=='en': return text
    # Convert only decimal tokens emitted by the canonical numeric renderer.
    # No thousands grouping, unit conversion, parsing of input, or JSON mutation.
    return re.sub(r'(?<![\w.])([+-]?\d+)\.(\d+)([eE][+-]?\d+)?(?![\w.])',
                  lambda match:match.group(1)+','+match.group(2)+(match.group(3) or ''),text)

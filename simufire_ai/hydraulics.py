"""Calculate a documented single-line hydraulic training profile, without Ollama."""
import argparse
import json
from pathlib import Path

from tactics.hydraulics import analyze_profile, read_profile
from tactics.presentation import render_hydraulic_answer, resolve_number_format


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--number-format',choices=('en','es','auto'),default='en',
                        help='Notación decimal: punto en en, coma en es; auto usa --language')
    parser.add_argument('--language',default='es',
                        help='Idioma para resolver el formato auto (es/en); el texto actual se mantiene en español')
    args = parser.parse_args()
    try:
        style = resolve_number_format(language=args.language,number_format=args.number_format)
        result = analyze_profile(read_profile(args.profile))
        result['answer'] = render_hydraulic_answer(result,language=args.language,number_format=args.number_format)
        result['presentation'] = {'number_format':style,'decimal_separator':'.' if style=='en' else ',',
                                  'thousands_grouping':False,'units':'bar, L/min, L, min',
                                  'text_language':'es','json_numbers':'RFC8259'}
        text = json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False) + '\n'
        args.output.parent.mkdir(parents=True, exist_ok=True)
        with args.output.open('x', encoding='utf-8') as stream:
            stream.write(text)
    except (OSError, ValueError) as error:
        parser.exit(1, f'ERROR: {error}\n')
    print(result['answer'])


if __name__ == '__main__':
    main()

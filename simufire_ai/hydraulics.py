"""Calculate a documented single-line hydraulic training profile, without Ollama."""
import argparse
import json
from pathlib import Path

from tactics.hydraulics import analyze_profile, read_profile, render_result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    try:
        result = analyze_profile(read_profile(args.profile))
        result['answer'] = render_result(result)
        text = json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False) + '\n'
        args.output.parent.mkdir(parents=True, exist_ok=True)
        with args.output.open('x', encoding='utf-8') as stream:
            stream.write(text)
    except (OSError, ValueError) as error:
        parser.exit(1, f'ERROR: {error}\n')
    print(result['answer'])


if __name__ == '__main__':
    main()

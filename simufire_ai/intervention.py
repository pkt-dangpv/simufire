"""Generate a bound teaching intervention report without Ollama or online calls."""
import argparse
from pathlib import Path

from pipeline import read_json
from tactics.intervention import build_intervention_report
from tactics.intervention_presentation import render_html, render_markdown


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--case',required=True,type=Path,help='JSON con escenario y estados')
    parser.add_argument('--profile',required=True,type=Path)
    parser.add_argument('--installation-context',type=Path)
    parser.add_argument('--request',required=True,type=Path)
    parser.add_argument('--output-dir',required=True,type=Path)
    parser.add_argument('--number-format',choices=('en','es','auto'),default='en')
    parser.add_argument('--language',default='es')
    args=parser.parse_args()
    try:
        fixture=read_json(args.case);profile=read_json(args.profile);request=read_json(args.request)
        declared=read_json(args.installation_context) if args.installation_context else None
        report=build_intervention_report(fixture,profile,declared,request)
        preferences={'number_format':args.number_format,'language':args.language}
        markdown=render_markdown(report,**preferences);html=render_html(report,**preferences)
        # Publish all inputs and outputs atomically, preserving earlier reports.
        import tempfile,shutil
        if args.output_dir.exists():raise FileExistsError('La carpeta de informe ya existe')
        args.output_dir.parent.mkdir(parents=True,exist_ok=True)
        from pipeline import validate_identifier,write_json
        validate_identifier(args.output_dir.name)
        lock=args.output_dir.parent/('.'+args.output_dir.name+'.lock')
        temporary=None
        lock_file=lock.open('x',encoding='utf-8')
        try:
            if args.output_dir.exists():raise FileExistsError('La carpeta de informe ya existe')
            temporary=Path(tempfile.mkdtemp(prefix='.simufire-report-',dir=args.output_dir.parent))
            for name,value in {'case.json':fixture,'profile.json':profile,'request.json':request,'report.json':report}.items():write_json(temporary/name,value)
            if declared is not None:write_json(temporary/'installation_context.json',declared)
            (temporary/'informe.md').write_text(markdown,encoding='utf-8')
            (temporary/'informe.html').write_text(html,encoding='utf-8')
            temporary.rename(args.output_dir);temporary=None
        finally:
            if temporary is not None and temporary.exists():
                if temporary.resolve().parent!=args.output_dir.parent.resolve() or not temporary.name.startswith('.simufire-report-'):
                    raise ValueError('Carpeta temporal fuera del directorio de publicación')
                shutil.rmtree(temporary)
            lock_file.close();lock.unlink()
    except (OSError,ValueError) as error:parser.exit(1,'ERROR: '+str(error)+'\n')
    print('Informe generado: '+str(args.output_dir))


if __name__=='__main__':main()

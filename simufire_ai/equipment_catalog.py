"""Consult equipment and NIST references; optionally discover primary documents online."""
import argparse
import http.client
import json
from pathlib import Path

from tactics.catalogue import lookup
from tactics.online_sources import INDEXES, fetch_document, search_primary_index
from tactics.standards import lookup_standards


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--query')
    parser.add_argument('--category',choices=('pump','hose','nozzle','fan','tactical','standards'))
    parser.add_argument('--online',action='store_true')
    parser.add_argument('--source',choices=tuple(INDEXES))
    parser.add_argument('--fetch-url')
    parser.add_argument('--evidence-dir',type=Path)
    parser.add_argument('--output',type=Path)
    args = parser.parse_args()
    if not args.query and not args.fetch_url: parser.error('Se requiere --query o --fetch-url')
    if args.fetch_url and (args.query or args.source or args.category):
        parser.error('--fetch-url se utiliza sin consulta, categoría ni índice')
    if args.online and not args.evidence_dir: parser.error('--online requiere --evidence-dir')
    if (args.source or args.fetch_url or args.evidence_dir) and not args.online:
        parser.error('La consulta de internet requiere --online')
    if args.online and args.query and not args.source: parser.error('Elegir --source para buscar documentos')
    if args.output and args.output.exists(): parser.error('No se sobrescriben informes existentes')
    try:
        if args.fetch_url:
            report,_ = fetch_document(args.fetch_url,online=True,evidence_dir=args.evidence_dir)
        else:
            report = lookup_standards(args.query) if args.category=='standards' else lookup(args.query,category=args.category)
            if args.online:
                report['online_candidates'] = search_primary_index(args.query,args.source,
                    online=True,evidence_dir=args.evidence_dir)
        if args.output:
            args.output.parent.mkdir(parents=True,exist_ok=True)
            with args.output.open('x',encoding='utf-8') as stream:
                json.dump(report,stream,ensure_ascii=False,indent=2,allow_nan=False)
            print('OK: consulta guardada en '+str(args.output))
        else: print(json.dumps(report,ensure_ascii=False,indent=2,allow_nan=False))
    except (ValueError,OSError,http.client.HTTPException) as error:
        parser.exit(1,'ERROR: '+str(error)+'\n')


if __name__=='__main__': main()

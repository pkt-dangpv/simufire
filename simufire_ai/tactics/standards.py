"""Public standards metadata and scope summaries, kept apart from manufacturer curves."""
import copy
import hashlib
import json
import math
from pathlib import Path
from urllib.parse import urlsplit

from jsonschema import Draft202012Validator, FormatChecker
from tactics.catalogue import load_catalog, words
from tactics.hydraulics import read_profile
from tactics.online_sources import validate_url

PATH = Path(__file__).with_name('catalog')/'standards_references.json'
SCHEMA = PATH.with_name('standards_references.schema.json')
NFPA_HOSTS = {'www.nfpa.org','docinfofiles.nfpa.org'}
EN_HOSTS = {'www.boe.es','tienda.aenor.com','www.boutique.afnor.org','store.uni.com','revista.une.org'}


def validate_registry(data):
    errors=list(Draft202012Validator(read_profile(SCHEMA),format_checker=FormatChecker()).iter_errors(data))
    if errors: raise ValueError('Referencias normativas: '+errors[0].message)
    for field,key in [('sources','source_id'),('standards','standard_id')]:
        ids=[item[key] for item in data[field]]
        if len(set(ids))!=len(ids): raise ValueError('Identificador duplicado: '+key)
    sources={s['source_id']:s for s in data['sources']}
    for source in sources.values(): validate_url(source['url'])
    for entry in data['standards']:
        hosts=NFPA_HOSTS if entry['family']=='NFPA' else EN_HOSTS
        for sid in entry['source_ids']:
            if sid not in sources or urlsplit(sources[sid]['url']).hostname not in hosts:
                raise ValueError('Fuente incompatible con la familia normativa')
        names=[]
        for fact in entry['scope_facts']:
            try: finite=math.isfinite(fact['value'])
            except OverflowError: finite=False
            if not finite: raise ValueError('Valor de ámbito no finito')
            if fact['source_id'] not in entry['source_ids']: raise ValueError('Dato sin fuente del ámbito consultado')
            names.append(fact['name'])
        if len(set(names))!=len(names): raise ValueError('Dato de ámbito duplicado')
    return data


def load_registry(): return validate_registry(read_profile(PATH))


def lookup_standards(query,registry=None):
    if not isinstance(query,str) or not query.strip() or len(query)>160: raise ValueError('Consulta normativa inválida')
    tokens=words(query)
    if not tokens: raise ValueError('Consulta normativa sin términos')
    data=load_registry() if registry is None else validate_registry(registry)
    matches=[]
    for entry in data['standards']:
        # Equipment-topic searches must not match incidental mentions in a
        # limitation such as "no pump setting is inferred" in a nozzle scope.
        if any(t in {'pump','hose','nozzle','fan'} and t not in entry['topics'] for t in tokens): continue
        haystack=words(json.dumps(entry,ensure_ascii=False))
        if all(t in haystack for t in tokens): matches.append(copy.deepcopy(entry))
    ids={sid for entry in matches for sid in entry['source_ids']}
    canonical=json.dumps(data,ensure_ascii=False,sort_keys=True,allow_nan=False).encode('utf-8')
    return {'query':query,'category':'standards','registry_id':data['registry_id'],
            'registry_sha256':hashlib.sha256(canonical).hexdigest(),
            'status':'reference_matches' if matches else 'missing_from_registry','matches':matches,
            'sources':[copy.deepcopy(s) for s in data['sources'] if s['source_id'] in ids],
            'equipment_compliance_assessed':False,'automatic_tactical_decision':False,'online_candidates':None}


def nozzle_reference_pressure(equipment_id,*,catalog=None):
    """Report the selected manufacturer's value; never infer it from EN/NFPA or language."""
    data=load_catalog() if catalog is None else catalog
    # Validation belongs to the catalog authority, even when a caller supplies data.
    from tactics.catalogue import validate_catalog
    validate_catalog(data)
    records=[e for e in data['equipment'] if e['equipment_id']==equipment_id and e['category']=='nozzle']
    if len(records)!=1: raise ValueError('Lanza no encontrada')
    facts=[f for f in records[0]['facts'] if f['name']=='reference_pressure']
    if len(facts)!=1 or facts[0]['status']!='transcribed' or facts[0]['unit']!='bar':
        raise ValueError('Presión de referencia ausente, conflictiva o con unidades no admitidas')
    fact=facts[0]
    if fact['value']<=0: raise ValueError('Presión de referencia no positiva')
    return {'equipment_id':equipment_id,'reference_pressure_bar':fact['value'],
            'conditions':fact['conditions'],'source':copy.deepcopy(next(s for s in data['sources'] if s['source_id']==fact['source_id'])),
            'basis':'manufacturer_document_for_selected_model','curve_synthesized':False,
            'normative_compliance_assessed':False}

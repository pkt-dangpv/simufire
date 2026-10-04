"""Versioned primary-source catalog. Reference facts are not deployment profiles."""
import copy
import hashlib
import json
import math
import re
import unicodedata
from collections import Counter
from pathlib import Path
from urllib.parse import urlsplit

from jsonschema import Draft202012Validator, FormatChecker
from tactics.hydraulics import read_profile

CATALOG_DIR = Path(__file__).with_name('catalog')
CATALOG_PATH = CATALOG_DIR/'equipment_and_references.json'
SCHEMA_PATH = CATALOG_DIR/'catalog.schema.json'
ALIASES = {'bomba':'pump','bombas':'pump','manguera':'hose','mangueras':'hose',
           'lanza':'nozzle','lanzas':'nozzle','ventilador':'fan','ventiladores':'fan',
           'ventilacion':'ventilation','rescate':'rescue','dotacion':'crew','viento':'wind'}
MANUFACTURER_HOSTS = {
    'Rosenbauer':{'www.rosenbauer.com'},'Godiva':{'www.godiva.co.uk'},
    'AWG':{'awg-fittings.com','www.awg-fittings.com','products.awg-fittings.com','produkte.awg-fittings.com'},
    'Gollmer & Hummel':{'gollmer-hummel.com'},'LEADER':{'www.leader-group.company'},
}
RESEARCH_HOSTS = {'www.nist.gov','nvlpubs.nist.gov','tsapps.nist.gov'}


def words(text):
    text = ''.join(c for c in unicodedata.normalize('NFKD',text.casefold()) if not unicodedata.combining(c))
    return [ALIASES.get(t,t) for t in re.findall(r'[a-z0-9]+',text)]


def validate_catalog(catalog):
    # Reject NaN, infinity and numbers outside the finite runtime range, including integers.
    def finite(value):
        if isinstance(value,dict):
            for item in value.values(): finite(item)
        elif isinstance(value,list):
            for item in value: finite(item)
        elif isinstance(value,(int,float)) and not isinstance(value,bool):
            try: valid = math.isfinite(value)
            except OverflowError: valid = False
            if not valid: raise ValueError('Número no finito en catálogo')
    finite(catalog)
    errors = list(Draft202012Validator(read_profile(SCHEMA_PATH),format_checker=FormatChecker()).iter_errors(catalog))
    if errors: raise ValueError('Catálogo: '+errors[0].message)
    def unique(items,key):
        ids = [i[key] for i in items]
        if len(set(ids)) != len(ids): raise ValueError('Identificador duplicado: '+key)
    for field,key in [('sources','source_id'),('equipment','equipment_id'),('tactical_references','reference_id')]:
        unique(catalog[field],key)
    sources = {s['source_id']:s for s in catalog['sources']}
    from tactics.online_sources import validate_url
    for source in sources.values(): validate_url(source['url'])
    for record in catalog['equipment']:
        for item in record['facts']+record['curve_documents']:
            if item['source_id'] not in sources or sources[item['source_id']]['authority'] != 'manufacturer':
                raise ValueError('Fuente de equipo inexistente o ajena al fabricante')
            if urlsplit(sources[item['source_id']]['url']).hostname not in MANUFACTURER_HOSTS.get(record['manufacturer'],set()):
                raise ValueError('La fuente no pertenece al fabricante del equipo')
        counts = Counter(f['name'] for f in record['facts'])
        for name,count in counts.items():
            entries = [f for f in record['facts'] if f['name']==name]
            if count>1 and (not record['conflicts'] or any(f['status']!='conflicting' for f in entries)
                            or len({f['source_id'] for f in entries}) != count):
                raise ValueError('Valores duplicados sin conflicto documentado: '+name)
            if any(f['status']=='conflicting' for f in entries) and count<2:
                raise ValueError('Conflicto sin comparación de fuentes: '+name)
    for ref in catalog['tactical_references']:
        if ref['source_id'] not in sources or sources[ref['source_id']]['authority'] != 'research_institute':
            raise ValueError('Referencia táctica sin fuente de investigación')
        if urlsplit(sources[ref['source_id']]['url']).hostname not in RESEARCH_HOSTS:
            raise ValueError('La referencia no procede de una institución de investigación admitida')
    return catalog


def load_catalog(path=CATALOG_PATH):
    return validate_catalog(read_profile(path))


def lookup(query,*,category=None,catalog=None):
    if not isinstance(query,str) or not query.strip() or len(query)>160:
        raise ValueError('La consulta debe contener entre 1 y 160 caracteres')
    if category not in (None,'pump','hose','nozzle','fan','tactical'):
        raise ValueError('Categoría desconocida')
    data = load_catalog() if catalog is None else validate_catalog(catalog)
    tokens = words(query)
    if not tokens: raise ValueError('La consulta no contiene términos de búsqueda')
    records = data['equipment']+data['tactical_references']
    matches = []
    for record in records:
        kind = record.get('category','tactical')
        if category and kind != category: continue
        searchable = ' '.join(words(json.dumps(record,ensure_ascii=False)))
        if all(t in searchable.split() for t in tokens): matches.append(copy.deepcopy(record))
    source_ids = {item['source_id'] for record in matches
                  for item in (record['facts']+record['curve_documents'] if 'facts' in record else [record])}
    return {'query':query,'category':category,'catalog_id':data['catalog_id'],
            'catalog_sha256':hashlib.sha256(CATALOG_PATH.read_bytes()).hexdigest() if catalog is None else
                hashlib.sha256(json.dumps(data,sort_keys=True,allow_nan=False).encode()).hexdigest(),
            'status':'catalog_matches' if matches else 'missing_from_catalog','matches':matches,
            'sources':[copy.deepcopy(s) for s in data['sources'] if s['source_id'] in source_ids],
            'simulation_equipment_available':False,'automatic_tactical_decision':False,
            'online_candidates':None}


def hydraulic_data_gaps(equipment_id,catalog=None):
    data = load_catalog() if catalog is None else validate_catalog(catalog)
    for record in data['equipment']:
        if record['equipment_id']==equipment_id:
            return {'equipment_id':equipment_id,'profile_ready':False,
                    'reasons':copy.deepcopy(record['data_gaps']),
                    'conflicts':copy.deepcopy(record['conflicts']),
                    'expert_review':'pending','availability':'not_declared'}
    raise ValueError('Equipo no encontrado: '+equipment_id)


def to_hydraulic_component(equipment_id,catalog=None):
    gaps = hydraulic_data_gaps(equipment_id,catalog)
    raise ValueError('Equipo aún no apto para cálculo: '+equipment_id+'; '+'; '.join(gaps['reasons']))

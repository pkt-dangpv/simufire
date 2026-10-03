"""Frozen question corpus: offline contracts by default, explicit Ollama mode.

Expectations are authored data, not freshly generated resolver output. Reports
keep model interpretation, evidence selection and mechanical grounding separate.
Grounding checks do not substitute for an expert assessment of the text.
"""
import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path
import statistics
import sys
import time
import urllib.request

BASE_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(BASE_DIR))
import pipeline
from llm import plan_question
from llm.question_context import context_fingerprint
from llm.render_question_answer import render_question_answer

CORPUS_DIR = BASE_DIR / 'tests/data/question_evaluation'


def load_corpus(directory=CORPUS_DIR):
    directory = Path(directory)
    freeze = pipeline.read_json(directory / 'freeze.json')
    actual_files = {p.name for p in directory.glob('*.json') if p.name != 'freeze.json'}
    if set(freeze['files']) != actual_files:
        raise ValueError('Frozen evaluation file inventory changed')
    for name, digest in freeze['files'].items():
        if Path(name).name != name or context_fingerprint(pipeline.read_json(directory/name)) != digest:
            raise ValueError('Frozen evaluation input changed: ' + name)
    corpus = pipeline.read_json(directory/'corpus.json')
    cases = corpus['cases']
    if len({case['id'] for case in cases}) != len(cases):
        raise ValueError('Duplicate evaluation case ID')
    if any(case['split'] not in ('dev', 'holdout') for case in cases):
        raise ValueError('Unknown evaluation split')
    for case in cases:
        if case['fixture']+'.json' not in freeze['files']:
            raise ValueError('Unknown fixture')
    return corpus, context_fingerprint(freeze)


def build_contexts(cases, directory=CORPUS_DIR):
    directory = Path(directory)
    thresholds = pipeline.read_json(directory/'thresholds.json')
    entries = pipeline.read_json(directory/'knowledge.json')
    contexts = {}
    for name in sorted({case['fixture'] for case in cases}):
        fixture = pipeline.read_json(directory/(name+'.json'))
        contexts[name] = pipeline.build_analysis(fixture['scenario'], fixture['states'],
            'eval_'+name, thresholds=thresholds, entries=entries)['context.json']
    return contexts


def source_fingerprint():
    # Covers prompt, scope and renderer too, beyond the analysis engine hash.
    paths = [BASE_DIR/'pipeline.py', Path(__file__),
             *sorted((BASE_DIR/'llm').glob('*.py')),
             *sorted((BASE_DIR/'analyzer').glob('*.py')),
             *sorted((BASE_DIR/'knowledge').glob('*.py')),
             *sorted((BASE_DIR/'schemas').glob('*.json'))]
    return context_fingerprint({p.relative_to(BASE_DIR).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in paths})


def model_metadata():
    """Query the installed local model before any evaluation queries."""
    base = plan_question.OLLAMA_URL.rsplit('/', 2)[0]
    with urllib.request.urlopen(base+'/api/tags', timeout=10) as response:
        tags = json.loads(response.read())
    model = next((item for item in tags['models'] if item.get('name') == plan_question.MODEL), None)
    if model is None or not model.get('digest'):
        raise ValueError('Configured Ollama model missing or unidentified')
    with urllib.request.urlopen(base+'/api/version', timeout=10) as response:
        version = json.loads(response.read())['version']
    return {'name':plan_question.MODEL,'digest':model['digest'],'details':model.get('details'),
            'ollama_version':version,'temperature':0,'think':False,'request_timeout_s':120}


def grounding_errors(context, plan, answer):
    """Structural checks of provenance, metadata and source isolation."""
    errors = []
    facts = {fact['fact_id']:fact for fact in context['scenario_facts']}
    knowledge = {entry['knowledge_id']:entry for entry in context['technical_knowledge']}
    for key in ('source_context_sha256', 'run_id', 'scenario_id'):
        expected = context_fingerprint(context) if key=='source_context_sha256' else context.get(key)
        if plan.get(key) != expected or answer.get(key) != expected:
            errors.append('context_identity:'+key)
    if answer['fact_ids'] != plan['primary_fact_ids'] or answer['supporting_fact_ids'] != plan['supporting_fact_ids']:
        errors.append('plan_answer_fact_mismatch')
    for ids_key, meta_key in (('fact_ids','fact_metadata'),('supporting_fact_ids','supporting_fact_metadata')):
        ids = answer[ids_key]
        if any(fid not in facts for fid in ids):
            errors.append('foreign_fact'); continue
        expected_meta = [{key:facts[fid][key] for key in ('fact_id','certainty','causal')} for fid in ids]
        if answer[meta_key] != expected_meta:
            errors.append('certainty_or_causal_changed')
    expected_provenance = [{key:facts[fid][key] for key in ('fact_id','time_s','compartment_id','compartment_ids','event_ids','evidence_interval_s') if key in facts[fid]}
                           for fid in answer['fact_ids'] if fid in facts]
    if answer['fact_provenance'] != expected_provenance:
        errors.append('provenance_changed')
    if any(kid not in knowledge for kid in answer['knowledge_ids']):
        errors.append('foreign_knowledge')
    allowed_sources = {knowledge[kid]['source']['source_id'] for kid in answer['knowledge_ids'] if kid in knowledge}
    if not set(answer['source_ids']) <= allowed_sources:
        errors.append('foreign_source')
    if (plan['intent']=='causality' and answer['answer_status']!='clarification_required'
            and 'no puede afirmarse' not in answer['answer']):
        errors.append('causal_caveat_missing')
    if answer['answer_status'] in ('clarification_required','unsupported','not_detected','insufficient_data','theory_only','knowledge_unavailable') and answer['fact_ids']:
        errors.append('facts_in_empty_or_theory_response')
    return errors


def evaluate_case(case, context, classifier):
    expected = case['expected']
    result = {'case_id':case['id'],'fixture':case['fixture'],'split':case['split'],
              'question':case['question'],'expected':expected}
    raw = None
    classify_duration = None
    prompt_digest = None
    def capture(prompt, schema):
        nonlocal raw, classify_duration, prompt_digest
        prompt_digest = hashlib.sha256(prompt.encode('utf-8')).hexdigest()
        start = time.perf_counter()
        try:
            raw = classifier(prompt, schema)
            return raw
        finally:
            classify_duration = time.perf_counter()-start
    start = time.perf_counter()
    try:
        plan = plan_question.create_question_plan(context, case['question'], case['id'], classifier=capture)
        planned = time.perf_counter()
        answer = render_question_answer(context, plan)
        rendered = time.perf_counter()
        parsed = json.loads(raw)
        # Timeline topics are intentionally derived from selected facts by code.
        result['checks'] = {
            'model_intent':parsed['intent']==expected['intent'],
            'model_topics':None if expected['intent']=='timeline' else set(parsed['topics'])==set(expected['topics']),
            'final_intent':plan['intent']==expected['intent'],
            'final_topics':set(plan['topics'])==set(expected['topics']),
            'answer_status':answer['answer_status']==expected['answer_status'],
            'fact_selection':set(answer['fact_ids'])==set(expected['fact_ids']),
            'knowledge_selection':set(answer['knowledge_ids'])==set(expected['knowledge_ids']),
            'wording_constraints':all(text in answer['answer'] for text in expected['contains'])
                                  and all(text not in answer['answer'] for text in expected['excludes']),
        }
        result['grounding_errors'] = grounding_errors(context, plan, answer)
        result['plan'], result['answer'] = plan, answer
        result['render_duration_s'] = rendered-planned
    except (OSError, ValueError, RuntimeError) as error:
        result['error'] = {'type':type(error).__name__,'message':str(error)}
        result['checks'] = {}
        result['grounding_errors'] = []
    result.update(raw_model_response=raw, classifier_duration_s=classify_duration,
                  total_duration_s=time.perf_counter()-start, prompt_sha256=prompt_digest)
    result['passed'] = not result.get('error') and not result['grounding_errors'] and all(value is not False for value in result['checks'].values())
    return result


def summarize(results):
    checks = sorted({key for result in results for key in result['checks']})
    durations = sorted(result['classifier_duration_s'] for result in results if result['classifier_duration_s'] is not None)
    per_split = {split:{'total':sum(r['split']==split for r in results),
                       'passed':sum(r['split']==split and r['passed'] for r in results)}
                 for split in sorted({r['split'] for r in results})}
    return {'total':len(results),'passed':sum(result['passed'] for result in results),
            'errors':sum(bool(result.get('error')) for result in results),
            'grounding_violations':sum(bool(result['grounding_errors']) for result in results),
            'checks':{key:{'passed':sum(r['checks'].get(key) is True for r in results),
                           'evaluated':sum(r['checks'].get(key) is not None for r in results)} for key in checks},
            'by_split':per_split,
            'intent_confusion':dict(Counter(expected_intent+' -> '+r.get('plan',{}).get('intent','ERROR')
                for r in results for expected_intent in [r['expected']['intent']])),
            'classifier_latency_s':{'median':statistics.median(durations) if durations else None,
                'p95':durations[max(0, math.ceil(.95*len(durations))-1)] if durations else None,
                'max':max(durations) if durations else None}}


def run_evaluation(*, mode='offline', split='all', directory=CORPUS_DIR, progress=None):
    if mode not in ('offline','ollama') or split not in ('dev','holdout','all'):
        raise ValueError('Unknown evaluation mode or split')
    if mode=='ollama' and split=='all':
        raise ValueError('Run development and holdout separately')
    corpus, digest = load_corpus(directory)
    cases = [case for case in corpus['cases'] if split=='all' or case['split']==split]
    model = model_metadata() if mode=='ollama' else None
    contexts = build_contexts(cases, directory)
    source = source_fingerprint()
    results = []
    for index, case in enumerate(cases, 1):
        classifier = plan_question.call_ollama if mode=='ollama' else lambda prompt, schema, c=case:json.dumps(c['classification'])
        result = evaluate_case(case, contexts[case['fixture']], classifier)
        results.append(result)
        if progress: progress(index, len(cases), result)
    # Detect model replacement, source edits or corpus edits during measurement.
    if source_fingerprint()!=source or load_corpus(directory)[1]!=digest:
        raise ValueError('Evaluation inputs changed during run')
    if mode=='ollama' and model_metadata()!=model:
        raise ValueError('Installed model changed during evaluation')
    return {'report_version':'1','created_at_utc':datetime.now(timezone.utc).isoformat(),
        'mode':mode,'split':split,'corpus_sha256':digest,'source_sha256':source,
        'engine_sha256':pipeline.engine_fingerprint(),'runtime':{'python':sys.version,'jsonschema':pipeline.version('jsonschema')},
        'model':model,'context_sha256':{name:context_fingerprint(ctx) for name,ctx in contexts.items()},
        'limitations':['Synthetic, related fixtures; not a representative real-world accuracy estimate.',
            'Labels reviewed by implementation author, pending independent expert review.',
            'Offline mode injects labels and does not measure Qwen.',
            'Grounding checks are structural and wording-specific, not a complete semantic assertion audit.',
            'Temperature zero does not guarantee model reproducibility.'],
        'summary':summarize(results),'results':results}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ollama',action='store_true')
    parser.add_argument('--split',choices=('dev','holdout','all'),default='all')
    parser.add_argument('--output',required=True,type=Path)
    args = parser.parse_args()
    if args.output.exists(): parser.error('Refusing to overwrite an evaluation report')
    def progress(index, total, result):
        print(f'{index}/{total} {result["case_id"]}: {"PASS" if result["passed"] else "FAIL"}',flush=True)
    try:
        report = run_evaluation(mode='ollama' if args.ollama else 'offline',split=args.split,progress=progress)
        args.output.parent.mkdir(parents=True,exist_ok=True)
        # Exclusive file creation keeps previous measurements intact.
        with args.output.open('x',encoding='utf-8') as stream:
            json.dump(report,stream,ensure_ascii=False,indent=2,allow_nan=False)
    except (OSError, ValueError, RuntimeError) as error:
        parser.exit(1,f'ERROR: {error}\n')
    print(json.dumps(report['summary'],ensure_ascii=False,indent=2))
    parser.exit(0 if report['summary']['passed']==report['summary']['total'] else 1)


if __name__=='__main__': main()

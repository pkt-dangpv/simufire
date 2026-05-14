import json
d = json.load(open('sim/validation/reports/v3_hallway_fed_exposure.json'))
for k, v in d['baseline']['checks'].items():
    act = v.get('actual', 0.0)
    rule = v.get('rule', {})
    p = v.get('pass', True)
    marker = ' <-- FAIL' if not p else ''
    exp = rule.get('expected', '-')
    tol = rule.get('tolerance', '-')
    mn = rule.get('min', '-')
    print(f'  {k}: actual={act} exp={exp} tol={tol} min={mn}{marker}')

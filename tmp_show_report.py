import json, sys

def show_report(name):
    d = json.load(open(f'sim/validation/reports/{name}.json'))
    b = d.get('baseline', {})
    ap = b.get('all_pass', '?')
    print(f'=== {name} all_pass={ap} ===')
    for k, v in b.get('checks', {}).items():
        act = v.get('actual', 0.0)
        rule = v.get('rule', {})
        p = v.get('pass', True)
        marker = ' <-- FAIL' if not p else ''
        exp = rule.get('expected', '-')
        tol = rule.get('tolerance', '-')
        mn = rule.get('min', '-')
        print(f'  {k}: actual={act} exp={exp} tol={tol} min={mn}{marker}')

for name in sys.argv[1:]:
    show_report(name)

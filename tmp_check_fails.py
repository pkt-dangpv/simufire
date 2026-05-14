import json
for name in ['v5_ventilation_hrr_spike', 'v7_underventilated_co_peak', 'v8_suppression_reburn']:
    d = json.load(open(f'sim/validation/reports/{name}.json'))
    b = d.get('baseline', {})
    print(f'=== {name} ===')
    for k, v in b.get('checks', {}).items():
        if not v.get('pass', True):
            print(f'  FAIL: {k}')
            actual = v.get('actual')
            rule = v.get('rule', {})
            print(f'    actual={actual} expected={rule.get("expected")} tol={rule.get("tolerance")} min={rule.get("min")} max={rule.get("max")}')
    print()

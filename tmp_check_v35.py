import json
for case in ['v3_hallway_fed_exposure', 'v5_ventilation_hrr_spike']:
    with open(f'sim/validation/reports/{case}.json') as f:
        d = json.load(f)
    print(f"=== {case} all_pass={d['all_pass']} ===")
    for r in d['results']:
        status = 'PASS' if r['pass'] else 'FAIL'
        print(f"  {status}: {r['metric']} actual={r['actual']}")

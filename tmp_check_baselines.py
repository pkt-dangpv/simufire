import json, os, datetime
base = 'C:/Users/dangp/Documents/GitHub/simufire/sim/validation'
cases = ['v3_hallway_fed_exposure','v4_co_remote_rooms','v5_ventilation_hrr_spike','v6_spread_to_hallway','v7_underventilated_co_peak','v8_suppression_reburn','g1_gie_confinement_attack','g2_gie_transitional_attack','g3_gie_ppv_post_knockdown','g4_gie_delayed_entry_hazard']
for case in cases:
    rp = f'{base}/reports/{case}.json'
    if not os.path.exists(rp):
        print(f'{case}: MISSING REPORT')
        continue
    mt = os.path.getmtime(rp)
    ts = datetime.datetime.fromtimestamp(mt).strftime('%H:%M:%S')
    d = json.load(open(rp, encoding='utf-8-sig'))
    b = d.get('baseline', {})
    ap = b.get('all_pass', '?')
    fails = [k for k, v in b.get('checks', {}).items() if not v.get('pass', True)]
    if ap:
        print(f'PASS {case} ({ts})')
    else:
        print(f'FAIL {case} ({ts}): {fails}')

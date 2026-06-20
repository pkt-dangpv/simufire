# Phase 4A Sweep Results — slow_growth_sealed chi_rad fix

CFAST targets: t480=151.003+/-10.0C   t600=152.025+/-15.0C

| Config (chi_rad / amb_rate) | t480(C) | t480 result | t600(C) | t600 result | O2 |
|------------------------------|---------|-------------|---------|-------------|----|
| chi=0.30 amb=0.002           |   168.7 | FAIL d=+17.7 |   189.0 | FAIL d=+36.9 | FAIL |
| chi=0.30 amb=0.005           |   163.4 | FAIL d=+12.4 |   182.3 | FAIL d=+30.2 | FAIL |
| chi=0.30 amb=0.008           |   158.4 | PASS        |   175.8 | FAIL d=+23.7 | FAIL |
| chi=0.30 amb=0.010           |   155.0 | PASS        |   171.4 | FAIL d=+19.4 | FAIL |
| chi=0.35 amb=0.002           |   162.3 | FAIL d=+11.3 |   182.3 | FAIL d=+30.2 | FAIL |
| chi=0.35 amb=0.005           |   157.1 | PASS        |   175.5 | FAIL d=+23.4 | FAIL |
| chi=0.35 amb=0.008           |   152.0 | PASS        |   168.8 | FAIL d=+16.8 | FAIL |
| chi=0.35 amb=0.010           |   148.7 | PASS        |   164.5 | PASS        | FAIL |
| chi=0.40 amb=0.002           |   155.8 | PASS        |   175.3 | FAIL d=+23.3 | FAIL |
| chi=0.40 amb=0.005           |   150.5 | PASS        |   168.4 | FAIL d=+16.3 | FAIL |
| chi=0.40 amb=0.008           |   145.4 | PASS        |   161.6 | PASS        | FAIL |
| chi=0.40 amb=0.010           |   142.1 | PASS        |   157.2 | PASS        | FAIL |
| chi=0.45 amb=0.002           |   149.0 | PASS        |   167.9 | FAIL d=+15.9 | FAIL |
| chi=0.45 amb=0.005           |   143.7 | PASS        |   160.9 | PASS        | FAIL |
| chi=0.45 amb=0.008           |   138.6 | FAIL d=-12.4 |   154.0 | PASS        | FAIL |
| chi=0.45 amb=0.010           |   135.3 | FAIL d=-15.7 |   149.5 | PASS        | FAIL |
| chi=0.50 amb=0.002           |   141.9 | PASS        |   160.1 | PASS        | FAIL |
| chi=0.50 amb=0.005           |   136.6 | FAIL d=-14.4 |   152.9 | PASS        | FAIL |
| chi=0.50 amb=0.008           |   131.7 | FAIL d=-19.3 |   145.9 | PASS        | FAIL |
| chi=0.50 amb=0.010           |   128.4 | FAIL d=-22.6 |   141.4 | PASS        | FAIL |

## O2 detail (best PASS configs)


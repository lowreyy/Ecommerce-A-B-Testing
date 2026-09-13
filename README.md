# Ecommerce-A-B-Testing
# A/B Test Analysis: Homepage/Checkout Experiment

Statistical analysis of a three-arm A/B test (Control vs. Variant_A vs. Variant_B) for an e-commerce homepage/checkout experience, using PostgreSQL for data storage/querying and Python for statistical testing and visualization.

**TL;DR:** Variant_B drove a statistically significant **31.5% relative lift** in conversion rate over Control, held consistently across device, traffic source, country, and loyalty tier segments, with no negative impact on refund rate. Recommend rolling out Variant_B.

## Business Question

The product/marketing team ran a visit-level experiment testing two homepage/checkout variants against the current experience. Should we roll out a variant — and if so, which one?

## Tech Stack

- **PostgreSQL** — data storage and aggregation queries
- **Python** (`pandas`, `numpy`, `scipy`, `sqlalchemy`, `matplotlib`, `seaborn`) — statistical testing and visualization
- **Jupyter Notebook** — analysis environment

## Data Note

`experiment_group` is assigned at the **visit/event level, not the customer level** — 99.96% of customers appear under more than one experiment group across their visits. All metrics in this analysis are computed **per visit**, not per customer, since aggregating "per customer" and comparing across groups would be invalid (most customers were exposed to multiple variants).


## Methodology

1. **Sample Ratio Mismatch check** — confirmed the Control/A/B split matched the expected ~60/20/20 traffic allocation before trusting any downstream result.
2. **Primary metric** — conversion rate (purchase events / total visits) per group.
3. **Significance testing** — two-proportion z-test (pairwise) + overall chi-square test across all three groups.
4. **Funnel analysis** — visit retention through Home → PLP → PDP → Cart → Checkout → Purchase.
5. **Segment consistency checks** — re-ran the significance test within device type, traffic source, country, and loyalty tier to rule out Simpson's paradox (a variant that only "wins" in aggregate but loses in a key segment).
6. **Guardrail metrics** — average order value and refund rate, to catch a variant that buys purchases at the cost of higher returns.
7. **Revenue per visit** — estimated via bootstrap resampling (2,000 iterations) rather than a t-test, since per-visit revenue is zero-inflated (most visits don't convert).
8. **Revenue impact projection** — estimated incremental revenue if a variant replaced Control at current traffic volume.

## Results

### Conversion rate by group

| Group | Conversion Rate | vs. Control | p-value | Significant? |
|---|---|---|---|---|
| Control | 4.75% | — | — | — |
| Variant_A | 5.20% | +9.4% relative lift | < 0.0001 | Yes |
| Variant_B | 6.25% | **+31.5% relative lift** | < 0.0001 | Yes |

Overall chi-square test across all three groups: χ² = 725.43, p ≈ 3 × 10⁻¹⁵⁸ — the differences between groups are not due to chance.

### Segment consistency (Variant_B vs. Control)

The lift held in every segment cut, with no reversals:

- **Device type:** +30.3% (desktop), +33.3% (mobile), +22.9% (tablet) — all significant
- **Traffic source:** lift ranged from +16.1% (Email) to +106.0% (Direct) — all significant
- **Country:** +27.1% to +43.1% across all 7 countries — all significant
- **Loyalty tier:** +20.8% to +36.6% across all tiers — all significant

### Revenue & guardrail metrics

| Group | Avg Order Value | Refund Rate |
|---|---|---|
| Control | $91.02 | 2.95% |
| Variant_A | $89.51 | 2.92% |
| Variant_B | $88.54 | **2.84%** |

AOV is slightly lower in the variants (more, lower-value orders), but refund rate is not worse — in fact it's marginally better for Variant_B. No red flags here.

### Revenue per visit (bootstrap 95% CI)

| Group | RPV lift vs. Control | 95% CI |
|---|---|---|
| Variant_A | +$0.29 | [+0.15, +0.43] |
| Variant_B | +$1.07 | [+0.92, +1.22] |

### Projected revenue impact (rolling out to Control's traffic volume)

| Variant | Revenue per visit | Projected incremental revenue |
|---|---|---|
| Variant_A | $4.18 | +$183,098 |
| Variant_B | $4.96 | **+$671,469** |

## Recommendation

**Roll out Variant_B.** It produces the largest, most consistent lift in conversion and revenue per visit, the effect holds across every segment tested (no Simpson's paradox risk), and guardrail metrics (refund rate, AOV) show no downside.


## Data Schema (expected tables)

- **`events`** — one row per visit/interaction: `customer_id`, `experiment_group`, `event_type`, `page_category`, `device_type`, `traffic_source`, `timestamp`
- **`customers`** — `customer_id`, `country`, `loyalty_tier`
- **`transactions`** — `transaction_id`, `customer_id`, `timestamp`, `gross_revenue`, `refund_flag`, `quantity`

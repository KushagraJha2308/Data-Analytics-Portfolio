"""Transform: conform state names, validate against published totals, build the model.

Outputs
-------
dim_state            one row per State/UT, with region and snapshot attributes
fact_state_year      one row per State/UT per year, with derived indicators
source_reconciliation  published total vs the sum of the states, per source and year
"""
import logging
import re

import numpy as np
import pandas as pd

from . import config

log = logging.getLogger(__name__)

TOTAL_ROW = re.compile(r"total", re.IGNORECASE)

# Spellings seen across government publications, mapped to the name in state_master.csv.
STATE_ALIASES = {
    "a and n islands": "Andaman and Nicobar Islands",
    "andaman and nicobar": "Andaman and Nicobar Islands",
    "dadra and nagar haveli": "Dadra and Nagar Haveli and Daman and Diu",
    "daman and diu": "Dadra and Nagar Haveli and Daman and Diu",
    "dnh and dd": "Dadra and Nagar Haveli and Daman and Diu",
    "dadar and nagar haveli and daman and diu": "Dadra and Nagar Haveli and Daman and Diu",   # typo in source
    "nct of delhi": "Delhi",
    "jammu and kashmir (ut)": "Jammu and Kashmir",
    "orissa": "Odisha",
    "pondicherry": "Puducherry",
    "uttaranchal": "Uttarakhand",
}


# Rows that are neither a State/UT nor a total. 'NEF Shillong' is a Food Corporation of India
# regional office (North East Frontier) that one source lists alongside the states.
NON_STATE_ROWS = {"nef shillong"}


def normalise_name(name: str) -> str:
    """Lower-case, '&' -> 'and', collapse spaces: 'Jammu & Kashmir ' -> 'jammu and kashmir'."""
    text = str(name).replace("&", " and ").lower()
    return re.sub(r"\s+", " ", text).strip()


def conform_states(long: pd.DataFrame, master: pd.DataFrame):
    """Split total rows from state rows and attach the canonical state name."""
    lookup = {normalise_name(s): s for s in master["state"]}
    lookup.update(STATE_ALIASES)

    is_total = long["state_raw"].astype(str).str.contains(TOTAL_ROW)
    totals = long[is_total].copy()
    states = long[~is_total].copy()
    normalised = states["state_raw"].map(normalise_name)
    not_a_state = normalised.isin(NON_STATE_ROWS)
    if not_a_state.any():
        log.warning("Excluded %d values from non-state rows: %s", int(not_a_state.sum()),
                    sorted(states.loc[not_a_state, "state_raw"].unique()))
    states, normalised = states[~not_a_state].copy(), normalised[~not_a_state]
    states["state"] = normalised.map(lookup)

    unknown = states.loc[states["state"].isna(), "state_raw"].unique()
    if len(unknown):
        raise ValueError(f"State names not in state_master.csv or the alias list: {list(unknown)}")
    return states.drop(columns="state_raw"), totals


def reconcile_totals(states: pd.DataFrame, totals: pd.DataFrame) -> pd.DataFrame:
    """Compare each published total with the sum of the state rows it sits under."""
    keys = [c for c in ["source_file", "year", "metric"] if c in states.columns]
    computed = states.groupby(keys)["value"].sum().rename("sum_of_states")
    reported = totals.groupby(keys)["value"].sum().rename("published_total")
    out = pd.concat([reported, computed], axis=1).dropna(subset=["published_total"]).reset_index()
    out["difference"] = out["sum_of_states"] - out["published_total"]
    out["difference_pct"] = 100 * out["difference"] / out["published_total"]
    return out


def cross_check_deleted_cards(states: pd.DataFrame, others: pd.DataFrame, master: pd.DataFrame) -> int:
    """Count state-years where a second source disagrees with the main deleted-cards series."""
    main = states[states["metric"] == "deleted_cards"][["state", "year", "value"]]
    other_states, _ = conform_states(others, master)
    merged = other_states.merge(main, on=["state", "year"], suffixes=("_other", "_main"))
    both = merged.dropna(subset=["value_other", "value_main"])
    conflicts = int((both["value_other"] != both["value_main"]).sum())
    log.info("Deleted ration cards: %d overlapping state-years across 3 sources, %d conflicts",
             len(both), conflicts)
    return conflicts


def build_fact_state_year(states: pd.DataFrame) -> pd.DataFrame:
    fact = (states.pivot_table(index=["state", "year"], columns="metric", values="value", aggfunc="first")
            .reset_index().rename_axis(columns=None))
    for col in ["portability_txn", "interstate_txn", "beneficiaries", "distribution_mt", "deleted_cards"]:
        if col not in fact:
            fact[col] = np.nan
    fact = fact.sort_values(["state", "year"]).reset_index(drop=True)

    # Intra-state = all portability transactions minus the inter-state ones.
    fact["intrastate_txn"] = fact["portability_txn"] - fact["interstate_txn"]
    fact["interstate_share_pct"] = 100 * fact["interstate_txn"] / fact["portability_txn"]
    # Usage intensity: transactions for every 100 people entitled to rations.
    fact["portability_per_100_beneficiaries"] = 100 * fact["portability_txn"] / fact["beneficiaries"]
    fact["interstate_per_100k_beneficiaries"] = 1e5 * fact["interstate_txn"] / fact["beneficiaries"]
    # Sanity indicator: NFSA entitles most beneficiaries to 5 kg a month.
    fact["kg_per_beneficiary_month"] = fact["distribution_mt"] * 1000 / fact["beneficiaries"] / 12
    fact["deleted_per_1000_beneficiaries"] = 1000 * fact["deleted_cards"] / fact["beneficiaries"]

    previous = fact.groupby("state")["portability_txn"].shift(1)
    fact["portability_growth_pct"] = 100 * (fact["portability_txn"] / previous - 1)
    # A jump of 20x or more is a state joining the reporting system, not people changing behaviour.
    fact["is_onboarding_jump"] = (fact["portability_txn"] / previous >= config.ONBOARDING_MULTIPLE).astype(int)
    # The reported inter-state count should never exceed the reported total.
    fact["interstate_exceeds_total"] = (fact["interstate_txn"] > fact["portability_txn"]).astype(int)
    return fact


def build_dim_state(master: pd.DataFrame, snapshot_states: pd.DataFrame) -> pd.DataFrame:
    wide = (snapshot_states.pivot_table(index="state", columns="metric", values="value", aggfunc="first")
            .reset_index().rename_axis(columns=None))
    dim = master.merge(wide, on="state", how="left")
    dim["net_migrants"] = dim["migrants_in"] - dim["migrants_out"]
    dim["migrant_in_share_pct"] = 100 * dim["migrants_in"] / dim["migrants_in"].sum()
    dim["migrant_out_share_pct"] = 100 * dim["migrants_out"] / dim["migrants_out"].sum()
    dim["aay_share_pct"] = 100 * dim["beneficiaries_aay"] / dim["beneficiaries_2026"]
    dim["transit_loss_pct"] = 100 * dim["transit_loss_mt"] / dim["transit_moved_mt"]
    dim["migration_role"] = np.select(
        [dim["net_migrants"] > 0, dim["net_migrants"] < 0], ["Destination", "Origin"], default="Balanced")
    dim.loc[dim["migrants_in"].isna(), "migration_role"] = "Not reported"
    return dim


def validate(dim_state: pd.DataFrame, fact: pd.DataFrame, reconciliation: pd.DataFrame, conflicts: int) -> None:
    assert dim_state["state"].is_unique, "Duplicate state in dim_state"
    assert not fact.duplicated(["state", "year"]).any(), "Duplicate state-year"
    assert set(fact["state"]) <= set(dim_state["state"]), "Fact row for an unknown state"
    numeric = fact.select_dtypes("number").drop(columns=["portability_growth_pct"])
    assert (numeric.fillna(0) >= 0).all().all(), "Negative count"
    assert conflicts == 0, "The three deleted-ration-card sources disagree"
    worst = reconciliation["difference_pct"].abs().max()
    assert worst < 0.01, f"State rows do not add up to a published total (worst gap {worst:.3f}%)"
    log.info("Validation passed: %d states, %d state-years, %d published totals reconciled",
             len(dim_state), len(fact), len(reconciliation))


def transform(yearly: pd.DataFrame, snapshot: pd.DataFrame, deleted_checks: pd.DataFrame,
              master: pd.DataFrame) -> dict:
    yearly_states, yearly_totals = conform_states(yearly, master)
    snapshot_states, snapshot_totals = conform_states(snapshot, master)

    reconciliation = pd.concat([
        reconcile_totals(yearly_states, yearly_totals),
        reconcile_totals(snapshot_states, snapshot_totals).assign(year=np.nan),
    ], ignore_index=True)[["source_file", "metric", "year", "published_total", "sum_of_states",
                           "difference", "difference_pct"]]
    conflicts = cross_check_deleted_cards(yearly_states, deleted_checks, master)

    dim_state = build_dim_state(master, snapshot_states)
    fact = build_fact_state_year(yearly_states)
    validate(dim_state, fact, reconciliation, conflicts)
    return {"dim_state": dim_state, "fact_state_year": fact, "source_reconciliation": reconciliation}

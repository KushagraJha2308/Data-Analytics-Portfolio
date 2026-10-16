"""Modelling: walk-forward training and out-of-sample predictions.

Question: which stocks will beat the median stock over the next week?

Walk-forward validation is used instead of a random train/test split. With time
series, a random split lets the model train on the future and test on the past,
which inflates every score. Here each test year is predicted by a model that has
only seen earlier data, with a gap between train and test so that the 5-day
target of the last training rows cannot overlap the test period.
"""
import logging

import numpy as np
import pandas as pd
from scipy import stats
from sklearn.ensemble import HistGradientBoostingClassifier, RandomForestClassifier
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score, roc_auc_score
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler

from . import config
from .features import FEATURES, STOCK_FEATURES

log = logging.getLogger(__name__)


def make_models() -> dict:
    return {
        "Logistic regression": make_pipeline(StandardScaler(), LogisticRegression(C=0.1, max_iter=500)),
        "Random forest": RandomForestClassifier(
            n_estimators=200, max_depth=6, min_samples_leaf=200, n_jobs=-1,
            random_state=config.RANDOM_STATE),
        "Gradient boosting": HistGradientBoostingClassifier(
            max_depth=4, learning_rate=0.05, max_iter=200, min_samples_leaf=200,
            l2_regularization=1.0, random_state=config.RANDOM_STATE),
    }


def prepare(features: pd.DataFrame) -> pd.DataFrame:
    """Rank stock-level features across stocks on each date (0 to 1).

    Ranks make a feature comparable across calm and volatile markets and remove
    the influence of extreme values, without using any future information.
    """
    df = features.copy()
    df[STOCK_FEATURES] = df.groupby("date")[STOCK_FEATURES].rank(pct=True)
    return df


def walk_forward_splits(df: pd.DataFrame):
    """Yield (test_year, train_index, test_index) with a purge gap before each test year."""
    dates = np.sort(df["date"].unique())
    for year in range(config.FIRST_TEST_YEAR, pd.Timestamp(dates[-1]).year + 1):
        test_dates = dates[pd.DatetimeIndex(dates).year == year]
        if len(test_dates) == 0:
            continue
        first_test_pos = np.searchsorted(dates, test_dates[0])
        train_end = dates[first_test_pos - config.HORIZON - 1]      # purge: drop the last HORIZON days
        train = df.index[(df["date"] <= train_end) & df["target"].notna()]
        test = df.index[df["date"].isin(test_dates)]
        yield year, train, test


def run_walk_forward(features: pd.DataFrame) -> pd.DataFrame:
    """Return out-of-sample predictions: one row per model per stock per test date."""
    df = prepare(features)
    predictions = []
    for year, train, test in walk_forward_splits(df):
        x_train, y_train = df.loc[train, FEATURES], df.loc[train, "target"].astype(int)
        for name, model in make_models().items():
            model.fit(x_train, y_train)
            out = df.loc[test, ["date", "symbol", "sector", "fwd_ret", "target"]].copy()
            out["model"] = name
            out["test_year"] = year
            out["prob_up"] = model.predict_proba(df.loc[test, FEATURES])[:, 1]
            predictions.append(out)
        log.info("Fold %d: trained on %d rows up to %s, tested on %d rows",
                 year, len(train), df.loc[train, "date"].max().date(), len(test))
    return pd.concat(predictions, ignore_index=True)


def daily_ic(group: pd.DataFrame) -> float:
    """Information coefficient: rank correlation between prediction and realised return."""
    return stats.spearmanr(group["prob_up"], group["fwd_ret"]).statistic


def evaluate(predictions: pd.DataFrame) -> pd.DataFrame:
    """Classification and ranking metrics per model, on out-of-sample data only."""
    scored = predictions.dropna(subset=["target"])
    rows = []
    for name, grp in scored.groupby("model"):
        ic = grp.groupby("date")[["prob_up", "fwd_ret"]].apply(daily_ic)
        # Non-overlapping dates for the t-statistic: 5-day targets on consecutive days overlap.
        ic_independent = ic.iloc[::config.HORIZON]
        top = grp[grp.groupby("date")["prob_up"].rank(ascending=False, method="first") <= config.TOP_K]
        rows.append({
            "model": name,
            "rows": len(grp),
            "auc": roc_auc_score(grp["target"], grp["prob_up"]),
            "accuracy": accuracy_score(grp["target"], grp["prob_up"] > 0.5),
            "top_k_hit_rate": top["target"].mean(),
            "mean_ic": ic.mean(),
            "ic_t_stat": ic_independent.mean() / ic_independent.std(ddof=1) * np.sqrt(len(ic_independent)),
        })
    return pd.DataFrame(rows).sort_values("auc", ascending=False).reset_index(drop=True)


def evaluate_by_year(predictions: pd.DataFrame) -> pd.DataFrame:
    scored = predictions.dropna(subset=["target"])
    return (scored.groupby(["model", "test_year"])[["target", "prob_up"]]
            .apply(lambda g: roc_auc_score(g["target"], g["prob_up"]))
            .rename("auc").reset_index())

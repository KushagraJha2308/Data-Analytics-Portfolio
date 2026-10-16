"""Backtest: turn predictions into a simple strategy and compare it with fair benchmarks.

Every week the strategy buys the TOP_K stocks with the highest predicted
probability, in equal weights, and holds them for one week. Trading costs are
charged on every change in the portfolio. The benchmark holds all stocks in the
universe in equal weights, so any difference comes from stock selection alone.
"""
import numpy as np
import pandas as pd

from . import config

PERIODS_PER_YEAR = 252 / config.HORIZON


def rebalance_dates(preds: pd.DataFrame, top_k: int) -> np.ndarray:
    """Every HORIZON-th trading day, so holding periods do not overlap.

    Days on which only a handful of stocks traded (special sessions) are skipped:
    a top-K pick is meaningless when fewer than 2 x K stocks are available.
    """
    counts = preds.groupby("date").size()
    return np.sort(counts[counts >= 2 * top_k].index)[::config.HORIZON]


def run_backtest(predictions: pd.DataFrame, model: str, top_k: int = config.TOP_K,
                 cost: float = config.COST_PER_TRADE) -> pd.DataFrame:
    """Return one row per weekly rebalance: strategy, benchmark and cost."""
    preds = predictions[(predictions["model"] == model) & predictions["fwd_ret"].notna()]

    rows, previous = [], set()
    for date in rebalance_dates(preds, top_k):
        day = preds[preds["date"] == date]
        picks = day.nlargest(top_k, "prob_up")
        held = set(picks["symbol"])
        # Each replaced position is one sell and one buy.
        turnover = len(held - previous) / top_k
        trade_cost = turnover * 2 * cost
        rows.append({
            "date": date,
            "gross_return": picks["fwd_ret"].mean(),
            "cost": trade_cost,
            "strategy_return": picks["fwd_ret"].mean() - trade_cost,
            "benchmark_return": day["fwd_ret"].mean(),
            "turnover": turnover,
            "holdings": ", ".join(sorted(held)),
        })
        previous = held
    out = pd.DataFrame(rows)
    out["excess_return"] = out["strategy_return"] - out["benchmark_return"]
    return out


def performance(returns: pd.Series) -> dict:
    """Annualised statistics for a series of weekly returns."""
    growth = (1 + returns).cumprod()
    years = len(returns) / PERIODS_PER_YEAR
    annual_vol = returns.std(ddof=1) * np.sqrt(PERIODS_PER_YEAR)
    return {
        "annual_return": growth.iloc[-1] ** (1 / years) - 1,
        "annual_volatility": annual_vol,
        "sharpe": returns.mean() * PERIODS_PER_YEAR / annual_vol,      # risk-free rate taken as 0
        "max_drawdown": (growth / growth.cummax() - 1).min(),
        "total_return": growth.iloc[-1] - 1,
    }


def summarise(backtest: pd.DataFrame) -> pd.DataFrame:
    table = pd.DataFrame({
        "Strategy (after costs)": performance(backtest["strategy_return"]),
        "Strategy (before costs)": performance(backtest["gross_return"]),
        "Equal-weight benchmark": performance(backtest["benchmark_return"]),
    }).T
    return table


def excess_return_test(backtest: pd.DataFrame) -> dict:
    """Is the weekly excess return over the benchmark different from zero?"""
    excess = backtest["excess_return"]
    t_stat = excess.mean() / excess.std(ddof=1) * np.sqrt(len(excess))
    return {
        "weeks": len(excess),
        "mean_weekly_excess": excess.mean(),
        "t_stat": t_stat,
        "weeks_beating_benchmark": (excess > 0).mean(),
        "avg_turnover": backtest["turnover"].mean(),
    }


def random_portfolios(predictions: pd.DataFrame, model: str, n_sims: int = 1000,
                      top_k: int = config.TOP_K, seed: int = config.RANDOM_STATE) -> np.ndarray:
    """Annual return (before costs) of portfolios that pick TOP_K stocks at random each week.

    Shows where the model sits against luck: a model with no skill lands in the
    middle of this distribution.
    """
    preds = predictions[(predictions["model"] == model) & predictions["fwd_ret"].notna()]
    dates = rebalance_dates(preds, top_k)
    weekly = [preds.loc[preds["date"] == d, "fwd_ret"].to_numpy() for d in dates]
    rng = np.random.default_rng(seed)
    growth = np.ones(n_sims)
    for returns in weekly:
        picks = np.array([rng.choice(len(returns), size=top_k, replace=False) for _ in range(n_sims)])
        growth *= 1 + returns[picks].mean(axis=1)
    return growth ** (PERIODS_PER_YEAR / len(weekly)) - 1

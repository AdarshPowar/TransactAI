from pathlib import Path

import pandas as pd

from training.train_model import TrainingConfig, prepare_dataset


def test_prepare_dataset_loads_existing_backend_data():
    config = TrainingConfig(datasets=["training_dataset.xlsx"])
    df, stats = prepare_dataset(config)

    assert isinstance(df, pd.DataFrame)
    assert not df.empty
    assert "Description" in df.columns
    assert "Category" in df.columns
    assert stats["final_samples"] >= 1
    assert "category_distribution" in stats

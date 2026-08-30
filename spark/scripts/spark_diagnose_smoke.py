#!/usr/bin/env python3
"""Spark diagnose smoke: spark.range count (invoked from spark/diagnose.yml)."""
from __future__ import annotations

import os

from pyspark.sql import SparkSession

builder = SparkSession.builder.appName("spark-diagnose-smoke")
master = os.environ.get("SPARK_MASTER_URL") or os.environ.get("SPARK_MASTER")
if master:
    builder = builder.master(master)
driver = os.environ.get("SPARK_DRIVER_HOST")
if driver:
    builder = builder.config("spark.driver.host", driver)
spark = builder.getOrCreate()
spark.sparkContext.setLogLevel("ERROR")
count = spark.range(1000).count()
print(f"SMOKE_COUNT={count}")
spark.stop()

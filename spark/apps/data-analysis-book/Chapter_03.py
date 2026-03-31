#!/usr/bin/env python3
"""
Chapter 03: Word Count Analysis
Batch job for analyzing word frequencies in Gutenberg books.
"""

import os
import glob
from pyspark.sql import SparkSession
import pyspark.sql.functions as F

# Host / client-mode: prefer HDFS_DEFAULT_FS_CLIENT (NodePort, resolvable from dev machines).
# HDFS_DEFAULT_FS is for in-cluster Spark (hdfs-namenode.*.svc); it is not resolvable on hosts.
_HDFS_BASE = os.environ.get("HDFS_DEFAULT_FS_CLIENT") or os.environ.get(
    "HDFS_DEFAULT_FS", "hdfs://Lab2.lan:30900"
)

# Driver host must match this machine for client mode (executors in K8s connect back).
# spark_client_env.sh sets SPARK_DRIVER_HOST; override if you submit from a host other than Lab2.
_builder = (
    SparkSession.builder.appName("Chapter 03")
    .config("spark.ui.analytics.enabled", "false")
)
_sm = os.environ.get("SPARK_MASTER_URL") or os.environ.get("SPARK_MASTER")
if _sm:
    _builder = _builder.master(_sm)
_dh = os.environ.get("SPARK_DRIVER_HOST")
if _dh:
    _builder = _builder.config("spark.driver.host", _dh)
spark = _builder.getOrCreate()

# Reduce driver noise (book examples use WARN; we use ERROR to avoid major log warnings)
spark.sparkContext.setLogLevel("ERROR")

print("=== Chapter 03: Word Count Analysis ===")
print(f"Spark version: {spark.version}")
print(f"Spark master: {spark.sparkContext.master}")

# Data paths - use glob to expand wildcards into file list (avoids Spark 4.0 metadata warnings)
books = sorted(glob.glob("/mnt/spark/data/gutenberg_books/*.txt"))
if not books:
    raise SystemExit(
        "No input files under /mnt/spark/data/gutenberg_books/*.txt — "
        "mount NFS data share or copy Gutenberg .txt files before running Chapter 3."
    )

# From Chapter 2 Listing 2.20
book = spark.read.text(books)
lines = book.select(F.split(book.value, " ").alias("line"))
words = lines.select(F.explode(F.col("line")).alias("word"))
words_lower = words.select(F.lower(F.col("word")).alias("word_lower"))
words_clean = words_lower.select(
    F.regexp_extract(F.col("word_lower"), "[a-z]*", 0).alias("word")
)
words_nonull = words_clean.where(F.col("word") != "")

# Listing 3.1 Counting word frequencies using groupby() and count() 
groups = words_nonull.groupby(F.col("word"))
print("Grouped data:", groups)

results = words_nonull.groupby(F.col("word")).count()
print("Results schema:", results)
results.show()

# Exercise 3.1
print("\n=== Exercise 3.1: Word length analysis ===")
count_by_size = words_nonull.select(F.length(F.col("word")).alias("length")).groupby("length").count()
count_by_size.show()

total_words = count_by_size.agg(F.sum(F.col("count"))).collect()[0][0]
print(f"Total words: {total_words}")

# Listing 3.2 Displaying the top 10 words in Jane Austen's Pride and Prejudice 
print("\n=== Top 10 words ===")
results.orderBy("count", ascending=False).show(10)

# Exercise 3.2
print("\n=== Exercise 3.2: Word length distribution ===")
results.orderBy("count", ascending=False) \
    .groupby(F.length(F.col("word"))) \
    .count() \
    .show(5)

# Repartition for better performance
results = results.repartition(10)

# Listing 3.3 Writing results in multiple CSV files, one per partition
print("\n=== Writing results to CSV ===")
# Try Hadoop HDFS first, fallback to local filesystem
try:
    # Write to Hadoop HDFS
    results.write.csv(f"{_HDFS_BASE}/spark/simple_count.csv", mode="overwrite")
    print(f"Successfully wrote to Hadoop HDFS: {_HDFS_BASE}/spark/simple_count.csv")
except Exception as e:
    print(f"Hadoop write failed: {e}")
    print("Falling back to local filesystem...")
    # Fallback to local filesystem
    results.write.csv("/mnt/spark/data/simple_count.csv", mode="overwrite")
    print("Wrote to local filesystem: /mnt/spark/data/simple_count.csv")

print(f"Number of partitions: {results.rdd.getNumPartitions()}")

# Listing 3.4 Writing results under a single partition 
try:
    # Write to Hadoop HDFS
    results.coalesce(1).write.csv(
        f"{_HDFS_BASE}/spark/simple_count_single_partition.csv", mode="overwrite"
    )
    print(
        "Successfully wrote single partition to Hadoop HDFS: "
        f"{_HDFS_BASE}/spark/simple_count_single_partition.csv"
    )
except Exception as e:
    print(f"Hadoop single partition write failed: {e}")
    print("Falling back to local filesystem...")
    # Fallback to local filesystem
    results.coalesce(1).write.csv("/mnt/spark/data/simple_count_single_partition.csv", mode="overwrite")
    print("Wrote single partition to local filesystem: /mnt/spark/data/simple_count_single_partition.csv")

# Listing 3.5 Our first PySpark program, dubbed "Counting Jane Austen"
print("\n=== Listing 3.5: Complete word count analysis ===")
book = spark.read.text(books).repartition(10)

lines = book.select(F.split(book.value, " ").alias("line"))
words = lines.select(F.explode(F.col("line")).alias("word"))
words_lower = words.select(F.lower(F.col("word")).alias("word"))
words_clean = words_lower.select(
    F.regexp_extract(F.col("word"), "[a-z']*", 0).alias("word")
)
words_nonull = words_clean.where(F.col("word") != "")
results = words_nonull.groupby(F.col("word")).count()

results.orderBy("count", ascending=False).show(10)
# Write to Hadoop HDFS
try:
    results.coalesce(1).write.csv(
        f"{_HDFS_BASE}/spark/simple_count_single_partition.csv", mode="overwrite"
    )
    print(f"Successfully wrote to Hadoop HDFS: {_HDFS_BASE}/spark/simple_count_single_partition.csv")
except Exception as e:
    print(f"Hadoop write failed: {e}")
    print("Falling back to local filesystem...")
    results.coalesce(1).write.csv("/mnt/spark/data/simple_count_single_partition.csv", mode="overwrite")
    print("Wrote to local filesystem: /mnt/spark/data/simple_count_single_partition.csv")

# Listing 3.7 Chaining transformation methods
print("\n=== Listing 3.7: Chained transformations ===")
results = (
    spark.read.text(books)
    .select(F.split(F.col("value"), " ").alias("line"))
    .select(F.explode(F.col("line")).alias("word"))
    .select(F.lower(F.col("word")).alias("word"))
    .select(F.regexp_extract(F.col("word"), "[a-z']*", 0).alias("word"))
    .where(F.col("word") != "")
    .groupby("word")
    .count()
)

# Exercise 3.3
print("\n=== Exercise 3.3: Multiple file analysis ===")
results = (
    spark.read.text(books)
    .select(F.split(F.col("value"), " ").alias("line"))
    .select(F.explode(F.col("line")).alias("word"))
    .select(F.lower(F.col("word")).alias("word"))
    .select(F.regexp_extract(F.col("word"), "[a-z']*", 0).alias("word"))
    .where(F.col("word") != "")
    .groupby(F.col("word"))
    .count()
)

print(f"Total distinct words: {results.count()}")

all_results = (
    spark.read.text(books)
    .select(F.split(F.col("value"), " ").alias("line"))
    .select(F.explode(F.col("line")).alias("word"))
    .select(F.lower(F.col("word")).alias("word"))
    .select(F.regexp_extract(F.col("word"), "[a-z']*", 0).alias("word"))
    .where(F.col("word") != "")
    .groupby(F.col("word"))
    .count()
    .orderBy("count", ascending=False)
)

print("Top 10 words across all books:")
all_results.show(10)

# Exercise 3.4
print("\n=== Exercise 3.4: Words that appear only once ===")
results = (
    spark.read.text("/mnt/spark/data/gutenberg_books/1342-0.txt")
    .select(F.split(F.col("value"), " ").alias("line"))
    .select(F.explode(F.col("line")).alias("word"))
    .select(F.lower(F.col("word")).alias("word"))
    .select(F.regexp_extract(F.col("word"), "[a-z']*", 0).alias("word"))
    .where(F.col("word") != "")
    .groupby(F.col("word"))
    .count()
    .where(F.col("count") == 1)
    .select(F.col("word"))
)

print("Words that appear only once:")
results.show(5)

# Exercise 3.5
print("\n=== Exercise 3.5: Character frequency analysis ===")
chars = (
    spark.read.text("/mnt/spark/data/gutenberg_books/1342-0.txt")
    .select(F.split(F.col("value"), " ").alias("line"))
    .select(F.explode(F.col("line")).alias("word"))
    .select(F.lower(F.col("word")).alias("word"))
    .select(F.regexp_extract(F.col("word"), "[a-z']*", 0).alias("word"))
    .where(F.col("word") != "")
    .select(F.substring(F.col("word"), 0, 1).alias("first_character"))
    .groupby(F.col("first_character"))
    .count()
    .orderBy(F.col("count"), ascending=False)
)

print("First character frequency:")
chars.show(10)

# Exercise 3.6
print("\n=== Exercise 3.6: Total distinct words ===")
sresults = (
    spark.read.text("/mnt/spark/data/gutenberg_books/1342-0.txt")
    .select(F.split(F.col("value"), " ").alias("line"))
    .select(F.explode(F.col("line")).alias("word"))
    .select(F.lower(F.col("word")).alias("word"))
    .select(F.regexp_extract(F.col("word"), "[a-z']*", 0).alias("word"))
    .where(F.col("word") != "")
    .groupby(F.col("word"))
    .count()
)

print(f"Total distinct words in Pride and Prejudice: {sresults.count()}")

# Exercise: Compare word counts by file
print("\n=== Exercise: Word counts by file ===")

# Step 1: preprocess all the words
df = (
    spark.read.text(books)
    .select(F.input_file_name().alias("filename"), F.col("value"))
    .select(F.regexp_extract(F.col("filename"), r"([^/]+)$", 1).alias("basename"),
        F.col("value"))
    .select(F.col("basename"), F.split(F.col("value"), " ").alias("line"))
    .select(F.col("basename"), F.explode(F.col("line")).alias("word"))
    .select(F.col("basename"), F.lower(F.col("word")).alias("word"))
    .select(F.col("basename"), F.regexp_extract(F.col("word"), "[a-z']*", 0).alias("word"))
    .where(F.col("word") != "")
)

# Step 2: generate an intermediate count by basename and file
by_word_base_df = (
    df
    .groupBy(F.col("basename"), F.col("word"))
    .agg(F.count("*").alias("word_count"))
)

# Step 3: pivot with explicit basename list (unbounded pivot forces extra passes and can look "hung")
_basename_vals = [
    r[0]
    for r in by_word_base_df.select("basename").distinct().collect()
    if r[0] is not None
]
if not _basename_vals:
    raise SystemExit("Exercise pivot: no basenames found after preprocessing.")
by_word_pivot_base_df = (
    by_word_base_df
    .groupBy(F.col("word"))
    .pivot("basename", _basename_vals)
    .agg(F.sum(F.col("word_count")))
    .fillna(0)
)

# Step 4: create columns of each basename with the word counts
by_word_df = (
    by_word_base_df
    .groupBy(F.col("word"))
    .agg(F.sum(F.col("word_count")).alias("total"))
)

# Step 5: Merge in word counts by file and the total word counts into one df
merged_df = (
    by_word_df
    .join(by_word_pivot_base_df, on="word", how="left")
    .orderBy(F.col("total"), ascending=False)
)

print("Top 10 words with file breakdown:")
merged_df.show(10)

print("\n=== Chapter 03 completed successfully ===")
spark.stop()

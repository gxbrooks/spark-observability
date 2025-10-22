import glob
import pyspark.sql.functions as F
from pyspark.sql import SparkSession

spark = SparkSession.builder.appName(
    "Ch03 - Analyzing the vocabulary of Pride and Prejudice. - short, multiple files"
).getOrCreate()

# Use glob to expand wildcards into file list (avoids Spark 4.0 metadata warnings)
books = sorted(glob.glob("/spark-data/gutenberg_books/*.txt"))
book = spark.read.text(books)

results = (
    book.select(F.split(F.col("value"), " ").alias("line"))
    .select(F.explode(F.col("line")).alias("word"))
    .select(F.lower(F.col("word")).alias("word_lower"))
    .select(F.regexp_extract(F.col("word_lower"), "[a-z]*", 0).alias("word"))
    .where(F.col("word") != "")
    .groupby(F.col("word"))
    .count()
)

results.orderBy(F.col("count").desc()).show(10)

results.coalesce(1).write.mode("overwrite").csv(
    "/spark-data/results/chapter03/simple_count.csv"
)

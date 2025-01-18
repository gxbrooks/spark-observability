
# From Chapter 2 Listing 2.20

from pyspark.sql import SparkSession
from pyspark.sql.functions import col, split, explode, lower, regexp_extract, length, sum
spark = SparkSession.builder.getOrCreate()

books = [
            "./data/gutenberg_books/1342-0.txt", 
            "./data/gutenberg_books/11-0.txt", 
            "./data/gutenberg_books/1661-0.txt",
            "./data/gutenberg_books/2701-0.txt",
            "./data/gutenberg_books/30254-0.txt",
            "./data/gutenberg_books/84-0.txt",
        ]
book = spark.read.text(books)
lines = book.select(split(book.value, " ").alias("line"))
words = lines.select(explode(col("line")).alias("word"))
words_lower = words.select(lower(col("word")).alias("word_lower"))
words_clean = words_lower.select(
    regexp_extract(col("word_lower"), "[a-z]*", 0).alias("word")
)
words_nonull = words_clean.where(col("word") != "")

# Listing 3.1 Counting word frequencies using groupby() and count() 
groups = words_nonull.groupby(col("word"))

print(groups)
 
# <pyspark.sql.group.GroupedData at 0x10ed23da0>
 
results = words_nonull.groupby(col("word")).count()
 
print(results)
 
# DataFrame[word: string, count: bigint]
 
results.show()

# Exercise 3.1


# Option a + works
count_by_size = words_nonull.select(length(col("word")).alias("length")).groupby("length").count()
# Option b = A column or function parameter with name `length` cannot be resolved
# words_nonull.select(length(col("word"))).groupby("length").count()
# Option c - no column named "length"
# words_nonull.groupby("length").select("length").count()


count_by_size.select("length").count()

count_by_size.agg(sum(col("count"))).collect()[0][0]
count_by_size.agg(sum("count").alias("total")).collect()

# Listing 3.2 Displaying the top 10 words in Jane Austen’s Pride and Prejudice 
results.orderBy("count", ascending=False).show(10)
results.orderBy(col("count").desc()).show(10)


# Exercise 3.2 #############################################################################

(
    results.orderBy("count", ascending=False)
    .groupby(length(col("word")))
    .count()
    .show(5)
)
# sort is done on the non-aggregated columns, then grouped
(
    results
    .groupby(length(col("word")))
    .count()
    .orderBy("count", ascending=False)
    .show(5)
)
# sort is done on the aggregated columns, then grouped

results = results.repartition(10)

# Listing 3.3 Writing our results in multiple CSV files, one per partition results.write.csv("./data/simple_count.csv")
results.write.csv("./data/simple_count.csv", mode="overwrite")
print(f"Number of partitions: {results.rdd.getNumPartitions()}")

# Listing 3.4 Writing our results under a single partition 
results.coalesce(1).write.csv("./data/simple_count_single_partition.csv", mode="overwrite")

# Listing 3.5 Our first PySpark program, dubbed “Counting Jane Austen”
from pyspark.sql import SparkSession
from pyspark.sql.functions import (
    col,
    explode,
    lower,
    regexp_extract,
    split,
)
 
spark = SparkSession.builder.appName(
    "Analyzing the vocabulary of Pride and Prejudice."
).getOrCreate()
 
book = spark.read.text(books).repartition(10)
 
lines = book.select(split(book.value, " ").alias("line"))
 
words = lines.select(explode(col("line")).alias("word"))
 
words_lower = words.select(lower(col("word")).alias("word"))
 
words_clean = words_lower.select(
    regexp_extract(col("word"), "[a-z']*", 0).alias("word")
)
 
words_nonull = words_clean.where(col("word") != "")
 
results = words_nonull.groupby(col("word")).count()
 
results.orderBy("count", ascending=False).show(10)
 
results.coalesce(1).write.csv("./data/simple_count_single_partition.csv", mode="overwrite")


# Listing 3.6 Simplifying our PySpark functions import # Before
from pyspark.sql.functions import col, explode, lower, regexp_extract, split
import pyspark.sql.functions as F

dir(F) #to list out the module

# Listing 3.7 Removing intermediate variables by chaining transformation methods # Before
book = spark.read.text(books)
 
lines = book.select(split(book.value, " ").alias("line"))
 
words = lines.select(explode(col("line")).alias("word"))
 
words_lower = words.select(lower(col("word")).alias("word"))
 
words_clean = words_lower.select(
    regexp_extract(col("word"), "[a-z']*", 0).alias("word")
)

words_nonull = words_clean.where(col("word") != "")
 
results = words_nonull.groupby("word").count()
 
# After
import pyspark.sql.functions as F
 
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

# Listing 3.8 Chaining for writing over the same variable
df = spark.read.text("./data/gutenberg_books/1342-0.txt")   
df = df.select(F.split(F.col("value"), " ").alias("line"))   
 
# alternatively
df = (
       spark.read.text("./data/gutenberg_books/1342-0.txt") 
       .select(F.split(F.col("value"), " ").alias("line"))   
     )

# recommended formatter - not integrated with Notepad++
# https://black.readthedocs.io/en/stable/

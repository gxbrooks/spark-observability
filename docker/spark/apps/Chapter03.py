
# From Chapter 2 Listing 2.20

from pyspark.sql import SparkSession
from pyspark.sql.functions  import col, split, explode, lower, regexp_extract, length, sum
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
spark.stop()
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
# Before section of Listing3.7
book = spark.read.text(books)
 
lines = book.select(split(book.value, " ").alias("line"))
 
words = lines.select(explode(col("line")).alias("word"))
 
words_lower = words.select(lower(col("word")).alias("word"))
 
words_clean = words_lower.select(
    regexp_extract(col("word"), "[a-z']*", 0).alias("word")
)

words_nonull = words_clean.where(col("word") != "")
 
results = words_nonull.groupby("word").count()
 
# After section of List 3.7
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


#######################################################
# Excercise 3.3

# Part 1

# If you need to read multiple text files, replace `1342-0` by `*`.
results = (
    spark.read.text("./data/gutenberg_books/*.txt")
    .select(F.split(F.col("value"), " ").alias("line"))
    .select(F.explode(F.col("line")).alias("word"))
    .select(F.lower(F.col("word")).alias("word"))
    .select(F.regexp_extract(F.col("word"), "[a-z']*", 0).alias("word"))
    .where(F.col("word") != "")
    .groupby(F.col("word"))
    .count()
    .count()
)

print(results)

all_results = (
    spark.read.text("./data/gutenberg_books/*.txt")
    .select(F.split(F.col("value"), " ").alias("line"))
    .select(F.explode(F.col("line")).alias("word"))
    .select(F.lower(F.col("word")).alias("word"))
    .select(F.regexp_extract(F.col("word"), "[a-z']*", 0).alias("word"))
    .where(F.col("word") != "")
    .groupby(F.col("word"))
    .count()
    .orderBy("count", ascending=False)
)

# verify answer is correct
rows = all_results.collect()

# part 2
def countDistinctBookWords (dir):
    
    wordSpark = SparkSession.builder.appName(
        "Counting word occurences from a book."
        ).getOrCreate()
    wordSpark.sparkContext.setLogLevel("WARN")
    distinctWords = (
        spark.read.text("./data/gutenberg_books/*.txt")
        .select(F.split(F.col("value"), " ").alias("line"))
        .select(F.explode(F.col("line")).alias("word"))
        .select(F.lower(F.col("word")).alias("word"))
        .select(F.regexp_extract(F.col("word"), "[a-z']*", 0).alias("word"))
        .where(F.col("word") != "")
        .groupby(F.col("word"))
        .count()
        .collect())
    print(f"Distinct words = {len(distinctWords)}")
    wordSpark.stop()

countDistinctBookWords("./data/gutenberg_books/*.txt")
#regenerate the session becasue of the wordSpark.stop() above
spark = SparkSession.builder.getOrCreate()
######################################################
# Excercise 3.4

results = (
    spark.read.text("./data/gutenberg_books/1342-0.txt")
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

results.show(5)

######################################################
# Excercise 3.5

chars = (
    spark.read.text("./data/gutenberg_books/1342-0.txt")
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

chars = (
    spark.read.text("./data/gutenberg_books/1342-0.txt")
    .select(F.split(F.col("value"), " ").alias("line"))
    .select(F.explode(F.col("line")).alias("word"))
    .select(F.lower(F.col("word")).alias("word"))
    .select(F.regexp_extract(F.col("word"), "[a-z']*", 0).alias("word"))
    .where(F.col("word") != "")
    .select(F.substring(F.col("word"), 1, 0).alias("first_character"))
)

######################################################
# Excercise 3.6

# essay questions why not .count().sum()
#
# count returns a dataframe and there is no shortcut function for sum aggregation

sresults = (
    spark.read.text("./data/gutenberg_books/1342-0.txt")
    .select(F.split(F.col("value"), " ").alias("line"))
    .select(F.explode(F.col("line")).alias("word"))
    .select(F.lower(F.col("word")).alias("word"))
    .select(F.regexp_extract(F.col("word"), "[a-z']*", 0).alias("word"))
    .where(F.col("word") != "")
    .groupby(F.col("word"))
    .count()
)
sresults.show()
sresults.count()

######################################################
# Excercise self: Compare the word counts by file, sorting by the total number of words..


# step 1: preprocess all the words
df = (
    spark.read.text("./data/gutenberg_books/*.txt")
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


# Step 3: create columns for each basename 
by_word_pivot_base_df = (
    by_word_base_df
    .groupBy(F.col("word"))
    .pivot("basename")
    .agg(F.sum(F.col("word_count")))
    .fillna(0)
    )

# Step 3: create columns of each basename with the word counts
by_word_df = (
    by_word_base_df
    .groupBy(F.col("word"))
    .agg(F.sum(F.col("word_count")).alias("total"))
    )

# step 4: Merge in word counts by file and the total word counts into one df
merged_df = (
    by_word_df
    .join(by_word_pivot_base_df, on="word", how="left")
    .orderBy(F.col("total"), ascending=False)
    )

spark.stop()

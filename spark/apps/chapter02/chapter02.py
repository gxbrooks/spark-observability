

# Listing 2.2

from pyspark.sql import SparkSession 
from pyspark.sql.functions import col, split, explode, lower, regexp_extract
spark = (SparkSession
         .builder          
         .appName("Analyzing the vocabulary of Pride and Prejudice.")
         .getOrCreate())

# Listing 2.3
spark.sparkContext.setLogLevel("INFO")

book = spark.read.text("/mnt/spark/data/gutenberg_books/1342-0.txt")

book.show()

# Listing 2.6 Printing the schema of our data frame
book.printSchema()
print(book.dtypes)


# Listing 2.7 Using PySpark’s documentation directly in the REPL

print(spark.__doc__)

# Listing 2.8 Showing a little data using the .show() method

book.show()

# Listing 2.9 Showing less length, more width with the show() method

book.show(10, truncate=50)


# Listing 2.10 Splitting our lines of text into arrays or words from pyspark.sql.functions import split
 
lines = book.select(split(book.value, " ").alias("line"))
 
lines.show(5)

# Listing 2.11 The simplest select statement ever book.select(book.value)

book.select(book.value)

# Listing 2.12 Selecting the value column from the book data frame from pyspark.sql.functions import col
 
book.select(book.value)
book.select(book["value"])
book.select(col("value"))
book.select("value")

# Listing 2.13 Splitting our lines of text into lists of words 
from pyspark.sql.functions import col, split
 
lines = book.select(split(col("value"), " "))
 
lines
 
# DataFrame[split(value,  , -1): array<string>]
 
lines.printSchema()
 
# root
#  |-- split(value,  , -1): array (nullable = true)
#  |    |-- element: string (containsNull = true)
 

# Listing 2.14 Our data frame before and after the aliasing book.select(split(col("value"), " ")).printSchema()
# root
#  |-- split(value,  , -1): array (nullable = true)    ❶
#  |    |-- element: string (containsNull = true)
 
book.select(split(col("value"), " ").alias("line")).printSchema()
 
# Listing 2.15 Renaming a column, two ways

# This looks a lot cleaner
lines = book.select(split(book.value, " ").alias("line"))
lines.printSchema()
# This is messier, and you have to remember the name PySpark assigns automatically
lines = book.select(split(book.value, " "))
lines = lines.withColumnRenamed("split(value,  , -1)", "line")
lines.printSchema()

# Listing 2.16 Exploding a column of arrays into rows of elements

from pyspark.sql.functions import explode, col
 
words = lines.select(explode(col("line")).alias("word"))
words.show(15)

# Listing 2.17 Lower the case of the words in the data frame 
from pyspark.sql.functions import lower
words_lower = words.select(lower(col("word")).alias("word_lower"))
words_lower.show()

# Listing 2.18 Using regexp_extract to keep what looks like a word 
from pyspark.sql.functions import regexp_extract
words_clean = words_lower.select(
    regexp_extract(col("word_lower"), "[a-z]+", 0).alias("word") 
)
words_clean.show()

# Exercise 2.1
from pyspark.sql.functions import col, explode
 
exo_2_1_df = spark.createDataFrame(
    [
        [[1, 2, 3, 4, 5]],
        [[5, 6, 7, 8, 9, 10]]
    ],
    ["numbers"]
)
 
solution_2_1_df = exo_2_1_df.select(explode(col("numbers")))
 
print(f"solution_2_1_df contains {solution_2_1_df.count()} records.")
exo_2_1_df.show()

# Listing 2.19 Filtering rows in your data frame using where or filter 
words_nonull = words_clean.filter(col("word") != "")
 
words_nonull.show()

print(f"solution_2_1_df contains {words_nonull.count()} records.")
print(f"words_nonull contains {words_clean.count()} records.")

# Exercise 2.2 Counting words versus numbers
from pyspark.sql.types import StructType, StructField, StringType, IntegerType

exo2_2_df = spark.createDataFrame(
    [["test", "more test", 10_000_000_000]], ["one", "two", "three"]
)
 
exo2_2_df.printSchema()

string_type = StringType()
string_columns = 0
all_columns = 0
for field in exo2_2_df.schema.fields: 
    field_name = field.name 
    field_type = field.dataType 
    print(f"Field Name: {field_name}, Field Type: {field_type}")
    if field_type == string_type:
      string_columns = string_columns + 1
    all_columns = all_columns + 1

print("String columns={}  Non-string columns={}  Total Columns={}\n".format(string_columns, all_columns - string_columns, all_columns))



# Excersize 2.3 #############################################################################
from pyspark.sql.functions import col, length
 
# The `length` function returns the number of characters in a string column.
 
exo2_3_dfa = (
    spark.read.text("/mnt/spark/data/gutenberg_books/1342-0.txt")
    .select(length(col("value")))
    .withColumnRenamed("length(value)", "number_of_char")
)
exo2_3_dfb = (
    spark.read.text("/mnt/spark/data/gutenberg_books/1342-0.txt")
    .select(length(col("value")))
)

# Excersize 2.4 #############################################################################
from pyspark.sql.functions import col, greatest
 
exo2_4_df = spark.createDataFrame(
    [["key", 10_000, 20_000]], ["key", "value1", "value2"]
)
exo2_4_df.printSchema()

from pyspark.sql.functions import col, greatest
# The following statement will return an error
from pyspark.sql.utils import AnalysisException
 
try:
    exo2_4_mod = exo2_4_df.select(
        greatest(col("value1"), col("value2")).alias("maximum_value")
    ).select("key", "max_value")
except AnalysisException as err:
    print(err)

# Correct answer
exo2_4_mod =  exo2_4_df.select(col("key"), greatest(col("value1"), col("value2")).alias("max_value"))
exo2_4_mod.show()
 
# Excersize 2.5 #############################################################################
# Listing 2.20 The words_nonull for the exercise

from pyspark.sql import SparkSession
from pyspark.sql.functions import col, split, explode, lower, regexp_extract
spark = SparkSession.builder.getOrCreate()
 
book = spark.read.text("/mnt/spark/data/gutenberg_books/1342-0.txt")
lines = book.select(split(book.value, " ").alias("line"))
words = lines.select(explode(col("line")).alias("word"))
words_lower = words.select(lower(col("word")).alias("word_lower"))
words_clean = words_lower.select(
    regexp_extract(col("word_lower"), "[a-z]*", 0).alias("word")
)
words_nonull = words_clean.where(col("word") != "")
# Excersize 2.5
words_no_is = words_nonull.where(col("word") != "is")
words_no_short = words_nonull.where(length(col("word")) > 3)

# Excersize 2.6 #############################################################################

words_not_in = words_nonull.where(~col("word").isin(["is", "not", "the", "if"]))

# Excersize 2.7 #############################################################################
from pyspark.sql.functions import col, split
 
try:
    book = spark.read.text("/mnt/spark/data/gutenberg_books/1342-0.txt")
    # Intentional error
    # book = book.printSchema()
    lines = book.select(split(book.value, " ").alias("line"))
    words = lines.select(explode(col("line")).alias("word"))
except AnalysisException as err:
    print(err)

try:
    book = spark.read.text("/mnt/spark/data/gutenberg_books/1342-0.txt")
    book.printSchema()
    lines = book.select(split(book.value, " ").alias("line"))
    words = lines.select(explode(col("line")).alias("word"))
except AnalysisException as err:
    print(err)



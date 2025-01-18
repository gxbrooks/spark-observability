# ex 2.3
from pyspark.sql import SparkSession
from pyspark.sql.functions import col, length

def myshow(df, version_)
    print(version)
    df.show()
    

spark = SparkSession.builder.appName(
    "Ch02 - Analyzing the vocabulary of Pride and Prejudice."
).getOrCreate()

# Rewrite:
exo2_3_df_origin = (
    spark.read.text("./data/gutenberg_books/1342-0.txt")
    .select(length(col("value")))
    .withColumnRenamed("length(value)", "number_of_char")
)

myshow(exo2_3_df_origin, "exo2_3_df_origin")

# Solution:
exo2_3_df_solution = (
    spark.read.text("./data/gutenberg_books/1342-0.txt")
    .select(length(col("value")).alias("number_of_char"))
)
myshow(exo2_3_df_solution, "exo2_3_df_solution")

# ex 2.5
# a)
words_without_is = words_nonull.where(col("word") != "is")
myshow(words_without_is

words_without_is.show()
# b)
words_more_than_3_char = words_nonull.where(length(col("word")) > 3)

words_more_than_3_char.show()
# ex 2.6
words_no_is_not_the_if = (
    words_nonull.where(~col("word").isin(
        ["no", "is", "the", "if"])))

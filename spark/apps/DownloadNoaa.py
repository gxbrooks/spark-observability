
from pyspark.sql import SparkSession
from google.cloud import bigquery
from functools import reduce
from itertools import islice
from pyspark.sql import SparkSession, functions as F


def get_noaa_gsod_data(year, spark):
    """
    Reads data from a single year of the NOAA GSOD dataset.

    Args:
        year (int): The year to read data for.
        spark (SparkSession): The SparkSession object.

    Returns:
        pyspark.sql.DataFrame: A DataFrame containing the data for the specified year.
    """
    df = spark.read.format("bigquery") \
               .option("table", f"bigquery-public-data.noaa_gsod.gsod{year}") \
               .load()

    # Create a 'date' column if it doesn't exist
    if 'date' not in df.columns:
        df = df.withColumn("date", F.make_date(F.col("year").cast("integer"), 
                                              F.col("mo").cast("integer"), 
                                              F.col("da").cast("integer"))) 

    return df

# Create a SparkSession
noaa = (
    SparkSession.builder 
    .appName("NOAA GSOD Data") 
    .config(
        "spark.jars.packages", 
        "com.google.cloud.spark:spark-bigquery-with-dependencies_2.12:0.32.0"
    ).config("spark.hadoop.google.cloud.auth.service.account.enable", "true") 
    .config("spark.hadoop.google.cloud.auth.service.account.json.keyfile", "./apps/bq-api-key.json") 
    .config("spark.sql.execution.arrow.pyspark.enabled", "true") 
    .config("spark.sql.execution.arrow.pyspark.fallback.enabled", "true") 
    .getOrCreate()
)

# Define years to read data from
years = range(2014, 2024)

# Use reduce to combine DataFrames
noaa_df = reduce(lambda df1, df2: df1.union(df2), 
    (get_noaa_gsod_data(year, noaa) for year in years[1:]), 
    get_noaa_gsod_data(years[0], noaa)) 

# Show the first few rows of the combined DataFrame
# noaa_df.show(5)


# Save as Parquet
(
    noaa_df
    .write.mode("overwrite")
    .parquet("file:///opt/spark/data/gsod_data.parquet")
)

# Stop the SparkSession
noaa.stop()
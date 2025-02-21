
from pyspark.sql import SparkSession
from google.cloud import bigquery
from functools import reduce
from pyspark.sql import SparkSession, functions as F
import pyspark.sql.types as T


"""
spark-submit  \
    --master spark://spark-master:7077 \
    --deploy-mode client \
    --packages com.google.cloud.spark:spark-bigquery-with-dependencies_2.12:0.32.0 \
    ./apps/GSOD_Download.py
"""
def get_noaa_gsod_data(year, noaa):
    """
    Reads data from a single year of the NOAA GSOD dataset.

    Args:
        year (int): The year to read data for.
        spark (SparkSession): The SparkSession object.

    Returns:
        pyspark.sql.DataFrame: A DataFrame containing the data for the specified year.
    """
    df = noaa.read.format("bigquery") \
               .option("table", f"bigquery-public-data.noaa_gsod.gsod{year}") \
               .load()

    # Align types with the types expected in the book 
    # Rioux, Jonathan. Data Analysis with Python and PySpark Manning. Kindle Edition. 
    
    df = (
        df
        .withColumn("year", F.col("year").cast("integer"))
        .withColumn("mo", F.col("mo").cast("integer"))
        .withColumn("da", F.col("da").cast("integer"))
        .withColumn("temp", F.col("temp").cast("float"))
        .dropna(subset=["year", "mo", "da", "temp"])
        # Clean up data over 1M rows with stn = "999999"
        .filter((F.col("temp") != 9999.9) & (F.col("stn") != "999999"))
    )
    # Create a 'date' column if it doesn't exist
    # apparently more recent years have a data column
    if 'date' in df.columns:
        df = df.withColumn("date", F.col("date").cast(T.DateType()))
    else:
        df = df.withColumn(
                "date", 
                F.make_date(
                    F.col("year"), 
                    F.col("mo"), 
                    F.col("da")))
    return df

# Create a SparkSession

"""
Do not use the config:
    .config("spark.jars.packages", "com.google.cloud.spark:spark-bigquery-with-dependencies_2.12:0.30.0")

As it does not work well with spark-submit even though it works with iPython. Instead you need to call 
spark-submit and add the packages parameter:

    --packages com.google.cloud.spark:spark-bigquery-with-dependencies_2.12:0.32.0' 

For this code, without the ocnfig (above) for spark.jar.packages, you need to set the 
environment variable PYSPARK_DRIVER_PYTHON=ipython and then launch the pyspark script with the same 
package parameter. For example:

    docker compose exec \
        -e PYSPARK_DRIVER_PYTHON=ipython spark-master \
        pyspark --packages com.google.cloud.spark:spark-bigquery-with-dependencies_2.12:0.32.0'

For references see the source code of bin/pyspark 
"""
noaa = (
    SparkSession.builder 
    .appName("NOAA GSOD Data") 
    #
    # Copilot's initial recommendation
    # .config("spark.jars", "gs://spark-lib/bigquery/spark-bigquery-with-dependencies_2.12-0.23.2.jar") \
    # The books version
    # .config("spark.jars.packages", "com.google.cloud.spark:spark-bigquery-with-dependencies_2.12:0.19.1")
    # Copilot recommended version for Spark 3.5.1
    # .config("spark.jars.packages", "com.google.cloud.spark:spark-bigquery-with-dependencies_2.12:0.32.0")
    # .config("spark.jars.packages", "com.google.cloud.spark:spark-bigquery-with-dependencies_2.12:0.30.0")
    .config("spark.hadoop.google.cloud.auth.service.account.enable", "true") 
    .config("spark.hadoop.google.cloud.auth.service.account.json.keyfile", '/opt/spark/apps/bq-api-key.json') 
    .config("spark.sql.execution.arrow.pyspark.enabled", "true") 
    .config("spark.sql.execution.arrow.pyspark.fallback.enabled", "true") 
    .getOrCreate()
)

noaa = (
    SparkSession.builder 
    .appName("NOAA GSOD Data") 
    .config("spark.jars.packages", "com.google.cloud.spark:spark-bigquery-with-dependencies_2.12:0.32.0")
    .config("spark.hadoop.google.cloud.auth.service.account.enable", "true") 
    .config("spark.hadoop.google.cloud.auth.service.account.json.keyfile", '/opt/spark/apps/bq-api-key.json') 
    .config("spark.sql.execution.arrow.pyspark.enabled", "true") 
    .config("spark.sql.execution.arrow.pyspark.fallback.enabled", "true") 
    .getOrCreate()
)

# Define years to read data from
years = range(2014, 2024)

# Use reduce to combine DataFrames
noaa_df = reduce(lambda df1, df2: df1.unionByName(df2), 
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





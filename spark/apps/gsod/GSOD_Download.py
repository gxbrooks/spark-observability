from pyspark.sql import SparkSession
from functools import reduce
import pyspark.sql.functions as F
import pyspark.sql.types as T
import os


"""
spark-submit  \
    --master spark://spark-master:7077 \
    --deploy-mode client \
    --packages com.google.cloud.spark:spark-bigquery-with-dependencies_2.13:0.37.0 \
    ./apps/GSOD_Download.py
"""
def get_noaa_gsod_data(year, noaa, api_key_path):
    """
    Reads data from a single year of the NOAA GSOD dataset.

    Args:
        year (int): The year to read data for.
        noaa (SparkSession): The SparkSession object.
        api_key_path (str): Path to the BigQuery API key JSON file.

    Returns:
        pyspark.sql.DataFrame: A DataFrame containing the data for the specified year.
    """
    df = noaa.read.format("bigquery") \
               .option("table", f"bigquery-public-data.noaa_gsod.gsod{year}") \
               .option("credentialsFile", api_key_path) \
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
# Note: When using spark-submit, add --packages parameter:
#   --packages com.google.cloud.spark:spark-bigquery-with-dependencies_2.12:0.32.0
# The spark.jars.packages config doesn't work well with spark-submit

# Determine API key path based on execution context
# For cluster mode: /opt/spark/apps/bq-api-key.json
# For client mode: use relative path from script location
script_dir = os.path.dirname(os.path.abspath(__file__))
api_key_path = os.path.join(script_dir, "bq-api-key.json")

# Check if running in cluster (keyfile exists at cluster path) or client mode
if os.path.exists('/opt/spark/apps/bq-api-key.json'):
    api_key_path = '/opt/spark/apps/bq-api-key.json'
elif not os.path.exists(api_key_path):
    raise FileNotFoundError(f"BigQuery API key not found at {api_key_path} or /opt/spark/apps/bq-api-key.json")

print(f"Using BigQuery API key: {api_key_path}")

# Note: When running with python3 directly, the packages config may work
# When using spark-submit, use --packages parameter instead
noaa = (
    SparkSession.builder 
    .appName("NOAA GSOD Data") 
    .config("spark.jars.packages", "com.google.cloud.spark:spark-bigquery-with-dependencies_2.13:0.37.0,javax.inject:javax.inject:1")
    .config("spark.sql.execution.arrow.pyspark.enabled", "true") 
    .config("spark.sql.execution.arrow.pyspark.fallback.enabled", "true") 
    .getOrCreate()
)

# Test mode: Set TEST_MODE environment variable to download just one year
# Example: TEST_MODE=1 python3 spark/apps/gsod/GSOD_Download.py
test_mode = os.environ.get('TEST_MODE', '0') == '1'

if test_mode:
    print("=" * 60)
    print("TEST MODE: Downloading single year (2023) to verify API key")
    print("=" * 60)
    # Test with just one year
    test_year = 2023
    print(f"Downloading data for year {test_year}...")
    noaa_df = get_noaa_gsod_data(test_year, noaa, api_key_path)
    print(f"Successfully downloaded {noaa_df.count()} records for {test_year}")
    noaa_df.show(5)
    print(f"Schema:")
    noaa_df.printSchema()
    print("=" * 60)
    print("TEST PASSED: API key is valid and function works correctly")
    print("To download all years, run without TEST_MODE=1")
    print("=" * 60)
else:
    # Define years to read data from (2014-2023, 10 years)
    years = range(2014, 2024)
    print(f"Downloading NOAA GSOD data for years {years[0]} to {years[-1]} ({len(years)} years)")
    
    # Use reduce to combine DataFrames
    print("Downloading first year...")
    noaa_df = get_noaa_gsod_data(years[0], noaa, api_key_path)
    print(f"Year {years[0]}: {noaa_df.count()} records")
    
    for year in years[1:]:
        print(f"Downloading year {year}...")
        year_df = get_noaa_gsod_data(year, noaa, api_key_path)
        count = year_df.count()
        print(f"Year {year}: {count} records")
        noaa_df = noaa_df.unionByName(year_df, allowMissingColumns=True)
    
    total_count = noaa_df.count()
    print(f"\nTotal records across all years: {total_count}")
    
    # Show the first few rows of the combined DataFrame
    print("\nSample data:")
    noaa_df.show(5)
    
    # Save as Parquet
    output_path = "/mnt/spark/data/gsod_data.parquet"
    print(f"\nSaving to {output_path}...")
    (
        noaa_df
        .write.mode("overwrite")
        .parquet(output_path)
    )
    print(f"Successfully saved {total_count} records to {output_path}")

# Stop the SparkSession
noaa.stop()





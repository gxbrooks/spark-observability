
#!/usr/bin/env python3
"""
Chapter 09: Advanced Analytics
Spark 4.0.1 with Python 3.11
"""

import os
from pyspark.sql import SparkSession
from functools import reduce
import pyspark.sql.functions as F
import pyspark.sql.types as T
import pandas as pd

# Python version controlled by PYSPARK_PYTHON environment variable (set via spark_env.sh)

# Create Spark session - configuration comes from spark-defaults.conf
spark = SparkSession.builder \
    .appName("Chapter 09: Advanced Analytics") \
    .getOrCreate()

print("=== Chapter 09: Advanced Analytics ===")
print(f"Spark version: {spark.version}")
print(f"Spark master: {spark.sparkContext.master}")

#########################################################################################
#
# Un-named side panel
# Using the single parquet version
"""
spark = SparkSession.builder.appName(
    "Ch09 - Using UDFs"
    .config("spark.eventLog.enabled", "true") \
    .config("spark.eventLog.dir", os.getenv('SPARK_EVENTS_DIR', '/mnt/spark/events')) \
).getOrCreate()

gsod = (
    reduce(
        lambda x, y: x.unionByName(y, allowMissingColumns=True),
        [
            # spark.read.parquet(f"/mnt/spark/data/gsod_noaa/gsod{year}.parquet")
            spark.read.parquet(f"/mnt/spark/data/gsod_noaa/gsod{year}.parquet")
            for year in range(2010, 2021)
        ],
    )
    .dropna(subset=["year", "mo", "da", "temp"])
    .where(F.col("temp") != 9999.9)
    .drop("date")
)
"""

#########################################################################################
#
# Un-named side panel


# Try to read GSOD data, create sample data if not available
try:
    gsod = spark.read.parquet(f"/mnt/spark/data/gsod_data.parquet")
    print("Info    : Loaded GSOD data from parquet file")
except Exception as e:
    print(f"Warning : GSOD parquet file not found: {e}")
    print("Info    : Creating sample weather data for demonstration...")
    
    # Create sample weather data for demonstration
    from pyspark.sql.types import StructType, StructField, StringType, IntegerType, DoubleType
    
    sample_data = [
        ("2020-01-01", "USW00094728", 2020, 1, 1, 15.5, 25.0, 5.0),
        ("2020-01-02", "USW00094728", 2020, 1, 2, 12.3, 22.0, 2.5),
        ("2020-01-03", "USW00094728", 2020, 1, 3, 18.7, 28.0, 9.0),
        ("2020-01-04", "USW00094728", 2020, 1, 4, 20.1, 30.0, 10.0),
        ("2020-01-05", "USW00094728", 2020, 1, 5, 16.8, 26.0, 7.5),
        ("2020-02-01", "USW00094728", 2020, 2, 1, 14.2, 24.0, 4.5),
        ("2020-02-02", "USW00094728", 2020, 2, 2, 17.9, 27.0, 8.5),
        ("2020-02-03", "USW00094728", 2020, 2, 3, 13.6, 23.0, 4.0),
        ("2020-03-01", "USW00094728", 2020, 3, 1, 19.4, 29.0, 9.5),
        ("2020-03-02", "USW00094728", 2020, 3, 2, 21.2, 31.0, 11.0),
    ]
    
    schema = StructType([
        StructField("date", StringType(), True),
        StructField("station", StringType(), True),
        StructField("year", IntegerType(), True),
        StructField("mo", IntegerType(), True),
        StructField("da", IntegerType(), True),
        StructField("temp", DoubleType(), True),
        StructField("max", DoubleType(), True),
        StructField("min", DoubleType(), True)
    ])
    
    gsod = spark.createDataFrame(sample_data, schema)
    print("Info    : Created sample weather data for demonstration")

#########################################################################################
#
# 

# Listing 9.1 Initializing PySpark within your Python shell with BigQuery connector 

from pyspark.sql import SparkSession
 
# spark = SparkSession.builder.config(
#     "spark.jars.packages",
#     "com.google.cloud.spark:spark-bigquery-with-dependencies_2.12:0.19.1", ## 1
#     .config("spark.eventLog.enabled", "true") \
#     .config("spark.eventLog.dir", os.getenv('SPARK_EVENTS_DIR', '/mnt/spark/events')) \
# ).getOrCreate()

# [...]
# com.google.cloud.spark#spark-bigquery-with-dependencies_2.12 added as a dependency
# :: resolving dependencies :: org.apache.spark#spark-submit-parent-77d4bbf3-1fa4-4d43-b5f7-59944801d46c;1.0
#     confs: [default]
#     found com.google.cloud.spark#spark-bigquery-with-dependencies_2.12;0.19.1 in central
# downloading https://repo1.maven.org/maven2/com/google/cloud/spark/spark-bigquery-with-dependencies_2.12/
#              0.19.1/spark-bigquery-with-dependencies_2.12-0.19.1.jar ...
#     [SUCCESSFUL ] com.google.cloud.spark#spark-bigquery-with-dependencies_2.12;0.19.1!
#                    spark-bigquery-with-dependencies_2.12.jar (888ms)
# :: resolution report :: resolve 633ms :: artifacts dl 889ms
#     :: modules in use:
#     com.google.cloud.spark#spark-bigquery-with-dependencies_2.12;0.19.1 from central in [default]
#     ---------------------------------------------------------------------
#     |                  |            modules            ||   artifacts   |
#     |       conf       | number| search|dwnlded|evicted|| number|dwnlded|
#     ---------------------------------------------------------------------
#     |      default     |   1   |   1   |   1   |   0   ||   1   |   1   |
#     ---------------------------------------------------------------------
# :: retrieving :: org.apache.spark#spark-submit-parent-77d4bbf3-1fa4-4d43-b5f7-59944801d46c
#     confs: [default]
#     1 artifacts copied, 0 already retrieved (33158kB/23ms)

#########################################################################################
#
# 
# Listing 9.2 Reading the stations and gsod tables for 2010 to 2020 

from functools import reduce
import pyspark.sql.functions as F
 
 
def read_df_from_bq(year):                                         ## 1
    return (
        spark.read.format("bigquery").option(                      ## 2
            "table", 
            f"bigquery-public-data.noaa_gsod.gsod{year}"           ## 3
        )  
        .option("credentialsFile", "./apps/bq-api-key.json")        ## 4
        .load()
    )

# Use parquet files instead of BigQuery (BigQuery connector not available for Spark 4.0.1)
def read_df_from_parquet(year):
    """Read GSOD data from parquet file for a specific year."""
    return spark.read.parquet(f"/mnt/spark/data/gsod_noaa/gsod{year}.parquet")
 
# Commented out BigQuery code - using parquet files instead
# gsod = (
#     reduce(
#         lambda x, y: x.unionByName(y, allowMissingColumns=True),
#         [read_df_from_bq(year) for year in range(2014, 2024)],     ## 5
#     )
#     .dropna(subset=["year", "mo", "da", "temp"])
#     .where(F.col("temp") != 9999.9)
#     .drop("date")
# )

# Use parquet files instead
gsod = (
    reduce(
        lambda x, y: x.unionByName(y, allowMissingColumns=True),
        [read_df_from_parquet(year) for year in range(2014, 2024)],
    )
    .dropna(subset=["year", "mo", "da", "temp"])
    .where(F.col("temp") != 9999.9)
    # Convert date string back to date type if needed
    .withColumn("date", F.to_date(F.col("date"), "yyyy-MM-dd"))
)

#########################################################################################
#
# 
# Listing 9.3 Reading the gsod data from 2010 to 2020 via a loop 

# Commented out BigQuery code - using parquet files instead
# gsod_alt = read_df_from_bq(2010)     # 1
# for year in range(2011, 2020):
#     gsod_alt = gsod_alt.unionByName(
#         read_df_from_bq(year), allowMissingColumns=True
#     )
# gsod_alt = gsod_alt.drop("date")

# Use parquet files instead (2014-2023 available)
gsod_alt = read_df_from_parquet(2014)
for year in range(2015, 2024):
    gsod_alt = gsod_alt.unionByName(
        read_df_from_parquet(year), allowMissingColumns=True
    )
gsod_alt = (
    gsod_alt
    .dropna(subset=["year", "mo", "da", "temp"])
    .where(F.col("temp") != 9999.9)
    .withColumn("date", F.to_date(F.col("date"), "yyyy-MM-dd"))
    .drop("date")
)


#########################################################################################
#
# 
# Listing 9.4 Creating a pandas scalar UDF that transforms Fahrenheit into Celsius 
import pandas as pd
import pyspark.sql.types as T
 
 
@F.pandas_udf(T.DoubleType())                 ## 1
def f_to_c(degrees: pd.Series) -> pd.Series:  ## 2
    """Transforms Farhenheit to Celsius."""
    return (degrees - 32) * 5 / 9

#########################################################################################
#
# 
# Listing 9.5 Using a Series to Series UDF like any other column manipulation function 

gsod = gsod.withColumn("temp_c", f_to_c(F.col("temp")))
gsod.select("temp", "temp_c").distinct().show(5)
 
# +-----+-------------------+
# | temp|             temp_c|
# +-----+-------------------+
# | 37.2| 2.8888888888888906|
# | 85.9| 29.944444444444443|
# | 53.5| 11.944444444444445|
# | 71.6| 21.999999999999996|
# |-27.6|-33.111111111111114|
# +-----+-------------------+
# only showing top 5 rows

#########################################################################################
#
# 
# Listing 9.6 Using an Iterator of Series to Iterator of Series UDF 
from time import sleep
from typing import Iterator
 
 
@F.pandas_udf(T.DoubleType())
def f_to_c2(degrees: Iterator[pd.Series]) -> Iterator[pd.Series]:  ## 1
    """Transforms Farhenheit to Celsius."""
    sleep(5)                                                       ## 2
    for batch in degrees:                                          ## 3
        yield (batch - 32) * 5 / 9                                 ## 3
 
 
gsod.select(
    "temp", f_to_c2(F.col("temp")).alias("temp_c")
).distinct().show(5)
# +-----+-------------------+
# | temp|             temp_c|
# +-----+-------------------+
# | 37.2| 2.8888888888888906|
# | 85.9| 29.944444444444443|
# | 53.5| 11.944444444444445|
# | 71.6| 21.999999999999996|
# |-27.6|-33.111111111111114|
# +-----+-------------------+
# only showing top 5 rows

#########################################################################################
#
# 
# Listing 9.7 Assembling the date from three columns using an Iterator of multiple Series UDF 

from typing import Tuple
 
@F.pandas_udf(T.DateType())
def create_date(
    year_mo_da: Iterator[Tuple[pd.Series, pd.Series, pd.Series]]
) -> Iterator[pd.Series]:
    """Merges three cols (representing Y-M-D of a date) into a Date col."""
    for year, mo, da in year_mo_da:
        yield pd.to_datetime(
            pd.DataFrame(dict(year=year, month=mo, day=da))
        )
 
 
gsod.select(
    "year", "mo", "da",
    create_date(F.col("year"), F.col("mo"), F.col("da")).alias("date2"),
).distinct().show(5)

#########################################################################################
#
# 
# Exercise 9.1 
# What are the values of WHICH_TYPE and WHICH_SIGNATURE in the following code block? 

exo9_1 = pd.Series(["red", "blue", "blue", "yellow"])
 
# def color_to_num(colors: WHICH_SIGNATURE) -> WHICH_SIGNATURE:
# Exercise 9.1: The signature should be Series -> Series (not Iterator)
def color_to_num(colors: pd.Series) -> pd.Series:
    return colors.apply(
        lambda x: {"red": 1, "blue": 2, "yellow": 3}.get(x)
    )
 
 
color_to_num(exo9_1)
 
# 0    1
# 1    2
# 2    2
# 3    3

# color_to_num_udf = F.pandas_udf(color_to_num, WHICH_TYPE)
# Exercise 9.1: WHICH_TYPE should be T.IntegerType() for the return type
color_to_num_udf = F.pandas_udf(color_to_num, T.IntegerType())

#########################################################################################
#
# 
# Listing 9.8 Creating a grouped aggregate UDF 

from sklearn.linear_model import LinearRegression                   ## 1
 
@F.pandas_udf(T.DoubleType())
def rate_of_change_temperature(day: pd.Series, temp: pd.Series) -> float:
    """Returns the slope of the daily temperature for a given period of time."""
    return (
        LinearRegression()                                          ## 2
        .fit(X=day.astype(int).values.reshape(-1, 1), y=temp)       ## 3
        .coef_[0]                                                   ## 4
    )

#########################################################################################
#
# 
# Listing 9.9 Applying our grouped aggregate UDF using agg() 

result = gsod.groupby("stn", "year", "mo").agg(
    rate_of_change_temperature(gsod["da"], gsod["temp"]).alias(   ## 1
        "rt_chg_temp"
    )
)
result.show(5, False)
# +------+----+---+---------------------+
# |stn   |year|mo |rt_chg_temp          |
# +------+----+---+---------------------+
# |010250|2018|12 |-0.01014397905759162 |
# |011120|2018|11 |-0.01704736746691528 |
# |011150|2018|10 |-0.013510329829648423|
# |011510|2018|03 |0.020159116598556657 |
# |011800|2018|06 |0.012645501680677372 |
# +------+----+---+---------------------+
# only showing top 5 rows

#########################################################################################
#
# 
# Listing 9.10 A group map UDF to scale temperature values 
def scale_temperature(temp_by_day: pd.DataFrame) -> pd.DataFrame:
    """Returns a simple normalization of the temperature for a site.
 
    If the temperature is constant for the whole window, defaults to 0.5."""
    temp = temp_by_day.temp
    answer = temp_by_day[["stn", "year", "mo", "da", "temp"]]
    if temp.min() == temp.max():
        return answer.assign(temp_norm=0.5)
    return answer.assign(
        temp_norm=(temp - temp.min()) / (temp.max() - temp.min())
    )

#########################################################################################
#
# 
# Listing 9.11 Split-apply-combing in PySpark 
gsod_map = gsod.groupby("stn", "year", "mo").applyInPandas(
    scale_temperature,
    schema=(
        # "stn string, year string, mo string, "
        # "da string, temp double, temp_norm double"
        # Converted year, mo, & day to int in generation of 
        # gsod parquet file
        "stn string, year int, mo int, "
        "da int, temp double, temp_norm double"
    ),
)

gsod_map.show(5, False)
# +------+----+---+---+----+-------------------+
# |stn   |year|mo |da |temp|temp_norm          |
# +------+----+---+---+----+-------------------+
# |010250|2018|12 |08 |21.8|0.06282722513089001|
# |010250|2018|12 |27 |28.3|0.40314136125654443|
# |010250|2018|12 |31 |29.1|0.4450261780104712 |
# |010250|2018|12 |19 |27.6|0.36649214659685864|
# |010250|2018|12 |04 |36.6|0.8376963350785339 |
# +------+----+---+---+----+-------------------+

#########################################################################################
#
# 
# Listing 9.12 Moving one station, one month’s worth of data into a local pandas DataFrame 

# gsod_local = gsod.where(
# The df should be gsod_map, where "temp_norm" is defined
# and not gsod - see Listing 9.10
gsod_local = gsod_map.where(
    # "year = '2018' and mo = '08' and stn = '710920'"
    "year = 2018 and mo = 08 and stn = '710920'"
).toPandas()
 
 
print(
    rate_of_change_temperature.func(                ## 1
        gsod_local["da"], gsod_local["temp_norm"]
    )
)
# -0.007830974115511494

#########################################################################################
#
# 
# Exercise 9.2 
# Using the following definitions, create a temp_to_temp(value, from_temp, to_temp) that 
# takes a numerical value in from_temp degrees and converts it to to degrees. Use a 
# pandas UDF this time (we did the same exercise in chapter 8). 

# C = (F - 32) * 5 / 9 (Celsius) 
# K = C + 273.15 (temp_K) 
# R = F + 459.67 (temp_R)

# add Celius, temp_K and temp_R temperatures to gsod

schema_FCKR = T.StructType([
    T.StructField("stn", T.StringType()),
    T.StructField("year", T.IntegerType()),
    T.StructField("mo", T.IntegerType()),
    T.StructField("da", T.IntegerType()),
    T.StructField("temp", T.FloatType()),
    T.StructField("temp_C", T.FloatType()),
    T.StructField("temp_K", T.FloatType()),
    T.StructField("temp_R", T.FloatType())
])

# Important for grouped operations
def convert_temp(df: pd.DataFrame) -> pd.DataFrame:
    """Converts temperature from Fahrenheit to temp_C."""
    df['temp_C'] = (df['temp'] - 32) * 5/9  # Fahrenheit to temp_C conversion
    df['temp_K'] = df['temp_C']  + 273.15
    df['temp_R'] = df['temp'] + 459.67
    # Return only the desired columns
    return df[['stn', 'year', 'mo', 'da', 'temp', 'temp_C', 'temp_K', 'temp_R']]  


gsod_FCKR = (
    gsod
    .select(F.col("stn"), F.col("year"), F.col("mo"), F.col("da"), F.col("temp"))
    .groupBy("stn", "year", "mo")
    .applyInPandas(convert_temp, schema=schema_FCKR)
    )
    
gsod_FCKR.show(3)

#########################################################################################
#
# 
# Exercise 9.3 
# Modify the following code block to use temp_C degrees instead of Fahrenheit. 
# How is the result of the UDF different if applied to the same data frame? 

schema_C_norm = T.StructType([
    T.StructField("stn", T.StringType()),
    T.StructField("year", T.IntegerType()),
    T.StructField("mo", T.IntegerType()),
    T.StructField("da", T.IntegerType()),
    T.StructField("temp_C", T.FloatType()),
    T.StructField("temp_C_norm", T.FloatType())
])

def scale_temperature_C(temp_by_day: pd.DataFrame) -> pd.DataFrame:
    """Returns a simple normalization of the temperature for a site.
 
    If the temperature is constant for the whole window, defaults to 0.5."""
    temp = temp_by_day.temp_C
    answer = temp_by_day[["stn", "year", "mo", "da", "temp_C"]]
    if temp.min() == temp.max():
        return answer.assign(temp_C_norm=0.5)
    return answer.assign(
        temp_C_norm=(temp - temp.min()) / (temp.max() - temp.min())
    )

gsod_C_norm = (
    gsod_FCKR
    .select(F.col("stn"), F.col("year"), F.col("mo"), F.col("da"), F.col("temp_C"))
    .groupBy("stn", "year", "mo")
    .applyInPandas(scale_temperature_C, schema=schema_C_norm)
    )

gsod_C_norm.show(3)

#########################################################################################
#
# 
# Exercise 9.4 
# Complete the schema of the following code block, using scale_temperature_C from the 
# previous exercise. What happens if we apply our group map UDF like so instead? 

schema_exo = T.StructType([
    T.StructField("stn", T.StringType()),
    T.StructField("year", T.IntegerType()),
    T.StructField("mo", T.IntegerType()),
    T.StructField("da", T.IntegerType()),
    T.StructField("temp", T.FloatType()),
    T.StructField("temp_norm", T.FloatType())
    ])

gsod_exo = (
        gsod_FCKR
        .groupby("year", "mo")
        .applyInPandas(scale_temperature, schema=schema_exo)
    )

#########################################################################################
#
# 
# Exercise 9.5 
# Modify the following code block to return both the intercept of the linear regression 
# as well as the slope in an ArrayType. (Hint: The intercept is in the 
# intercept_ attribute of the fitted model.) 

from sklearn.linear_model import LinearRegression
 
 
@F.pandas_udf(T.DoubleType())
def rate_of_change_temperature(day: pd.Series, temp: pd.Series) -> float:
    """Returns the slope of the daily temperature for a given period of time."""
    return (
        LinearRegression()
        .fit(X=day.astype("int").values.reshape(-1, 1), y=temp)
        .coef_[0]
    )

@F.pandas_udf(T.DoubleType())
def rate_of_change_temperature(day: pd.Series, temp: pd.Series) -> float:
    """Returns the slope of the daily temperature for a given period of time."""

    model = (
        LinearRegression()
        .fit(X=day.astype("int").values.reshape(-1, 1), y=temp)
        )
    return (
        LinearRegression()
        .fit(X=day.astype("int").values.reshape(-1, 1), y=temp)
        .coef_[0]
    )


result = gsod.groupby("stn", "year", "mo").agg(
    rate_of_change_temperature(gsod["da"], gsod["temp"]).alias(   ## 1
        "rt_chg_temp"
    )
)
result.show(5, False)
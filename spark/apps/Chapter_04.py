#########################################################################################
#
# Listing 4.1 Creating our SparkSession object to start using PySpark 

import os
from pyspark.sql import SparkSession
import pyspark.sql.functions as F

# Set Python environment variables for version compatibility
os.environ['PYSPARK_PYTHON'] = 'python3.8'
os.environ['PYSPARK_DRIVER_PYTHON'] = 'python3.8'

# Create Spark session with proper configuration
spark = SparkSession.builder \
    .appName("Chapter 04") \
    .master(os.getenv('SPARK_MASTER_URL', 'spark://Lab2.lan:32582')) \
    .getOrCreate()

print("=== Chapter 04: Data Ingestion and Schema ===")
print(f"Spark version: {spark.version}")
print(f"Spark master: {spark.sparkContext.master}")

#########################################################################################
#
# Listing 4.2 Creating a data frame out of our grocery list 

my_grocery_list = [
    ["Banana", 2, 1.74],
    ["Apple", 4, 2.04],
    ["Carrot", 1, 1.09],
    ["Cake", 1, 10.99],
]  
  
df_grocery_list = spark.createDataFrame(
    my_grocery_list, ["Item", "Quantity", "Price"]
)
 
df_grocery_list.printSchema()

#########################################################################################
#
# Listing 4.3 Reading our broadcasting information 

import os
 
DIRECTORY = "/mnt/spark/data/broadcast_logs"
logs = spark.read.csv(
    os.path.join(DIRECTORY, "BroadcastLogs_2018_Q3_M8_sample.CSV"),  
    sep="|",                                                  
    header=True,                                              
    inferSchema=True,                                         
    timestampFormat="yyyy-MM-dd",                             
)

#########################################################################################
#
# Listing 4.4 The spark.read.csv function, with every parameter explicitly laid out 

logs = spark.read.csv(
    path=os.path.join(DIRECTORY, "BroadcastLogs_2018_Q3_M8_sample.CSV"),
    sep="|",
    header=True,
    inferSchema=True,
    timestampFormat="yyyy-MM-dd",
)

#########################################################################################
#
# Listing 4.5 The schema of our logs data frame 

logs.printSchema()

#########################################################################################
#
# Exercise 4.1 Let’s take the following file, called sample.csv, which contains three columns: 

# Item,Quantity,Price
# $Banana, organic$,1,0.99
# Pear,7,1.24
# $Cake, chocolate$,1,14.50 
# Complete the following code to ingest the file successfully.

import io

csv_string ="""Item,Quantity,Price
$Banana, organic$,1,0.99
Pear,7,1.24
$Cake, chocolate$,1,14.50"""

import pyspark.sql.types as T
schema = T.StructType([
    T.StructField("Item", T.StringType(), True),
    T.StructField("Quantity", T.IntegerType(), True),
    T.StructField("Price", T.FloatType(), True)
])

# Infered schema
df = (
    spark.read
        .option("header", True)
        .option("inferSchema", True)
        .option("sep", ",")
        .option("quote", "$")
        .option("lineSep", "\n")
        .csv(spark.sparkContext.parallelize( csv_string.splitlines()))
    )
df.printSchema()
 
 # Explicity schema
df = (
spark.read
    .option("header", True)
    .option("inferSchema", True)
    .option("sep", ",")
    .option("quote", "$")
    .option("lineSep", "\n")
    .schema(schema)
    .csv(spark.sparkContext.parallelize( csv_string.splitlines()))
)
df.printSchema()


#########################################################################################
#
# Listing 4.6 Selecting five rows of the first three columns of our data frame

logs.select("BroadcastLogID", "LogServiceID", "LogDate").show(5, False)
 
# +--------------+------------+-------------------+
# |BroadcastLogID|LogServiceID|LogDate            |
# +--------------+------------+-------------------+
# |1196192316    |3157        |2018-08-01 00:00:00|
# |1196192317    |3157        |2018-08-01 00:00:00|
# |1196192318    |3157        |2018-08-01 00:00:00|
# |1196192319    |3157        |2018-08-01 00:00:00|
# |1196192320    |3157        |2018-08-01 00:00:00|
# +--------------+------------+-------------------+
# only showing top 5 rows

#########################################################################################
#
# Listing 4.7 Four ways to select columns in PySpark, all equivalent in terms of results 
# Using the string to column conversion
logs.select("BroadCastLogID", "LogServiceID", "LogDate")
logs.select(*["BroadCastLogID", "LogServiceID", "LogDate"])
 
# Passing the column object explicitly
logs.select(
    F.col("BroadCastLogID"), F.col("LogServiceID"), F.col("LogDate")
)
logs.select(
    *[F.col("BroadCastLogID"), F.col("LogServiceID"), F.col("LogDate")]
)

#########################################################################################
#
# Listing 4.8 Peeking at the data frame in chunks of three columns 

import numpy as np
 
column_split = np.array_split(
    np.array(logs.columns), 
    len(logs.columns) // 3  
)  
 
print(column_split)
 
# [array(['BroadcastLogID', 'LogServiceID', 'LogDate'], dtype='<U22'),
#  [...]
#  array(['Producer2', 'Language1', 'Language2'], dtype='<U22')]'

# Needed to add tolist to x: x.tolist()
for x in column_split:
    logs.select(*x.tolist()).show(2, False)
 
# +--------------+------------+-------------------+
# |BroadcastLogID|LogServiceID|LogDate            |
# +--------------+------------+-------------------+
# |1196192316    |3157        |2018-08-01 00:00:00|
# |1196192317    |3157        |2018-08-01 00:00:00|
# |1196192318    |3157        |2018-08-01 00:00:00|
# |1196192319    |3157        |2018-08-01 00:00:00|
# |1196192320    |3157        |2018-08-01 00:00:00|
# +--------------+------------+-------------------+
# only showing top 5 rows
# ... and more tables of three columns



#########################################################################################
#
# Listing 4.9 Getting rid of columns using the drop() method 
logsDrop = logs.drop("BroadcastLogID", "SequenceNO")
 
# Testing if we effectively got rid of the columns
print("BroadcastLogID" in logs.columns)  # => False
print("SequenceNo" in logs.columns)  # => False


#########################################################################################
#
# Listing 4.10 Getting rid of columns, select style 
logsSelectA = logs.select(
    *[x for x in logs.columns if x not in ["BroadcastLogID", "SequenceNO"]]
)
print("BroadcastLogID" in logsSelectA.columns)  # => False
print("SequenceNo" in logsSelectA.columns)  # => False

logsSelectB = logs.select(
    [x for x in logs.columns if x not in ["BroadcastLogID", "SequenceNO"]]
    )
print("BroadcastLogID" in logsSelectB.columns)  # => False
print("SequenceNo" in logsSelectB.columns)  # => False   
    

#########################################################################################
#
# Exercise 4.2 What is the printed result of this code? 

# sample_frame.columns # => ['item', 'price', 'quantity', 'UPC']

# print(sample_frame.drop('item', 'UPC', 'prices').columns) 


# a) ['item' 'UPC']
# b) ['item', 'upc'] 
# c) ['price', 'quantity']  # << Answer - prices doesn't match price
# d) ['price', 'quantity', 'UPC'] 
# e) Raises an error




#########################################################################################
#
# Listing 4.11 Selecting and displaying the Duration column

logs.select(F.col("Duration")).show(5)

# +----------------+
# |        Duration|
# +----------------+
# |02:00:00.0000000|
# |00:00:30.0000000|
# |00:00:15.0000000|
# |00:00:15.0000000|
# |00:00:15.0000000|
# +----------------+
# only showing top 5 rows
 
print(logs.select(F.col("Duration")).dtypes) 
 
# [('Duration', 'string')]




#########################################################################################
#
# Listing 4.13 Creating a duration in second field from the Duration column
logs.select(
    F.col("Duration"),
    (
        F.col("Duration").substr(1, 2).cast("int") * 60 * 60
        + F.col("Duration").substr(4, 2).cast("int") * 60
        + F.col("Duration").substr(7, 2).cast("int")
    ).alias("Duration_seconds"),
).distinct().show(5)
 
# +----------------+----------------+
# |        Duration|Duration_seconds|
# +----------------+----------------+
# |00:10:30.0000000|             630|
# |00:25:52.0000000|            1552|
# |00:28:08.0000000|            1688|
# |06:00:00.0000000|           21600|
# |00:32:08.0000000|            1928|
# +----------------+----------------+
# only showing top 5 rows



#########################################################################################
#
# Listing 4.14 Creating a new column with withColumn() 

logs = logs.withColumn(
    "Duration_seconds",
    (
        F.col("Duration").substr(1, 2).cast("int") * 60 * 60
        + F.col("Duration").substr(4, 2).cast("int") * 60
        + F.col("Duration").substr(7, 2).cast("int")
    ),
)
 
logs.printSchema()
 
# root
#  |-- LogServiceID: integer (nullable = true)
#  |-- LogDate: timestamp (nullable = true)

#########################################################################################
#
# Listing 4.15 Renaming one column at a type, the withColumnRenamed() way 
logs = logs.withColumnRenamed("Duration_seconds", "duration_seconds")
 
logs.printSchema()
# root
#  |-- LogServiceID: integer (nullable = true)
#  |-- LogDate: timestamp (nullable = true)
#  |-- AudienceTargetAgeID: integer (nullable = true)
#  |-- AudienceTargetEthnicID: integer (nullable = true)
#  [...]
#  |-- Language2: integer (nullable = true)
#  |-- duration_seconds: integer (nullable = true)



#########################################################################################
#
# Listing 4.16 Batch lowercasing using the toDF() method 

logs.toDF(*[x.lower() for x in logs.columns]).printSchema()
 
# root
#  |-- logserviceid: integer (nullable = true)
#  |-- logdate: timestamp (nullable = true)
#  |-- audiencetargetageid: integer (nullable = true)
#  |-- audiencetargetethnicid: integer (nullable = true)
#  |-- categoryid: integer (nullable = true)
#  [...]
#  |-- language2: integer (nullable = true)
#  |-- duration_seconds: integer (nullable = true)

# Rioux, Jonathan. Data Analysis with Python and PySpark (p. 172). Manning. Kindle Edition. 

#########################################################################################
#
# Listing 4.17 Selecting our columns in alphabetical order using select() 

logs.select(sorted(logs.columns)).printSchema()
 
# root
#  |-- AudienceTargetAgeID: integer (nullable = true)
#  |-- AudienceTargetEthnicID: integer (nullable = true)
#  |-- BroadcastOriginPointID: integer (nullable = true)
#  |-- CategoryID: integer (nullable = true)
#  |-- ClosedCaptionID: integer (nullable = true)
#  |-- CompositionID: integer (nullable = true)
#  [...]
#  |-- Subtitle: string (nullable = true)
#  |-- duration_seconds: integer (nullable = true)


#########################################################################################
#
# Listing 4.18 Describing everything in one fell swoop 

for i in logs.columns:
    logs.describe(i).show()
 
# +-------+------------------+   ❶
# |summary|      LogServiceID|
# +-------+------------------+
# |  count|           7169318|
# |   mean|3453.8804215407936|
# | stddev|200.44137201584468|
# |    min|              3157|
# |    max|              3925|
# +-------+------------------+
#
# [...]
#
# +-------+                      ❷
# |summary|
# +-------+
# |  count|
# |   mean|
# | stddev|
# |    min|
# |    max|
# +-------+
 
# [... many more little tables]



#########################################################################################
#
# Listing 4.19 Summarizing everything in one fell swoop 
for i in logs.columns:
    logs.select(i).summary().show()                           #  ❶
 
# +-------+------------------+
# |summary|      LogServiceID|
# +-------+------------------+
# |  count|           7169318|
# |   mean|3453.8804215407936|
# | stddev|200.44137201584468|
# |    min|              3157|
# |    25%|              3291|
# |    50%|              3384|
# |    75%|              3628|
# |    max|              3925|
# +-------+------------------+
#
# [... many more slightly larger tables]
 
for i in logs.columns:
    logs.select(i).summary("min", "10%", "90%", "max").show()
 
# +-------+------------+
# |summary|LogServiceID|
# +-------+------------+
# |    min|        3157|
# |    10%|        3237|
# |    90%|        3710|
# |    max|        3925|
# +-------+------------+
#
# [...]



#########################################################################################
#
# Exercise 4.3 
# Reread the data in a logs_raw data frame (the data file is /mnt/spark/data/broadcast_logs/BroadcastLogs_2018_Q3_M8.CSV), 
# this time without passing any optional parameters. Print the first five rows of data, as well as the schema. 
# What are the differences in terms of data and schema between logs and logs_raw? 


# only one column

DIRECTORY = "/mnt/spark/data/broadcast_logs"
logsNoParams = spark.read.csv(
    os.path.join(DIRECTORY, "BroadcastLogs_2018_Q3_M8_sample.CSV")
)
logsNoParams.printSchema()
# root
#  |-- _c0: string (nullable = true)

logsNoParams.show(2)
# 
# logsNoParams.show(2)
# +--------------------+
# |                 _c0|
# +--------------------+
# |BroadcastLogID|Lo...|
# |1196192316|3157|2...|
# +--------------------+
# only showing top 2 rows

#########################################################################################
#
# Exercise 4.4 
# Create a new data frame, logs_clean, that contains only the columns that do not end with ID.

DIRECTORY = "/mnt/spark/data/broadcast_logs"
logs = spark.read.csv(
    os.path.join(DIRECTORY, "BroadcastLogs_2018_Q3_M8_sample.CSV"),  
    sep="|",                                                  
    header=True,                                              
    inferSchema=True,                                         
    timestampFormat="yyyy-MM-dd",                             
) 

logs.select([x for x in logs.columns if not "ID" == x[-2:]]).printSchema()

# root
 # |-- LogDate: date (nullable = true)
 # |-- SequenceNO: integer (nullable = true)
 # |-- Duration: string (nullable = true)
 # |-- EndTime: string (nullable = true)
 # |-- LogEntryDate: date (nullable = true)
 # |-- ProductionNO: string (nullable = true)
 # |-- ProgramTitle: string (nullable = true)
 # |-- StartTime: string (nullable = true)
 # |-- Subtitle: string (nullable = true)
 # |-- Producer1: string (nullable = true)
 # |-- Producer2: string (nullable = true)
 # |-- Language1: integer (nullable = true)
 # |-- Language2: integer (nullable = true)
 # |-- duration_seconds: integer (nullable = true)


#########################################################################################
#


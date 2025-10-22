
#!/usr/bin/env python3
"""
Chapter 07: Data Aggregation
Spark 4.0.1 with Python 3.11
"""

import os
from pyspark.sql import SparkSession
from pyspark.sql.utils import AnalysisException     #❶
import pyspark.sql.functions as F
import pyspark.sql.types as T
from functools import reduce

# Python version controlled by PYSPARK_PYTHON environment variable (set via spark_env.sh)

# Create Spark session - configuration comes from spark-defaults.conf
spark = SparkSession.builder \
    .appName("Chapter 07: Data Aggregation") \
    .getOrCreate()

print("=== Chapter 07: Data Aggregation ===")
print(f"Spark version: {spark.version}")
print(f"Spark master: {spark.sparkContext.master}")

#########################################################################################
#
# Listing 7.1 Reading and counting the liquid elements by period 

elements = spark.read.csv(
    "/mnt/spark/data/elements/Periodic_Table_Of_Elements.csv",
    header=True,
    inferSchema=True,
)
 
elements.where(F.col("phase") == "liq").groupby("period").count().show()
# -- In SQL: We assume that the data is in a table called `elements`
 
# SELECT
#   period,
#   count(*)
# FROM elements
# WHERE phase = 'liq'
#     .config("spark.eventLog.enabled", "true") \
#     .config("spark.eventLog.dir", os.getenv('SPARK_EVENTS_DIR', '/mnt/spark/events')) \
# GROUP BY period; 

#########################################################################################
#
# Listing 7.1 Reading and counting the liquid elements by period 

elements = spark.read.csv(
    "/mnt/spark/data/elements/Periodic_Table_Of_Elements.csv",
    header=True,
    inferSchema=True,
)
 
elements.where(F.col("phase") == "liq").groupby("period").count().show()
# -- In SQL: We assume that the data is in a table called `elements`
 
# SELECT
  # period,
  # count(*)
# FROM elements
# WHERE phase = 'liq'
# GROUP BY period;


#########################################################################################
#
# Listing 7.2 Trying (and failing) at querying a data frame SQL style 
# try:
#     spark.sql(
#         "select period, count(*) from elements "
#         "where phase='liq' group by period"
#     ).show(5)
# except AnalysisException as e:
#     print(e)
 
# 'Table or view not found: elements; line 1 pos 29'

#########################################################################################
#
# Listing 7.3 Trying (and succeeding at) querying a data frame SQL style 

elements.createOrReplaceTempView("elements") #❶
 
spark.sql(
    "select period, count(*) from elements where phase='liq' group by period"
).show(5)
 
# +------+--------+
# |period|count(1)|
# +------+--------+
# |     6|       1|
# |     4|       1|
# +------+--------+                          #❷

# Rioux, Jonathan. Data Analysis with Python and PySpark (p. 305). Manning. Kindle Edition. 


#########################################################################################
#
# Listing 7.4 Using the catalog to display our registered view and then drop it 

spark.catalog                                  #❶
 
#  <pyspark.sql.catalog.Catalog at 0x117ef0c18>
 
spark.catalog.listTables()                     #❷
 
#  [Table(name='elements', database=None, description=None,
#         tableType='TEMPORARY', isTemporary=True)]
 
spark.catalog.dropTempView("elements")      #❸
spark.catalog.listTables()                  #❹
 
# []

#########################################################################################
#
# Listing 7.5 Downloading the data from Backblaze 
"""
$ pip install wget
 
$ python code/Ch07/download_backblaze_data.py full
 
# [some data download progress bars]
 
$ ls  data/backblaze         #❶
 
__MACOSX/        data_Q2_2019.zip    data_Q4_2019/
data_Q1_2019.zip    data_Q3_2019/        data_Q4_2019.zip
data_Q2_2019/        data_Q3_2019.zip    drive_stats_2019_Q1/

"""

# Rioux, Jonathan. Data Analysis with Python and PySpark (p. 309). Manning. Kindle Edition. 


#########################################################################################
#
# Listing 7.6 Reading Backblaze data into a data frame and registering a view 

DATA_DIRECTORY = "/mnt/spark/data/backblaze_data/"
 
q1 = spark.read.csv(
    # Typo in listing
    # DATA_DIRECTORY + "drive_stats_2019_Q1", header=True, inferSchema=True
    DATA_DIRECTORY + "data_Q1_2019", header=True, inferSchema=True
)
q2 = spark.read.csv(
    DATA_DIRECTORY + "data_Q2_2019", header=True, inferSchema=True
)
q1 = spark.read.csv(
    # Typo in listing
    # DATA_DIRECTORY + "drive_stats_2019_Q1", header=True, inferSchema=True
    DATA_DIRECTORY + "data_Q1_2019", header=True, inferSchema=True
)
q2 = spark.read.csv(
    DATA_DIRECTORY + "data_Q2_2019", header=True, inferSchema=True
)
q3 = spark.read.csv(
    DATA_DIRECTORY + "data_Q3_2019", header=True, inferSchema=True
)
q4 = spark.read.csv(
    DATA_DIRECTORY + "data_Q4_2019", header=True, inferSchema=True
)
 
# Q4 has two more fields than the rest
 
q4_fields_extra = set(q4.columns) - set(q1.columns)
 
for i in q4_fields_extra:
    q1 = q1.withColumn(i, F.lit(None).cast(T.StringType()))
    q2 = q2.withColumn(i, F.lit(None).cast(T.StringType()))
    q3 = q3.withColumn(i, F.lit(None).cast(T.StringType()))
 
 
# if you are only using the minimal set of data, use this version
# if you are only using the minimal set of data, use this version
backblaze_2019 = q3
 
# if you are using the full set of data, use this version
backblaze_2019 = (
    q1.select(q4.columns)
    .union(q2.select(q4.columns))
    .union(q3.select(q4.columns))
    .union(q4)
)
 
# Setting the layout for each column according to the schema
 
backblaze_2019 = backblaze_2019.select(
    [
        F.col(x).cast(T.LongType()) if x.startswith("smart") else F.col(x)
        for x in backblaze_2019.columns
    ]
)
 
backblaze_2019.createOrReplaceTempView("backblaze_stats_2019")

#########################################################################################
#
# Listing 7.7 Comparing select and where in PySpark and SQL 

spark.sql(
    "select serial_number from backblaze_stats_2019 where failure = 1"
).show(
    5
)         # ❶
  
backblaze_2019.where("failure = 1").select(F.col("serial_number")).show(5)
 
# +-------------+
# |serial_number|
# +-------------+
# |    57GGPD9NT|
# |     ZJV02GJM|
# |     ZJV03Y00|
# |     ZDEB33GK|
# |     Z302T6CW|
# +-------------+
# only showing top 5 rows


#########################################################################################
#
# Listing 7.8 Grouping and ordering in PySpark and SQL 

spark.sql(
    """SELECT
           model,
           min(capacity_bytes / pow(1024, 3)) min_GB,
           max(capacity_bytes/ pow(1024, 3)) max_GB
FROM backblaze_stats_2019
        GROUP BY 1
        ORDER BY 3 DESC"""
).show(5)
 
backblaze_2019.groupby(F.col("model")).agg(
    F.min(F.col("capacity_bytes") / F.pow(F.lit(1024), 3)).alias("min_GB"),
    F.max(F.col("capacity_bytes") / F.pow(F.lit(1024), 3)).alias("max_GB"),
).orderBy(F.col("max_GB"), ascending=False).show(5)
 
# +--------------------+--------------------+-------+
# |               model|              min_GB| max_GB|
# +--------------------+--------------------+-------+
# |       ST16000NM001G|             14902.0|14902.0|
# | TOSHIBA MG07ACA14TA|-9.31322574615478...|13039.0|
# |HGST HUH721212ALE600|             11176.0|11176.0|
# |       ST12000NM0007|-9.31322574615478...|11176.0|
# |       ST12000NM0008|             11176.0|11176.0|
# +--------------------+--------------------+-------+


#########################################################################################
#
# Listing 7.9 Using having in SQL and relying on where in PySpark 
spark.sql(
    """SELECT
           model,
           min(capacity_bytes / pow(1024, 3)) min_GB,
           max(capacity_bytes/ pow(1024, 3)) max_GB
        FROM backblaze_stats_2019
        GROUP BY 1
        HAVING min_GB != max_GB
        ORDER BY 3 DESC"""
).show(5)
 
backblaze_2019.groupby(F.col("model")).agg(
    F.min(F.col("capacity_bytes") / F.pow(F.lit(1024), 3)).alias("min_GB"),
    F.max(F.col("capacity_bytes") / F.pow(F.lit(1024), 3)).alias("max_GB"),
).where(F.col("min_GB") != F.col("max_GB")).orderBy(
    F.col("max_GB"), ascending=False
).show(
    5
)
 
# +--------------------+--------------------+-------+
# |               model|              min_GB| max_GB|
# +--------------------+--------------------+-------+
# | TOSHIBA MG07ACA14TA|-9.31322574615478...|13039.0|
# |       ST12000NM0007|-9.31322574615478...|11176.0|
# |HGST HUH721212ALN604|-9.31322574615478...|11176.0|
# |       ST10000NM0086|-9.31322574615478...| 9314.0|
# |HGST HUH721010ALE600|-9.31322574615478...| 9314.0|
# +--------------------+--------------------



#########################################################################################
#
# Listing 7.10 Creating a view in Spark SQL and in PySpark

backblaze_2019.createOrReplaceTempView("drive_stats")
 
spark.sql(
    """
    CREATE OR REPLACE TEMP VIEW drive_days AS
        SELECT model, count(*) AS drive_days
        FROM drive_stats
        GROUP BY model"""
)
drive_days_sql = spark.sql("""
    select model, drive_days
    from drive_days"""
    )
drive_days_sql.show(5)


drive_days_pyspark = backblaze_2019.groupby(F.col("model")).agg(
    F.count(F.col("*")).alias("drive_days")
)

drive_days_pyspark.show(5)

# define failures as a view
spark.sql(
    """CREATE OR REPLACE TEMP VIEW failures AS
           SELECT model, count(*) AS failures
           FROM drive_stats
           WHERE failure = 1
           GROUP BY model"""
)

# get the failures

failures_sql = spark.sql("""
    select model, failures
    from failures"""
    )
failures_sql.show(5)


failures_pyspark = (
    backblaze_2019.where(F.col("failure") == 1)
    .groupby(F.col("model"))
    .agg(F.count(F.col("*")).alias("failures"))
)
failures_pyspark.show(5)

#########################################################################################
#
# Listing 7.11 Unioning tables together in Spark SQL and in PySpark 

columns_backblaze = ", ".join(q4.columns)   #❶
  
q1.createOrReplaceTempView("Q1")            #❷
q2.createOrReplaceTempView("Q2")
q3.createOrReplaceTempView("Q3")
q4.createOrReplaceTempView("Q4")
 
spark.sql(
    """
    CREATE OR REPLACE TEMP VIEW backblaze_2019 AS
    SELECT {col} FROM Q1 UNION ALL
    SELECT {col} FROM Q2 UNION ALL
    SELECT {col} FROM Q3 UNION ALL
    SELECT {col} FROM Q4
""".format(
        col=columns_backblaze
    )
)
# check the total number of rows
spark.sql("""select count(1) total from backblaze_2019""").show()

backblaze_2019 = (                          #❸
    q1.select(q4.columns)
    .union(q2.select(q4.columns))
    .union(q3.select(q4.columns))
.union(q4)
)
# check the total number of rows
print(backblaze_2019.count())

#########################################################################################
#
# Listing 7.12 Joining tables in Spark SQL and in PySpark 
drive_days = spark.sql(
    """select
           drive_days.model,
           drive_days,
           failures
    from drive_days
    left join failures
    on
        drive_days.model = failures.model"""
)
drive_days.show(5)

# failures not define here
# drive_days.join(failures, on="model", how="left").show(5)

#########################################################################################
#
#Listing 7.13 Finding drive models with highest failure rates using subqueries 
spark.sql(
    """
    SELECT
        failures.model,
        failures / drive_days failure_rate
    FROM (
        SELECT
            model,
            count(*) AS drive_days
        FROM drive_stats
        GROUP BY model) drive_days
    INNER JOIN (
        SELECT
            model,
count(*) AS failures
        FROM drive_stats
        WHERE failure = 1
        GROUP BY model) failures
    ON
        drive_days.model = failures.model
    ORDER BY 2 desc
    """
).show(5)

#########################################################################################
#
# Listing 7.14 Finding highest failure rates using common table expressions 
spark.sql(
    """
    WITH drive_days as (             --❶
        SELECT                       --❶
            model,                   --❶
            count(*) AS drive_days   --❶
        FROM drive_stats             --❶
        GROUP BY model),             --❶
    failures as (                    --❶
        SELECT                       --❶
            model,                   --❶
            count(*) AS failures     --❶
        FROM drive_stats             --❶
        WHERE failure = 1            --❶
        GROUP BY model)              --❶
    SELECT
        failures.model,
        failures / drive_days failure_rate
    FROM drive_days
    INNER JOIN failures
    ON
        drive_days.model = failures.model
    ORDER BY 2 desc
    """
).show(5)

#########################################################################################
#
# Listing 7.15 Finding the highest failure rate using Python scope rules 
def failure_rate(drive_stats):
    drive_days = drive_stats.groupby(F.col("model")).agg(     #❶
        F.count(F.col("*")).alias("drive_days")
    )
    failures = (
        drive_stats.where(F.col("failure") == 1)
        .groupby(F.col("model"))
        .agg(F.count(F.col("*")).alias("failures"))
    )
    answer = (                                                #❷
        drive_days.join(failures, on="model", how="inner")
        .withColumn("failure_rate", F.col("failures") / F.col("drive_days"))
        .orderBy(F.col("failure_rate").desc())
    )
    return answer
 
 
failure_rate(backblaze_2019).show(5)
print("drive_days" in dir())                                  #❸

#########################################################################################
#
# Exercise 7.1 
# Taking the elements data frame, which PySpark code is equivalent to the following SQL statement? 
#
# select count(*) from elements where Radioactive is not null; 
#
# a) element.groupby("Radioactive").count().show() 
# b) elements.where(F.col("Radioactive").isNotNull()).groupby().count().show() 
# c) elements.groupby("Radioactive").where(F.col("Radioactive").isNotNull()).show() 
#    GroupBy objects does not have a where method
# d) elements.where(F.col("Radioactive").isNotNull()).count() 
#    D is the answer
# e) None of the queries above


#########################################################################################
#
# Listing 7.16 The data ingestion part of our program 

from functools import reduce
 
import pyspark.sql.functions as F
from pyspark.sql import SparkSession

# Reuse existing SparkSession (created at top of file)
# spark = SparkSession.builder.getOrCreate()  # Already created
 
# DATA_DIRECTORY = "/mnt/spark/data/backblaze/"
DATA_DIRECTORY = "/mnt/spark/data/backblaze_data/"
 
DATA_FILES = [
    # "drive_stats_2019_Q1",
    "data_Q1_2019",
    "data_Q2_2019",
    "data_Q3_2019",
    "data_Q4_2019",
]
 
data = [
    spark.read.csv(DATA_DIRECTORY + file, header=True, inferSchema=True)
    for file in DATA_FILES
]
 
common_columns = list(
    reduce(lambda x, y: x.intersection(y), [set(df.columns) for df in data])
)
 
assert set(["model", "capacity_bytes", "date", "failure"]).issubset(
    set(common_columns)
)
 
full_data = reduce(
    lambda x, y: x.select(common_columns).union(y.select(common_columns)), data
)

#########################################################################################
#
# Listing 7.17 Processing our data so it’s ready for the query function

full_data2 = full_data.selectExpr(
    "model", "capacity_bytes / pow(1024, 3) capacity_GB", "date", "failure"
)
 
drive_days = full_data2.groupby("model", "capacity_GB").agg(
    F.count("*").alias("drive_days")
)
 
failures = (
    full_data2.where("failure = 1")
    .groupby("model", "capacity_GB")
    .agg(F.count("*").alias("failures"))
)
 
summarized_data = (
    drive_days.join(failures, on=["model", "capacity_GB"], how="left")
    .fillna(0.0, ["failures"])
    .selectExpr("model", "capacity_GB", "failures / drive_days failure_rate")
    .cache()
)

#########################################################################################
#
# Listing 7.18 Replacing selectExpr() with a regular select() 

full_data4 = full_data.select(
    F.col("model"),
    (F.col("capacity_bytes") / F.pow(F.lit(1024), 3)).alias("capacity_GB"),
    F.col("date"),
    F.col("failure")
)

#########################################################################################
#
# Listing 7.19 Using a SQL expression in our failures data frame code

failures = (
    full_data4.where("failure = 1")
    .groupby("model", "capacity_GB")
    .agg(F.expr("count(*) failures"))
)

#########################################################################################
#
# Listing 7.20 The most_reliable_drive_for_capacity() function 

def most_reliable_drive_for_capacity(data, capacity_GB=2048, precision=0.25, top_n=3):
    """Returns the top 3 drives for a given approximate capacity.
 
    Given a capacity in GB and a precision as a decimal number, we keep the N
    drives where:
 
    - the capacity is between (capacity * 1/(1+precision)), capacity * (1+precision)
    - the failure rate is the lowest
 
    """
    capacity_min = capacity_GB / (1 + precision)
    capacity_max = capacity_GB * (1 + precision)
 
    answer = (
        data.where(f"capacity_GB between {capacity_min} and {capacity_max}")#❶
        .orderBy("failure_rate", "capacity_GB", ascending=[True, False])
        .limit(top_n)                                                       #❷
     )
 
    return answer
 
most_reliable_drive_for_capacity(summarized_data, capacity_GB=11176.0).show()
# +--------------------+-----------+--------------------+
# |               model|capacity_GB|        failure_rate|
# +--------------------+-----------+--------------------+
# |HGST HUH721010ALE600|     9314.0|                 0.0|
# |HGST HUH721212ALN604|    11176.0|1.088844437497695E-5|
# |HGST HUH721212ALE600|    11176.0|1.528677999266234...|
# +--------------------+-----------+--------------------+

#########################################################################################
#
# Exercise 7.2 

# If we look at the code that follows, we can simplify it even further and avoid creating 
# two tables outright. Can you write a summarized_data without having to use a table 
# other than full_data and no join? (Bonus: Try using pure PySpark, then pure Spark SQL, 
# and then a combo of both.) 

full_data72 = full_data.selectExpr(
    "model", "capacity_bytes / pow(1024, 3) capacity_GB", "date", "failure"
)
 
drive_days = full_data72.groupby("model", "capacity_GB").agg(
    F.count("*").alias("drive_days")
)
 
failures = (
    full_data72.where("failure = 1")
    .groupby("model", "capacity_GB")
    .agg(F.count("*").alias("failures"))
)

summarized_data = (
    drive_days.join(failures, on=["model", "capacity_GB"], how="left")
    .fillna(0.0, ["failures"])
    .selectExpr("model", "capacity_GB", "failures / drive_days failure_rate")
    .cache()
)

## One step, pure Spark

summarized_data_pys = (
    full_data72
    .groupby("model", "capacity_GB")
    .agg(
        F.count("*").alias("drive_days"),
        F.sum(F.col("failure")).alias("failures")
        )
    .fillna(0.0, ["failures"])
    .withColumn(
        "failure_rate", 
        F.col("failures") / F.col("drive_days")
        )
    .orderBy(F.col("failure_rate"), ascending=False)
    .cache()
)

## Single step, pure SQL

full_data72.createOrReplaceTempView("full_data72")

summarized_data_sql = spark.sql("""
    with stats as 
    (
        select model,
            capacity_GB,
            count(1) as drive_days,
            sum(failure) as failures
        from full_data72
        group by model, capacity_GB
    )
    select model,
        capacity_GB,
        failures / drive_days as failure_rate
    from stats
    order by failures / drive_days desc
    """
)


#########################################################################################
#
# Exercise 7.3 
# The analysis in the chapter is flawed in that the age of a drive is not taken into 
# consideration. Instead of ordering the model by failure rate, order by average age 
# at failure (assume that every drive fails on the maximum date reported if they are 
# still alive). (Hint: Remember that you need to count the age of each drive first.)

# sub exercise to enforce consistence on dates. Most are in the yyyy-MM-dd format. 
# about 100K are in the M/d/yy format.

full_data_date = (
    full_data
    .withColumn(
        "date_date",
        F.when(F.to_date(F.col("date"), "yyyy-MM-dd").isNotNull(), 
            F.to_date(F.col("date"), "yyyy-MM-dd"))
        .when(F.to_date(F.col("date"), "M/d/yy").isNotNull(),
            F.to_date(F.col("date"), "M/d/yy"))
        .otherwise(None)
        )
    .groupBy("model", "serial_number")
    .agg(
        F.min(F.col("date_date")).alias("min_day"),
        F.max(F.col("date_date")).alias("max_day"),
        F.count("*").alias("Days"),
        F.sum(F.col("failure")).alias("failures")
    ).withColumn("duration", F.date_diff(F.col("max_day"), F.col("min_day")))
    .select(
        F.col("serial_number"),
        F.col("min_day"),
        F.col("max_day"),
        F.col("duration"),
        F.col("failures"),
        F.col("days")  
    )
)
# find bad dates
dates = (
    full_data
    .withColumn(
        "date_date",
        F.when(F.to_date(F.col("date"), "yyyy-MM-dd").isNotNull(), 
            F.to_date(F.col("date"), "yyyy-MM-dd"))
        .when(F.to_date(F.col("date"), "M/d/yy").isNotNull(),
            F.to_date(F.col("date"), "M/d/yy"))
        .otherwise(None)
        )
    .groupBy(F.col("date_date"), F.col("date"))
    .agg(F.count("*"))
    .orderBy(F.col("date_date"))
)

# Answer to exercise
# We filter out non-failed drives.
# since data only spans a year out of potentially serveral, 
# the average MTBF is not accurate
average_days_to_failure = (
    full_data
    .select(F.col("model"), F.col("serial_number"), F.col("failure"))
    .groupby("model", "serial_number")
    .agg(
        F.count("*").alias("drive_days"),
        F.sum(F.col("failure")).alias("failed")
        )
    .fillna(0.0, ["failed"])
    .where(F.col("failed") > 0)
    .groupBy("model")
    .agg(F.avg(F.col("drive_days")).alias("days_to_failure"))
    .orderBy(F.col("days_to_failure"), ascending=True)
    .withColumn("days_to_failure", F.format_number(F.col("days_to_failure"), 1))
)

#########################################################################################
#
# Exercise 7.4 
# What is the total capacity (in TB) that Backblaze records at the beginning of each month?

capacity = (
    full_data
    .withColumn(
        "date_date",
        F.when(F.to_date(F.col("date"), "yyyy-MM-dd").isNotNull(), 
            F.to_date(F.col("date"), "yyyy-MM-dd"))
        .when(F.to_date(F.col("date"), "M/d/yy").isNotNull(),
            F.to_date(F.col("date"), "M/d/yy"))
        .otherwise(None)
        )
    .groupBy(
        F.col("model"), 
        F.col("serial_number"),
        F.year(F.col("date_date")).alias("year"),
        F.month(F.col("date_date")).alias("month")
    ).agg(F.max(F.col("capacity_bytes")).alias("capacity"))
    .groupBy(F.col("year"), F.col("month"))
    .agg(F.sum(F.col("capacity")).alias("capacity"))
    .orderBy(F.col("year"), F.col("month"))    
)
        
#########################################################################################
#
# Exercise 7.5 

# Note There is a much more elegant way to solve this problem that we see in chapter 10 
# using window functions. In the meantime, this exercise can be solved with the judicious 
# usage of group bys and joins. If you look at the data, you’ll see that some drive models 
# can report an erroneous capacity. In the data preparation stage, restage the full_data 
# data frame so that the most common capacity for each drive is used.

sizes = (
    full_data
    .groupBy(F.col("capacity_bytes"))
    .agg(F.count("*").alias("count"))
    .orderBy(F.col("capacity_bytes"))      
)
sizes.show(20)
divisor = 2**30
clean_data = (
    full_data
    .select(
        F.col("model"),
        F.col("date"),
        F.col("failure"),
        F.col("serial_number"),
        F.col("capacity_bytes")
    ).withColumn(
        "date",
        F.when(F.to_date(F.col("date"), "yyyy-MM-dd").isNotNull(), 
            F.to_date(F.col("date"), "yyyy-MM-dd"))
        .when(F.to_date(F.col("date"), "M/d/yy").isNotNull(),
            F.to_date(F.col("date"), "M/d/yy"))
        .otherwise(None)
    ).where(~ ( F.col("capacity_bytes") < 0))
    .withColumn(
        "capacity_gb", 
        F.floor((F.col("capacity_bytes").cast("long")) 
            / F.lit(2**30).cast("long")))
   .drop("capacity_bytes")
)

#########################################################################################
#



#########################################################################################
#




import os
import datetime
from pyspark.sql import SparkSession
import pyspark.sql.functions as F
import pyspark.sql.types as T
from pyspark.sql.utils import AnalysisException

# Set Python environment variables for version compatibility
os.environ['PYSPARK_PYTHON'] = 'python3.8'
os.environ['PYSPARK_DRIVER_PYTHON'] = 'python3.8'

# Set Spark local IP to avoid hostname resolution warning
os.environ['SPARK_LOCAL_IP'] = '192.168.1.48'

# Setup
DIRECTORY = "/mnt/spark/data/broadcast_logs"
spark = SparkSession.builder \
    .appName("Chapter 05: Data Processing") \
    .master(os.getenv('SPARK_MASTER_URL', 'spark://Lab2.lan:32582')) \
    .config("spark.eventLog.enabled", "true") \
    .config("spark.eventLog.dir", os.getenv('SPARK_EVENTS_DIR', '/mnt/spark/events')) \
    .getOrCreate()

print("=== Chapter 05: Data Processing ===")
print(f"Spark version: {spark.version}")
print(f"Spark master: {spark.sparkContext.master}")
spark.sparkContext.setLogLevel("WARN")

logs = spark.read.csv(
    os.path.join(DIRECTORY, "BroadcastLogs_2018_Q3_M8_sample.CSV"),  
    sep="|",                                                  
    header=True,                                              
    inferSchema=True,                                         
    timestampFormat="yyyy-MM-dd",                             
) 

logs = logs.withColumn(
        "duration_seconds",
        (
            F.col("Duration").substr(1, 2).cast("int") * 60 * 60
            + F.col("Duration").substr(4, 2).cast("int") * 60
            + F.col("Duration").substr(7, 2).cast("int")
        ),
    )
    
#########################################################################################
#
# Listing 5.1 Exploring our first link table: log_identifier 

DIRECTORY = "/mnt/spark/data/broadcast_logs"
log_identifier = spark.read.csv(
    os.path.join(DIRECTORY, "ReferenceTables/LogIdentifier.csv"),
    sep="|",
    header=True,
    inferSchema=True,
)
 
log_identifier.printSchema()
# root
#  |-- LogIdentifierID: string (nullable = true)              ❶
#  |-- LogServiceID: integer (nullable = true)                ❷
#  |-- PrimaryFG: integer (nullable = true)                   ❸
 
log_identifier = log_identifier.where(F.col("PrimaryFG") == 1)
print(log_identifier.count())
# 758
 
log_identifier.show(5)
# +---------------+------------+---------+
# |LogIdentifierID|LogServiceID|PrimaryFG|
# +---------------+------------+---------+
# |           13ST|        3157|        1|
# |         2000SM|        3466|        1|
# |           70SM|        3883|        1|
# |           80SM|        3590|        1|
# |           90SM|        3470|        1|
# +---------------+------------+---------+
# only showing top 5 rows

#########################################################################################
#
# Listing 5.2 A bare-bone recipe for a join in PySpark 
# [LEFT].join(
    # [RIGHT],
    # on=[PREDICATES]
    # how=[METHOD]
# )


#########################################################################################
#
# Listing 5.3 A bare-bone join in PySpark, with left and right tables filled in 

# logs.join(            ❶
    # log_identifier,   ❷
    # on=[PREDICATES]
    # how=[METHOD]
# )



#########################################################################################
#
# Listing 5.4 A join in PySpark, with left and right tables and predicate 
# logs.join(
    # log_identifier,
    # on="LogServiceID"
    # how=[METHOD]
# )


#########################################################################################
#
# Listing 5.5 Our join in PySpark, with all the parameters filled in 
logs_and_channels = logs.join(
    log_identifier,
    on="LogServiceID",
    how="inner"         
)


#########################################################################################
#
# Listing 5.6 A join that generates two seemingly identically named columns 

from pyspark.sql.utils import AnalysisException   

logs_and_channels_verbose = logs.join(
    log_identifier, logs["LogServiceID"] == log_identifier["LogServiceID"]
)
# with the join, you get the join column twice.

logs_and_channels_verbose.printSchema()
 
# root
#  |-- LogServiceID: integer (nullable = true)              # < First occurance ❶
#  |-- LogDate: timestamp (nullable = true)
#  |-- AudienceTargetAgeID: integer (nullable = true)
#  |-- AudienceTargetEthnicID: integer (nullable = true)
#  [...]
#  |-- duration_seconds: integer (nullable = true)
#  |-- LogIdentifierID: string (nullable = true)
#  |-- LogServiceID: integer (nullable = true)              # < Second occurance
#  |-- PrimaryFG: integer (nullable = true)
 
try:
    logs_and_channels_verbose.select("LogServiceID")
except AnalysisException as err:
    print(err)


#########################################################################################
#
# Listing 5.7 Using the simplified syntax for equi-joins 

logs_and_channels = logs.join(log_identifier, "LogServiceID")
 
logs_and_channels.printSchema()
 
# root
#  |-- LogServiceID: integer (nullable = true)
#  |-- LogDate: timestamp (nullable = true)
#  |-- AudienceTargetAgeID: integer (nullable = true)
#  |-- AudienceTargetEthnicID: integer (nullable = true)
#  |-- CategoryID: integer (nullable = true)
#  [...]
#  |-- Language2: integer (nullable = true)
#  |-- duration_seconds: integer (nullable = true)
#  |-- LogIdentifierID: string (nullable = true)    # ❶ Only one copy kepts
#  |-- PrimaryFG: integer (nullable = true)




#########################################################################################
#
# Listing 5.8 Using the origin name of the column for unambiguous selection 

logs_and_channels_verbose = logs.join(
    log_identifier, logs["LogServiceID"] == log_identifier["LogServiceID"]
)
 
logs_and_channels.drop(log_identifier["LogServiceID"]).select(
    "LogServiceID")           
 
# DataFrame[LogServiceID: int]


#########################################################################################
#
# Listing 5.9 Aliasing our tables to resolve the origin l

logs_and_channels_verbose = logs.alias("left").join(        
    log_identifier.alias("right"),                          
    logs["LogServiceID"] == log_identifier["LogServiceID"],
)
 
logs_and_channels_verbose.drop(F.col("right.LogServiceID")).select(
    "LogServiceID"
)                                                           
 
# DataFrame[LogServiceID: int]

#########################################################################################
#
# Listing 5.10 Linking the category and program class tables using two left joins
DIRECTORY = "/mnt/spark/data/broadcast_logs"
 
cd_category = spark.read.csv(
    os.path.join(DIRECTORY, "ReferenceTables/CD_Category.csv"),
    sep="|",
    header=True,
    inferSchema=True,
).select(
    "CategoryID",
    "CategoryCD",
    F.col("EnglishDescription").alias("Category_Description"),     # ❶
)

cd_program_class = spark.read.csv(
    os.path.join(DIRECTORY, "ReferenceTables/CD_ProgramClass.csv"),
    sep="|",
    header=True,
    inferSchema=True,
).select(
    "ProgramClassID",
    "ProgramClassCD",
    F.col("EnglishDescription").alias("ProgramClass_Description"),  #❷
)
 
full_log = logs_and_channels.join(cd_category, "CategoryID", how="left").join(
    cd_program_class, "ProgramClassID", how="left"
)

#########################################################################################
#
# Exercise 5.1 
#
# Assume two tables, left and right, each containing a column named my_column. 
# What is the result of this code? one = left.join(right, how="left_semi", on="my_column")
# two = left.join(right, how="left_anti", on="my_column")
#
# one.union(two)

# from pyspark.sql import SparkSession

# Sample DataFrames
left_data = [
    (1, "Alice"),
    (2, "Bob"),
    (3, "Charlie"),
    (4, "David")
]
left_df = spark.createDataFrame(left_data, ["id", "name"])

right_data = [
    (2, "New York"),
    (3, "London"),
    (5, "Paris")
]
right_df = spark.createDataFrame(right_data, ["id", "city"])

one = left_df.join(right_df,how="left_semi", on="id")
two = left_df.join(right_df, how="left_anti", on="id")
one.union(two).show()

# You get back to the original full table of the left df.

# Perform a LEFT ANTI JOIN
result_df = left_df.join(right_df, "id", "left_anti")

result_df.show()

# SQL equivalent
left_df.createOrReplaceTempView("left_table")
right_df.createOrReplaceTempView("right_table")

spark.sql("SELECT l.* FROM left_table l LEFT ANTI JOIN right_table r ON l.id = r.id").show()

# spark.stop()

#########################################################################################
#
# Exercise 5.2 

# Assume two data frames, red and blue. Which is the appropriate join to use in red.join(blue, ...) 
# if you want to join red and blue and keep all the records satisfying the predicate? 
    # a) Left 
    # b) Right 
    # c) Inner 
    # d) Theta 
    # e) Cross

# Inner if the predicate is equality otherwise theta

#########################################################################################
#
# Exercise 5.3 

# Assume two data frames, red and blue. 
# Which is the appropriate join to use in red.join(blue, ...) 
# if you want to join red and blue 
# and keep all the records satisfying the predicate and the records in the blue table?
    # a) Left 
    # b) Right 
    # c) Inner 
    # d) Theta 
    # e) Cross

# Inner if the predicate is equality otherwise theta

# right join as presumeably Blue is the second (rightmost) table

#########################################################################################
#
# Listing 5.11 Displaying the most popular types of programs 
# Add back in duration_seconds from Chapter 4
   
(full_log
 .groupby("ProgramClassCD", "ProgramClass_Description")
 .agg(F.sum("Duration_seconds").alias("duration_total"))
 .orderBy("duration_total", ascending=False).show(100, False)
 )
 
# +--------------+--------------------------------------+--------------+
# |ProgramClassCD|ProgramClass_Description              |duration_total|
# +--------------+--------------------------------------+--------------+
# |PGR           |PROGRAM                               |652802250     |
# |COM           |COMMERCIAL MESSAGE                    |106810189     |

#########################################################################################
#
# Listing 5.12 A GroupedData object representation 
full_log.groupby()
# <pyspark.sql.group.GroupedData at 0x119baa4e0>


#########################################################################################
#
# Listing 5.13 Computing only the commercial time for each program in our table 
F.when(
    F.trim(F.col("ProgramClassCD")).isin(
        ["COM", "PRC", "PGI", "PRO", "PSA", "MAG", "LOC", "SPO", "MER", "SOL"]
    ),
    F.col("duration_seconds"),
).otherwise(0)

#########################################################################################
#
# Listing 5.14 Using our new column into agg() to compute our final answer 

answer = (
    full_log
    .groupby("LogIdentifierID")
    .agg(
        F.sum(                                                              #❶
            F.when(                                                         #❶
                F.trim(F.col("ProgramClassCD")).isin(                       #❶
                    ["COM", "PRC", "PGI", "PRO", "LOC", "SPO", "MER", "SOL"]#❶
                ),                                                          #❶
                F.col("duration_seconds")                                  #❶
            ).otherwise(0)                                                  #❶
        ).alias("duration_commercial"),                                     #❶
        F.sum("duration_seconds").alias("duration_total"),
    )
    .withColumn(
        "commercial_ratio", F.col(
            "duration_commercial") / F.col("duration_total")
    )
)
 
answer.orderBy("commercial_ratio", ascending=False).show(1000, False)
 
# +---------------+-------------------+--------------+---------------------+
# |LogIdentifierID|duration_commercial|duration_total|commercial_ratio     |
# +---------------+-------------------+--------------+---------------------+
# |HPITV          |403                |403           |1.0                  |
# |TLNSP          |234455             |234455        |1.0                  |
# |MSET           |101670             |101670        |1.0                  |
# |TELENO         |545255             |545255        |1.0                  |
# |CIMT           |19935              |19935         |1.0                  |
# |TANG           |271468             |271468        |1.0                  |
# |INVST          |623057             |633659        |0.9832686034602207   |
# [...]
# |OTN3           |0                  |2678400       |0.0                  |
# |PENT           |0                  |2678400       |0.0                  |
# |ATN14          |0                  |2678400       |0.0                  |
# |ATN11          |0                  |2678400       |0.0                  |
# |ZOOM           |0                  |2678400       |0.0                  |
# |EURO           |0                  |null          |null                 |
# |NINOS          |0                  |null          |null                 |
# +---------------+-------------------+--------------+---------------------+

#########################################################################################
#
# Listing 5.15 Dropping only the records that have a null commercial_ratio value 

answer_no_null = answer.dropna(subset=["commercial_ratio"])
 
answer_no_null.orderBy(
    "commercial_ratio", ascending=False).show(1000, False)
 
# +---------------+-------------------+--------------+---------------------+
# |LogIdentifierID|duration_commercial|duration_total|commercial_ratio     |
# +---------------+-------------------+--------------+---------------------+
# |HPITV          |403                |403           |1.0                  |
# |TLNSP          |234455             |234455        |1.0                  |
# |MSET           |101670             |101670        |1.0                  |
# |TELENO         |545255             |545255        |1.0                  |
# |CIMT           |19935              |19935         |1.0                  |
# |TANG           |271468             |271468        |1.0                  |
# |INVST          |623057             |633659        |0.9832686034602207   |
# [...]
# |OTN3           |0                  |2678400       |0.0                  |
# |PENT           |0                  |2678400       |0.0                  |
# |ATN14          |0                  |2678400       |0.0                  |
# |ATN11          |0                  |2678400       |0.0                  |
# |ZOOM           |0                  |2678400       |0.0                  |
# +---------------+-------------------+--------------+---------------------+
 
print(answer_no_null.count())  # 322

# I get 444 rows

#########################################################################################
#

# Listing 5.16 Filling our numerical records with zero using the fillna() method 

answer_no_null = answer.fillna(0)
 
answer_no_null.orderBy(
    "commercial_ratio", ascending=False).show(1000, False)
 
# +---------------+-------------------+--------------+---------------------+
# |LogIdentifierID|duration_commercial|duration_total|commercial_ratio     |
# +---------------+-------------------+--------------+---------------------+
# |HPITV          |403                |403           |1.0                  |
# |TLNSP          |234455             |234455        |1.0                  |
# |MSET           |101670             |101670        |1.0                  |
# |TELENO         |545255             |545255        |1.0                  |
# |CIMT           |19935              |19935         |1.0                  |
# |TANG           |271468             |271468        |1.0                  |
# |INVST          |623057             |633659        |0.9832686034602207   |
# [...]
# |OTN3           |0                  |2678400       |0.0                  |
# |PENT           |0                  |2678400       |0.0                  |
# |ATN14          |0                  |2678400       |0.0                  |
# |ATN11          |0                  |2678400       |0.0                  |
# |ZOOM           |0                  |2678400       |0.0                  |
# +---------------+-------------------+--------------+---------------------+
 
print(answer_no_null.count())  # 324     # ❶

# I get 446

#########################################################################################
#
# Listing 5.17 Our full program, ordering channels by decreasing proportion of commercials 

# import os
 
# import pyspark.sql.functions as F
# from pyspark.sql import SparkSession
 
# spark = SparkSession.builder.appName(
#     "Getting the Canadian TV channels with the highest/lowest proportion of commercials."
    .config("spark.eventLog.enabled", "true") \
    .config("spark.eventLog.dir", os.getenv('SPARK_EVENTS_DIR', '/mnt/spark/events')) \
# ).getOrCreate()
 
# spark.sparkContext.setLogLevel("WARN")
 
# Reading all the relevant data sources
 
DIRECTORY = "/mnt/spark/data/broadcast_logs"

logs = spark.read.csv(
    # Me: Updated filename
    os.path.join(DIRECTORY, "BroadcastLogs_2018_Q3_M8_sample.CSV"),
    sep="|",
    header=True,
    inferSchema=True
)
 
log_identifier = spark.read.csv(
    os.path.join(DIRECTORY, "ReferenceTables/LogIdentifier.csv"),
    sep="|",
    header=True,
    inferSchema=True,
)
cd_category = spark.read.csv(
    os.path.join(DIRECTORY, "ReferenceTables/CD_Category.csv"),
    sep="|",
    header=True,
    inferSchema=True,
).select("CategoryID",
    "CategoryCD",
    F.col("EnglishDescription").alias("Category_Description"),
)
 
cd_program_class = spark.read.csv(
    "/mnt/spark/data/broadcast_logs/ReferenceTables/CD_ProgramClass.csv",
    sep="|",
    header=True,
    inferSchema=True,
).select(
    "ProgramClassID",
    "ProgramClassCD",
    F.col("EnglishDescription").alias("ProgramClass_Description"),
)
 
# Data processing
 
logs = logs.drop("BroadcastLogID", "SequenceNO")

# Somehow, Spark started inferings HH:MM:SS is a timestamp and start converting
# these durations to a timestamp with the current date.
# the current date. 
# logs = logs.withColumn(
        # "duration_seconds",
        # (
            # F.col("Duration").substr(1, 2).cast("int") * 60 * 60
            # + F.col("Duration").substr(4, 2).cast("int") * 60
            # + F.col("Duration").substr(7, 2).cast("int")
        # ),
    # )
    
# We work around the issue by ignoring and skipping over the date.
logs = logs.withColumn(
        "duration_seconds",
        (
            F.col("Duration").cast("string").substr(12, 2).cast("int") * 60 * 60
            + F.col("Duration").cast("string").substr(15, 2).cast("int") * 60
            + F.col("Duration").cast("string").substr(18, 2).cast("int")
        ),
    )

# logs.select(
    # F.col("Duration"),                                                #❶
    # F.col("Duration").substr(1, 2).cast("int").alias("dur_hours"),    #❷
    # F.col("Duration").substr(4, 2).cast("int").alias("dur_minutes"),  #❸
    # F.col("Duration").substr(7, 2).cast("int").alias("dur_seconds"),  #❹
# ).distinct().show(5)
 

logs.select(
    F.col("Duration"),                                               
    (F.col("Duration").cast("string").substr(12, 2).cast("int") * 60 * 60).alias("dur_hours"),  
    (F.col("Duration").cast("string").substr(15, 2).cast("int") * 60).alias("dur_minutes"),
    F.col("Duration").cast("string").substr(18, 2).cast("int").alias("dur_seconds"),
    (
        F.col("Duration").cast("string").substr(13, 2).cast("int") * 60 * 60
        + F.col("Duration").cast("string").substr(16, 2).cast("int") * 60
        + F.col("Duration").cast("string").substr(19, 2).cast("int")
    ).alias("duration"),
).show(5)

logs.select(
    F.col("Duration"),                                               
    (F.col("Duration").cast("string").substr(12, 2).cast("int") * 60 * 60).alias("dur_hours"),  
    (F.col("Duration").cast("string").substr(15, 2).cast("int") * 60).alias("dur_minutes"),
    F.col("Duration").cast("string").substr(18, 2).cast("int").alias("dur_seconds")
    ).withColumn(
        "duration",
        (
            F.col("dur_hours") * 60 * 60
            + F.col("dur_minutes") * 60
            + F.col("dur_seconds")
        )
    ).show(5)
 
logs.select(
    F.col("Duration"),                                               
    (F.col("Duration").cast("string").substr(12, 2).cast("int") * 60 * 60).alias("dur_hours"),  
    (F.col("Duration").cast("string").substr(15, 2).cast("int") * 60).alias("dur_minutes"),
    F.col("Duration").cast("string").substr(18, 2).cast("int").alias("dur_seconds")
    ).withColumn(
        "duration",
        (
            F.col("Duration").cast("string").substr(12, 2).cast("int") * 60 * 60
            + F.col("Duration").cast("string").substr(15, 2).cast("int") * 60
            + F.col("Duration").cast("string").substr(18, 2).cast("int")
        )
    ).show(5) 
    
logs.select(
    F.col("LogServiceID"),
    F.col("CategoryID"),
    F.col("ProgramClassID"),
    F.col("Duration"),
    F.col("duration_seconds")
).show(10) 


log_identifier = log_identifier.where(F.col("PrimaryFG") == 1)
 
logs_and_channels = logs.join(log_identifier, "LogServiceID")
 
full_log = logs_and_channels.join(cd_category, "CategoryID", how="left").join(
    cd_program_class, "ProgramClassID", how="left"
)

full_log.select(
        F.col("LogIdentifierID"),
        F.col("ProgramClassCD"),
        F.col("duration_seconds")
    ).show(20)

answer = (
    full_log.groupby("LogIdentifierID")
    .agg(
        F.sum(
            F.when(
                F.trim(F.col("ProgramClassCD")).isin(
                    ["COM", "PRC", "PGI", "PRO", "LOC", "SPO", "MER", "SOL"]
                ),
                F.col("duration_seconds"),
            ).otherwise(0)
).alias("duration_commercial"),
        F.sum("duration_seconds").alias("duration_total"),
    )
    .withColumn(
        "commercial_ratio", F.col("duration_commercial") / F.col("duration_total")
    )
    .fillna(0)
)

(
    answer
    .orderBy("commercial_ratio", ascending=False)
    .show(50, False)
)

#########################################################################################
#
# Listing 5.15 Dropping only the records that have a null commercial_ratio value 
answer_no_null = answer.dropna(subset=["commercial_ratio"])
 
answer_no_null.orderBy(
    "commercial_ratio", ascending=False).show(1000, False)
 
# +---------------+-------------------+--------------+---------------------+
# |LogIdentifierID|duration_commercial|duration_total|commercial_ratio     |
# +---------------+-------------------+--------------+---------------------+
# |HPITV          |403                |403           |1.0                  |
# |TLNSP          |234455             |234455        |1.0                  |
# |MSET           |101670             |101670        |1.0                  |
# |TELENO         |545255             |545255        |1.0                  |
# |CIMT           |19935              |19935         |1.0                  |
# |TANG           |271468             |271468        |1.0                  |
# |INVST          |623057             |633659        |0.9832686034602207   |
# [...]
# |OTN3           |0                  |2678400       |0.0                  |
# |PENT           |0                  |2678400       |0.0                  |
# |ATN14          |0                  |2678400       |0.0                  |
# |ATN11          |0                  |2678400       |0.0                  |
# |ZOOM           |0                  |2678400       |0.0                  |
# +---------------+-------------------+--------------+---------------------+

#########################################################################################
#
# Listing 5.16 Filling our numerical records with zero using the fillna() method 

answer_no_null = answer.fillna(0)
 
answer_no_null.orderBy(
    "commercial_ratio", ascending=False).show(1000, False)
 
# +---------------+-------------------+--------------+---------------------+
# |LogIdentifierID|duration_commercial|duration_total|commercial_ratio     |
# +---------------+-------------------+--------------+---------------------+
# |HPITV          |403                |403           |1.0                  |
# |TLNSP          |234455             |234455        |1.0                  |
# |MSET           |101670             |101670        |1.0                  |
# |TELENO         |545255             |545255        |1.0                  |
# |CIMT           |19935              |19935         |1.0                  |
# |TANG           |271468             |271468        |1.0                  |
# |INVST          |623057             |633659        |0.9832686034602207   |
# [...]
# |OTN3           |0                  |2678400       |0.0                  |
# |PENT           |0                  |2678400       |0.0                  |
# |ATN14          |0                  |2678400       |0.0                  |
# |ATN11          |0                  |2678400       |0.0                  |
# |ZOOM           |0                  |2678400       |0.0                  |
# +---------------+-------------------+--------------+---------------------+
 
print(answer_no_null.count())  # 324

#########################################################################################
#
# Listing 5.17 Our full program, ordering channels by decreasing proportion of commercials
# import os
 
# import pyspark.sql.functions as F
# from pyspark.sql import SparkSession
 
# spark = SparkSession.builder.appName(
#     "Getting the Canadian TV channels with the highest/lowest proportion of commercials."
    .config("spark.eventLog.enabled", "true") \
    .config("spark.eventLog.dir", os.getenv('SPARK_EVENTS_DIR', '/mnt/spark/events')) \
# ).getOrCreate()
 
# spark.sparkContext.setLogLevel("WARN")
 
# Reading all the relevant data sources
 
DIRECTORY = "/mnt/spark/data/broadcast_logs"
 
logs = spark.read.csv(
    # os.path.join(DIRECTORY, "BroadcastLogs_2018_Q3_M8.CSV"),
    os.path.join(DIRECTORY, "BroadcastLogs_2018_Q3_M8_sample.CSV"),
    sep="|",
    header=True,
    inferSchema=True,
)
 
log_identifier = spark.read.csv(
    os.path.join(DIRECTORY, "ReferenceTables/LogIdentifier.csv"),
    sep="|",
    header=True,
    inferSchema=True,
)
cd_category = spark.read.csv(
    os.path.join(DIRECTORY, "ReferenceTables/CD_Category.csv"),
    sep="|",
    header=True,
    inferSchema=True,
).select(
"CategoryID",
    "CategoryCD",
    F.col("EnglishDescription").alias("Category_Description"),
)
 
cd_program_class = spark.read.csv(
    "/mnt/spark/data/broadcast_logs/ReferenceTables/CD_ProgramClass.csv",
    sep="|",
    header=True,
    inferSchema=True,
).select(
    "ProgramClassID",
    "ProgramClassCD",
    F.col("EnglishDescription").alias("ProgramClass_Description"),
)
 
# Data processing
 
logs = logs.drop("BroadcastLogID", "SequenceNO")
 
# logs = logs.withColumn(
    # "duration_seconds",
    # (
        # F.col("Duration").substr(1, 2).cast("int") * 60 * 60
        # + F.col("Duration").substr(4, 2).cast("int") * 60
        # + F.col("Duration").substr(7, 2).cast("int")
    # ),
# )
logs = logs.withColumn(
        "duration_seconds",
        (
            F.col("Duration").cast("string").substr(12, 2).cast("int") * 60 * 60
            + F.col("Duration").cast("string").substr(15, 2).cast("int") * 60
            + F.col("Duration").cast("string").substr(18, 2).cast("int")
        ),
    ) 
log_identifier = log_identifier.where(F.col("PrimaryFG") == 1)
 
logs_and_channels = logs.join(log_identifier, "LogServiceID")
 
full_log = logs_and_channels.join(cd_category, "CategoryID", how="left").join(
    cd_program_class, "ProgramClassID", how="left"
)
 
answer = (
    full_log.groupby("LogIdentifierID")
    .agg(
        F.sum(
            F.when(
                F.trim(F.col("ProgramClassCD")).isin(
                    ["COM", "PRC", "PGI", "PRO", "LOC", "SPO", "MER", "SOL"]
                ),
                F.col("duration_seconds"),
            ).otherwise(0)
).alias("duration_commercial"),
        F.sum("duration_seconds").alias("duration_total"),
    )
    .withColumn(
        "commercial_ratio", F.col("duration_commercial") / F.col("duration_total")
    )
    .fillna(0)
)
 
answer.orderBy("commercial_ratio", ascending=False).show(1000, False)


#########################################################################################
#
# Exercise 5.4 Write PySpark code that will return the result of the following 
# code block without using a left anti-join:

# left.join(right, how="left_anti", on="my_column").select("my_column").distinct()

# left.subract(left.join(right, how="left", on="my_column", )).select("my_column").distinct()

#########################################################################################
#
# Exercise 5.5 Using the data from the data/broadcast_logs/Call_Signs.csv 
# (careful: the delimiter here is the comma, not the pipe!), 
# add the Undertaking_Name to our final table to display a human-readable description of the channel.

call_sign = spark.read.csv(
    "/mnt/spark/data/broadcast_logs/Call_Signs.csv",
    sep=",",
    header=True,
    inferSchema=True,
)

full_log_call_sign = full_log.join(
    call_sign,
    on = "LogIdentifierID",
    how = "left"
)

answer_call_sign = (
    full_log_call_sign.groupby("LogIdentifierID", "Undertaking_Name")
    .agg(
        F.sum(
            F.when(
                F.trim(F.col("ProgramClassCD")).isin(
                    ["COM", "PRC", "PGI", "LOC", "SPO", "MER", "SOL"]
                ),
                F.col("duration_seconds"),
            ).when(
                 F.trim(F.col("ProgramClassCD")) == "PRO",
                 F.col("duration_seconds") * 0.75
            ).otherwise(0)
        ).alias("duration_commercial"),
        F.sum("duration_seconds").alias("duration_total")
    )
    .withColumn(
        "commercial_ratio", F.col("duration_commercial") / F.col("duration_total")
    )
    .fillna(0)
)

#########################################################################################
#
# Exercise 5.6 

# The government of Canada is asking for your analysis, but they’d like 
# the PRC to be weighted differently. They’d like each PRC second to be considered 
# 0.75 commercial seconds. Modify the program to account for this change.

answer_call_sign_PRO = (
    full_log_call_sign.groupby("LogIdentifierID", "Undertaking_Name")
    .agg(
        F.sum(
            F.when(
                F.trim(F.col("ProgramClassCD")).isin(
                    ["COM", "PRC", "PGI", "LOC", "SPO", "MER", "SOL"]
                ),
                F.col("duration_seconds"),
            ).when(
                 F.trim(F.col("ProgramClassCD")) == "PRO",
                 F.col("duration_seconds") * 0.75
            ).otherwise(0)
        ).alias("duration_commercial"),
        F.sum("duration_seconds").alias("duration_total"),
    )
    .withColumn(
        "commercial_ratio", F.col("duration_commercial") / F.col("duration_total")
    )
    .fillna(0)
    )   


#########################################################################################
#
# Exercise 5.7 

# On the data frame returned from commercials.py, return the number of channels in each bucket
# based on their commercial_ratio. (Hint: look at the documentation for round on how to round a value.) commercial_ratio number_of_channels 

exec(open("code/Ch05/commercials.py").read())

# 1.0 0.9 0.8 ... 0.1 0.0


commercial_ratio = full_log.groupby("LogIdentifierID").agg(
    F.sum(
        F.when(
            F.trim(F.col("ProgramClassCD")).isin(
                ["COM", "PRC", "PGI", "PRO", "LOC", "SPO", "MER", "SOL"]
            ),
            F.col("duration_seconds"),
        ).otherwise(0)
    ).alias("duration_commercial"),
    F.sum("duration_seconds").alias("duration_total"),
).withColumn(
    "commercial_ratio", F.col("duration_commercial") / F.col("duration_total")
).orderBy(
    "commercial_ratio", ascending=False
)

commercial_ratio.show(
    1000, False
)

(
    commercial_ratio
    .groupby(
        F.round(F.col("commercial_ratio"), 1).alias("Bucket")
    )
    .agg(F.count("*").alias("Channels"))
    .orderBy(F.col("Bucket"))
).show()

#########################################################################################
#


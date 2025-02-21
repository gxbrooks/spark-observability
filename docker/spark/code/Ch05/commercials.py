#  commercials.py #############################################################
#
# This program computes the commercial ratio for each channel present in the
# dataset.
#
###############################################################################

import os

import pyspark.sql.functions as F
from pyspark.sql import SparkSession

spark = SparkSession.builder.appName(
    "Getting the Canadian TV channels with the highest/lowest proportion of commercials."
).getOrCreate()

spark.sparkContext.setLogLevel("WARN")

###############################################################################
# Reading all the relevant data sources
###############################################################################

DIRECTORY = "./data/broadcast_logs"

logs = spark.read.csv(
    os.path.join(DIRECTORY, "BroadcastLogs_2018_Q3_M8_sample.CSV"),
    # os.path.join(DIRECTORY, "BroadcastLogs_2018_Q3_M8.CSV"),
    sep="|",
    header=True,
    inferSchema=True,
)

log_identifier = spark.read.csv(
    # "./data/Ch03/ReferenceTables/LogIdentifier.csv",
    "./data/ReferenceTables/LogIdentifier.csv",
    sep="|",
    header=True,
    inferSchema=True,
)

cd_category = spark.read.csv(
    # "./data/Ch03/ReferenceTables/CD_Category.csv",
    "./data/ReferenceTables/CD_Category.csv",
    sep="|",
    header=True,
    inferSchema=True,
).select(
    "CategoryID",
    "CategoryCD",
    F.col("EnglishDescription").alias("Category_Description"),
)

cd_program_class = spark.read.csv(
    # "./data/Ch03/ReferenceTables/CD_ProgramClass.csv",
    "./data/ReferenceTables/CD_ProgramClass.csv",
    sep="|",
    header=True,
    inferSchema=True,
).select(
    "ProgramClassID",
    "ProgramClassCD",
    F.col("EnglishDescription").alias("ProgramClass_Description"),
)

###############################################################################
# Data processing
###############################################################################

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

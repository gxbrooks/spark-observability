from pyspark.sql import SparkSession
from functools import reduce
import pyspark.sql.functions as F
import pyspark.sql.types as T
import pandas as pd
 
spark = SparkSession.builder.appName(
    "Ch09 - Using UDFs"
).getOrCreate()


gsod = spark.read.parquet(f"/mnt/spark/data/gsod_data.parquet")

gsod_light = (
    gsod
    .select(F.col("stn"), F.col("year"), F.col("mo"), F.col("da"), F.col("temp"), F.col("date"))
    .groupBy(F.col("stn"), F.col("year"), F.col("mo"), F.col("da"), F.col("temp"), F.col("date"))
    .agg(F.count("*").alias("count_temp"))
)

gsod_light.write.mode("ignore").parquet("/mnt/spark/data/gsod_light.parquet")

(
    gsod
    .groupBy(F.col("stn"))
    .agg(F.count("*").alias("count"))
    .orderBy(F.col("count"), ascending=False)
    ).show(20)

gsod_light = spark.read.parquet("/mnt/spark/data/gsod_light.parquet")

gsod_light_p = (
    gsod_light
    # pare back the number of records to one station
    # time windows really only make sense on a station basis
    .where(F.col("stn") == "720613")
    .withColumn("dt_num", F.unix_timestamp(F.col("date")))
)

gsod.select(F.col("stn"), F.col("year"), F.col("mo"), F.col("da"), F.col("temp"), F.col("date")).show(40)


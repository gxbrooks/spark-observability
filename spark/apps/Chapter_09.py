

gbda-api@generated-mote-449417-v5.iam.gserviceaccount.com	



#########################################################################################
#
# 


gsod = (
    reduce(
        lambda x, y: x.unionByName(y, allowMissingColumns=True),
        [
            spark.read.parquet(f"./data/gsod_noaa/gsod{year}.parquet")
            for year in range(2010, 2021)
        ],
    )
    .dropna(subset=["year", "mo", "da", "temp"])
    .where(F.col("temp") != 9999.9)
    .drop("date")
)



#########################################################################################
#
# 

# Listing 9.1 Initializing PySpark within your Python shell with BigQuery connector 

from pyspark.sql import SparkSession
 
spark = SparkSession.builder.config(
    "spark.jars.packages",
    "com.google.cloud.spark:spark-bigquery-with-dependencies_2.12:0.19.1", #❶
).getOrCreate()

# [...]
# com.google.cloud.spark#spark-bigquery-with-dependencies_2.12 added as a dependency
# :: resolving dependencies :: org.apache.spark#spark-submit-parent-77d4bbf3-1fa4-4d43-b5f7-59944801d46c;1.0
#     confs: [default]
#     found com.google.cloud.spark#spark-bigquery-with-dependencies_2.12;0.19.1 in central
# downloading https://repo1.maven.org/maven2/com/google/cloud/spark/spark-bigquery-with-dependencies_2.12/
              0.19.1/spark-bigquery-with-dependencies_2.12-0.19.1.jar ...
#     [SUCCESSFUL ] com.google.cloud.spark#spark-bigquery-with-dependencies_2.12;0.19.1!
                    spark-bigquery-with-dependencies_2.12.jar (888ms)
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
 
 
def read_df_from_bq(year):                                         #❶
    return (
        spark.read.format("bigquery").option(                      #❷
            "table", 
            f"bigquery-public-data.noaa_gsod.gsod{year}"           #❸
        )  
        .option("credentialsFile", "./apps/generated-mote-449417-v5-af94559d1817.json") #❹
        .load()
)
 
 
gsod = (
    reduce(
        lambda x, y: x.unionByName(y, allowMissingColumns=True),
        # [read_df_from_bq(year) for year in range(2010, 2021)],     #❺
        [read_df_from_bq(year) for year in range(2014, 2024)],     #❺
    )
    .dropna(subset=["year", "mo", "da", "temp"])
    .where(F.col("temp") != 9999.9)
    .drop("date")
)

#########################################################################################
#
# 



#########################################################################################
#
# 



#########################################################################################
#
# 



#########################################################################################
#
# 



#########################################################################################
#
# 



#########################################################################################
#
# 



#########################################################################################
#
# 



#########################################################################################
#
# 



#########################################################################################
#
# 



#########################################################################################
#
# 



#########################################################################################
#
# 



#########################################################################################
#
# 



#########################################################################################
#
# 




#!/usr/bin/env python3
"""
Chapter 10: Machine Learning
Spark 4.0.1 with Python 3.11
"""

import os
from pyspark.sql import SparkSession
from functools import reduce
import pyspark.sql.functions as F
import pyspark.sql.types as T
import pandas as pd
from pyspark.sql.window import Window

# Python version controlled by PYSPARK_PYTHON environment variable (set via spark_env.sh)

# Create Spark session - configuration comes from spark-defaults.conf
spark = SparkSession.builder \
    .appName("Chapter 10: Machine Learning") \
    .getOrCreate()

print("=== Chapter 10: Machine Learning ===")
print(f"Spark version: {spark.version}")
print(f"Spark master: {spark.sparkContext.master}")


#########################################################################################
#
# 
# Listing 10.1 Reading the data necessary: GSOD NOAA weather data
# gsod = spark.read.parquet("/mnt/spark/data/window/gsod.parquet")
gsod = spark.read.parquet(f"/mnt/spark/data/gsod_data.parquet")


#########################################################################################
#
# 
# Listing 10.2 Computing the lowest temperature for each year using groupBy() 

coldest_temp = gsod.groupby("year").agg(F.min("temp").alias("temp"))
coldest_temp.orderBy("temp").show()

warmest_temp = gsod.groupby("year").agg(F.max("temp").alias("temp"))
warmest_temp.orderBy("temp").show()
 
# +----+------+
# |year|  temp|
# +----+------+
# |2017|-114.7|
# |2018|-113.5|
# |2019|-114.7|
# +----+------+


#########################################################################################
#
# 
# Listing 10.3 Using a left semi-join for computing the coldest station/day for each year

coldest_when = gsod.join(
    coldest_temp, how="left_semi", on=["year", "temp"]
).select("stn", "year", "mo", "da", "temp")
 
coldest_when.orderBy("year", "mo", "da").show()
 
# +------+----+---+---+------+
# |   stn|year| mo| da|  temp|
# +------+----+---+---+------+
# |896250|2017| 06| 20|-114.7|
# |896060|2018| 08| 27|-113.5|
# |895770|2019| 06| 15|-114.7|
# +------+----+---+---+------+

#########################################################################################
#
# 
# Listing 10.4 Creating a WindowSpec object by using the Window builder class 

from pyspark.sql.window import Window    ## 1
 
each_year = Window.partitionBy("year")   ## 2
 
print(each_year)
# <pyspark.sql.window.WindowSpec object at 0x7f978fc8e6a0>

#########################################################################################
#
# 
# Listing 10.5 Using a left semi-join for computing the coldest station/day for each year

coldest_when = gsod.join(
    coldest_temp, how="left_semi", on=["year", "temp"]
).select("stn", "year", "mo", "da", "temp")
 
coldest_when.orderBy("year", "mo", "da").show()
 
# +------+----+---+---+------+
# |   stn|year| mo| da|  temp|
# +------+----+---+---+------+
# |896250|2017| 06| 20|-114.7|
# |896060|2018| 08| 27|-113.5|
# |895770|2019| 06| 15|-114.7|
# +------+----+---+---+------+

#########################################################################################
#
# 
# Listing 10.6 Selecting the minimum temperature for each year using a window function 

(gsod
 .withColumn("min_temp", F.min("temp").over(each_year))    ## 1
 .where("temp = min_temp")
 .select("year", "mo", "da", "stn", "temp")
 .orderBy("year", "mo", "da")
 .show())
# +----+---+---+------+------+
# |year| mo| da|   stn|  temp|
# +----+---+---+------+------+
# |2017| 06| 20|896250|-114.7|
# |2018| 08| 27|896060|-113.5|
# |2019| 06| 15|895770|-114.7|
# +----+---+---+------+------+

#########################################################################################
#
# 
# Listing 10.7 Using a window function within a select() method 

gsod.select(
    "year",
    "mo",
    "da",
    "stn",
    "temp",
    F.min("temp").over(each_year).alias("min_temp"),
).where(
    "temp = min_temp"
).drop(                 ## 1
    "min_temp"
).orderBy(
    "year", "mo", "da"
).show()

#########################################################################################
#
# 
# Exercise 10.1 Using the gsod data frame, which window spec that, once applied, could 
# generate the hottest station for each day? 
# a) Window.partitionBy("da") 
# b) Window.partitionBy("stn", "da") 
# c) Window.partitionBy("year", "mo", "da") <== Answer one station per day
# d) Window.partitionBy("stn", "year", "mo", "da") 
# e) None of the above 

max_station_per_day = Window.partitionBy("year", "mo", "da") 

gsod.select(
    "year",
    "mo",
    "da",
    "temp",
    "stn",
    F.max("temp").over(max_station_per_day).alias("max_temp"),
).where(
    "temp = max_temp"
).drop(                 ## 1
    "max_temp"
).orderBy(
    "year", "mo", "da"
).show()


#########################################################################################
#
# 
# Listing 10.8 Reading gsod_light from the book’s code repository 

# gsod_light = spark.read.parquet("/mnt/spark/data/window/gsod_light.parquet")
gsod_light = (
    gsod
    .select(F.col("stn"), F.col("year"), F.col("mo"), F.col("da"), F.col("temp"), F.col("date"))
    .groupBy(F.col("stn"), F.col("year"), F.col("mo"), F.col("da"), F.col("temp"), F.col("date"))
    .agg(F.count("*").alias("count_temp"))
)
 
gsod_light.orderBy("count_temp", ascending=False).show()
# +------+----+---+---+----+----------+
# |   stn|year| mo| da|temp|count_temp|
# +------+----+---+---+----+----------+
# |994979|2017| 12| 11|21.3|        21|
# |998012|2017| 03| 02|31.4|        24|
# |719200|2017| 10| 09|60.5|        11|
# |917350|2018| 04| 21|82.6|         9|
# |076470|2018| 06| 07|65.0|        24|
# |996470|2018| 03| 12|55.6|        12|
# |041680|2019| 02| 19|16.1|        15|
# |949110|2019| 11| 23|54.9|        14|
# |998252|2019| 04| 18|44.7|        11|
# |998166|2019| 03| 20|34.8|        12|
# +------+----+---+---+----+----------+

#########################################################################################
#
# 
# Listing 10.9 An ordered version of the month-partitioned window 

temp_per_month_asc = Window.partitionBy("mo").orderBy("count_temp")   ## 1# 2

#########################################################################################
#
# Listing 10.10 The rank() according to the value of the count_temp column 

gsod_light.withColumn(
    "rank_tpm", F.rank().over(temp_per_month_asc)    ## 1
).show()
# +------+----+---+---+----+----------+--------+
# |   stn|year| mo| da|temp|count_temp|rank_tpm|
# +------+----+---+---+----+----------+--------+
# |949110|2019| 11| 23|54.9|        14|       1|     # 2
# |996470|2018| 03| 12|55.6|        12|       1|     # 3
# |998166|2019| 03| 20|34.8|        12|       1|     # 3
# |998012|2017| 03| 02|31.4|        24|       3|     # 4
# |041680|2019| 02| 19|16.1|        15|       1|
# |076470|2018| 06| 07|65.0|        24|       1|
# |719200|2017| 10| 09|60.5|        11|       1|
# |994979|2017| 12| 11|21.3|        21|       1|
# |917350|2018| 04| 21|82.6|         9|       1|
# |998252|2019| 04| 18|44.7|        11|       2|
# +------+----+---+---+----+----------+--------+

#########################################################################################
#
# 
gsod_light.withColumn(
    "rank_tpm", F.dense_rank().over(temp_per_month_asc)   ## 1
).show()
 
# +------+----+---+---+----+----------+--------+
# |   stn|year| mo| da|temp|count_temp|rank_tpm|
# +------+----+---+---+----+----------+--------+
# |949110|2019| 11| 23|54.9|        14|       1|
# |996470|2018| 03| 12|55.6|        12|       1|          # 2
# |998166|2019| 03| 20|34.8|        12|       1|          # 2
# |998012|2017| 03| 02|31.4|        24|       2|          # 3
# |041680|2019| 02| 19|16.1|        15|       1|
# |076470|2018| 06| 07|65.0|        24|       1|
# |719200|2017| 10| 09|60.5|        11|       1|
# |994979|2017| 12| 11|21.3|        21|       1|
# |917350|2018| 04| 21|82.6|         9|       1|
# |998252|2019| 04| 18|44.7|        11|       2|
# +------+----+---+---+----+----------+--------+

#########################################################################################
#
# 
# Listing 10.12 Computing percentage rank for every recorded temperature per year 

temp_each_year = each_year.orderBy("temp")                    ## 1
 
gsod_light.withColumn(
    "rank_tpm", F.percent_rank().over(temp_each_year)
).show()
 
# +------+----+---+---+----+----------+------------------+
# |   stn|year| mo| da|temp|count_temp|          rank_tpm|
# +------+----+---+---+----+----------+------------------+
# |041680|2019| 02| 19|16.1|        15|               0.0|
# |998166|2019| 03| 20|34.8|        12|0.3333333333333333|
# |998252|2019| 04| 18|44.7|        11|0.6666666666666666|    # 2
# |949110|2019| 11| 23|54.9|        14|               1.0|
# |994979|2017| 12| 11|21.3|        21|               0.0|
# |998012|2017| 03| 02|31.4|        24|               0.5|
# |719200|2017| 10| 09|60.5|        11|               1.0|
# |996470|2018| 03| 12|55.6|        12|               0.0|
# |076470|2018| 06| 07|65.0|        24|               0.5|
# |917350|2018| 04| 21|82.6|         9|               1.0|
# +------+----+---+---+----+----------+------------------+

#########################################################################################
#
# 
# Listing 10.13 Computing the two-tile value over the window 

gsod_light.withColumn("rank_tpm", F.ntile(2).over(temp_each_year)).show()
 
# +------+----+---+---+----+----------+--------+
# |   stn|year| mo| da|temp|count_temp|rank_tpm|
# +------+----+---+---+----+----------+--------+
# |041680|2019| 02| 19|16.1|        15|       1|
# |998166|2019| 03| 20|34.8|        12|       1|
# |998252|2019| 04| 18|44.7|        11|       2|
# |949110|2019| 11| 23|54.9|        14|       2|
# |994979|2017| 12| 11|21.3|        21|       1|
# |998012|2017| 03| 02|31.4|        24|       1|
# |719200|2017| 10| 09|60.5|        11|       2|
# |996470|2018| 03| 12|55.6|        12|       1|
# |076470|2018| 06| 07|65.0|        24|       1|
# |917350|2018| 04| 21|82.6|         9|       2|
# +------+----+---+---+----+----------+--------+

gsod_light.withColumn("rank_tpm", F.ntile(1000).over(temp_each_year)).orderBy(F.col("year"), F.col("mo"), F.col("da")).show()

#########################################################################################
#
# 
# Listing 10.14 Numbering records within each window partition using row_number() 

gsod_light.withColumn(
    "rank_tpm", F.row_number().over(temp_each_year)
).show()
 
# +------+----+---+---+----+----------+--------+
# |   stn|year| mo| da|temp|count_temp|rank_tpm|
# +------+----+---+---+----+----------+--------+
# |041680|2019| 02| 19|16.1|        15|       1|   # 1
# |998166|2019| 03| 20|34.8|        12|       2|   # 1
# |998252|2019| 04| 18|44.7|        11|       3|   # 1
# |949110|2019| 11| 23|54.9|        14|       4|   # 1
# |994979|2017| 12| 11|21.3|        21|       1|
# |998012|2017| 03| 02|31.4|        24|       2|
# |719200|2017| 10| 09|60.5|        11|       3|
# |996470|2018| 03| 12|55.6|        12|       1|
# |076470|2018| 06| 07|65.0|        24|       2|
# |917350|2018| 04| 21|82.6|         9|       3|
# +------+----+---+---+----+----------+--------+ 

# # 1 row_number() will give you strictly increasing ranks for every record in your window.

#########################################################################################
#
# 
# Listing 10.15 Creating a window with a descending-ordered column 

temp_per_month_desc = Window.partitionBy("mo").orderBy(
    F.col("count_temp").desc()                           ## 1
)
 
gsod_light.withColumn(
    "row_number", F.row_number().over(temp_per_month_desc)
).show()
 
# +------+----+---+---+----+----------+----------+
# |   stn|year| mo| da|temp|count_temp|row_number|
# +------+----+---+---+----+----------+----------+
# |949110|2019| 11| 23|54.9|        14|         1|
# |998012|2017| 03| 02|31.4|        24|         1|
# |996470|2018| 03| 12|55.6|        12|         2|
# |998166|2019| 03| 20|34.8|        12|         3|
# |041680|2019| 02| 19|16.1|        15|         1|
# |076470|2018| 06| 07|65.0|        24|         1|
# |719200|2017| 10| 09|60.5|        11|         1|
# |994979|2017| 12| 11|21.3|        21|         1|
# |998252|2019| 04| 18|44.7|        11|         1|
# |917350|2018| 04| 21|82.6|         9|         2|
# +------+----+---+---+----+----------+----------+ 

# # 1 By default, a column will be ordered with ascending values. Passing the desc() method will reverse that order for that column.

#########################################################################################
#
# 
# Listing 10.16 Getting the temperature of the previous two observations using lag() 



gsod_light.withColumn(
    "previous_temp", F.lag("temp").over(temp_each_year)
).withColumn(
    "previous_temp_2", F.lag("temp", 2).over(temp_each_year)
).show()


each_stn = Window.partitionBy("stn") 
temp_each_stn = each_stn.orderBy(F.col("year"), F.col("mo"), F.col("da"))

gsod_light.withColumn(
    "previous_temp", F.lag("temp").over(temp_each_stn)
).withColumn(
    "previous_temp_2", F.lag("temp", 2).over(temp_each_stn)
).orderBy(F.col("stn"), F.col("year"), F.col("mo"), F.col("da")).show(40)

# there are significant gaps in days for measurements at a station
(
    gsod
    .select(F.col("stn"), F.col("year"), F.col("mo"), F.col("da"), F.col("temp"))
    .orderBy(F.col("stn"), F.col("year"), F.col("mo"), F.col("da"))
    .show(40)
)

# +------+----+---+---+----+----------+-------------+---------------+
# |   stn|year| mo| da|temp|count_temp|previous_temp|previous_temp_2|
# +------+----+---+---+----+----------+-------------+---------------+
# |041680|2019| 02| 19|16.1|        15|         null|           null|
# |998166|2019| 03| 20|34.8|        12|         16.1|           null|  # 1
# |998252|2019| 04| 18|44.7|        11|         34.8|           16.1|  # 1
# |949110|2019| 11| 23|54.9|        14|         44.7|           34.8|
# |994979|2017| 12| 11|21.3|        21|         null|           null|
# |998012|2017| 03| 02|31.4|        24|         21.3|           null|
# |719200|2017| 10| 09|60.5|        11|         31.4|           21.3|
# |996470|2018| 03| 12|55.6|        12|         null|           null|
# |076470|2018| 06| 07|65.0|        24|         55.6|           null|
# |917350|2018| 04| 21|82.6|         9|         65.0|           55.6|
# +------+----+---+---+----+----------+-------------+---------------+ # 1 The previous observation of the second record is the twice-previous observation of the third record, and so on.


#########################################################################################
#
# 
# Listing 10.17 percent_rank() and cume_dist() over a window 

gsod_light.withColumn(
    "percent_rank", F.percent_rank().over(temp_each_year)
).withColumn("cume_dist", F.cume_dist().over(temp_each_year)).show()
 
# +------+----+---+---+----+----------+----------------+----------------+
# |   stn|year| mo| da|temp|count_temp|    percent_rank|       cume_dist|
# +------+----+---+---+----+----------+----------------+----------------+
# |041680|2019| 02| 19|16.1|        15|             0.0|            0.25|
# |998166|2019| 03| 20|34.8|        12|0.33333333333333|             0.5|
# |998252|2019| 04| 18|44.7|        11|0.66666666666666|            0.75|
# |949110|2019| 11| 23|54.9|        14|             1.0|             1.0|
# |994979|2017| 12| 11|21.3|        21|             0.0|0.33333333333333|
# |998012|2017| 03| 02|31.4|        24|             0.5|0.66666666666666|
# |719200|2017| 10| 09|60.5|        11|             1.0|             1.0|
# |996470|2018| 03| 12|55.6|        12|             0.0|0.33333333333333|
# |076470|2018| 06| 07|65.0|        24|             0.5|0.66666666666666|
# |917350|2018| 04| 21|82.6|         9|             1.0|             1.0|
# +------+----+---+---+----+----------+----------------+----------------+

#########################################################################################
#
# 
# Exercise 10.2 If you have a window where all the ordered values are the same, 
# what is the result of applying ntile() to the window?

# answer = randomly assign values in the same partioin to tiles

# Create a Spark session
    .config("spark.eventLog.enabled", "true") \
    .config("spark.eventLog.dir", os.getenv('SPARK_EVENTS_DIR', '/mnt/spark/events')) \
tSpark = SparkSession.builder.appName("DateFunctionExample").getOrCreate()

# Example data
data = [ (1, 1),
     (1, 1),
     (1, 1),
     (1, 1),
     (1, 1),
     (1, 1),
     (1, 1),
     (1, 1),
     (1, 1),
     (1, 1),
     (1, 1),
     (1, 1),
     (1, 1),
     (1, 1),
     (1, 1),
     (1, 1)
     ]

columns = ["part", "val"]

# Create a DataFrame
tdf = spark.createDataFrame(data, columns)

each_part = Window.partitionBy("part") 
val_each_part = each_part.orderBy(F.col("val"))

tdf.withColumn(
    "rank_tpm", F.ntile(4).over(val_each_part)
).show()

#########################################################################################
#
# 
# Listing 10.18 Ordering a window and the computation of the average 

not_ordered = Window.partitionBy("year")
ordered = not_ordered.orderBy("temp")
gsod_light.withColumn(
    "avg_NO", F.avg("temp").over(not_ordered)
).withColumn("avg_O", F.avg("temp").over(ordered)).show()
 
# +------+----+---+---+----+----------+----------------+------------------+
# |   stn|year| mo| da|temp|count_temp|          avg_NO|             avg_O|
# +------+----+---+---+----+----------+----------------+------------------+
# |041680|2019| 02| 19|16.1|        15|          37.625|              16.1|
# |998166|2019| 03| 20|34.8|        12|          37.625|             25.45|
# |998252|2019| 04| 18|44.7|        11|          37.625|31.866666666666664|
# |949110|2019| 11| 23|54.9|        14|          37.625|            37.625|
# |994979|2017| 12| 11|21.3|        21|37.7333333333334|              21.3|
# |998012|2017| 03| 02|31.4|        24|37.7333333333334|             26.35|
# |719200|2017| 10| 09|60.5|        11|37.7333333333334|37.733333333333334|
# |996470|2018| 03| 12|55.6|        12| 67.733333333333|              55.6|
# |076470|2018| 06| 07|65.0|        24| 67.733333333333|              60.3|
# |917350|2018| 04| 21|82.6|         9| 67.733333333333| 67.73333333333333|
# +------+----+---+---+----+----------+----------------+------------------+
#                                            ^ # 1            ^ # 2 
# # 1 All good: the average is consistent across each window, and the results are logical. 
# # 2 Some odd stuff is happening. It looks like each window grows, record by record, so the average changes every time.

#########################################################################################
#
# 
# Listing 10.19 Rewriting the window spec with explicit window boundaries

not_ordered = Window.partitionBy("year").rowsBetween(
    Window.unboundedPreceding, Window.unboundedFollowing    ## 1
)
ordered = not_ordered.orderBy("temp").rangeBetween(
    Window.unboundedPreceding, Window.currentRow            ## 2
) 
# # 1 This window is unbounded: every record, from the first to the last, is in the window. 
# # 2 This window is growing to the left: every record up to the current row value is included in a window.

#########################################################################################
#
# 
# Listing 10.20 Creating a date column to apply range window on 

gsod_light_p = (
    gsod_light.withColumn("year", F.lit(2019))
    .withColumn(
        "dt",
        F.to_date(
            F.concat_ws("-", F.col("year"), F.col("mo"), F.col("da"))
        ),
    )
    .withColumn("dt_num", F.unix_timestamp("dt"))
)

gsod_light_p = (
    gsod_light.withColumn("year", F.lit(2019))
    .withColumn("dt_num", F.unix_timestamp(F.col("date")))
)

gsod_light_p.show()
 
#                                          
# +------+----+---+---+----+----------+----------+----------+  
# |   stn|year| mo| da|temp|count_temp|        dt|    dt_num|  
# +------+----+---+---+----+----------+----------+----------+  
# |041680|2019| 02| 19|16.1|        15|2019-02-19|1550552400|  
# |998012|2019| 03| 02|31.4|        24|2019-03-02|1551502800|  
# |996470|2019| 03| 12|55.6|        12|2019-03-12|1552363200|  
# |998166|2019| 03| 20|34.8|        12|2019-03-20|1553054400|  
# |998252|2019| 04| 18|44.7|        11|2019-04-18|1555560000|  
# |917350|2019| 04| 21|82.6|         9|2019-04-21|1555819200|  
# |076470|2019| 06| 07|65.0|        24|2019-06-07|1559880000|  
# |719200|2019| 10| 09|60.5|        11|2019-10-09|1570593600|  
# |949110|2019| 11| 23|54.9|        14|2019-11-23|1574485200|  
# |994979|2019| 12| 11|21.3|        21|2019-12-11|1576040400|  
# +------+----+---+---+----+----------+----------+----------+  
#
#                                         ^ # 1         ^ # 2 
# # 1 The new column is of type DateType(), which can be treated (window wise) as a number. 
# # 2 When using PySpark, windows must be over numerical values. Using unix_timestamp() is 
#   the easiest way to convert a date/timestamp to a number.


#########################################################################################
#
# 
# Listing 10.21 Computing the average temperature for a 60-day sliding window 

ONE_MONTH_ISH = 30 * 60 * 60 * 24  
# or 2_592_000 seconds
one_month_ish_before_and_after = (
    Window.partitionBy("year")
    .orderBy("dt_num")
    .rangeBetween(-ONE_MONTH_ISH, ONE_MONTH_ISH)     ## 1
)
 
gsod_light_p.withColumn(
    "avg_count", F.avg("count_temp").over(one_month_ish_before_and_after)
).show()
 
# +------+----+---+---+----+----------+----------+----------+-------------+
# |   stn|year| mo| da|temp|count_temp|        dt|    dt_num|    avg_count|
# +------+----+---+---+----+----------+----------+----------+-------------+
# |041680|2019| 02| 19|16.1|        15|2019-02-19|1550552400|        15.75|
# |998012|2019| 03| 02|31.4|        24|2019-03-02|1551502800|        15.75|
# |996470|2019| 03| 12|55.6|        12|2019-03-12|1552363200|        15.75|
# |998166|2019| 03| 20|34.8|        12|2019-03-20|1553054400|         14.8|
# |998252|2019| 04| 18|44.7|        11|2019-04-18|1555560000|10.6666666666|
# |917350|2019| 04| 21|82.6|         9|2019-04-21|1555819200|         10.0|
# |076470|2019| 06| 07|65.0|        24|2019-06-07|1559880000|         24.0|
# |719200|2019| 10| 09|60.5|        11|2019-10-09|1570593600|         11.0|
# |949110|2019| 11| 23|54.9|        14|2019-11-23|1574485200|         17.5|
# |994979|2019| 12| 11|21.3|        21|2019-12-11|1576040400|         17.5|
# +------+----+---+---+----+----------+----------+----------+-------------+ 
#
# # 1 The range becomes (current_row_value – ONE_MONTH_ISH, current_row_value + ONE_MONTH_ISH).

#########################################################################################
#
# 
# Listing 10.22 Using a pandas UDF over window intervals import pandas as pd
  
# Spark 2.4, use the following
# @F.pandas_udf("double", PandasUDFType.GROUPED_AGG)
@F.pandas_udf("double")
def median(vals: pd.Series) -> float:
    return vals.median()


gsod_light.withColumn(
    "median_temp", median("temp").over(Window.partitionBy("year"))    ## 1
).withColumn(
    "median_temp_g",
    median("temp").over(
        Window.partitionBy("year").orderBy("mo", "da")                ## 2
    ),                                                                ## 2
).show()
#                                          
# +------+----+---+---+----+----------+-----------+-------------+
# |   stn|year| mo| da|temp|count_temp|median_temp|median_temp_g|
# +------+----+---+---+----+----------+-----------+-------------+
# |041680|2019| 02| 19|16.1|        15|      39.75|         16.1|
# |998166|2019| 03| 20|34.8|        12|      39.75|        25.45|
# |998252|2019| 04| 18|44.7|        11|      39.75|         34.8|
# |949110|2019| 11| 23|54.9|        14|      39.75|        39.75|
# |998012|2017| 03| 02|31.4|        24|       31.4|         31.4|
# |719200|2017| 10| 09|60.5|        11|       31.4|        45.95|
# |994979|2017| 12| 11|21.3|        21|       31.4|         31.4|
# |996470|2018| 03| 12|55.6|        12|       65.0|         55.6|
# |917350|2018| 04| 21|82.6|         9|       65.0|         69.1|
# |076470|2018| 06| 07|65.0|        24|       65.0|         65.0|
# +------+----+---+---+----+----------+-----------+-------------+
#
#                     ^ # 3  ^ # 4 
# # 1 The UDF is applied over an unbounded/unordered window frame. 
# # 2 The same UDF is now applied over a bounded/ordered window frame. 
# # 3 Since the window is unbounded, every record within a window has the same median. 
# # 4 Since the window is bounded to the right, the median changes as we add more records 
#   to the window.

#########################################################################################
#
# 
# Exercise 10.4 
# Using the following code, first identify the day with the warmest temperature for each 
# year, and then compute the average temperature. What happens when there are more than 
# two occurrences? 

each_year = Window.partitionBy("year")
 
(
    gsod
    .withColumn("min_temp", F.min("temp").over(each_year))
    .where("temp = min_temp")
    .select("year", "mo", "da", "stn", "temp")
    .orderBy("year", "mo", "da")
    .show()
 )

(
    gsod
    .withColumn("max_temp", F.max("temp").over(each_year))
    .where("temp = max_temp")
    .select("year", "mo", "da", "stn", "temp")
    .orderBy("year", "mo", "da")
    .show()
 )
# not clear on what the avergage should range over
(
    gsod
    .withColumn("max_temp", F.max("temp").over(each_year))
    .where("temp = max_temp")
    .select("year", "mo", "da", "stn", "temp")
    .groupBy(F.col("year"), F.col("mo"), F.col("da"), F.col("stn") )
    .agg(F.avg("temp"))
    .orderBy("year", "mo", "da")
    .show()
 )

# It is odd that the highest temp was 110.0 across all the years

#########################################################################################
#
# Exercise 10.5 
# How would you create a rank that is full, meaning that each record within a the 
# temp_per_month_asc has a unique rank, using the gsod_light data frame? For records
# with an identical orderBy() value, the order of rank does not matter. 

temp_per_month_asc = Window.partitionBy("mo").orderBy("count_temp")
 
# gsod_light = spark.read.parquet("/mnt/spark/data/window/gsod_light.parquet")
gsod_light_book = spark.read.parquet("/mnt/spark/data/gsod_light.parquet")
gsod_light_book.withColumn(
    "rank_tpm", F.rank().over(temp_per_month_asc)  ## 1
).show()

# unclear how to meet (1) below
gsod_light_book.withColumn(
    "rank_tpm", F.dense_rank().over(temp_per_month_asc)  ## 1
).orderBy(F.col("mo"), F.col("count_temp")).show()

# +------+----+---+---+----+----------+--------+
# |   stn|year| mo| da|temp|count_temp|rank_tpm|
# +------+----+---+---+----+----------+--------+
# |949110|2019| 11| 23|54.9|        14|       1|
# |996470|2018| 03| 12|55.6|        12|       1|   # 1
# |998166|2019| 03| 20|34.8|        12|       1|   # 1
# |998012|2017| 03| 02|31.4|        24|       3|
# |041680|2019| 02| 19|16.1|        15|       1|
# |076470|2018| 06| 07|65.0|        24|       1|
# |719200|2017| 10| 09|60.5|        11|       1|
# |994979|2017| 12| 11|21.3|        21|       1|
# |917350|2018| 04| 21|82.6|         9|       1|
# |998252|2019| 04| 18|44.7|        11|       2|
# +------+----+---+---+----+----------+--------+ 
# # 1 These records should be 1 and 2.

#########################################################################################
#
# Exercise 10.6 
# Take the gsod data frame (not the gsod_light) and create a new column that is True 
# if the temperature at a given station is maximum

# 7 days 
SEVEN_DAYS = 7 * 60 * 60 * 24
seven_days_plus_minus = (
    Window
    .partitionBy(F.col("stn"))
    .orderBy(F.col("dt_num"))
    .rangeBetween(- SEVEN_DAYS, SEVEN_DAYS)
    )

( gsod
    .groupBy(F.col("stn"))
    .agg(F.count("*").alias("count"))
    .orderBy(F.col("count"), ascending=False)
    .show()
    )
# station with most records is 720613
(
    gsod
    .select(F.col("date"), F.col("stn"), F.col("temp"))
    .withColumn("dt_num", F.unix_timestamp("date"))
    .withColumn("max_temp", 
        F.max(F.col("temp")).over(seven_days_plus_minus))
    .withColumn("is_max", F.col("temp") == F.col("max_temp"))
    .orderBy(F.col("stn"), F.col("dt_num"))
    .where(F.col("stn") == "720613")
    .show(100)
    )

#########################################################################################
#
# Exercise 10.7 
# How would you create a window like the code that follows, but taking into 
# account that months have different number of days? For instance, March has 31 days, but 
# April has 30 days, so you can’t do a window spec over a set number of days. 
# (Hint: My solution doesn’t use dt_num.) ONE_MONTH_ISH = 30 * 60 * 60 * 24  # or 2_592_000 seconds

ONE_MONTH_ISH = 30 * 60 * 60 * 24  # or 2_592_000 seconds
one_month_ish_before_and_after = (
    Window.partitionBy("year")
    .orderBy("dt_num")
    .rangeBetween(-ONE_MONTH_ISH, ONE_MONTH_ISH)
 )
 
gsod_light_p = (
    # gsod_light.withColumn("year", F.lit(2019))
    gsod_light_book.withColumn("year", F.lit(2019))
    .withColumn(
        "dt",
        F.to_date(
            F.concat_ws("-", F.col("year"), F.col("mo"), F.col("da"))
        ),
    )
    .withColumn("dt_num", F.unix_timestamp("dt"))
)
 
gsod_light_p.withColumn(
    "avg_count", F.avg("count_temp").over(one_month_ish_before_and_after)
).show()

# +------+----+---+---+----+----------+----------+----------+-------------+
# |   stn|year| mo| da|temp|count_temp|        dt|    dt_num|    avg_count|
# +------+----+---+---+----+----------+----------+----------+-------------+
# |041680|2019| 02| 19|16.1|        15|2019-02-19|1550552400|        15.75|
# |998012|2019| 03| 02|31.4|        24|2019-03-02|1551502800|        15.75|
# |996470|2019| 03| 12|55.6|        12|2019-03-12|1552363200|        15.75|
# |998166|2019| 03| 20|34.8|        12|2019-03-20|1553054400|         14.8|
# |998252|2019| 04| 18|44.7|        11|2019-04-18|1555560000|10.6666666666|
# |917350|2019| 04| 21|82.6|         9|2019-04-21|1555819200|         10.0|
# |076470|2019| 06| 07|65.0|        24|2019-06-07|1559880000|         24.0|
# |719200|2019| 10| 09|60.5|        11|2019-10-09|1570593600|         11.0|
# |949110|2019| 11| 23|54.9|        14|2019-11-23|1574485200|         17.5|
# |994979|2019| 12| 11|21.3|        21|2019-12-11|1576040400|         17.5|
# +------+----+---+---+----+----------+----------+----------+-------------+

# answer

one_month_ish_before_and_after = (
    Window.partitionBy("year")
    .orderBy(F.col("mo_num"))
    .rangeBetween(-1, 1)
 )

gsod_light_p = (
    gsod_light_book.withColumn("year", F.lit(2019))
    .withColumn("mo_num",(F.col("year") * 12 + F.col("mo")).cast("int"))
)

(
    gsod_light_p
    .withColumn(
        "avg_count", 
        F.avg("count_temp").over(one_month_ish_before_and_after))
    .orderBy("year", "mo", "da")
    .show(40)
)

# result

# +------+----+---+---+----+----------+-------+------------------+
# |   stn|year| mo| da|temp|count_temp| mo_num|         avg_count|
# +------+----+---+---+----+----------+-------+------------------+
# |041680|2019| 02| 19|16.1|        15|24230.0|             15.75|
# |998012|2019| 03| 02|31.4|        24|24231.0|13.833333333333334|
# |996470|2019| 03| 12|55.6|        12|24231.0|13.833333333333334|
# |998166|2019| 03| 20|34.8|        12|24231.0|13.833333333333334|
# |998252|2019| 04| 18|44.7|        11|24232.0|              13.6|
# |917350|2019| 04| 21|82.6|         9|24232.0|              13.6|
# |076470|2019| 06| 07|65.0|        24|24234.0|              24.0|
# |719200|2019| 10| 09|60.5|        11|24238.0|              12.5|
# |949110|2019| 11| 23|54.9|        14|24239.0|15.333333333333334|
# |994979|2019| 12| 11|21.3|        21|24240.0|              17.5|
# +------+----+---+---+----+----------+-------+------------------+

#########################################################################################
#
# 
gsod_month = (
    gsod
    .select("stn", "year", "mo", "da", "temp")
    .groupBy("stn", "year", "mo")
    .agg(F.avg("temp").alias("temp"))
    .orderBy("stn", "year", "mo")
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


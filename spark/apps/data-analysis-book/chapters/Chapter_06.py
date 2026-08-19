

#!/usr/bin/env python3
"""
Chapter 06: JSON Processing
Spark 4.0.1 with Python 3.11
"""

import os
import glob
from pyspark.sql import SparkSession
import pyspark.sql.functions as F
import pyspark.sql.types as T

# Python version controlled by PYSPARK_PYTHON environment variable (set via spark_env.sh)

# Use derived SPARK_LOCAL_IP from shell environment; do not hardcode host IPs.

# Create Spark session - configuration comes from spark-defaults.conf
spark = SparkSession.builder \
    .appName("Chapter 06: JSON Processing") \
    .getOrCreate()

print("=== Chapter 06: JSON Processing ===")
print(f"Spark version: {spark.version}")
print(f"Spark master: {spark.sparkContext.master}")

#########################################################################################
#
# Listing 6.3 Ingesting a JSON document using the JSON specialized SparkReader
 
shows = spark.read.json("/mnt/spark/data/shows/shows-silicon-valley.json")   #❶
 
shows.count()
# 1                                                                 #❷

#########################################################################################
#
# Listing 6.4 Reading multiple JSON documents using the multiLine option 
# Use glob to expand wildcards into file list (avoids Spark 4.0 metadata warnings)
show_files = sorted(glob.glob("/mnt/spark/data/shows/shows-*.json"))
three_shows = spark.read.json(show_files, multiLine=True)
 
three_shows.count()
# 3
 
assert three_shows.count() == 3

#########################################################################################
#
# Listing 6.5 Nested structures with a deeper level of indentation 
shows.printSchema()
# root                                          ❶
#  |-- _embedded: struct (nullable = true)      ❷
#  |    |-- episodes: array (nullable = true)
#  |    |    |-- element: struct (containsNull = true)
#  |    |    |    |-- _links: struct (nullable = true)
#  |    |    |    |    |-- self: struct (nullable = true)
#  |    |    |    |    |    |-- href: string (nullable = true)
#  |    |    |    |-- airdate: string (nullable = true)
#  |    |    |    |-- airstamp: string (nullable = true)
#  |    |    |    |-- airtime: string (nullable = true)
#  |    |    |    |-- id: long (nullable = true)
#  |    |    |    |-- image: struct (nullable = true)
#  |    |    |    |    |-- medium: string (nullable = true)
#  |    |    |    |    |-- original: string (nullable = true)
#  |    |    |    |-- name: string (nullable = true)
#  |    |    |    |-- number: long (nullable = true)
#  |    |    |    |-- runtime: long (nullable = true)
#  |    |    |    |-- season: long (nullable = true)
#  |    |    |    |-- summary: string (nullable = true)
#  |    |    |    |-- url: string (nullable = true)
#  |-- _links: struct (nullable = true)
#  |    |-- previousepisode: struct (nullable = true)
#  |    |    |-- href: string (nullable = true)
#  |    |-- self: struct (nullable = true)
#  |    |    |-- href: string (nullable = true)
#  |-- externals: struct (nullable = true)
#  |    |-- imdb: string (nullable = true)
#  |    |-- thetvdb: long (nullable = true)
#  |    |-- tvrage: long (nullable = true)
#  |-- genres: array (nullable = true)
#  |    |-- element: string (containsNull = true)
#  |-- id: long (nullable = true)
# [and more columns...]



#########################################################################################
#
# Listing 6.6 Printing the columns of the shows data frame 

print(shows.columns)
 
# ['_embedded', '_links', 'externals', 'genres', 'id', 'image',
#  'language', 'name', 'network', 'officialSite', 'premiered',
#  'rating', 'runtime', 'schedule', 'status', 'summary', 'type',
#  'updated', 'url', 'webChannel', 'weight']


#########################################################################################
#
# Listing 6.7 Selecting the name and genres columns 

array_subset = shows.select("name", "genres")
# array_subset = three_shows.select("name", "genres")
 
array_subset.show(1, False)
# +--------------+--------+
# |name          |genres  |
# +--------------+--------+
# |Silicon Valley|[Comedy]|
# +--------------+--------+

three_shows.select("name", "genres").show()
 
#########################################################################################
#
# Listing 6.8 Extracting elements from an array 

import pyspark.sql.functions as F
 
array_subset = array_subset.select(
    "name",
    array_subset.genres[0].alias("dot_and_index"),           #❶
    F.col("genres")[0].alias("col_and_index"),
    array_subset.genres.getItem(0).alias("dot_and_method"),  #❷
    F.col("genres").getItem(0).alias("col_and_method"),
)
 
array_subset.show()
 
# +--------------+-------------+-------------+--------------+--------------+
# |          name|dot_and_index|col_and_index|dot_and_method|col_and_method|
# +--------------+-------------+-------------+--------------+--------------+
# |Silicon Valley|       Comedy|       Comedy|        Comedy|        Comedy|
# +--------------+-------------+-------------+--------------+--------------+

# Rioux, Jonathan. Data Analysis with Python and PySpark (p. 250). Manning. Kindle Edition. 



#########################################################################################
#
# Listing 6.9 Performing multiple operations on an array column 

array_subset_repeated = array_subset.select(
    "name",
    F.lit("Comedy").alias("one"),
    F.lit("Horror").alias("two"),
    F.lit("Drama").alias("three"),
    F.col("dot_and_index"),
).select(
    "name",
    F.array("one", "two", "three").alias("Some_Genres"),                #❶
    F.array_repeat("dot_and_index", 5).alias("Repeated_Genres"),        #❷
)
 
array_subset_repeated.show(1, False)
 
# +--------------+-----------------------+----------------------------------------+
# |name          |Some_Genres            |Repeated_Genres                         |
# +--------------+-----------------------+----------------------------------------+
# |Silicon Valley|[Comedy, Horror, Drama]|[Comedy, Comedy, Comedy, Comedy, Comedy]|
# +--------------+-----------------------+----------------------------------------+
 
array_subset_repeated.select(
    "name", F.size("Some_Genres"), F.size("Repeated_Genres")            #❸
).show()

# +--------------+-----------------+---------------------+
# |          name|size(Some_Genres)|size(Repeated_Genres)|
# +--------------+-----------------+---------------------+
# |Silicon Valley|                3|                    5|
# +--------------+-----------------+---------------------+
array_subset_repeated.select(
    "name",
    F.array_distinct("Some_Genres"),                                    #❹
    F.array_distinct("Repeated_Genres"),                                #❹
).show(1, False)
 
# +--------------+---------------------------+-------------------------------+
# |name          |array_distinct(Some_Genres)|array_distinct(Repeated_Genres)|
# +--------------+---------------------------+-------------------------------+
# |Silicon Valley|[Comedy, Horror, Drama]    |[Comedy]                       |
# +--------------+---------------------------+-------------------------------+
 
array_subset_repeated = array_subset_repeated.select(
    "name",
    F.array_intersect("Some_Genres", "Repeated_Genres").alias(          #❺
        "Genres"
    ),
)
 
array_subset_repeated.show()
 
# +--------------+--------+
# |          name|  Genres|
# +--------------+--------+
# |Silicon Valley|[Comedy]|
# +--------------+--------+

#########################################################################################
#
# Listing 6.10 Using array_position() to search for Genres string 

array_subset_repeated.select(
    "Genres", F.array_position("Genres", "Comedy")
).show()
 
# +--------+------------------------------+
# |  Genres|array_position(Genres, Comedy)|
# +--------+------------------------------+
# |[Comedy]|                             1|
# +--------+------------------------------+



#########################################################################################
#
# Listing 6.11 Creating a map from two arrays 

columns = ["name", "language", "type"]
 
# shows_map = shows.select(
shows_map = three_shows.select(
    *[F.lit(column) for column in columns],
    F.array(*columns).alias("values"),
)
shows_map = shows_map.select(F.array(*columns).alias("keys"), "values")
 
shows_map.show()
# +--------------------+--------------------+
# |                keys|              values|
# +--------------------+--------------------+
# |[name, language, ...|[Silicon Valley, ...|
# +--------------------+--------------------+
 
shows_map = shows_map.select(
    F.map_from_arrays("keys", "values").alias("mapped")
)
 
shows_map.printSchema()
 
# root
#  |-- mapped: map (nullable = false)
#  |    |-- key: string
#  |    |-- value: string (valueContainsNull = true)
shows_map.show(1, False)
 
# +---------------------------------------------------------------+
# |mapped                                                         |
# +---------------------------------------------------------------+
# |[name -> Silicon Valley, language -> English, type -> Scripted]|
# +---------------------------------------------------------------+
 
shows_map.select(
    F.col("mapped.name"),      #❶
    F.col("mapped")["name"],   #❷
    shows_map.mapped["name"],  #❸
).show()
 
# +--------------+--------------+--------------+
# |       name   |  mapped[name]|  mapped[name]|
# +--------------+--------------+--------------+
# |Silicon Valley|Silicon Valley|Silicon Valley|
# +--------------+--------------+--------------+

#########################################################################################
#
# Exercise 6.1 Assume the following JSON document: 

import json

json_string = """{"name": "Sample name",
    "keywords": ["PySpark", "Python", "Data"]}""" 

json_struct = json.loads(json_string)

# What is the schema once read by spark.read.json?

df = spark.createDataFrame([json_struct])
df.printSchema()

#########################################################################################
#
# Exercise 6.2 Assume the following JSON document: 
    
json_string = """{"name": "Sample name",
    "keywords": ["PySpark", 3.2, "Data"]}"""
    
# What is the schema once read by spark.read.json?

json_struct = json.loads(json_string)

# What is the schema once read by spark.read.json?

df = spark.createDataFrame([json_struct])
df.printSchema()
df.show()

#########################################################################################
#
# Listing 6.12 The schedule column with an array of strings and a string 

shows.select("schedule").printSchema()
 
# root
#  |-- schedule: struct (nullable = true)            ❶
#  |    |-- days: array (nullable = true)
#  |    |    |-- element: string (containsNull = true)
#  |    |-- time: string (nullable = true)

#########################################################################################
#
# Listing 6.13 The _embedded column schema 

shows.select(F.col("_embedded")).printSchema()
# root
#  |-- _embedded: struct (nullable = true)                   ❶
#  |    |-- episodes: array (nullable = true)                ❷
#  |    |    |-- element: struct (containsNull = true)
#  |    |    |    |-- _links: struct (nullable = true)       ❸


#########################################################################################
#
# Listing 6.14 Promoting the fields within a struct as columns 

shows_clean = shows.withColumn(
 "episodes", F.col("_embedded.episodes")
).drop("_embedded")
 
shows_clean.printSchema()
# root
#  |-- _links: struct (nullable = true)
#  |    |-- previousepisode: struct (nullable = true)
#  |    |    |-- href: string (nullable = true)
#  |    |-- self: struct (nullable = true)
#  |    |    |-- href: string (nullable = true)
#  |-- externals: struct (nullable = true)
#  |    |-- imdb: string (nullable = true)
#  [...]
#  |-- episodes: array (nullable = true)            ❶
#  |    |-- element: struct (containsNull = true)
#  |    |    |-- _links: struct (nullable = true)
#  |    |    |    |-- self: struct (nullable = true)
#  |    |    |    |    |-- href: string (nullable = true)
#  |    |    |-- airdate: string (nullable = true)
#  |    |    |-- airstamp: string (nullable = true)
#  |    |    |-- airtime: string (nullable = true)
#  |    |    |-- id: long (nullable = true)
#  |    |    |-- image: struct (nullable = true)
#  |    |    |    |-- medium: string (nullable = true)
#  |    |    |    |-- original: string (nullable = true)
# [... rest of schema]

#########################################################################################
#
# Listing 6.15 Selecting a field in an Array[Struct] to create a column 

episodes_name = shows_clean.select(F.col("episodes.name"))              #❶
episodes_name.printSchema()
 
# root
#  |-- name: array (nullable = true)
#  |    |-- element: string (containsNull = true)
 
episodes_name.select(F.explode("name").alias("name")).show(3, False)   #❷
# +-------------------------+
# |name                     |
# +-------------------------+
# |Minimum Viable Product   |
# |The Cap Table            |
# |Articles of Incorporation|
# +-------------------------+


#########################################################################################
#
# Listing 6.16 A sample of the schema for the shows data frame 

shows.printSchema()
# root                                    ❶
#  |-- _links: struct (nullable = true)
#  |    |-- previousepisode: struct (nullable = true)
#  |    |    |-- href: string (nullable = true)
#  |    |-- self: struct (nullable = true)
#  |    |    |-- href: string (nullable = true)
#  |-- externals: struct (nullable = true)
#  |    |-- imdb: string (nullable = true)
#  [... rest of schema]

#########################################################################################
#
# Listing 6.17 The schema for the _embedded field 

import pyspark.sql.types as T
 
episode_links_schema = T.StructType(
    [
        T.StructField(
            "self", T.StructType([T.StructField("href", T.StringType())]) #❶
        )
    ]
)  
  
episode_image_schema = T.StructType(
    [
        T.StructField("medium", T.StringType()),                          #❷
        T.StructField("original", T.StringType()),                        #❷
    ]
)  
  
episode_schema = T.StructType(
    [
        T.StructField("_links", episode_links_schema),                    #❸
        T.StructField("airdate", T.DateType()),
        T.StructField("airstamp", T.TimestampType()),
        T.StructField("airtime", T.StringType()),
        T.StructField("id", T.StringType()),
        T.StructField("image", episode_image_schema),                     #❸
        T.StructField("name", T.StringType()),
        T.StructField("number", T.LongType()),
        T.StructField("runtime", T.LongType()),
        T.StructField("season", T.LongType()),
        T.StructField("summary", T.StringType()),
        T.StructField("url", T.StringType()),
    ]
)
 
embedded_schema = T.StructType(
    [
        T.StructField(
            "_embedded",
            T.StructType(
                [
                    T.StructField(
                        "episodes", T.ArrayType(episode_schema)           #❹
                    )
                ]
            ),
        )
    ]
)

#########################################################################################
#
# Listing 6.18 Reading a JSON document using an explicit partial schema 

shows_with_schema = spark.read.json(
    "/mnt/spark/data/shows/shows-silicon-valley.json",
    schema=embedded_schema,                    #❶
    mode="FAILFAST",                           #❷
)

#########################################################################################
#
# Listing 6.19 Validating the airdate and airstamp field reading 

for column in ["airdate", "airstamp"]:
    shows.select(f"_embedded.episodes.{column}").select(
        F.explode(column)
    ).show(5)
 
# +----------+
# |       col|
# +----------+
# |2014-04-06|
# |2014-04-13|
# |2014-04-20|
# |2014-04-27|
# |2014-05-04|
# +----------+
# only showing top 5 rows
 
# +-------------------+
# |                col|
# +-------------------+
# |2014-04-06 22:00:00|
# |2014-04-13 22:00:00|
# |2014-04-20 22:00:00|
# |2014-04-27 22:00:00|
# |2014-05-04 22:00:00|
# +-------------------+
# only showing top 5 rows

#########################################################################################
#
# Listing 6.20 Witnessing a JSON document ingestion with incompatible schema 

from py4j.protocol import Py4JJavaError                   #❶
 
episode_schema_BAD = T.StructType(
    [
        T.StructField("_links", episode_links_schema),
        T.StructField("airdate", T.DateType()),
        T.StructField("airstamp", T.TimestampType()),
        T.StructField("airtime", T.StringType()),
        T.StructField("id", T.StringType()),
        T.StructField("image", episode_image_schema),
        T.StructField("name", T.StringType()),
        T.StructField("number", T.LongType()),
        T.StructField("runtime", T.LongType()),
        T.StructField("season", T.LongType()),
        T.StructField("summary", T.LongType()),            #❷
        T.StructField("url", T.LongType()),                #❷
     ]
)
 
embedded_schema2 = T.StructType(
    [
        T.StructField(
            "_embedded",
            T.StructType(
                [
                    T.StructField(
                        "episodes", T.ArrayType(episode_schema_BAD)
                    )
                ]
            ),
        )
    ]
)


shows_with_schema_wrong = spark.read.json(
    "/mnt/spark/data/shows/shows-silicon-valley.json",
    schema=embedded_schema2,
    mode="FAILFAST",
)
 
try:
    shows_with_schema_wrong.show()
except Py4JJavaError:
    pass
 
# Huge Spark ERROR stacktrace, relevant bit:
#
# Caused by: java.lang.RuntimeException: Failed to parse a value for data type
#   bigint (current token: VALUE_STRING).                 ❸


#########################################################################################
#
# Listing 6.21 Pretty-printing the schema 

import pprint          #❶
 
pprint.pprint(
    shows_with_schema.select(
        F.explode("_embedded.episodes").alias("episode")
    )
    .select("episode.airtime")
    .schema.jsonValue()
)
# {'fields': [{'metadata': {},
#             'name': 'airtime',
#             'nullable': True,
#             'type': 'string'}],
# 'type': 'struct'}

#########################################################################################
#
# Listing 6.22 Pretty-printing dummy complex types

pprint.pprint(
    T.StructField("array_example", T.ArrayType(T.StringType())).jsonValue()
)
 
# {'metadata': {},
#  'name': 'array_example',
#  'nullable': True,
#  'type': {'containsNull': True, 'elementType': 'string', 'type': 'array'}}❶
 
pprint.pprint(
    T.StructField(
        "map_example", T.MapType(T.StringType(), T.LongType())
    ).jsonValue()
)
 
# {'metadata': {},
#  'name': 'map_example',
#  'nullable': True,
#  'type': {'keyType': 'string',
#           'type': 'map',
#           'valueContainsNull': True,
#           'valueType': 'long'}}                                           ❷
 
pprint.pprint(
    T.StructType(
        [
            T.StructField(
                "map_example", T.MapType(T.StringType(), T.LongType())
            ),
            T.StructField("array_example", T.ArrayType(T.StringType())),
        ]
    ).jsonValue()
)
 
# {'fields': [{'metadata': {},                                              ❸
#              'name': 'map_example',
#              'nullable': True,
#              'type': {'keyType': 'string',
#                       'type': 'map',
#                       'valueContainsNull': True,
#                       'valueType': 'long'}},
#             {'metadata': {},
#              'name': 'array_example',
#              'nullable': True,
#              'type': {'containsNull': True,
#                       'elementType': 'string',
#                       'type': 'array'}}],
#  'type': 'struct'} ❶ The array types contains


#########################################################################################
#
# Listing 6.23 Validating JSON schema is equal to data frame schema 

other_shows_schema = T.StructType.fromJson(
    json.loads(shows_with_schema.schema.json())
)
 
print(other_shows_schema == shows_with_schema.schema)  # True



#########################################################################################
#
# Exercise 6.3 What is wrong with this schema? 

# schema = T.StructType([T.StringType(), T.LongType(), T.LongType()])

# all messed up, StructType takes a sequence of Structfields as args

#########################################################################################
#
# Listing 6.24 Exploding the _embedded.episodes into 53 distinct records 

episodes = shows.select(
    "id", F.explode("_embedded.episodes").alias("episodes")
)                                                              #❶
episodes.show(5, truncate=70)
 
# +---+----------------------------------------------------------------------+
# | id|                                                              episodes|
# +---+----------------------------------------------------------------------+
# |143|{{{http:/ /api.tvmaze.com/episodes/10897}}, 2014-04-06, 2014-04-07T0...|
# |143|{{{http:/ /api.tvmaze.com/episodes/10898}}, 2014-04-13, 2014-04-14T0...|
# |143|{{{http:/ /api.tvmaze.com/episodes/10899}}, 2014-04-20, 2014-04-21T0...|
# |143|{{{http:/ /api.tvmaze.com/episodes/10900}}, 2014-04-27, 2014-04-28T0...|
# |143|{{{http:/ /api.tvmaze.com/episodes/10901}}, 2014-05-04, 2014-05-05T0...|
# +---+----------------------------------------------------------------------+
# only showing top 5 rows
 
episodes.count()  # 53



#########################################################################################
#
# Listing 6.25 Exploding a map using posexplode() 

episode_name_id = shows.select(
    F.map_from_arrays(                                         #❶
        F.col("_embedded.episodes.id"), F.col("_embedded.episodes.name")
    ).alias("name_id")
)
 
episode_name_id = episode_name_id.select(
    F.posexplode("name_id").alias("position", "id", "name")    #❷
)
 
episode_name_id.show(5)
 
# +--------+-----+--------------------+
# |position|   id|                name|
# +--------+-----+--------------------+
# |       0|10897|Minimum Viable Pr...|
# |       1|10898|       The Cap Table|
# |       2|10899|Articles of Incor...|
# |       3|10900|    Fiduciary Duties|
# |       4|10901|      Signaling Risk|
# +--------+-----+--------------------+
# only showing top 5 rows

episode_name_id.printSchema()

#########################################################################################
#
# Listing 6.26 Collecting our results back into an array 

collected = episodes.groupby("id").agg(
    F.collect_list("episodes").alias("episodes")
)
 
collected.count()  # 1
 
collected.printSchema()

# |-- id: long (nullable = true)
# |-- episodes: array (nullable = true)
# |    |-- element: struct (containsNull = false)
# |    |    |-- _links: struct (nullable = true)
# |    |    |    |-- self: struct (nullable = true)
# |    |    |    |    |-- href: string (nullable = true)
# |    |    |-- airdate: string (nullable = true)
# |    |    |-- airstamp: timestamp (nullable = true)
# |    |    |-- airtime: string (nullable = true)
# |    |    |-- id: long (nullable = true)
# |    |    |-- image: struct (nullable = true)
# |    |    |    |-- medium: string (nullable = true)
# |    |    |    |-- original: string (nullable = true)
# |    |    |-- name: string (nullable = true)
# |    |    |-- number: long (nullable = true)
# |    |    |-- runtime: long (nullable = true)
# |    |    |-- season: long (nullable = true)
# |    |    |-- summary: string (nullable = true)
# |    |    |-- url: string (nullable = true)


#########################################################################################
#
# Listing 6.27 Creating a struct column using the struct function 

struct_ex = shows.select(
    F.struct(                                          #❶
         F.col("status"), F.col("weight"), F.lit(True).alias("has_watched")
    ).alias("info")
)
struct_ex.show(1, False)

# +-----------------+
# |info             |
# +-----------------+
# |{Ended, 96, true}|                                  ❷
# +-----------------+
 
struct_ex.printSchema()
# root
#  |-- info: struct (nullable = false)                 ❸
#  |    |-- status: string (nullable = true)
#  |    |-- weight: long (nullable = true)
#  |    |-- has_watched: boolean (nullable = false)


#########################################################################################
#
# Exercise 6.4 

# Why is it a bad idea to use the period or the square bracket in a column name, given 
# that you also use it to reach hierarchical entities within a data frame?
 
 
 # Ans = Very difficult to read. Also, allow column names will need to be quoted


#########################################################################################
#
# Exercise 6.5 

# Although much less common, you can create a data frame from a dictionary. Since dictionaries
# are so close to JSON documents, build the schema for ingesting the following dictionary. 
# (Both JSON or PySpark schemas are valid here.)



#########################################################################################
#
# Exercise 6.7 
# 
# Take the shows data frame and extract the air date and name of each episode in two array columns.

three_shows.select( 
    F.col("name").alias("show"),
    F.col("_embedded.episodes").alias("eps")
    ).select(
        F.col("show"),
        F.col("eps.name").alias("ename"),
        F.col("eps.airdate").alias("eairdate")
    ).show()

# similar but put the episode name and airdate into a table for each show

three_shows.select( 
    F.col("name").alias("show"),
    F.explode(F.col("_embedded.episodes")).alias("eps")
   ).groupBy(
    "show"
   ).agg(
    F.collect_list(F.col("eps.name").alias("ename")),
    F.collect_list(F.col("eps.airtime").alias("airtime"))
   ).show()
   
three_shows.select( 
    F.col("name").alias("Show"),
    F.explode(F.col("_embedded.episodes")).alias("eps")
    ).groupBy(
    "show"
    ).agg(
        F.collect_list(
            F.struct(
                F.col("eps.name").alias("ename"),
                F.col("eps.airtime").alias("airtime")
            )
        ).alias("Episode imes")
   ).show()

#########################################################################################
#



#########################################################################################
#



#########################################################################################
#



#########################################################################################
#



#########################################################################################
#



#########################################################################################
#





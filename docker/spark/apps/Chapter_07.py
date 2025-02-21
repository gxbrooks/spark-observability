
from pyspark.sql import SparkSession
from pyspark.sql.utils import AnalysisException     ❶
import pyspark.sql.functions as F
import pyspark.sql.types as T
 
spark = SparkSession.builder.getOrCreate()

#########################################################################################
#
# Listing 7.1 Reading and counting the liquid elements by period 

elements = spark.read.csv(
    "./data/elements/Periodic_Table_Of_Elements.csv",
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
try:
    spark.sql(
        "select period, count(*) from elements "
        "where phase='liq' group by period"
    ).show(5)
except AnalysisException as e:
    print(e)
 
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

Rioux, Jonathan. Data Analysis with Python and PySpark (p. 305). Manning. Kindle Edition. 


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

Rioux, Jonathan. Data Analysis with Python and PySpark (p. 309). Manning. Kindle Edition. 


#########################################################################################
#
# Listing 7.6 Reading Backblaze data into a data frame and registering a view 

DATA_DIRECTORY = "./data/backblaze/"
 
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

Rioux, Jonathan. Data Analysis with Python and PySpark (pp. 310-311). Manning. Kindle Edition. 



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




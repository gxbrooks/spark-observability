





#########################################################################################
#
# Listing 8.1 Promoting a Python list to an RDD 

from pyspark.sql import SparkSession
 
spark = SparkSession.builder.getOrCreate()
 
collection = [1, "two", 3.0, ("four", 4), {"five": 5}]             #❶
 
sc = spark.sparkContext                                            #❷
 
collection_rdd = sc.parallelize(collection)                        #❸
 
print(collection_rdd)
# ParallelCollectionRDD[0] at parallelize at PythonRDD.scala:195   ❹

#########################################################################################
#
# Listing 8.2 Mapping a simple function, add_one(), to each element 
from py4j.protocol import Py4JJavaError
def add_one(value):
    return value + 1                           #❶
 
collection_rdd = collection_rdd.map(add_one)   #❷
 
try:
    print(collection_rdd.collect())            #❸
except Py4JJavaError:
    pass
 
# Stack trace galore! The important bit, you'll get one of the following:
# TypeError: can only concatenate str (not "int") to str
# TypeError: unsupported operand type(s) for +: 'dict' and 'int'
# TypeError: can only concatenate tuple (not "int") to tuple


#########################################################################################
#
# Listing 8.3 Mapping safer_add_one() to each element in an RDD 

collection_rdd = sc.parallelize(collection)       #❶
  
def safer_add_one(value):
    try:
        return value + 1
    except TypeError:
        return value                              #❷
        
collection_rdd = collection_rdd.map(safer_add_one)
 
print(collection_rdd.collect())
# [2, 'two', 4.0, ('four', 4), {'five': 5}]

#########################################################################################
#
# Listing 8.4 Filtering our RDD with a lambda function 

collection_rdd = collection_rdd.filter(
    lambda elem: isinstance(elem, (float, int))
)
 
print(collection_rdd.collect())
# [2, 4.0]

#########################################################################################
#
Listing 8.5 Applying the add() function via reduce() 
from operator import add                #❶
collection_rdd = sc.parallelize([4, 7, 9, 1, 3])
 
print(collection_rdd.reduce(add))  # 24

#########################################################################################
#
# Exercise 8.1 
#
# The PySpark RDD API provides a count() method that returns the number of elements in 
# the RDD as an integer. Reproduce the behavior of this method using map(), filter(), 
# and/or reduce(). 

print(
    collection_rdd
    .map(
        lambda x: 1
    ).reduce(
        lambda x, y: x + y
    )
)
#########################################################################################
#
# Exercise 8.2 
# That is the return value of the following code block? 
a_rdd = sc.parallelize([0, 1, None, [], 0.0])
 
a_rdd.filter(lambda x: x).collect() 

# a) [1] # << answer because zeros, None, and empty list are all evaluateed as false
# b) [0, 1] 
# c) [0, 1, 0.0]  
# d) [] 
# e) [1, []]


#########################################################################################
#
# Listing 8.7 Creating a data frame containing a single-array column
import pyspark.sql.functions as F
import pyspark.sql.types as T
 
fractions = [[x, y] for x in range(100) for y in range(1, 100)]    #❶
 
frac_df = spark.createDataFrame(fractions, ["numerator", "denominator"])
 
frac_df = frac_df.select(
    F.array(F.col("numerator"), F.col("denominator")).alias(       #❷
        "fraction"
    ),  
)
 
frac_df.show(5, False)
# +--------+
# |fraction|
# +--------+
# |[0, 1]  |
# |[0, 2]  |
# |[0, 3]  |
# |[0, 4]  |
# |[0, 5]  |
# +--------+
# only showing top 5 rows

#########################################################################################
#
# Listing 8.8 Creating our three Python functions 

from fractions import Fraction                                     #❶
from typing import Tuple, Optional                                 #❷
 
Frac = Tuple[int, int]                                             #❸
 
 
def py_reduce_fraction(frac: Frac) -> Optional[Frac]:              #❹
    """Reduce a fraction represented as a 2-tuple of integers."""
    num, denom = frac
    if denom:
        answer = Fraction(num, denom)
        return answer.numerator, answer.denominator
    return None
assert py_reduce_fraction((3, 6)) == (1, 2)                        #❺
assert py_reduce_fraction((1, 0)) is None
 
 
def py_fraction_to_float(frac: Frac) -> Optional[float]:
    """Transforms a fraction represented as a 2-tuple of integers into a float."""
    num, denom = frac
    if denom:
        return num / denom
    return None
 
 
assert py_fraction_to_float((2, 8)) == 0.25
assert py_fraction_to_float((10, 0)) is None

#########################################################################################
#
# Listing 8.9 Creating a UDF explicitly with the udf() function

SparkFrac = T.ArrayType(T.LongType())                        #❶
  
reduce_fraction = F.udf(py_reduce_fraction, SparkFrac)       #❷
  
frac_df = frac_df.withColumn(
    "reduced_fraction", reduce_fraction(F.col("fraction"))   #❸
)
 
frac_df.show(5, False)
# +--------+----------------+
# |fraction|reduced_fraction|
# +--------+----------------+
# |[0, 1]  |[0, 1]          |
# |[0, 2]  |[0, 1]          |
# |[0, 3]  |[0, 1]          |
# |[0, 4]  |[0, 1]          |
# |[0, 5]  |[0, 1]          |
# +--------+----------------+
# only showing top 5 rows

#########################################################################################
#
# Listing 8.10 Creating a UDF directly using the udf() decorator 

@F.udf(T.DoubleType())                                  #❶
def fraction_to_float(frac: Frac) -> Optional[float]:
    """Transforms a fraction represented as a 2-tuple of integers into a float."""
    num, denom = frac
    if denom:
        return num / denom
    return None
 
 
frac_df = frac_df.withColumn(
    "fraction_float", fraction_to_float(F.col("reduced_fraction"))
)
 
frac_df.select("reduced_fraction", "fraction_float").distinct().show(
    5, False
)
# +----------------+-------------------+
# |reduced_fraction|fraction_float     |
# +----------------+-------------------+
# |[3, 50]         |0.06               |
# |[3, 67]         |0.04477611940298507|
# |[7, 76]         |0.09210526315789473|
# |[9, 23]         |0.391304347826087  |
# |[9, 25]         |0.36               |
# +----------------+-------------------+
# only showing top 5 rows
assert fraction_to_float.func((1, 2)) == 0.5            #❷

#########################################################################################
#
# Exercise 8.3 

# Using the following definitions, create a temp_to_temp(value, from, to) 
# that takes a numerical value in from degrees and converts it to degrees. 
    # C = (F - 32) * 5 / 9 (Celsius) 
    # K = C + 273.15 (Kelvin)
    # R = F + 459.67 (Rankine)

@F.udf(T.DoubleType()) 
def F_to_C(f: float) -> [float]:
    return (f - 32) * 5 / 9
    
@F.udf(T.DoubleType()) 
def C_to_K(c: float) -> [float]:
    return c + 273.15
    
@F.udf(T.DoubleType()) 
def F_to_R(f: float) -> [float]:
    return f + 459.67
    


#########################################################################################
#
# Exercise 8.4 Correct the following UDF, so it doesn’t generate an error. 

@F.udf(T.IntegerType())
def naive_udf(t: str) -> str:
    return answer * 3.14159

@F.udf(T.IntegerType())
def naive_udf(t: int) -> float:
    return t * 3.14159
    
assert naive_udf.func(1) == 3.14159

#########################################################################################
#
# Exercise 8.5 
# Create a UDF that adds two fractions together, and test it by adding the 
# reduced_ fraction to itself in the test_frac data frame.

@F.udf(SparkFrac, SparkFrac)                                  #❶
def add_fractions(f1: Frac, f2: Frac) -> Frac:
    """Transforms a fraction represented as a 2-tuple of integers into a float."""
    f1_num, f1_denom = f1
    f2_num, f2_denom = f2

    return (f1_num + f2_num,  f1_denom + f2_denom)    

assert add_fractions.func((1,2), (3, 4)) == (4, 6)

#########################################################################################
#
# Exercise 8.6 
# Because of the LongType(), the py_reduce_fraction (see the previous exercise) will 
# not work if the numerator or denominator exceeds pow(2, 63)-1 or is lower than -pow(2, 63). 
# Modify the py_reduce_fraction to return None if this is the case.

# Since python 3, you no longer need to worry about the size of an int. It will grow to the
# size of available memory

#########################################################################################
#

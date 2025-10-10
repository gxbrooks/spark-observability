#!/usr/bin/env python3
"""
Spark IPython Client for Remote Cluster Connection

This module provides a PySpark client that connects to a remote Spark cluster
running in Kubernetes, allowing local development with remote execution.
"""

import os
import sys
from pyspark.sql import SparkSession
import IPython


class SparkIPythonClient:
    """Client for connecting to remote Spark cluster from local IPython."""
    
    def __init__(self, master_url=None, app_name="LocalDevelopment"):
        """
        Initialize the Spark IPython client.
        
        Args:
            master_url (str): Spark master URL (e.g., "spark://Lab2.lan:32582")
            app_name (str): Application name for the Spark session
        """
        self.master_url = master_url or os.getenv('SPARK_MASTER_URL', 'spark://Lab2.lan:32582')
        self.app_name = app_name
        self.spark = None
        
    def connect(self):
        """Create and return a Spark session connected to the remote cluster."""
        print('Creating Spark session...')
        
        self.spark = SparkSession.builder \
            .appName(self.app_name) \
            .master(self.master_url) \
            .getOrCreate()
            
        print('Spark session created successfully!')
        print('Spark version:', self.spark.version)
        print('Spark master:', self.spark.sparkContext.master)
        print('Available methods: spark.sql, spark.read, etc.')
        print('You can now run Spark code that executes on the remote cluster!')
        
        return self.spark
    
    def launch_ipython(self):
        """Launch IPython with the Spark session available."""
        if not self.spark:
            self.connect()
        
        # Make spark available in the global namespace
        import builtins
        builtins.spark = self.spark
        
        # Launch IPython
        IPython.embed()


def main():
    """Main entry point for the Spark IPython client."""
    import argparse
    
    parser = argparse.ArgumentParser(description='Launch IPython with Spark cluster connection')
    parser.add_argument('--master', help='Spark master URL')
    parser.add_argument('--app-name', default='LocalDevelopment', help='Application name')
    
    args = parser.parse_args()
    
    client = SparkIPythonClient(master_url=args.master, app_name=args.app_name)
    client.launch_ipython()


if __name__ == '__main__':
    main()

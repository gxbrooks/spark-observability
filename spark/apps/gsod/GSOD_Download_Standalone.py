#!/usr/bin/env python3
"""
Standalone NOAA GSOD Data Downloader

Downloads 10 years of NOAA GSOD data from BigQuery without using Spark,
then writes to Parquet format in two formats:
1. Single combined file: /mnt/spark/data/gsod_data.parquet
2. Individual year files: /mnt/spark/data/gsod_noaa/gsod{year}.parquet

Usage:
    python3 GSOD_Download_Standalone.py

Environment Variables:
    TEST_MODE=1  - Download only one year (2023) for testing
    FORCE=1      - Force re-download even if files already exist
"""

import os
import json
from pathlib import Path
from datetime import datetime
import pandas as pd
from google.cloud import bigquery
from google.oauth2 import service_account


def get_noaa_gsod_data(year, client):
    """
    Reads data from a single year of the NOAA GSOD dataset.

    Args:
        year (int): The year to read data for.
        client (bigquery.Client): The BigQuery client object.

    Returns:
        pandas.DataFrame: A DataFrame containing the data for the specified year.
    """
    # Query all columns (matching original Spark version)
    query = f"""
    SELECT *
    FROM `bigquery-public-data.noaa_gsod.gsod{year}`
    """
    
    print(f"  Querying BigQuery for year {year}...")
    query_job = client.query(query)
    
    # Show progress for large queries
    print(f"  Job ID: {query_job.job_id}")
    print(f"  Waiting for query to complete (this may take a few minutes)...")
    
    # Wait for the query to complete
    query_job.result()
    
    print(f"  Fetching results...")
    # Use BigQuery Storage API if available for faster downloads
    try:
        df = query_job.to_dataframe(progress_bar_type='tqdm')
    except Exception:
        # Fallback if tqdm not available
        df = query_job.to_dataframe()
    print(f"  Retrieved {len(df):,} rows for {year}")
    
    # Align types with the types expected in the book 
    # Rioux, Jonathan. Data Analysis with Python and PySpark Manning. Kindle Edition.
    
    # Convert to appropriate types
    df['year'] = pd.to_numeric(df['year'], errors='coerce').astype('Int64')
    df['mo'] = pd.to_numeric(df['mo'], errors='coerce').astype('Int64')
    df['da'] = pd.to_numeric(df['da'], errors='coerce').astype('Int64')
    df['temp'] = pd.to_numeric(df['temp'], errors='coerce').astype('float64')
    
    # Drop rows with nulls in required columns
    df = df.dropna(subset=['year', 'mo', 'da', 'temp'])
    
    # Clean up data over 1M rows with stn = "999999"
    df = df[(df['temp'] != 9999.9) & (df['stn'] != '999999')]
    
    # Create a 'date' column if it doesn't exist
    # apparently more recent years have a date column
    # Note: Convert to date (not datetime) to avoid nanosecond precision issues with Spark 4.0.1
    if 'date' in df.columns:
        df['date'] = pd.to_datetime(df['date'], errors='coerce').dt.date
    else:
        # Create date from year, mo, da
        df['date'] = pd.to_datetime(
            df[['year', 'mo', 'da']].apply(
                lambda x: f"{int(x['year'])}-{int(x['mo']):02d}-{int(x['da']):02d}" 
                if pd.notna(x['year']) and pd.notna(x['mo']) and pd.notna(x['da']) 
                else None, axis=1
            ),
            errors='coerce'
        ).dt.date
    
    # Drop rows where date creation failed
    df = df.dropna(subset=['date'])
    
    return df


def main():
    """Main function to download and process NOAA GSOD data."""
    
    # Determine API key path based on execution context
    script_dir = Path(__file__).parent
    api_key_path = script_dir / "bq-api-key.json"
    
    # Check if running in cluster (keyfile exists at cluster path) or client mode
    if Path('/opt/spark/apps/bq-api-key.json').exists():
        api_key_path = Path('/opt/spark/apps/bq-api-key.json')
    elif not api_key_path.exists():
        raise FileNotFoundError(
            f"BigQuery API key not found at {api_key_path} or /opt/spark/apps/bq-api-key.json"
        )
    
    print(f"Using BigQuery API key: {api_key_path}")
    
    # Load credentials and create BigQuery client
    credentials = service_account.Credentials.from_service_account_file(
        str(api_key_path),
        scopes=["https://www.googleapis.com/auth/bigquery"]
    )
    client = bigquery.Client(credentials=credentials, project=credentials.project_id)
    
    # Test mode: Set TEST_MODE environment variable to download just one year
    test_mode = os.environ.get('TEST_MODE', '0') == '1'
    
    if test_mode:
        print("=" * 60)
        print("TEST MODE: Downloading single year (2023) to verify API key")
        print("=" * 60)
        # Test with just one year
        test_year = 2023
        print(f"Downloading data for year {test_year}...")
        df = get_noaa_gsod_data(test_year, client)
        print(f"Successfully downloaded {len(df)} records for {test_year}")
        print("\nFirst 5 rows:")
        print(df.head())
        print("\nDataFrame info:")
        print(df.info())
        print("=" * 60)
        print("TEST PASSED: API key is valid and function works correctly")
        print("To download all years, run without TEST_MODE=1")
        print("=" * 60)
    else:
        # Define years to read data from (2014-2023, 10 years)
        years = range(2014, 2024)
        force_download = os.environ.get('FORCE', '0') == '1'
        
        # Output paths
        single_file_path = Path("/mnt/spark/data/gsod_data.parquet")
        year_files_dir = Path("/mnt/spark/data/gsod_noaa")
        year_files_dir.mkdir(parents=True, exist_ok=True)
        
        # Check if files already exist
        single_file_exists = single_file_path.exists()
        year_files_exist = all((year_files_dir / f"gsod{year}.parquet").exists() for year in years)
        
        if not force_download and single_file_exists and year_files_exist:
            print("=" * 60)
            print("All GSOD data files already exist.")
            print(f"Single file: {single_file_path}")
            print(f"Year files: {year_files_dir}/gsod{{year}}.parquet")
            print("Set FORCE=1 to re-download all data.")
            print("=" * 60)
            return
        
        print(f"Downloading NOAA GSOD data for years {years[0]} to {years[-1]} ({len(years)} years)")
        if force_download:
            print("FORCE mode: Re-downloading all data")
        print()
        
        # Download data for each year
        dataframes = []
        for year in years:
            year_file_path = year_files_dir / f"gsod{year}.parquet"
            
            # Skip if file exists and not forcing
            if not force_download and year_file_path.exists():
                print(f"Year {year}: File already exists, skipping download")
                print(f"  Loading from {year_file_path}...")
                year_df = pd.read_parquet(year_file_path)
                print(f"  Loaded {len(year_df):,} records")
            else:
                print(f"Processing year {year}...")
                year_df = get_noaa_gsod_data(year, client)
                print(f"  Processed {len(year_df):,} records")
                
                # Save individual year file
                # Convert date to string to avoid Spark 4.0.1 timestamp precision issues
                print(f"  Saving to {year_file_path}...")
                year_df_export = year_df.copy()
                if 'date' in year_df_export.columns:
                    year_df_export['date'] = year_df_export['date'].astype(str)
                year_df_export.to_parquet(
                    year_file_path,
                    engine='pyarrow',
                    compression='snappy',
                    index=False
                )
                year_file_size = year_file_path.stat().st_size / (1024 * 1024)  # Size in MB
                print(f"  Saved {len(year_df):,} records ({year_file_size:.2f} MB)")
            
            dataframes.append(year_df)
            print()
        
        # Combine all DataFrames
        print("Combining all years...")
        combined_df = pd.concat(dataframes, ignore_index=True)
        total_count = len(combined_df)
        print(f"Total records across all years: {total_count:,}")
        
        # Show the first few rows
        print("\nSample data (first 5 rows):")
        print(combined_df.head())
        print("\nDataFrame info:")
        print(combined_df.info())
        
        # Save as single combined Parquet file (if not exists or forcing)
        if force_download or not single_file_exists:
            print(f"\nSaving combined file to {single_file_path}...")
            # Convert date to string to avoid Spark 4.0.1 timestamp precision issues
            combined_df_export = combined_df.copy()
            if 'date' in combined_df_export.columns:
                combined_df_export['date'] = combined_df_export['date'].astype(str)
            combined_df_export.to_parquet(
                single_file_path,
                engine='pyarrow',
                compression='snappy',
                index=False
            )
            
            # Verify file was created
            file_size = single_file_path.stat().st_size / (1024 * 1024)  # Size in MB
            print(f"Successfully saved {total_count:,} records to {single_file_path}")
            print(f"File size: {file_size:.2f} MB")
        else:
            print(f"\nSingle combined file already exists: {single_file_path}")
            print("Set FORCE=1 to overwrite.")
        
        print("\nDone!")
        print(f"\nFiles created:")
        print(f"  Single file: {single_file_path}")
        print(f"  Year files: {year_files_dir}/gsod{{year}}.parquet (for years {years[0]}-{years[-1]})")


if __name__ == "__main__":
    main()


# gridMET Normals

This repository contains R scripts for downloading, processing, and calculating climate normals from [gridMET](http://www.climatologylab.org/gridmet.html) daily gridded surface meteorological data.

## Overview

The `gridmet-normals.r` script performs three main tasks:

1. **Downloads gridMET daily data** - Mirrors the gridMET archive from the Northwest Knowledge Network server
2. **Calculates temporal aggregations** - Computes monthly and yearly summaries from daily data
3. **Generates climate normals** - Calculates 30-year normal statistics using gamma distribution fitting

The resulting normals are saved as Cloud Optimized GeoTIFFs (COGs) for efficient spatial data access.

## Prerequisites

### System Requirements

- R
- `rclone` command-line tool for downloading data

### R Package Dependencies

The script requires the following R packages:

- `tidyverse` - Data manipulation and visualization
- `magrittr` - Pipe operators (loaded explicitly, though included in tidyverse)
- `sf` - Spatial features handling
- `terra` - Spatial data processing
- `normals` - Custom package for calculating climate normals (from `mt-climate-office/normals`)
- `digest` - File checksumming
- `furrr` - Parallel processing with futures
- `future.mirai` - Parallel backend
- `mirai` - Asynchronous processing

## Installation

### Option 1: Docker (Recommended)

The easiest way to run this project is using Docker, which provides a consistent environment with all dependencies pre-installed.

1. Clone this repository:
```bash
git clone https://github.com/mt-climate-office/gridmet-normals.git
cd gridmet-normals
```

2. Build and run using Docker Compose:
```bash
docker compose up --build
```

The `data/` directory will be created locally and mounted into the container to persist downloaded data and outputs.

### Option 2: Local R Installation

1. Clone this repository:
```bash
git clone https://github.com/mt-climate-office/gridmet-normals.git
cd gridmet-normals
```

2. Open the R project file `gridmet-normals.Rproj` in RStudio, or start R in the project directory.

3. Install required packages by running the first section of `gridmet-normals.r`:
```r
pak::pak(
  c(
    "tidyverse",
    "sf?source",
    "terra?source",
    "mt-climate-office/normals",
    "digest",
    "furrr",
    "future.mirai",
    "mirai"
  )
)
```

## Usage

### Running with Docker

**One-time execution:**
```bash
docker compose up
```

**Automated daily execution with cron:**

1. Make the run script executable (if not already):
```bash
chmod +x run-cron.sh
```

2. Add a cron job to run daily at 2 AM:
```bash
crontab -e
```

Add this line (adjust the path to match your installation):
```
0 2 * * * /path/to/gridmet-normals/run-cron.sh
```

**Manual Docker run without compose:**
```bash
docker build -t gridmet-normals .
docker run -v $(pwd)/data:/app/data gridmet-normals
```

### Running with GitHub Actions / act

This repository includes a GitHub Actions workflow that can be run locally using [act](https://github.com/nektos/act). This allows you to execute the workflow in a local environment without using GitHub-hosted runners. The workflow sets up the R environment and all dependencies directly through GitHub Actions steps, without requiring Docker.

**Prerequisites:**
- Install [act](https://github.com/nektos/act) following the instructions at https://github.com/nektos/act

**Run the workflow locally:**
```bash
act workflow_dispatch
```

The workflow will:
1. Install Homebrew
2. Install dependencies via Homebrew (R, rclone, NetCDF, GDAL, GEOS, PROJ, udunits)
3. Install required R packages (tidyverse, sf, terra, normals, etc.)
4. Run the gridMET normals processing script
5. Save results to the `data/` directory
6. Create an artifact with the processed data

**Note:** The workflow is configured with `workflow_dispatch` trigger only, meaning it must be triggered manually and will not run automatically on GitHub-hosted runners.

### Running with Local R Installation

Run the entire script to process gridMET data:

```r
source("gridmet-normals.r")
```

Or run sections individually in an interactive R session.

### Workflow Details

#### 1. Download gridMET Archive

The script downloads daily gridMET NetCDF files from:
```
https://www.northwestknowledge.net/metdata/data/
```

Files are saved to `data/gridmet/daily/` and include:
- Energy Release Component (erc)
- Reference Evapotranspiration (etr, pet)
- Precipitation (pr)
- Relative Humidity (rmax, rmin)
- Specific Humidity (sph)
- Solar Radiation (srad)
- Wind Speed (vs)
- Temperature (th, tmmn, tmmx)
- Vapor Pressure Deficit (vpd)

The download uses checksums to track file changes and only processes updated files on subsequent runs.

#### 2. Calculate Temporal Aggregations

Daily data is aggregated to:
- **Monthly** - Saved to `data/gridmet/monthly/`
- **Yearly** - Saved to `data/gridmet/yearly/`

Aggregation functions:
- **Sum**: precipitation (pr), evapotranspiration (etr, pet)
- **Mean**: all other variables

#### 3. Generate Climate Normals

Climate normals are calculated using the most recent complete 30 years of data:
- Monthly normals (e.g., January, February, ..., December)
- Annual normals

The script:
- Excludes the current incomplete month/year
- Uses the 30 most recent complete years
- Fits gamma distributions to the data
- Outputs Cloud Optimized GeoTIFFs to `data/gridmet/normals/`

## Output

The script generates several types of output files:

### Data Directory Structure
```
data/
├── gridmet/
│   ├── daily/              # Raw daily NetCDF files from gridMET
│   ├── daily.checksum      # Checksums for change tracking
│   ├── monthly/            # Monthly aggregated NetCDF files
│   ├── yearly/             # Yearly aggregated NetCDF files
│   └── normals/            # Climate normals as COG files
```

### Normal Files

Normal files are named following this pattern:
```
{variable}_{year_range}_{period}_data.tif
{variable}_{year_range}_{period}_shape.tif
{variable}_{year_range}_{period}_scale.tif
```

Where:
- `{variable}`: Climate variable (e.g., pr, tmmx, tmmn)
- `{year_range}`: Range of years used (e.g., 1995–2024, dynamically calculated from the 30 most recent complete years)
- `{period}`: Either a month name or "annual"

## Data Source

This project uses [gridMET](http://www.climatologylab.org/gridmet.html) data, a high-resolution gridded surface meteorological dataset covering the contiguous United States at ~4km resolution from 1979 to present.

**Citation:**
Abatzoglou, J.T., 2013. Development of gridded surface meteorological data for ecological applications and modeling. International Journal of Climatology, 33(1), pp.121-131.

## License

This project is developed by the [Montana Climate Office](https://climate.umt.edu/).

## Contributors

See git commit history for contributor information.

## Notes

- The script uses parallel processing to speed up calculations
- Incremental updates are supported via checksumming - only new/changed files are processed
- Cloud Optimized GeoTIFF format enables efficient web-based access to normals data
- The current incomplete month and year are automatically excluded from normal calculations

# Use rocker/geospatial as base - includes R, sf, terra dependencies (GDAL, PROJ, GEOS)
FROM rocker/geospatial:4

# Install wget2 and other system dependencies
RUN apt-get update && apt-get install -y \
    wget2 \
    libnetcdf-dev \
    netcdf-bin \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy R script and project files
COPY gridmet-normals.r /app/
COPY gridmet-normals.Rproj /app/

# Install R packages
# Using pak for faster package installation
RUN R -e "install.packages('pak', repos = 'https://r-lib.github.io/p/pak/stable/')" && \
    R -e "pak::pak(c( \
      'tidyverse', \
      'sf?source', \
      'terra?source', \
      'digest', \
      'furrr', \
      'future.mirai', \
      'mirai', \
      'carrier' \
    ))" && \
    R -e "pak::pak(c( \
      'mt-climate-office/normals' \
    ))"

# Create data directory with appropriate permissions
RUN mkdir -p /app/data/gridmet

# Set environment variable to avoid interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Default command runs the R script
CMD ["Rscript", "gridmet-normals.r"]

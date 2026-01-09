# pak::pak(
#   c(
#     "tidyverse",
#     "sf?source",
#     "terra?source",
#     "digest",
#     "furrr",
#     "future.mirai",
#     "mirai",
#     "carrier"
#   )
# )
# 
# pak::pak("mt-climate-office/normals")

library(normals)
library(magrittr)
library(sf)
library(terra)
library(furrr)

## 1. Update gridMET archive
dir.create(
  "data/gridmet/daily",
  showWarnings = FALSE,
  recursive = TRUE
)

gridmet_archive <-
  "https://www.northwestknowledge.net/metdata/data/"

system2(
  "rclone",
  args = c(
    'sync',
    ' :http: data/gridmet/daily',
    '--http-url', gridmet_archive,
    '--filter "- *chill_hours*"',
    '--filter "+ *_[0-9][0-9][0-9][0-9].nc"',
    '--filter "- *"',
    '--max-depth 1',
    '--transfers 8',
    '--multi-thread-streams 8',
    '--multi-thread-cutoff 64M'#,
    # '--dry-run',
    # '--stats 0',
    # '--verbose'
  ),
  env = c(
    "RCLONE_CONFIG=/dev/null"
  )
)

## 2. Calculate monthly aggregates
gridmet_daily <-
  list.files(
    "data/gridmet/daily",
    full.names = TRUE,
    recursive = TRUE
  ) %>%
  tibble::tibble(file = .) %>%
  dplyr::rowwise() %>%
  dplyr::mutate(
    checksum =
      file.info(file) %>%
      digest::digest()
  ) %>%
  dplyr::ungroup()

# Which files have changed?
# We will only calculate statistics for those that have changed.
if(!file.exists("data/gridmet/daily.checksum")){
  gridmet_daily <-
    gridmet_daily %T>%
    readr::write_csv("data/gridmet/daily.checksum") %>%
    dplyr::mutate(process = TRUE)
} else {
  gridmet_daily %<>%
    dplyr::left_join(
      readr::read_csv("data/gridmet/daily.checksum"),
      by = "file",
      suffix = c("", ".old")) %>%
    dplyr::mutate(process = checksum != checksum.old) %T>%
    {
      dplyr::select(., !c(checksum.old, process)) %>%
        readr::write_csv("data/gridmet/daily.checksum")
    }
}

# Force Processing
gridmet_daily %<>%
  dplyr::mutate(process = TRUE)

# Calculate monthly and yearly aggregations
dir.create(
  "data/gridmet/monthly",
  showWarnings = FALSE,
  recursive = TRUE
)

dir.create(
  "data/gridmet/yearly",
  showWarnings = FALSE,
  recursive = TRUE
)

aggregate_timestep <-
  function(x, func, timestep = "monthly", force = FALSE){
    
    outfile <-
      stringr::str_replace(x, "daily", timestep)
    
    if(file.exists(outfile) & !force)
      return(outfile)
    
    orig <- 
      terra::rast(x) %>%
      {
        terra::`time<-`(
          .,
          lubridate::as_date(terra::depth(.), origin = "1900-01-01")
        )
      } 
    
    return(
      terra::tapp(
        orig,
        index = ifelse(timestep == "monthly", "yearmonths", "years"),
        fun = func
      ) %>%
        terra::`varnames<-`(terra::varnames(orig)) %>%
        terra::`units<-`(terra::units(orig)[1]) %>%
        terra::writeCDF(filename = outfile,
                        overwrite = TRUE,
                        compression = 9) %>%
        terra::sources() %>%
        fs::path_rel()
    )
  }

future::plan(future.mirai::mirai_multisession(workers = 8))

gridmet_summaries <-
  gridmet_daily %>%
  dplyr::mutate(
    variable_year =
      file %>%
      basename() %>%
      tools::file_path_sans_ext()
  ) %>%
  tidyr::separate_wider_delim(
    cols = variable_year,
    delim = "_",
    names = c("variable", "year")
  ) %>%
  dplyr::arrange(variable, year) %>%
  dplyr::filter(
    variable %in%
      c("erc", "etr", "pet", "pr",
        "rmax", "rmin",
        "sph", "srad",
        "th", "tmmn", "tmmx",
        "vpd", "vs")) %>%
  dplyr::mutate(
    func =
      dplyr::case_match(
        variable,
        c("pr", "etr", "pet") ~ "sum",
        .default = "mean")
  ) %>%
  dplyr::filter(process) %>%
  dplyr::mutate(
    monthly = furrr::future_map2_chr(file, func, aggregate_timestep, timestep = "monthly", force = TRUE),
    yearly = furrr::future_map2_chr(file, func, aggregate_timestep, timestep = "yearly", force = TRUE)
  )

future::plan(sequential)

## Calculate Normals
mirai::daemons(8)

dir.create(
  "data/gridmet/normals",
  showWarnings = FALSE,
  recursive = TRUE
)

gridmet_normals <-
  dplyr::bind_rows(
    tibble::tibble(
      file = list.files(
        "data/gridmet/monthly",
        full.names = TRUE,
        recursive = TRUE
      ),
      timestep = "monthly"
    ),
    tibble::tibble(
      file = list.files(
        "data/gridmet/yearly",
        full.names = TRUE,
        recursive = TRUE
      ),
      timestep = "yearly"
    )
  ) %>%
  dplyr::mutate(
    variable_year =
      file %>%
      basename() %>%
      tools::file_path_sans_ext()
  ) %>%
  tidyr::separate_wider_delim(
    cols = variable_year,
    delim = "_",
    names = c("variable", "year")
  ) %>%
  dplyr::arrange(variable, dplyr::desc(year)) %>%
  dplyr::rowwise() %>%
  dplyr::mutate(
    rast = list(
      terra::rast(file) %>%
        terra::as.list() %>%
        tibble::tibble(rast = .))
  ) %>%
  tidyr::unnest(rast) %>%
  dplyr::rowwise() %>%
  dplyr::mutate(
    year = terra::time(rast, format = "years"),
    month = ifelse(timestep == "monthly", terra::time(rast, format = "months"), NA)
  ) %>%
  dplyr::ungroup() %>%
  dplyr::filter(
    !(
      year == lubridate::year(lubridate::today()) & 
        (month == lubridate::month(lubridate::today()) | is.na(month))
    )
  ) %>%
  dplyr::arrange(variable, month, dplyr::desc(year)) %>%
  dplyr::group_by(variable, month) %>%
  dplyr::slice_head(n = 30) %>%
  dplyr::summarise(
    rast = list(
      terra::rast(rast)
    ),
    .groups = "drop"
  ) %>%
  dplyr::mutate(
    month = tidyr::replace_na(as.character(month), "annual"),
    descriptor = terra::time(rast, format = "years") %>%
      range() %>%
      paste(collapse = "–") %>%
      glue::glue("{variable}_",., "_{month}"),
    rast = 
      purrr::map2_chr(
        rast, descriptor,
        \(x,n){
          outfile <- file.path("data/gridmet/normals", paste0(n, "_data.tif"))
          if(!file.exists(outfile))
            normals::write_as_cog(x = x, filename = outfile)
          return(outfile)
        }
      )
  ) %>%
  dplyr::mutate(
    normals = 
      purrr::pmap(
        .l = list(rast, descriptor),
        .f = purrr::in_parallel(
          \(x, y){
            normals::gamma_from_rast(
              terra::rast(x),
              out_dir = "data/gridmet/normals",
              descriptor = y
            )
          }
        )
      )
  )

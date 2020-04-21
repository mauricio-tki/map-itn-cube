###############################################################################################################
## test_dsub_from_instance.r
## Amelia Bertozzi-Villa
## July 2019
## 
## Create and submit a dsube command for each year of predict_rasters

## NB: This script requires an immense amount of memory, only rerun it if you absolutely must.
##############################################################################################################


# dsub --provider google-v2 --project map-special-0001 --disk-size 400 --boot-disk-size 50 --image eu.gcr.io/map-special-0001/map-geospatial  --regions europe-west1 --label "type=itn_cube" --machine-type n1-standard-1  --logging gs://map_users/amelia/itn/itn_cube/logs --input CODE=gs://map_users/amelia/itn/code/generate_cube/test_dsub_from_instance.r --command 'Rscript ${CODE}'


years <- 2020:2021

func_dir <- "/Users/bertozzivill/repos/map-itn-cube/generate_cube/"

# options 
machine_type <- "n1-standard-8"
label <- "'type=itn_cube'"
disk_size <- 400
boot_disk_size <- 50

cloud_func_dir <- "gs://map_users/amelia/itn/code/generate_cube/"

core_cov_dir <- "gs://map_users/amelia/itn/itn_cube/results/covariates"
cov_label <- "20200401"
cov_dir <- file.path(core_cov_dir, cov_label)

stockflow_dir <- "gs://map_users/amelia/itn/stock_and_flow/results/"
stockflow_label <- "20200418_BMGF_ITN_C1.00_R1.00_V2"

core_dir <- "gs://map_users/amelia/itn/itn_cube/"
cube_indir_label <- "20200420_BMGF_ITN_C1.00_R1.00_V2_test_new_prediction"
cube_outdir_label <- cube_indir_label

# machine options
dsub_str <- "dsub --provider google-v2 --project map-special-0001 --image eu.gcr.io/map-special-0001/map-geospatial --regions europe-west1"
label_str <- paste("--label", label)
machine_str <- paste("--machine-type", machine_type)
disk_str <- paste("--disk-size", disk_size)
boot_disk_str <- paste("--boot-disk-size", boot_disk_size)

# directories
logging_str <- paste("--logging", paste0(core_dir, "logs"))

output_dir_str <- paste("--output-recursive", paste0("main_outdir=", core_dir, "results/", cube_outdir_label))

input_dir_str <- paste("--input-recursive", 
                       paste0("input_dir=", core_dir, "input_data"),
                       paste0("indicators_indir=", stockflow_dir, stockflow_label, "/for_cube"),
                       paste0("main_indir=", core_dir, "results/", cube_indir_label),
                       paste0("func_dir=", cloud_func_dir)
                       )

# year-specific submission:

for (this_year in years){
  print(paste("submitting for", this_year))
  
  input_str <- paste("--input", 
                     paste0("static_cov_dir=", cov_dir, "/static_covariates.csv"),
                     paste0("annual_cov_dir=", cov_dir, "/annual_covariates.csv"),
                     paste0("dynamic_cov_dir=", cov_dir, "/dynamic_covariates/dynamic_", this_year, ".csv"),
                     paste0("run_individually=", cloud_func_dir, "run_individually.txt"),
                     paste0("CODE=", cloud_func_dir, "04_predict_rasters.r")
  )
  
  final_str <- paste0("--command 'Rscript ${CODE} ",  this_year, "' ")
  
  full_dsub_str <- paste(dsub_str, label_str, machine_str, disk_str, boot_disk_str, logging_str, input_str, input_dir_str, output_dir_str, final_str)
  
  system(full_dsub_str, wait=F)
  Sys.sleep(2)
  
}







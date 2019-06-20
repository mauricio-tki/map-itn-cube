
###############################################################################################################
## view_changes.r
## Amelia Bertozzi-Villa
## June 2019
## 
## For bug fix and update runs: see how these changes impact either the original, or any other, run. 
## 
##############################################################################################################

# dsub --provider google-v2 --project my-test-project-210811 --image gcr.io/my-test-project-210811/map_geospatial --regions europe-west1 --label "type=itn_cube" --machine-type n1-standard-16 --logging gs://map_data_z/users/amelia/logs --input-recursive new_dir=gs://map_data_z/users/amelia/itn_cube/results/20190619_new_emplogit func_dir=gs://map_data_z/users/amelia/itn_cube/code/generate_cube old_dir=gs://map_data_z/users/amelia/itn_cube/results/20190614_rearrange_scripts --input CODE=gs://map_data_z/users/amelia/itn_cube/code/generate_cube/view_changes.r --output out_path=gs://map_data_z/users/amelia/itn_cube/results/20190619_new_emplogit/05_predictions/compare_changes.pdf --command 'Rscript ${CODE}'

rm(list=ls())

package_load <- function(package_list){
  # package installation/loading
  new_packages <- package_list[!(package_list %in% installed.packages()[,"Package"])]
  if(length(new_packages)) install.packages(new_packages)
  lapply(package_list, library, character.only=T)
}

package_load(c( "raster", "data.table", "rasterVis", "stats", "RColorBrewer", "gridExtra", "ggplot2"))

if(Sys.getenv("func_dir")=="") {
  new_dir <- "/Volumes/GoogleDrive/My Drive/itn_cube/results/20190620_drop_gaps/"
  old_dir <- "/Volumes/GoogleDrive/My Drive/itn_cube/results/20190619_new_emplogit/"
  out_path <- file.path(new_dir, "05_predictions/view_changes.pdf")
  func_dir <- "/Users/bertozzivill/repos/map-itn-cube/generate_cube/"
} else {
  new_dir <- Sys.getenv("new_dir")
  old_dir <- Sys.getenv("old_dir")
  out_path <- Sys.getenv("out_path") 
  func_dir <- Sys.getenv("func_dir") # code directory for function scripts
}

source(file.path(func_dir, "check_file_similarity.r"))

append_dts <- function(old, new){
  old[, type:="Old"]
  new[, type:="New"]
  return(rbind(old, new))
}


pdf(out_path, width=11, height=7)

## 01: check stock and flow

new_stockflow_means <- fread(file.path(new_dir, "01_stock_and_flow_probs_means.csv"))
old_stockflow_means <- fread(file.path(old_dir, "01_stock_and_flow_probs_means.csv"))
all_means <- append_dts(old_stockflow_means, new_stockflow_means)
all_means[, hh_size:=factor(hh_size)]
all_means[, prob_any_net:=1-stockflow_prob_no_nets]

means_plot <- ggplot(all_means, aes(x=year, y=stockflow_mean_nets_per_hh, color=hh_size)) +
              geom_line(aes(linetype=type)) +
              facet_wrap(~iso3) +
              labs(title="Stock and Flow: Mean Nets Per HH",
                   y="Mean Nets")
print(means_plot)

probs_plot <- ggplot(all_means, aes(x=year, y=prob_any_net, color=hh_size)) +
              geom_line(aes(linetype=type)) +
              facet_wrap(~iso3) +
              labs(title="Stock and Flow: Prob(Any Nets)",
                   y="Prob(Any Nets)")
print(probs_plot)

new_stockflow_access <- fread(file.path(new_dir, "01_stock_and_flow_access.csv") )
old_stockflow_access <- fread(file.path(old_dir, "01_stock_and_flow_access_continent_dist.csv"))
all_stockflow_access <- append_dts(old_stockflow_access, new_stockflow_access)

all_stockflow_access[, time:=year + (month-1)/12] # temp until you get a "time" var throughout
stockflow_access_plot <- ggplot(all_stockflow_access, aes(x=time, y=nat_access, color=type)) +
                          geom_line() +
                          facet_wrap(~iso3) +
                          labs(title="Stock and Flow Access",
                               y="National Access")


## 02: check survey data --TODO plots
print("comparing old and new data files")
new_data <- fread(file.path(new_dir, "02_survey_data.csv"))
new_data[, iso3:=NULL]
old_data <- fread(file.path(old_dir, "02_survey_data.csv"))
old_data[, c("gap_1", "gap_3"):=NULL]
all_data <- append_dts(old_data, new_data)
toplot_data <- melt(all_data, id.vars=c("type", "flooryear", "Survey", "cellnumber"), measure.vars = c("national_access", "gap_2"))

year_plot <- ggplot(toplot_data, aes(x=factor(flooryear), y=value)) +
              geom_boxplot(aes(color=type)) +
              facet_grid(variable ~., scales="free") +
              theme(legend.position="bottom",
                    legend.title = element_blank(),
                    axis.text.x = element_text(angle=45, hjust=1)) +
              labs(title="Data value by Year",
                   y="",
                   x="")
print(year_plot)

surv_plot <- ggplot(toplot_data, aes(x=Survey, y=value)) +
              geom_boxplot(aes(color=type)) +
              facet_grid(variable ~., scales="free") +
              theme(legend.position="bottom",
                    legend.title = element_blank(),
                    axis.text.x = element_text(angle=45, hjust=1)) +
              labs(title="Data value by Survey",
                   y="",
                   x="")
print(surv_plot)


## 03: check covariates -- TODO plots
print("comparing old and new data covariate files")
new_covs <- fread(file.path(new_dir, "03_data_covariates.csv"))
old_covs <- fread(file.path(old_dir, "03_data_covariates.csv"))

check_sameness(old_covs, new_covs)


## 04: inla models
print("comparing old and new inla files")
load(file.path(new_dir, "04_inla_dev_gap.Rdata"))
new_models <- copy(inla_outputs)
load(file.path(old_dir, "04_inla_dev_gap.Rdata"))
old_models <- copy(inla_outputs)

for (this_name in names(new_models)){
  print(paste("Evaluating inla type", this_name))
  new_model <- new_models[[this_name]][["model_output"]]
  old_model <- old_models[[this_name]][["model_output"]]
  
  new_fixed <- new_model$summary.fixed
  new_fixed$cov<-rownames(new_fixed)
  new_fixed <- data.table(new_fixed)
  new_fixed <- new_fixed[order(cov)]
  new_fixed[, type:="New"]
  new_fixed[, kld:=NULL]
  
  new_hyperpar <- new_model$summary.hyperpar
  new_hyperpar$cov<-rownames(new_hyperpar)
  new_hyperpar <- data.table(new_hyperpar)
  new_hyperpar[, type:="New"]
  
  old_fixed <- old_model$summary.fixed
  old_fixed$cov<-rownames(old_fixed)
  old_fixed <- data.table(old_fixed)
  old_fixed <- old_fixed[order(cov)]
  old_fixed[, type:="Old"]
  old_fixed[, kld:=NULL]
  
  old_hyperpar <- old_model$summary.hyperpar
  old_hyperpar$cov<-rownames(old_hyperpar)
  old_hyperpar <- data.table(old_hyperpar)
  old_hyperpar[, type:="Old"]
  
  all_toplot <- rbind(new_fixed, new_hyperpar, old_fixed, old_hyperpar)
  all_toplot[, cov_id:=rep(1:length(unique(cov)), 2)]
  all_toplot <- melt.data.table(all_toplot, id.vars=c("type", "cov", "cov_id"))
  
  diff_plot <- ggplot(all_toplot, aes(x=value, y=cov)) +
                geom_point(aes(color=type)) +
                facet_wrap(~variable) +
                labs(title=paste("INLA comparision:", this_name),
                     x="Value",
                     y="") +
                theme(legend.position = "bottom",
                      legend.title = element_blank())
  
  print(diff_plot)
  
}


# 05: .tifs
print("comparing old and new raster files")
old_raster_dir <- file.path(old_dir, "05_predictions")
new_raster_dir <- file.path(new_dir, "05_predictions")
new_files <- list.files(new_raster_dir)
old_files <- list.files(old_raster_dir)

compare_tifs <- function(old_tif, new_tif, name="", cutoff=0.001){
  
  print(name)

  diff <- old_tif-new_tif
  
  stacked <- stack(old_tif, new_tif)
  names(stacked) <- c(paste("Old", name), paste("New", name))
  
  stackplot <- levelplot(stacked,
                         par.settings=rasterTheme(region=brewer.pal(8, "RdYlGn")),
                         xlab=NULL, ylab=NULL, scales=list(draw=F), margin=F)
  
  
  return(stackplot)
}

for (var_name in c("\\.MEAN", "\\.DEV", "\\.ACC", "\\.GAP", "\\.USE", "\\.RAKED_USE")){
  print(paste("predicting for", var_name))
  new_stack <- stack(file.path(new_raster_dir, new_files[grepl(var_name, new_files)]))
  old_stack <- stack(file.path(old_raster_dir, old_files[grepl(var_name, old_files)]))
  stack_diff <- new_stack - old_stack
  
  plot_idx <- 1
  for (this_stack in c(new_stack, old_stack, stack_diff)){
    
    if (plot_idx==3){
      stackplot <- levelplot(this_stack,
                             par.settings=rasterTheme(region=brewer.pal(8, "PRGn")), at=seq(-1,1,1/4),
                             xlab=NULL, ylab=NULL, scales=list(draw=F), margin=F)
    }else{
      stackplot <- levelplot(this_stack,
                             par.settings=rasterTheme(region=brewer.pal(8, "RdYlGn")),
                             xlab=NULL, ylab=NULL, scales=list(draw=F), margin=F)
    }
    
    print(stackplot)
    plot_idx <- plot_idx+1
  }
  
  
}

graphics.off()



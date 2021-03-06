###############################################################################################################
## paper_plots.r
## Amelia Bertozzi-Villa
## March 2020
## 
## prototype ITN outputs for paper and thesis
##############################################################################################################

library(dplyr)
library(survey)
library(raster)
library(rasterVis)
library(gridExtra)
library(MapSuite)
library(maptools)
library(PNWColors)
library(Hmisc)
library(geofacet)
library(data.table)
library(INLA)
library(sf)


rm(list=ls())

############ ----------------------------------------------------------------------------------------------------------------------
## Inputs  ----------------------------------------------------------------------------------------------------------------------
############ ----------------------------------------------------------------------------------------------------------------------

years <- 2000:2020
years_for_rel_gain <- c(2015, 2020)

cube_indir <- "/Volumes/GoogleDrive/My Drive/itn_cube/results/20201001_new_2020_dists/04_predictions"
cube_validation_indir <- "/Volumes/GoogleDrive/My Drive/itn_cube/results/20201221_validation_from_20201001"
stockflow_indir <- "/Volumes/GoogleDrive/My Drive/stock_and_flow/results/20200930_new_2020_dists"
survey_indir <- "/Volumes/GoogleDrive/My Drive/stock_and_flow/input_data/01_input_data_prep/20200731"
nmcp_indir <- "/Volumes/GoogleDrive/My Drive/stock_and_flow/input_data/00_survey_nmcp_manufacturer/nmcp_manufacturer_from_who/data_2020/20200929/ready_for_stockflow/"
data_fname <- "../02_data_covariates.csv"


shape_dir <- "/Volumes/GoogleDrive/My Drive/itn_cube/input_data/general/shapefiles/"
pop_tif_dir <- "/Volumes/GoogleDrive/My Drive/itn_cube/results/covariates/gbd_populations"
gaul_tif_fname <- "/Volumes/GoogleDrive/My Drive/itn_cube/input_data/general/african_cn5km_2013_no_disputes.tif"
iso_gaul_fname <- "/Volumes/GoogleDrive/My Drive/itn_cube/input_data/general/iso_gaul_map.csv"

setwd(cube_indir)
out_dir <- file.path(cube_indir, "../final_plots")
supp_dir <- file.path(out_dir, "supplementary_plots")
dir.create(supp_dir, showWarnings = F)

# directory for saving figure data to git repo (paper submission requirement)
repo_fig_dir <- "~repos/map-itn-cube/paper_figures/figure_data/"
geofacet_fname <- "~/repos/map-itn-cube/paper_figures/geofacet_ssa_malaria.csv"

# supplementary image default sizes
supp_std_width <- 12
supp_std_height <- 9

############ ----------------------------------------------------------------------------------------------------------------------
## Functions  ----------------------------------------------------------------------------------------------------------------------
############ ----------------------------------------------------------------------------------------------------------------------

gg_color_hue <- function(n) {
  hues = seq(15, 375, length = n + 1)
  hcl(h = hues, l = 65, c = 100)[1:n]
}

emplogit <- function (y, eps = 1e-3){
  log((eps + y)/(1 - y + eps))
} 

emplogit2<-function(y, n){
  # approximation of a log odds
  # y: # of occurrences of interest
  # n: # of tries
  top=y+0.5
  bottom=n-y+0.5
  return(log(top/bottom))
}


################## ----------------------------------------------------------------------------------------------------------------------
## Stock and Flow   ----------------------------------------------------------------------------------------------------------------------
################# ----------------------------------------------------------------------------------------------------------------------

## Data: Survey count and type by country
survey_summary <- fread(file.path(survey_indir, "summary_tables", "summary_table_intermediate.csv"))
survey_summary[, short_source:=ifelse(source %like% "MICS", "MICS",
                                      ifelse(source %like% "OTHER", "Other",
                                             source))]


survey_panel <- ggplot(survey_summary, aes(x=main_year, y=reorder(country, desc(country)))) + 
  geom_point(aes(shape=included_in_cube, color=short_source), size=3) +
  scale_x_continuous(labels=2000:2019, breaks = 2000:2019) + 
  theme_bw() + 
  labs(y="", 
       x="",
       title="Surveys by Country and Type",
       shape="Included in\nGeospatial Regression?",
       color="Survey Type")

pdf(file.path(supp_dir, "survey_panel.pdf"), width=12, height=9)
  print(survey_panel)
graphics.off()

## Plot NMCP data with missings
nmcp_data <- fread(list.files(nmcp_indir, full.names = T)[list.files(nmcp_indir) %like% "prepped_llins"])
nmcp_data[, llin_mils:= llins/1e6]
nmcp_data[, format_source:= factor(source, 
                                   levels=c("alma", "nmcp", "pmi", "who", "min", "custom"),
                                   labels=c("ALMA", "NMCPs", "PMI Reports", "WHO (2020)", "3yr Minimum", "Custom"))]

nmcp_colors <- gg_color_hue(6)
nmcp_plot <- ggplot(nmcp_data[year %in% years], aes(x=year, y=llin_mils)) +
  geom_line() + 
  geom_point(aes(color=format_source), size=2) +
  scale_color_manual(values=c(nmcp_colors[1], nmcp_colors[3], nmcp_colors[2], nmcp_colors[4:6])) + 
  facet_wrap(~ISO3, scales="free_y") +
  theme(axis.text.x = element_text(angle = 45, hjust=1)) +
  labs(x="",
       y="LLINs Distributed (Millions)",
       title="LLIN Distribution Data by Type",
       color="Data Source")

pdf(file.path(supp_dir, "nmcp_data_timeseries.pdf"), width=supp_std_width, height=supp_std_height)
  print(nmcp_plot)
graphics.off()

stockflow_model_name <- gsub(".*/[0-9]{8}_", "", stockflow_indir)

# loads a file with data.frames "nets_in_houses_all", "nmcp_data_all", "stock_all", "survey_data_all", "half_life_comparison"
load(file.path(stockflow_indir, "for_plotting.RData"))

half_life_comparison <- half_life_comparison[net_type=="llin" & model==stockflow_model_name]

for_sigmoids <- half_life_comparison[base_year==2000, # these should be the same every year with a single half life, so just pick a year 
                                     list(sig=mean(sig),
                                          half_life=mean(half_life)), by=c("iso3", "model", "net_type", "time")]

half_life_means <- for_sigmoids[, list (sig=mean(sig), half_life=mean(half_life)), by=c("model", "net_type", "time")]
midpoints <- unique(half_life_means[, list(model, net_type, half_life)])

two_colors <- gg_color_hue(2)
sigmoid_plot <- ggplot(for_sigmoids, aes(x=time, y=sig)) +
  geom_line(aes(group=iso3), alpha=0.5, color=two_colors[2]) +
  # geom_line(data=half_life_means, size=2, color=two_colors[1]) +
  # geom_vline(data=midpoints, aes(xintercept=half_life), size=2) +
  geom_vline(xintercept=3) + 
  #geom_text(data=midpoints, aes(x=half_life-0.75, y=1, label=paste("Mean half-life:\n", half_life, "years"))) + 
  labs(title="",
       x="Time since net received (years)",
       y="Prop. of nets retained")

country_lambdas <- unique(for_sigmoids[, list(model, net_type, iso3, half_life)])
descending_order <- country_lambdas[order(half_life, decreasing=T)]$iso3

half_life_bounds <- fread(file.path(stockflow_indir, "trace_plots", "llin_bounds.csv"))
half_life_bounds <- dcast.data.table(half_life_bounds, iso3 ~ type, value.var = "half_life")
country_lambdas <- merge(country_lambdas, half_life_bounds, by="iso3")
# color by survey count
survey_count <- survey_summary[, list(svy_count=.N), by="iso3"]
country_lambdas <- merge(country_lambdas, survey_count)
country_lambdas[, high_svy:=ifelse(svy_count>=3, 1, 0)]
country_lambdas[, iso3:= factor(iso3, levels = descending_order)]

color_red <- gg_color_hue(2)[1]
half_life_iso_plot <- ggplot(country_lambdas, aes(x=iso3, color=factor(high_svy))) +
  geom_hline(yintercept=3, linetype="dotted") + 
  geom_linerange(aes(ymin=lower, ymax=upper)) + 
  geom_text(aes(label=iso3, y=half_life)) +
  scale_color_manual(values=c(color_red, "dimgrey")) +
  theme(axis.text.x = element_blank(),
        axis.ticks.x = element_blank(),
        axis.line.x = element_blank(),
        legend.position = "none") +
  labs(x="",
       y="LLIN Median Retention Time (years)")

pdf(file.path(out_dir, "fig_5_half_lives.pdf"), width=14, height=9)
  print(half_life_iso_plot)
graphics.off()

write.csv(country_lambdas[, list(iso3, half_life, lower=round(lower,2), upper=round(upper,2), svy_count)],
          file=file.path(repo_fig_dir, "fig_5_llin_half_lives.csv"), row.names = F)

write.csv(country_lambdas[, list(iso3, half_life, lower=round(lower,2), upper=round(upper,2), svy_count)],
          file=file.path(out_dir, "llin_half_lives.csv"), row.names = F)

# time series of net crop vs survey data
net_crop_timeseries_plot <- ggplot(nets_in_houses_all[model==stockflow_model_name & date<(max(years)+1)], aes(x=date, color=type, fill=type)) +
  geom_ribbon(aes(ymin=lower, ymax=upper), alpha=0.3) +
  geom_line(aes(y=nets_houses), size=1) +
  geom_pointrange(data=survey_data_all[model==stockflow_model_name],
                  aes(y=svy_net_count, ymin=svy_net_lower, ymax=svy_net_upper, shape=type), alpha=0.85, color="black") + 
  facet_wrap(.~iso3, scales="free_y") + 
  theme(legend.position = "bottom",
        axis.text.x = element_text(angle=45, hjust=1)) +
  labs(title= "Net Crop by Country",
       x="Time",
       y="Net count")


# time series of available stock, nmcp distributions, & model distributions
colors <- gg_color_hue(4)[c(1,2)]
stock_and_dist_plot <- ggplot(stock_all[model==stockflow_model_name &
                                          metric!="raw_llins_distributed" &
                                          metric!="nmcp_count_llin_est" & 
                                          year %in% years], aes(x=year, color=metric)) +
  geom_point(data=nmcp_data_all[model==stockflow_model_name &  type=="llin"], 
             aes(y=nets_distributed_data),size=2, alpha=0.5, color="black") +
  geom_line(aes(y=value), size=1) +
  scale_color_manual(values=colors) + 
  # geom_point(aes(y=value)) + 
  facet_wrap(.~iso3, scales="free_y") +
  theme(legend.position = "bottom") + 
  labs(title= "LLIN Stock and Distribution by Country",
       x="Time",
       y="Net count")


## individual country plot for Figure 1
fig_1_country <- "BFA"
fig_one_dist_dt <- stock_all[model==stockflow_model_name & iso3==fig_1_country &
                               metric!="nmcp_count_llin_est" &
                               year %in% years]
fig_one_dist_dt[, bound:=ifelse(metric=="adjusted_llins_distributed", 0, 1)]
fig_one_dist_dt[, value:=value/1000000]
color_blue <- gg_color_hue(2)[2]
color_red <- gg_color_hue(2)[1]


fig_one_distplot <- ggplot(fig_one_dist_dt[bound==1], aes(x=year, y=value)) +
                            geom_bar(data=fig_one_dist_dt[metric=="initial_stock"], stat="identity", color="black", fill=NA) + 
                            geom_bar(data=fig_one_dist_dt[metric=="raw_llins_distributed"], stat="identity", alpha=0.75) +
                            geom_pointrange(data=fig_one_dist_dt[bound==0], aes(ymin=value, ymax=value), alpha=0.99, fill=color_blue, color=color_blue) + 
                            # geom_point(data=fig_one_dist_dt[bound==0], shape=3, color=color_blue, size=8) + 
                            ylim(0, 17.5) +
                            xlim(2000, 2020) + 
                            theme(legend.position = "none") + 
                            labs(title= "",
                                 x="",
                                 y="Net count (millions)")


fig_one_dist_dt_wide <- dcast.data.table(fig_one_dist_dt, year ~ metric, value.var="value")
fig_one_distplot_alt <- ggplot(fig_one_dist_dt_wide, aes(x=year, y=adjusted_llins_distributed)) +
                            geom_pointrange(aes(ymin=raw_llins_distributed, ymax=initial_stock), alpha=0.75, fill="black") + 
                            # geom_pointrange(aes(ymin=adjusted_llins_distributed, ymax=adjusted_llins_distributed), color=color_blue, size=0.25) + 
                            ylim(0, 17.5) +
                            xlim(2000, 2020) + 
                            theme(legend.position = "none") + 
                            labs(title= "",
                                 x="",
                                 y="Net count (millions)")


fig_one_crop_dt <- nets_in_houses_all[iso3==fig_1_country &  model==stockflow_model_name & type=="llin" & date<(max(years)+1)]
fig_one_crop_dt[, lower:=lower/1000000]
fig_one_crop_dt[, upper:=upper/1000000]
fig_one_crop_dt[, nets_houses:=nets_houses/1000000]
fig_one_counterfact <- fig_one_dist_dt[metric=="adjusted_llins_distributed"]
fig_one_counterfact[, cumulative:= cumsum(value)]
fig_one_counterfact <- melt(fig_one_counterfact, id.vars = c("year"), measure.vars = c("value", "cumulative"))
fig_one_counterfact[, year:=year+0.75]

fig_one_cropplot <- ggplot(fig_one_crop_dt, aes(x=date)) +
                            geom_line(data=fig_one_counterfact, aes(x=year, y=value, group=variable), color=color_red) + 
                            geom_ribbon(aes(ymin=lower, ymax=upper), alpha=0.3,  fill=color_blue) +
                            geom_line(aes(y=nets_houses), size=1, color=color_blue) +
                            geom_pointrange(data=survey_data_all[model==stockflow_model_name & type=="llin" & iso3==fig_1_country],
                                            aes(y=svy_net_count/1000000, ymin=svy_net_lower/1000000, ymax=svy_net_upper/1000000, shape=type), alpha=0.85, color="black") + 
                            ylim(0, 17.5) +
                            theme(legend.position = "none") +
                            labs(title= "",
                                 x="",
                                 y="")

pdf(file.path(out_dir, "fig_1_raw.pdf"), width=8, height=4)
  grid.arrange(fig_one_distplot, fig_one_cropplot, ncol=2)
graphics.off()

 ############ ----------------------------------------------------------------------------------------------------------------------
## ITN Cube: Time series  ---------------------------------------------------------------------------------------------------------
############ ----------------------------------------------------------------------------------------------------------------------

# regression coefficients, "inla_outputs_for_prediction"
load(file.path(cube_indir, "../03_inla_outputs_for_prediction.Rdata"))
fixed_effects <- rbindlist(lapply(names(inla_outputs_for_prediction), function(outcome_var){
  fe <- data.table(inla_outputs_for_prediction[[outcome_var]]$fixed, keep.rownames = T)[, list(outcome_var=outcome_var, cov=rn, mean, lower=`0.025quant`, upper=`0.975quant`)]
  fe[, cov_label:=factor(cov, levels=c("Intercept",
                                       "Aridity_Index_v2.Synoptic.Overall.Data.5km.mean",
                                      "SRTM_elevation.Synoptic.Overall.Data.5km.mean",
                                      "SRTM_SlopePCT_Corrected.Synoptic.Overall.Data.5km.mean",
                                      "VIIRS.SLC.2014.Annual.mean.5km.mean",
                                      "Accessibility.2015.Annual.Data.5km.mean",
                                      "pf_seasonality",
                                      "PET_v2.Synoptic.Overall.Data.5km.mean",
                                      "Africa_TMI_90m.mean",
                                      "Population",
                                      "Landcover_2_Evergreen_Broadleaf_Forest",
                                      "Landcover_4_Deciduous_Broadleaf_Forest",
                                      "Landcover_5_Mixed_Forest",
                                      "Landcover_6_Closed_Shrublands",
                                      "Landcover_7_Open_Shrublands",
                                      "Landcover_8_Woody_Savannas",
                                      "Landcover_9_Savannas",
                                      "Landcover_10_Grasslands",
                                      "Landcover_11_Permanent_Wetlands",
                                      "Landcover_12_Croplands",
                                      "Landcover_14_Cropland_Natural_Vegetation_Mosaic",
                                      "Landcover_16_Barren_Or_Sparsely_Populated",
                                      "Landcover_17_Water",
                                      "EVI",
                                      "TCW",
                                      "LST_day",
                                      "LST_night",
                                      "TSI"),
                        labels=c("Intercept",
                                 "Aridity",
                                 "Elevation",
                                  "Slope",
                                  "NightTime Lights",
                                  "Accessibility to Cities",
                                  "Pf Seasonality",
                                  "PET",
                                  "TMI",
                                  "Population",
                                  "LC2: Ever Broadleaf",
                                  "LC4: Decid Broadleaf",
                                  "LC5: Mixed Forest",
                                  "LC6: Closed Shrublands",
                                  "LC7: Open Shrublands",
                                  "LC8: Woody Savannas",
                                  "LC9: Savannas",
                                  "LC10: Grasslands",
                                  "LC11: Perm Wetlands",
                                  "LC12: Croplands",
                                  "LC14: Crop/Natural Veg",
                                  "LC16: Barren/Sparse Pop",
                                  "LC17: Water",
                                  "EVI",
                                  "TCW",
                                  "Daytime LST",
                                  "Nighttime LST",
                                  "TSI"))]
  
  fe[, vals_label:= paste0(round(mean, 3), " (", round(lower,3), ", ", round(upper, 3), ")")]
  
  return(fe)
}))

fixed_effects[, outcome_var:= factor(outcome_var, 
                                     levels = c("access_dev", "use_gap", "percapita_net_dev"),
                                     labels = c("Access Deviation", "Use Gap", "NPC Deviation"))]

write.csv(fixed_effects, file = file.path(out_dir, "reg_coeffs.csv"), row.names=F)

reg_coeffs_plot <- ggplot(fixed_effects, aes(x=mean, y=outcome_var, color=outcome_var)) +
                              geom_vline(xintercept = 0) + 
                              geom_errorbarh(aes(xmin=lower, xmax=upper)) + 
                              geom_point() +
                              facet_wrap(~cov_label) + 
                              theme(legend.position = "none") +
                              labs(x="Coefficient",
                                   y="",
                                   title="Geospatial Regression Coefficients")

pdf(file.path(supp_dir, "reg_coeffs.pdf"), width=14, height=supp_std_height)
  print(reg_coeffs_plot)
graphics.off()

# survey data
cube_survey <- fread(file.path(cube_indir, "../01_survey_summary.csv"))
cube_survey[, use_rate_mean:=use_mean/access_mean]
cube_survey <- melt(cube_survey, id.vars = c("surveyid", "iso3", "date", "min_date", "max_date"), variable.name = "variable")
cube_survey[, metric:=ifelse(variable %like% "_se", "se", "mean")]
cube_survey[, variable:=gsub("_se", "", variable)]
cube_survey[, variable:=gsub("_mean", "", variable)]
cube_survey <- dcast.data.table(cube_survey, surveyid + iso3 + date + min_date + max_date + variable ~ metric)
cube_survey[, type:=variable]

# access and use line plots
cube_nat_level_fnames <- list.files(file.path(cube_indir, "aggregated"), full.names = T)
cube_nat_level_fnames <- cube_nat_level_fnames[!cube_nat_level_fnames %like% "mean_ONLY"]
cube_nat_level <- rbindlist(lapply(cube_nat_level_fnames, fread))
cube_nat_level <- cube_nat_level[iso3 %in% c(unique(nets_in_houses_all$iso3), "AFR")]

# shapefile
Africa <- readOGR(file.path(shape_dir, "Africa_simplified.shp"))
Africa_dt <- data.table(fortify(Africa, region = "COUNTRY_ID"))
Africa_dt[, modeled:= ifelse(id %in% unique(cube_nat_level$iso3), "Yes", "No")]

# merge on population-at-risk; adjust
pop_all <- fread(file.path(nmcp_indir, "ihme_populations.csv"))
pop <- pop_all[year %in% unique(cube_nat_level$year) & admin_unit_level=="ADMIN0" & age_bin=="All_Ages" & iso3 %in% unique(cube_nat_level$iso3),
                   list(iso3, country_name, year, par=pop_at_risk_pf, pop=total_pop)]
pop <- rbind(pop[, list(iso3="AFR", country_name="SSA", par=sum(par), pop=sum(pop)), by="year"],
             pop)
pop[, par_prop:=par/pop]

cube_nat_level <- merge(cube_nat_level, pop[, list(iso3, country_name, year, pop, par, par_prop)], all.x=T)
cube_nat_level[, par_adj_mean:=mean*(1/par_prop)]
cube_nat_level[, par_adj_lower:=lower*(1/par_prop)]
cube_nat_level[, par_adj_upper:=upper*(1/par_prop)]

# also adjust survey data for PAR
cube_survey[, year:=floor(date)]
cube_survey <- merge(cube_survey, pop, by=c("iso3", "year"), all.x=T)
cube_survey[, adj_mean:=mean*(1/par_prop)]


# plot access vs npc in survey data
acc_npc_data <- dcast.data.table(cube_survey, iso3 + year + surveyid + date ~ variable, value.var = "adj_mean")

ggplot(acc_npc_data, aes(x=percapita_nets, y=access)) + 
  geom_abline(slope=1.8) + 
  geom_point() + 
  geom_smooth()

hh_survey_data <- fread(file.path(cube_indir, "../01_survey_data.csv"))

ggplot(hh_survey_data, aes(x=percapita_nets, y=access_count/pixel_pop)) + 
  geom_abline(slope=1.8) + 
  geom_point(aes(size=pixel_pop), alpha=0.5) + 
  facet_wrap(~year) + 
  geom_smooth(color=color_red, size=2, se=F) + 
  geom_smooth(color=color_blue, size=2, se=F, aes(weight=pixel_pop)) + 
  labs(x="Nets Per Capita",
       y="Access (Proportion)", 
       title="NPC vs Access on the Survey Cluster Level")


# convert npc to net crop
net_crop <- cube_nat_level[variable=="percapita_nets", list(iso3, country_name, year, month, time, 
                                                            variable="net_crop",
                                                            mean=mean*pop,
                                                            lower=lower*pop,
                                                            upper=upper*pop,
                                                            par_adj_mean=mean*pop, # this is an absolute count, don't need to pop-adjust
                                                            par_adj_lower=lower*pop,
                                                            par_adj_upper=upper*pop,
                                                            pop,
                                                            par,
                                                            par_prop
                                                            )]

cube_nat_level <- rbind(net_crop, cube_nat_level)
cube_nat_level_annual <- cube_nat_level[is.na(month)]
cube_nat_level_annual[, time:=year]
cube_nat_level_annual[, month:=NULL]
cube_nat_level <- cube_nat_level[!is.na(time)]

continental_nets <- cube_nat_level_annual[iso3=="AFR" & variable %in%  c("net_crop", "access", "use")]
continental_nets[, par_adj_mean:=ifelse(variable=="net_crop", par_adj_mean/1000000, mean*100)]
continental_nets[, par_adj_lower:=ifelse(variable=="net_crop", par_adj_lower/1000000, lower*100)]
continental_nets[, par_adj_upper:=ifelse(variable=="net_crop", par_adj_upper/1000000, upper*100)]
continental_nets[, metric:= ifelse(variable=="net_crop", "Net Count (Millions)", "Access and Use (%)")]

continental_nets_plot <- ggplot(continental_nets[year %in% years], aes(x=time, y=par_adj_mean, color=variable, fill=variable)) + 
  geom_ribbon(aes(ymin=par_adj_lower, ymax=par_adj_upper), color=NA, alpha=0.35) + 
  geom_line() + 
  theme(legend.position = "none") +
  facet_grid(metric~., scales="free_y") +
  labs(title="Continent-level net count, access, and use, 2000-2020",
       x="",
       y="")

cube_nat_level[, code:=iso3]
cube_survey[, code:=iso3]
cube_nat_level[, label_year:= gsub("*20", "'", as.character(year))]

ssa_grid <- fread(geofacet_fname)

access_use_timeseries <- ggplot(cube_nat_level[variable %in% c("access", "use") & year %in% years],
                                aes(x=time-2000, color=variable, fill=variable)) + 
                          geom_hline(yintercept = 80, size=1, linetype="dotted") + 
                          geom_ribbon(aes(ymin=par_adj_lower*100, ymax=par_adj_upper*100), color=NA, alpha=0.35) + 
                          geom_line(aes(y=par_adj_mean*100), size=0.5) + 
                          geom_point(data=cube_survey[variable %in% c("access", "use")], aes(x=date-2000, y=adj_mean*100, shape=variable), color="black") + 
                          facet_geo(~code, grid = ssa_grid, label="name") + 
                          scale_shape_manual(values=c(0,2)) + 
                          theme_classic() + 
                          scale_x_continuous(breaks=seq(0,20,5), labels=c("'00", "'05", "'10", "'15", "'20"))+
                          theme(legend.title = element_blank(),
                                legend.position="none",
                                # axis.text.x = element_text(angle=45, hjust=1)
                                # axis.text.x = element_blank(),
                                axis.line = element_blank(),
                                axis.ticks.x = element_blank(),
                                panel.grid.major.x = element_line(color = "darkgrey", size=0.25)
                                ) + 
                          labs(title="",
                               x="",
                               y="Access or Use (%)")

access_timeseries <- ggplot(cube_nat_level[variable %in% c("access") & year %in% years],
                                aes(x=time-2000, color=variable, fill=variable)) + 
  geom_hline(yintercept = 80, size=0.75, linetype="dotted") + 
  geom_ribbon(aes(ymin=par_adj_lower*100, ymax=par_adj_upper*100), color=NA, alpha=0.35) + 
  geom_line(aes(y=par_adj_mean*100), size=0.5) + 
  geom_point(data=cube_survey[variable %in% c("access")], aes(x=date-2000, y=adj_mean*100, shape=variable), color="black") + 
  facet_geo(~code, grid = ssa_grid, label="name") + 
  scale_shape_manual(values=c(0,2)) + 
  theme_classic() + 
  scale_x_continuous(breaks=seq(0,20,5))+
  theme(legend.title = element_blank(),
        legend.position="none",
        # axis.text.x = element_text(angle=45, hjust=1)
        # axis.text.x = element_blank(),
        axis.line = element_blank(),
        axis.ticks.x = element_blank(),
        panel.grid.major.x = element_line(color = "darkgrey", size=0.25)
  ) + 
  labs(title="",
       x="",
       y="Access (%)")

sf_for_ref <- ggplot(Africa_dt, aes(x = long, y = lat, group = group)) + 
                  geom_polygon(aes(fill=modeled)) + 
                  geom_path(color = "black", size = 0.3) +
                  scale_fill_manual(values=c("white","gray80")) + 
                  coord_equal(xlim = c(-18, 52), ylim = c(-35, 38)) +
                  labs(x = NULL, y = NULL, title = "") +
                  theme_classic(base_size = 12) +
                  theme(axis.line = element_blank(), axis.text = element_blank(), axis.ticks = element_blank(),
                        plot.margin = unit(c(0, 0, 0, 0), "in"), legend.title=element_blank(), legend.position = "none")
                  
# combine
pdf(file.path(out_dir, "fig_2_access_use_geofacet.pdf"), width = (10), height = (11))
  vp <- viewport(width = 0.13, height = 0.13, x = 0.05, y = 0.225)
  print(access_use_timeseries)
  print(sf_for_ref, vp = vp)
graphics.off()


write.csv(cube_nat_level[variable %in% c("access", "use") & year %in% years, list(iso3, country_name, year, month, time, variable, 
                                                                                  mean_among_atrisk=par_adj_mean, 
                                                                                  lower_among_atrisk=par_adj_lower,
                                                                                  upper_among_atrisk=par_adj_upper,
                                                                                  prop_atrisk=par_prop)],
          file=file.path(repo_fig_dir, "fig_2_access_use_timeseries.csv"), row.names = F)

## use rate

use_rate_timeseries <- 
  ggplot(cube_nat_level[year %in% years &  time>=2005 & variable=="use_rate"], aes(x=time, y=mean, group=iso3))+ 
  geom_ribbon(aes(ymin=lower, ymax=upper), alpha=0.5) + 
  geom_hline(yintercept=1, color="#00BFC4") + 
  geom_line() + 
  geom_point(data=cube_survey[type=="use_rate" & date>=2005], aes(x=date, y=mean)) + 
  facet_wrap(~iso3) +
  theme_minimal() +
  theme(legend.title = element_blank(),
        axis.text.x = element_text(hjust=1, angle=45)) + 
  scale_x_continuous(minor_breaks = years) + 
  labs(
       x="Time",
       y="Use Rate",
       title="ITN Use Rate by Country")

pdf(file.path(supp_dir, "use_rate_timeseries.pdf"), width=supp_std_width, height=supp_std_height)
  print(use_rate_timeseries)
graphics.off()


# use gap line plot
use_gap_timeseries <- ggplot(cube_nat_level[variable=="use_gap" & year %in% years], aes(x=time, y=mean)) + 
  geom_ribbon(aes(ymin=lower, ymax=upper), alpha=0.5) + 
  geom_hline(yintercept=0, color="#00BFC4") + 
  geom_line() + 
  geom_point(data=cube_survey[type=="use_gap"], aes(x=date, y=mean)) + 
  facet_wrap(.~iso3) + 
  theme_minimal() +
  theme(legend.title = element_blank(),
        axis.text.x = element_text(angle=45, hjust=1)) + 
  labs(title="ITN Use Gap by Country",
       x="Time",
       y="Use Gap")

pdf(file.path(supp_dir, "use_gap_timeseries.pdf"), width=supp_std_width, height=supp_std_height)
  print(use_gap_timeseries)
graphics.off()

# access deviation line plot 
acc_dev_timeseries <- ggplot(cube_nat_level[variable=="access_dev" & year %in% years], aes(x=time, y=mean)) + 
  geom_ribbon(aes(ymin=lower, ymax=upper), alpha=0.5) +
  geom_hline(yintercept=0, color="#00BFC4") + 
  geom_line() + 
  geom_point(data=cube_survey[type=="access_deviation"], aes(x=date, y=mean)) + 
  facet_wrap(.~iso3) + 
  theme_minimal() +
  theme(legend.title = element_blank(),
        axis.text.x = element_text(angle=45, hjust=1)) + 
  labs(title="ITN Access Deviation by Country",
       x="Time",
       y="Access Deviation")


pdf(file.path(supp_dir, "acc_dev_timeseries.pdf"), width=supp_std_width, height=supp_std_height)
  print(acc_dev_timeseries)
graphics.off()

# percapita net deviation line plot
npc_dev_timeseries <- ggplot(cube_nat_level[variable=="percapita_net_dev" & year %in% years], aes(x=time, y=mean)) + 
  geom_ribbon(aes(ymin=lower, ymax=upper), alpha=0.5) + 
  geom_hline(yintercept=0, color="#00BFC4") + 
  geom_line() + 
  geom_point(data=cube_survey[type=="percapita_net_deviation"], aes(x=date, y=mean)) + 
  facet_wrap(.~iso3) + 
  theme_minimal() +
  theme(legend.title = element_blank(),
        axis.text.x = element_text(angle=45, hjust=1)) + 
  labs(title="Nets-per-Capita Deviation by Country",
       x="Time",
       y="NPC Deviation")


pdf(file.path(supp_dir, "npc_dev_timeseries.pdf"), width=supp_std_width, height=supp_std_height)
  print(npc_dev_timeseries)
graphics.off()


## Look at access-npc relationship by country-month
nat_level_for_compare_uncert <- melt(cube_nat_level, id.vars = c("iso3", "country_name", "year", "month", "time", "variable"), 
                                     measure.vars=c("mean", "lower", "upper"), variable.name = "metric")
nat_level_for_compare_uncert[, full_var:= paste0(variable, "_", metric)]
nat_level_for_compare_uncert <- dcast.data.table(nat_level_for_compare_uncert, iso3 + country_name + year + month + time  ~ full_var, value.var="value")

nat_level_for_compare_uncert[, potential_access_mean:=pmin(percapita_nets_mean*2, 1)]
nat_level_for_compare_uncert[, potential_access_lower:=pmin(percapita_nets_lower*2, 1)]
nat_level_for_compare_uncert[, potential_access_upper:=pmin(percapita_nets_upper*2, 1)]


for_potential_access <- melt(nat_level_for_compare_uncert, id.vars = c("iso3", "country_name", "year", "month", "time"),
                             measure.vars = c("access_mean", "access_lower", "access_upper",
                                              "potential_access_mean", "potential_access_lower", "potential_access_upper"))
for_potential_access[, metric:= gsub(".*_(.*)$", "\\1", variable)]
for_potential_access[, variable:= ifelse(variable %like% "potential", "Access with \nPerfect Allocation", "True Access")]
for_potential_access <- dcast.data.table(for_potential_access, iso3 + country_name + year + month + time + variable ~ metric)

potential_access_plot <- ggplot(for_potential_access, aes(x=time, color=variable, fill=variable)) + 
                            geom_hline(yintercept=0.8) + 
                            geom_ribbon(aes(ymin=lower, ymax=upper), color=NA, alpha=0.25) +
                            geom_line(aes(y=mean)) + 
                            scale_fill_manual(values=c(color_blue, color_red)) +
                            scale_color_manual(values=c(color_blue, color_red)) +
                            facet_wrap(~iso3) + 
                            theme(legend.title = element_blank(),
                                  axis.text.x = element_text(angle=45, hjust=1)) +
                            labs(x="Time",
                                 y="Access (Proportion)",
                                 title="Estimated True vs Optimal Access")

ggsave(plot=potential_access_plot, height=9,width=12, filename=file.path(supp_dir, "optimal_vs_true_access.pdf"), useDingbats=FALSE)



nat_level_subset <- nat_level_for_compare_uncert[year==2020]
nat_level_subset_afr <- copy(nat_level_subset)
nat_level_subset_afr[, code:="AFR"]
nat_level_subset[, code:=iso3]
nat_level_subset <- rbind(nat_level_subset, nat_level_subset_afr)

access_npc_plot <- ggplot(nat_level_subset[code!="AFR"], aes(x=percapita_nets_mean, y=access_mean)) + 
                    geom_errorbar(aes(ymin=access_lower, ymax=access_upper), color="lightgrey") + 
                    geom_errorbarh(aes(xmin=percapita_nets_lower, xmax=percapita_nets_upper), color="lightgrey") + 
                    geom_point(size=2) +
                    geom_abline(slope=1.8) + 
                    coord_equal(ratio=1, xlim=c(0, 1), ylim=c(0, 1), expand=F) + 
                    geom_smooth(color=color_blue, size=1, se=F) + 
                    labs(x="Nets Per Capita",
                         y="Access (Proportion)")



ggsave(plot=access_npc_plot, height=9,width=9, filename=file.path(out_dir, "fig_4_access_npc.pdf"), useDingbats=FALSE)

write.csv(nat_level_subset[code!="AFR", list(iso3, country_name, year, month, time, access_mean, access_lower, access_upper,
                                             percapita_nets_mean, percapita_nets_lower, percapita_nets_upper)],
          file=file.path(repo_fig_dir, "fig_4_access_npc.csv"), row.names = F)


# view household size dists
hhsize_dist <- fread("/Volumes/GoogleDrive/My Drive/stock_and_flow/input_data/01_input_data_prep/20200731/hhsize_from_surveys.csv")

# compare to survey clusters
nat_level_subset <- nat_level_for_compare_uncert[year>=2003]

access_npc_compare <- rbind(nat_level_subset[, list(year,
                                                    type="Modeled\nCountry-Months",
                                                    percapita_nets=percapita_nets_mean, 
                                                    percapita_nets_lower, 
                                                    percapita_nets_upper,
                                                    access=access_mean,
                                                    access_lower,
                                                    access_upper)],
                            hh_survey_data[, list(year,
                                                  type="Survey\nData Clusters",
                                                  percapita_nets,
                                                  access=access_count/pixel_pop)],
                            fill=T)


access_npc_compare_with_data <- ggplot(access_npc_compare, aes(x=percapita_nets, y=access, color=type)) + 
                                    geom_abline(slope=1.8) +
                                    geom_errorbar(aes(ymin=access_lower, ymax=access_upper), alpha=0.1) + 
                                    geom_errorbarh(aes(xmin=percapita_nets_lower, xmax=percapita_nets_upper), alpha=0.1) + 
                                    geom_point(alpha=0.25) + 
                                    geom_smooth(size=2, se=F, alpha=0.5) + 
                                    facet_wrap(~year) + 
                                    theme(axis.text.x = element_text(angle = 45, hjust=1)) + 
                                    labs(x="Nets Per Capita",
                                         y="Access (Proportion)", 
                                         title="Nets-Per-Capita vs Access, Data and Model",
                                         color="")

pdf(file.path(supp_dir, "access_npc_compare_with_data.pdf"), width=supp_std_width, height=supp_std_height)
  print(access_npc_compare_with_data)
graphics.off()

############ ----------------------------------------------------------------------------------------------------------------------
## ITN Cube: maps  ----------------------------------------------------------------------------------------------------------------
############ ----------------------------------------------------------------------------------------------------------------------

main_colors <- wpal("seaside", noblack = T)
use_rate_colors <- c("#722503", "#AB0002", "#F2A378", "#F4CA7D", "#C8D79E", "#70A800")
npc_colors <- rev(pnw_palette("Mushroom", 30))
  
max_pixels <- 5e5

background_raster <- raster(gaul_tif_fname)
NAvalue(background_raster) <- -9999
iso_gaul_map<-fread(iso_gaul_fname)
modeled_gauls <- iso_gaul_map[COUNTRY_ID %in% unique(nets_in_houses_all$iso3)]$GAUL_CODE

background_raster[background_raster%in% modeled_gauls] <- NA
background_raster[!is.na(background_raster)] <- 1
background_mask_dt <- data.table(rasterToPoints(background_raster))
names(background_mask_dt) <- c("long", "lat", "mask")

save(background_mask_dt, file=file.path(out_dir, "background_mask_dt.Rdata"))

background_plot_single <- levelplot(background_raster,
                                    par.settings=rasterTheme(region=c("gray80")),
                                    xlab=NULL, ylab=NULL, scales=list(draw=F), margin=F 
)


## Means and Uncertainty Quantiles  ----------------------------------------------------------------------------------------------------------------


uncert_year <- 2020
variables_to_plot <- c("access", "use_rate", "percapita_nets")

round_vals <- function(dt, sig=6){
  dt[, x:=round(x, sig)]
  dt[, y:=round(y, sig)]
  return(dt)
}

fig_3_dir <- file.path(repo_fig_dir, "fig_3_maps_with_uncert_quart")
dir.create(fig_3_dir, showWarnings = F)

rel_uncert_maps <- lapply(variables_to_plot, function(this_var){
  print(this_var)
  
  plot_label <- tools::toTitleCase(gsub("_", " ", this_var))
  
  if (this_var %in% c("access", "use")){
    pal <- wpal("seaside", noblack = T)
  }else if (this_var=="use_rate"){
    # pal <- c("#722503", "#AB0002", "#F2A378", "#F4CA7D", "#C8D79E", "#70A800")
    pal <- rev(pnw_palette("Sailboat", 30))
  }else if (this_var == "percapita_nets"){
    pal <- rev(pnw_palette("Mushroom", 30))
  }
  
  mean_raster <- raster(file.path("rasters", paste0("ITN_", uncert_year, "_", this_var, "_mean.tif")))
  mean_raster[mean_raster==0] <- NA
  lower_raster <- raster(file.path("rasters", paste0("ITN_", uncert_year, "_", this_var, "_lower.tif")))
  upper_raster <- raster(file.path("rasters", paste0("ITN_", uncert_year, "_", this_var, "_upper.tif")))
  lower_raster <- raster::mask(lower_raster, mean_raster)
  upper_raster <- raster::mask(upper_raster, mean_raster)
  
  pop_raster <- raster(file.path(pop_tif_dir, paste0("ihme_corrected_frankenpop_All_Ages_3_", uncert_year, ".tif")))
  pop_raster <- crop(pop_raster, mean_raster)
  pop_raster <- setExtent(pop_raster, mean_raster)
  
  mean_dt <- data.table(rasterToPoints(mean_raster))
  names(mean_dt) <- c("long", "lat", "value")
  mean_plot <- ggplot() +
    geom_raster(data = mean_dt, aes(fill = value, y = lat, x = long)) +
    annotate(geom = "raster", x = background_mask_dt$long, y = background_mask_dt$lat, fill = "gray80") +
    geom_path(data = Africa_dt, aes(x = long, y = lat, group = group), color = "black", size = 0.3) + 
    scale_fill_gradientn(colors= pal, limits=c(0, 1)) +
    coord_equal(xlim = c(-18, 52), ylim = c(-35, 38)) +
    labs(x = NULL, y = NULL, title = paste("Mean Values:", plot_label)) +
    theme_classic(base_size = 12) +
    theme(axis.line = element_blank(), axis.text = element_blank(), axis.ticks = element_blank(),
          plot.margin = unit(c(0, 0, 0, 0), "in"), legend.title=element_blank())
  
  
  rel_uncert_colors <- c("#EA818F", "#E7A184", "#88C7E2", "#8AB5DF",
                         "#EDAAB3", "#EEBEAA", "#ADD8EB", "#B1CBE6",
                         "#EFD4DB", "#EEDBD2", "#CBE2EB", "#CDD8EC",
                         "#F9F4F8", "#FAF7F5", "#EEF4F7", "#EDF1F7")
  ci_width <- upper_raster - lower_raster
  
  mean_raster[background_raster==1] <- NA
  ci_width[background_raster==1] <- NA
  pop_raster <- raster::mask(pop_raster, mean_raster)
  
  pop_dt <- round_vals(data.table(rasterToPoints(pop_raster)))
  names(pop_dt) <- c("long", "lat", "pop")
  mean_dt <- round_vals(data.table(rasterToPoints(mean_raster)))
  names(mean_dt) <- c("long", "lat", "mean")
  ci_width_dt <- round_vals(data.table(rasterToPoints(ci_width)))
  names(ci_width_dt) <- c("long", "lat", "cirange")
  mean_dt[, cellnum:= as.integer(rownames(mean_dt))]
  full_dt <- merge(merge(mean_dt, ci_width_dt), pop_dt)
  
  full_dt[, mean_quart := cut(mean, breaks = wtd.quantile(mean, pop, c(0, 0.25, 0.5, 0.75, 1), na.rm = T), labels = F, include.lowest = T)]
  full_dt[, uncert_quart := cut(cirange, breaks = wtd.quantile(cirange, pop, c(0, 0.25, 0.5, 0.75, 1), na.rm = T), labels = F, include.lowest = T)]
  full_dt$mean_quart[which(is.na(full_dt$mean_quart))] <- 4
  full_dt$uncert_quart[which(is.na(full_dt$uncert_quart))] <- 4
  
  # make legend
  levels <- CJ(uncert_quart = unique(full_dt$uncert_quart),
               mean_quart = unique(full_dt$mean_quart))
  levels[, comb := factor(paste(uncert_quart, mean_quart))]
  full_dt[, comb := factor(paste(uncert_quart, mean_quart), levels = levels(levels$comb))]
  full_dt[, year:= uncert_year]
  
  legend <- ggplot(levels) +
    geom_raster(aes(x = factor(mean_quart), y = factor(uncert_quart), fill = comb), show.legend = F) +
    scale_fill_manual(values = rel_uncert_colors) +
    scale_x_discrete(labels = c("Low", "", "", "High"), expand = c(0, 0)) +
    scale_y_discrete(labels = c("Low", "", "", "High"), expand = c(0, 0)) +
    coord_equal() +
    labs(x = paste0(" \n", plot_label), y = "Uncertainty\n ", title = NULL) +
    theme_minimal() +
    theme(axis.line = element_blank(), axis.ticks = element_blank(),
          panel.grid = element_blank(), axis.text.y = element_text(angle = 90, hjust = 0.5),
          plot.margin = unit(c(0, 0, 0, 0), "in"), panel.border = element_rect(fill = NA, color = "black"))
  
  rel_unc_plot <- ggplot() +
    geom_raster(data = full_dt, aes(fill = comb, y = lat, x = long), show.legend = F) +
    annotate(geom = "raster", x = background_mask_dt$long, y = background_mask_dt$lat, fill = "gray80") +
    geom_path(data = Africa_dt, aes(x = long, y = lat, group = group), color = "black", size = 0.3) + 
    scale_fill_manual(values = rel_uncert_colors) +
    coord_equal(xlim = c(-18, 52), ylim = c(-35, 38)) +
    labs(x = NULL, y = NULL, title = paste("Uncertainty Quartiles:", plot_label)) +
    theme_classic(base_size = 12) +
    theme(axis.line = element_blank(), axis.text = element_blank(), axis.ticks = element_blank(),
          plot.margin = unit(c(0, 0, 0, 0), "in"))
  
  template_raster <- copy(mean_raster)
  template_raster[!is.na(template_raster)] <- mean_dt$mean
  writeRaster(template_raster, file.path(fig_3_dir, paste0(this_var, "_", uncert_year, "_mean.tif")))
  
  template_raster[!is.na(template_raster)] <- full_dt[order(cellnum)]$comb
  writeRaster(template_raster, file.path(fig_3_dir, paste0(this_var, "_", uncert_year, "_uncert_quart.tif")))
  
  write.csv(levels, file=file.path(fig_3_dir, "uncert_levels.csv"), row.names = F)
  
  if (this_var=="access"){
    print("plotting ci width")
    ci_width_map <- ggplot() +
                    geom_raster(data = ci_width_dt, aes(fill = cirange, y = lat, x = long), show.legend = T) +
                    annotate(geom = "raster", x = background_mask_dt$long, y = background_mask_dt$lat, fill = "gray80") +
                    geom_path(data = Africa_dt, aes(x = long, y = lat, group = group), color = "black", size = 0.3) + 
                    scale_fill_gradientn(colors= brewer.pal(8, "Purples"), limits=c(0, 1)) +
                    coord_equal(xlim = c(-18, 52), ylim = c(-35, 38)) +
                    labs(x = NULL, y = NULL, title = paste("CI Range:", plot_label)) +
                    theme_classic(base_size = 12) +
                    theme(axis.line = element_blank(), axis.text = element_blank(), axis.ticks = element_blank(),
                          plot.margin = unit(c(0, 0, 0, 0), "in"))
  
    ggsave(plot=ci_width_map, height=5,width=5, filename=file.path(out_dir, "ci_width_for_mmc.pdf"), useDingbats=FALSE)
    
    }
  
  
  
  return(list(mean_plot, rel_unc_plot, legend))
  
})

rel_uncert_maps <- unlist(rel_uncert_maps, recursive=F)

pdf(file.path(out_dir, "fig_3_maps_with_uncert_quart.pdf"), width = (12), height = (10))
  do.call("grid.arrange", c(rel_uncert_maps, nrow=length(variables_to_plot)))
dev.off()


## Means and Exceedance  ----------------------------------------------------------------------------------------------------------------


raster_metrics <- data.table(var=variables_to_plot,
                             pos_exceed=c(0.5, 0.8, 0.3),
                             neg_exceed=c(0.3, 0.7, 0.1))
raster_fnames <- list.files("rasters")

plot_map <- function(rasters, metric, variable, maxpixels=5e5){
  
  if (metric %like% "Exceed"){
    if (metric %like% "Positive"){
      pal <- brewer.pal(4, "YlGnBu")
    }else{
      pal <- brewer.pal(4, "YlOrBr")
    }
    breaks <- seq(0, 1, 0.25)
  }else{
    if (variable %in% c("Access", "Use")){
      pal <- wpal("seaside", noblack = T)
    }else if (variable=="Use Rate"){
      pal <-    rev(pnw_palette("Sailboat", 30))
    }else if (variable == "Percapita Nets"){
      pal <- rev(pnw_palette("Mushroom", 30))
    }
    breaks <- seq(0, 1, 0.025)
  }
  
  names(rasters) <- gsub("(ITN_[0-9]{4})_.*", "\\1", names(rasters))
  
  return(levelplot(rasters,
                   par.settings=rasterTheme(region= pal), at= breaks,
                   xlab=NULL, ylab=NULL, scales=list(draw=F), margin=F, layout=c(nlayers(rasters), 1), 
                   main=ifelse(metric=="Mean", variable, metric))
  )
  
}


label_df <- rbindlist(lapply(variables_to_plot, function(this_var){
  this_df <- raster_metrics[var==this_var]
  new_df <- data.table(var=this_var,
                       var_label=tools::toTitleCase(gsub("_", " ", this_var)),
                       metric=c("neg_exceed",  "mean", "pos_exceed"),
                       cutoff=c( this_df$neg_exceed, NA, this_df$pos_exceed),
                       metric_label= c(paste("Negative Exceed:", this_df$neg_exceed), "Mean", paste("Positive Exceed:", this_df$pos_exceed))
                       )
}))
# label_df <- label_df[order(metric)]

exceed_plot_list <- lapply(1:nrow(label_df), function(idx){
  print(idx)
  this_df <- label_df[idx]
  
  this_raster <- raster(file.path("rasters", paste0("ITN_", uncert_year, "_", this_df$var, "_", this_df$metric, ifelse(is.na(this_df$cutoff), "", paste0("_", this_df$cutoff)), ".tif")))
  this_raster[this_raster==0] <- NA
  this_plot <- plot_map(this_raster, this_df$metric_label, this_df$var_label) + 
               background_plot_single + 
               latticeExtra::layer(sp.polygons(Africa))
  return(this_plot)
})


pdf(file.path(supp_dir, "exceedance_example.pdf"), width=supp_std_width, height=supp_std_height)
  do.call("grid.arrange", c(exceed_plot_list, ncol=3))
graphics.off()

## Relative Gain  ----------------------------------------------------------------------------------------------------------------

fig_6_dir <- file.path(repo_fig_dir, "fig_6_relgain_2020")
dir.create(fig_6_dir, showWarnings = F)

# relative gain for latest year
main_colors <- wpal("seaside", noblack = T)
relgain_colors <- wpal("cool_stormy", noblack = T)

rel_gain_plots <- lapply(years_for_rel_gain, function(this_year){
  
  this_use <- raster(file.path("rasters", paste0("ITN_", this_year, "_use_mean.tif")))*100
  this_access <- raster(file.path("rasters", paste0("ITN_", this_year, "_access_mean.tif")))*100
  
  # remove non-modeled countries
  this_use[this_use==0] <- NA
  this_access[this_access==0] <- NA
  
  # to prevent large numbers when dividing 
  this_use[this_use<0.01] <- 0.01
  this_access[this_access<0.01] <- 0.01
  
  this_capped_use <- min(this_use, this_access)
  this_use_rate <- (this_capped_use/this_access)*100
  
  # use gain: how many % points would you need to increase use to bring it to the level of access?
  use_gain <- this_access-this_capped_use
  
  # access gain: what would use look like if you maximized access everywhere? 
  access_gain <- this_use_rate - this_capped_use
  
  # save to repo for paper
  if (this_year==uncert_year){
    writeRaster(this_use, file.path(fig_6_dir, paste0("true_use_", uncert_year, ".tif")))
    writeRaster(this_access, file.path(fig_6_dir, paste0("use_with_max_use_rate_", uncert_year, ".tif")))
    writeRaster(this_use_rate, file.path(fig_6_dir, paste0("use_with_max_access_", uncert_year, ".tif")))
    writeRaster(use_gain, file.path(fig_6_dir, paste0("gain_from__max_use_rate_", uncert_year, ".tif")))
    writeRaster(access_gain, file.path(fig_6_dir, paste0("gain_from__max_access_", uncert_year, ".tif")))
  }
  
  
  true_use <- levelplot(this_use,
                        par.settings=rasterTheme(region= main_colors), at= seq(0, 100, 2.5),
                        xlab=NULL, ylab=NULL, scales=list(draw=F), margin=F, main=paste("ITN Use", this_year)) +
    latticeExtra::layer(sp.polygons(Africa))
  
  maxima <- stack(this_access, this_use_rate)
  names(maxima) <- c("Maximize Use Rate", "Maximize Access")
  maxima_plot <- levelplot(maxima,
                           par.settings=rasterTheme(region= main_colors), at= seq(0, 100, 2.5),
                           xlab=NULL, ylab=NULL, scales=list(draw=F), margin=F) +
    latticeExtra::layer(sp.polygons(Africa))
  
  new_comparison <- stack(use_gain, access_gain)
  names(new_comparison) <- c("Gain from Maximizing Use Rate", "Gain from Maximizing Access")
  relative_gain_continuous <- levelplot(new_comparison,
                                        par.settings=rasterTheme(region= relgain_colors), at= seq(0, 100, 2.5),
                                        xlab=NULL, ylab=NULL, scales=list(draw=F), margin=F) +
    latticeExtra::layer(sp.polygons(Africa))
  
  
  lay <- rbind(c(NA, NA, 2, 2, 2),
               c(1,  1,  2, 2, 2),
               c(1,  1,  3, 3, 3),
               c(NA, NA, 3, 3, 3)
  )
  
  full_plot <- arrangeGrob(true_use, maxima_plot, relative_gain_continuous, layout_matrix = lay)
  return(full_plot)
  
})

names(rel_gain_plots) <- years_for_rel_gain

pdf(file.path(out_dir, "fig_6_relgain_2020.pdf"), width=12, height=10)
  grid.arrange(rel_gain_plots[["2020"]])
graphics.off()

pdf(file.path(supp_dir, "rel_gain_alt.pdf"), width=11, height=8)
  grid.arrange(rel_gain_plots[["2015"]])
graphics.off()

## Regression performance  ----------------------------------------------------------------------------------------------------------------

data_vs_pred <- fread(file.path(cube_validation_indir, "03_data_vs_pred.csv"))
data_vs_pred[, outcome_var:= factor(outcome_var, 
                                          levels = c("access_dev", "use_gap", "percapita_net_dev"),
                                          labels = c("Access Deviation", "Use Gap", "NPC Deviation"))]
validation_metrics <- fread(file.path(cube_validation_indir, "03_validation_metrics.csv"))
validation_metrics[, outcome_var:= factor(outcome_var, 
                                          levels = c("access_dev", "use_gap", "percapita_net_dev"),
                                          labels = c("Access Deviation", "Use Gap", "NPC Deviation"))]
data_point_performance_plots <- ggplot(data_vs_pred, aes(x=true, y=mean)) +
                                  geom_abline() +
                                  geom_point(alpha=0.3) +
                                  facet_grid(.~outcome_var) + 
                                  labs(x="True Value",
                                       y="Predicted Value",
                                       title="Model fit to data for geospatial regressions")

pdf(file.path(supp_dir, "reg_performance.pdf"), width=7, height=4)
  print(data_point_performance_plots)
graphics.off()

pit_plots <- ggplot(validation_metrics, aes(x=pit)) +
              geom_histogram(bins=10) +
              theme_minimal(base_size=14) +
              facet_grid(. ~ outcome_var) +
              labs(title="PIT distribution for different models",
                   x="PIT",
                   y="Count")


pdf(file.path(supp_dir, "pit_plots.pdf"), width=7, height=4)
  print(pit_plots)
graphics.off()

## Stationarity Demo  ----------------------------------------------------------------------------------------------------------------

reg_data <- fread(file.path(cube_indir, "../03_data_for_model.csv"))
reg_data <- reg_data[, list(row_id, year, month, cellnumber, survey, iso3, time,
                            lat,
                            long=lon,
                            access=access_count/pixel_pop, 
                            use=use_count/pixel_pop,
                            percapita_nets,
                            access_dev,
                            use_gap,
                            percapita_net_dev)]
reg_data <- melt(reg_data, id.vars = c("row_id", "year", "month", "cellnumber", "survey", "iso3", "time", "lat", "long"))

reg_data[, variable_label:= factor(variable, 
                              levels = c("access", "use", "percapita_nets", "access_dev", "use_gap", "percapita_net_dev"),
                              labels = c("Access", "Use", "NPC", "Access Deviation", "Use Gap", "NPC Deviation"))]


reg_data_sp <- data.table(fortify(
                      st_as_sf(x = reg_data, 
                       coords = c("long", "lat"),
                       crs = "+proj=longlat +datum=WGS84 +ellps=WGS84 +towgs84=0,0,0")
))

reg_data_sp$long <- reg_data$long
reg_data_sp$lat <- reg_data$lat

standard_metrics <- ggplot(Africa_dt, aes(x = long, y = lat)) + 
                      geom_polygon(aes(fill=modeled, group = group)) + 
                      geom_path(aes(group = group), color = "black", size = 0.3) +
                      geom_point(data=reg_data_sp[variable %in% c("access", "use", "percapita_nets")], aes(color=value), size=0.25, alpha=0.75) +
                      facet_grid(.~variable_label) + 
                      scale_fill_manual(values=c("white","gray80"), guide="none") + 
                      scale_color_gradientn(colors=wpal("seaside", noblack = T), name="Metric") +
                      coord_equal(xlim = c(-18, 52), ylim = c(-35, 38)) +
                      labs(x = NULL, y = NULL, title = "") +
                      theme_classic(base_size = 12) +
                      theme(axis.line = element_blank(), axis.text = element_blank(), axis.ticks = element_blank(),
                            plot.margin = unit(c(0, 0, 0, 0), "in"))

dev_metrics <- ggplot(Africa_dt, aes(x = long, y = lat)) + 
                        geom_polygon(aes(fill=modeled, group = group)) + 
                        geom_path(aes(group = group), color = "black", size = 0.3) +
                        geom_point(data=reg_data_sp[variable%in% c("access_dev", "use_gap", "percapita_net_dev")], aes(color=value), size=0.25, alpha=0.75) +
                        facet_grid(.~variable_label) + 
                        scale_fill_manual(values=c("white","gray80"), guide="none") + 
                        scale_color_gradientn(colors=wpal("seaside", noblack = T), name="Deviation\nMetric") +
                        coord_equal(xlim = c(-18, 52), ylim = c(-35, 38)) +
                        labs(x = NULL, y = NULL, title = "") +
                        theme_classic(base_size = 12) +
                        theme(axis.line = element_blank(), axis.text = element_blank(), axis.ticks = element_blank(),
                              plot.margin = unit(c(0, 0, 0, 0), "in"))


pdf(file.path(supp_dir, "stationarity.pdf"), width=11, height=8)
  grid.arrange(standard_metrics, dev_metrics)
graphics.off()


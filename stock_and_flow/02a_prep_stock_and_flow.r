###############################################################################################################
## 02a_prep_stock_and_flow.r
## Amelia Bertozzi-Villa
## September 2019
## 
## A lot of the prep work for stock and flow isn't country-specific-- front-load it here.
##############################################################################################################

library(data.table)
library(rjags)
library(ggplot2)

rm(list=ls())

set.seed(084)

n.adapt=10000
update=1000000
n.iter=50000
thin=10

source("jags_functions.r")
main_dir <- "/Volumes/GoogleDrive/My Drive/stock_and_flow/input_data/"

# From Bonnie/Sam: pre-aggregated data from older surveys/reports, defer to eLife paper to explain them
mics3_data <- fread(file.path(main_dir,"00_survey_data/non_household_surveys/mics3_aggregated_08_august_2017.csv"),stringsAsFactors=FALSE)
no_report_surveydata <-fread(file.path(main_dir,"00_survey_data/non_household_surveys/other_aggregated_08_august_2017.csv"),stringsAsFactors=FALSE)

# From 01_prep_hh_survey_data: aggregated survey data. keep only needed columns;
survey_data <- fread(file.path(main_dir, "01_data_prep/itn_aggregated_survey_data.csv"),stringsAsFactors=FALSE)
survey_data <- survey_data[, list(surveyid, iso3, country, date,
                                  hh_size_mean=n_defacto_pop_mean,
                                  hh_size_se=n_defacto_pop_se,
                                  n_citn_mean=n_conv_itn_mean,
                                  n_citn_se=n_conv_itn_se,
                                  n_llin_mean,
                                  n_llin_se)]

### preprocess MICS3 Data #####----------------------------------------------------------------------------------------------------------------------------------

mics3_data[mics3_data==0] <- 1e-6 # jags dislikes zeros
mics3_list <- as.list(mics3_data)
mics3_list$survey_count <- nrow(mics3_data)

mic3_model_string = "
	model {
		for(i in 1:survey_count){

      # 'I(0,)' is truncation syntax in BUGS-- here, we're creating zero-truncated normals
			nets_per_hh[i] ~ dnorm(avg.NET.hh[i], se.NET.hh[i]^-2) I(0,)
			
			llin[i] ~ dnorm(avg.LLIN[i], se.LLIN[i]^-2) I(0,)
			citn[i] ~ dnorm(avg.ITN[i], se.ITN[i]^-2) I(0,)
			non[i] ~ dnorm(avg.NON[i], se.NON[i]^-2) I(0,)
			
			tot[i] <- llin[i] + citn[i] + non[i]

			llin_per_hh[i] <- nets_per_hh[i] * (llin[i]/tot[i]) # check: true?
			citn_per_hh[i] <- nets_per_hh[i] * (citn[i]/tot[i])
			
		}
	}
"

mics3_model <- jags.model(textConnection(mic3_model_string),
                          data = mics3_list,
                          n.chains = 1,
                          n.adapt = n.adapt)
update(mics3_model,n.iter=update)
mics3_model_output <- coda.samples(mics3_model,variable.names=c('nets_per_hh','llin','citn','tot','llin_per_hh','citn_per_hh'),
                                   n.iter=n.iter,thin=thin) 

mics3_model_estimates <- 
  rbind( as.data.table(c( metric = "mean" ,
                          list(year = mics3_data$date),
                          list(names = mics3_data$names),
                          extract_jags(c("llin_per_hh", "citn_per_hh"), colMeans(mics3_model_output[[1]])))), 
         as.data.table(c( metric = "sd" ,
                          list(year = mics3_data$date),
                          list(names = mics3_data$names),
                          extract_jags(c("llin_per_hh", "citn_per_hh"), apply(mics3_model_output[[1]],2,sd))))
  )

mics3_estimates <-data.table(surveyid=mics3_data$names,
                             country=mics3_data$Country,
                             iso3=mics3_data$ISO3,
                             date=mics3_data$date,
                             hh_size_mean=mics3_data$avg.hh.size,
                             hh_size_se=mics3_data$se.hh.size,
                             n_citn_mean=mics3_model_estimates[metric=="mean"]$citn_per_hh,
                             n_citn_se=mics3_model_estimates[metric=="sd"]$citn_per_hh,
                             n_llin_mean=mics3_model_estimates[metric=="mean"]$llin_per_hh,
                             n_llin_se=mics3_model_estimates[metric=="sd"]$llin_per_hh)

### preprocess No Report Surveys #####----------------------------------------------------------------------------------------------------------------------------------

# Justification for se calculation in eLife paper
no_report_estimates <- no_report_surveydata[, list(surveyid=paste(names, round(time)),
                                                   country=Country,
                                                   iso3=ISO3,
                                                   date=time,
                                                   hh_size_mean=average.household.size,
                                                   hh_size_se=average.household.size*0.01,
                                                   n_citn_mean=average.number.ofCITNs.per.household,
                                                   n_citn_se=average.number.ofCITNs.per.household*0.01,
                                                   n_llin_mean=average.number.of.LLINs.per.household,
                                                   n_llin_se=average.number.of.LLINs.per.household*0.01)]
no_report_estimates[no_report_estimates==0]<-1e-12

### Combine and process all surveys #####----------------------------------------------------------------------------------------------------------------------------------

survey_data <- rbind(survey_data,mics3_estimates,no_report_estimates)
survey_data <- survey_data[order(survey_data[,'date']),]

write.csv(survey_data, file.path(main_dir, "02_stock_and_flow_prep/prepped_survey_data.csv"), row.names=F)
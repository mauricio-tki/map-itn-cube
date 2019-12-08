###############################################################################################################
## 02_stock_and_flow.r
## Amelia Bertozzi-Villa
## Samir Bhatt
## July 2019
## 
## Main script for the stock and flow model
##############################################################################################################

# From Noor: many of the nets in SSD/DRC are going *to conflict areas*-- huge mismatch, not right to use as nationally representative

# possible covariates for ITN:
# - conflict area/refugee camp?
# - urban/rural
# or: get subnational distribution counts, rake to those


run_stock_and_flow <- function(this_country, start_year, end_year, main_dir, out_dir){
  
  print(paste("RUNNING STOCK AND FLOW FOR", this_country))
  
  ### Set initial values #####----------------------------------------------------------------------------------------------------------------------------------
  years <- start_year:end_year
  quarter_timesteps <- seq(start_year, end_year + 0.75, 0.25)
  set.seed(084)
  
  n.adapt=10000
  update=1000000
  n.iter=50000
  thin=10

  ### Read in all data #####----------------------------------------------------------------------------------------------------------------------------------
  
  # From WHO: NMCP data and manufacturer data
  # todo: compare 2018 and 2019
  nmcp_data<-fread(file.path(nmcp_manu_dir, "NMCP_2019.csv"),stringsAsFactors=FALSE)
  setnames(nmcp_data, "ITN", "CITN")
  
  # Set all NMCP NA's to zero based on time series patterns and notes from Manuela in TZA
  nmcp_data[is.na(LLIN), LLIN:=0]
  nmcp_data[is.na(CITN), CITN:=0]
  
  manufacturer_llins <- fread(file.path(nmcp_manu_dir, "MANU_2019.csv"),stringsAsFactors=FALSE)
  setnames(manufacturer_llins, names(manufacturer_llins), as.character(manufacturer_llins[1,]))
  manufacturer_llins <- manufacturer_llins[2:nrow(manufacturer_llins),]
  manufacturer_llins <- manufacturer_llins[Country!=""]
  manufacturer_llins[, Country := NULL]
  manufacturer_llins <- melt(manufacturer_llins, id.vars=c("MAP_Country_Name", "ISO3"), value.name="llins", variable.name="year")
  
  # From GBD2019 folder: annual population and pop at risk
  population_full <- fread(file.path(nmcp_manu_dir, "ihme_populations.csv"))
  population_full <- population_full[year>=2000 & admin_unit_level=="ADMIN0" & age_bin=="All_Ages", 
                        list(year, iso3, country_name, total_pop, pop_at_risk_pf, prop_pop_at_risk_pf=pop_at_risk_pf/total_pop)
                        ]
  
  # From 02a_prep_stock_and_flow: survey data
  survey_data <- fread(file.path(main_dir, "prepped_survey_data.csv"))
  
  # subset data
  this_survey_data <- survey_data[iso3 %in% this_country,]
  this_manufacturer_llins <- manufacturer_llins[ISO3==this_country]
  this_nmcp <- nmcp_data[ISO3==this_country]
  this_pop <- population_full[iso3==this_country & year<=end_year]
  
  # If running a sensitivity analysis, subset further
  if (!is.na(sensitivity_survey_count)){
    print(paste("RUNNING SENSITIVITY ANALYSIS: ", sensitivity_survey_count, "SURVEYS, IN ", sensitivity_type))
    
    setnames(this_survey_data, sensitivity_type, "this_order")
    this_survey_data <- this_survey_data[this_order<=sensitivity_survey_count]
    setnames(this_survey_data, "this_order", sensitivity_type)
    
    print(this_survey_data)
  }
  outdir_suffix <- ifelse(is.na(sensitivity_type), "", paste0("_", sensitivity_type))
  
  ### Formulate means and confidence around survey data #####----------------------------------------------------------------------------------------------------------------------------------
  
  # create blank dataframe if country has no surveys
  if(nrow(this_survey_data)==0){
    
    main_input_list <- list(    survey_llin_count = NA,
                                survey_llin_sd = NA,
                                survey_llin_lowerlim = NA,
                                survey_llin_upperlim = NA,
                                survey_citn_count = NA,
                                survey_citn_sd = NA,
                                survey_citn_lowerlim = NA,
                                survey_citn_upperlim = NA,
                                survey_quarter_start_indices = 1,
                                survey_quarter_end_indices = 0,
                                quarter_prop_completed = 1,
                                quarter_prop_remaining = 0,
                                manufacturer_llins = this_manufacturer_llins$llins,
                                year_count = length(years),
                                quarter_count = length(quarter_timesteps),
                                survey_count = 1,
                                population = this_pop$total_pop
    )
    
  }else { # calculate total nets from surveys 
    
    this_survey_data[this_survey_data==0] <- 1e-6 # add small amount of precision
    this_survey_data[, year:=floor(date)]
    this_survey_data <- merge(this_survey_data, this_pop[, list(year, population=total_pop)], by="year", all.x=T)
    
    totnet_calc_list <- c(as.list(this_survey_data), list(survey_count = nrow(this_survey_data)))
    
    # NOTE: I see no evidence that any of these surveys are not nationally representative; comment out
    ########### ADJUSTMENT FOR SURVEYS NOT CONDUCTED NATIONALLY BUT ON A POPULATION AT RISK BASIS
    # if(this_country=='Ethiopia') totnet_calc_list$population=c(68186507,75777180)
    # if(this_country=='Namibia') totnet_calc_list$population[totnet_calc_list$names%in%'Namibia 2009']=1426602
    # if(this_country=='Kenya') totnet_calc_list$population[totnet_calc_list$names%in%'Kenya 2007']=31148650
    ###############################################################################################
    
    survey_model_string = '
			model {
				for(i in 1:survey_count){
					hh[i] ~ dnorm(hh_size_mean[i], hh_size_se[i]^-2) I(0,)
					avg_llin[i] ~ dnorm(n_llin_mean[i],n_llin_se[i]^-2) I(0,)
					avg_citn[i] ~ dnorm(n_citn_mean[i],n_citn_se[i]^-2) I(0,)	
					
					llin_count[i] <- (avg_llin[i]*population[i]/hh[i]) 	
					citn_count[i] <- (avg_citn[i]*population[i]/hh[i])	
					
				}
			}
		'
    survey_prep_model <- jags.model(textConnection(survey_model_string),
                                    data = totnet_calc_list,
                                    n.chains = 1,
                                    n.adapt = n.adapt)
    update(survey_prep_model,n.iter=update)
    
    survey_model_output <- coda.samples(survey_prep_model,variable.names=c('llin_count','citn_count', 'avg_llin', 'avg_citn'),n.iter=n.iter, thin=50) 
    
    survey_model_estimates <- 
      rbind( as.data.table(c( metric = "mean" ,
                              list(year = totnet_calc_list$date),
                              extract_jags(c("llin_count", "citn_count"), colMeans(survey_model_output[[1]]))
                              )), 
             as.data.table(c( metric = "sd" ,
                              list(year = totnet_calc_list$date),
                              extract_jags(c("llin_count", "citn_count"), apply(survey_model_output[[1]],2,sd))))
      )
    
    survey_model_estimates <- melt(survey_model_estimates, id.vars = c("metric", "year"), value.name="net_count")
    survey_model_estimates <- dcast.data.table(survey_model_estimates, variable + year ~ metric)
    
    # add parameter limits for big model
    sd_limit_multiplier <- 3
    survey_model_estimates <- survey_model_estimates[, list(variable, year, mean, sd, 
                                                            lower_limit= pmax(mean - sd*sd_limit_multiplier, 0),
                                                            upper_limit= pmax(mean + sd*sd_limit_multiplier, 0)
    )]
    
    ggplot(survey_model_estimates, aes(x=year, color=variable)) + 
      geom_linerange(aes(ymin=lower_limit, ymax=upper_limit)) +
      geom_point(aes(y=mean)) +
      facet_grid(.~variable) +
      labs(title= paste("Survey Data Estimates:", this_country),
           x="Year",
           y="Nets")
  
    # quarter indices
   start_indices <-  sapply(floor(totnet_calc_list$date/0.25) * 0.25, function(time){which(time==quarter_timesteps)})
   end_indices <- start_indices+1
    
    # TODO: ADD SURVEY DATES
    main_input_list <- list(survey_llin_count = survey_model_estimates[variable=="llin_count"]$mean,
                            survey_llin_sd = survey_model_estimates[variable=="llin_count"]$sd,
                            survey_llin_lowerlim = survey_model_estimates[variable=="llin_count"]$lower_limit,
                            survey_llin_upperlim = survey_model_estimates[variable=="llin_count"]$upper_limit,
                            survey_citn_count = survey_model_estimates[variable=="citn_count"]$mean,
                            survey_citn_sd = survey_model_estimates[variable=="citn_count"]$sd,
                            survey_citn_lowerlim = survey_model_estimates[variable=="citn_count"]$lower_limit,
                            survey_citn_upperlim = survey_model_estimates[variable=="citn_count"]$upper_limit,
                            survey_quarter_start_indices = start_indices,
                            survey_quarter_end_indices = end_indices,
                            quarter_prop_completed = (totnet_calc_list$date - floor(totnet_calc_list$date/0.25) * 0.25)/0.25, # % of quarter elapsed
                            quarter_prop_remaining = 1- (totnet_calc_list$date - floor(totnet_calc_list$date/0.25) * 0.25)/0.25, # % of quarter yet to come
                            manufacturer_llins = this_manufacturer_llins$llins,
                            year_count = length(years),
                            quarter_count = length(quarter_timesteps),
                            survey_count = totnet_calc_list$survey_count,
                            population = this_pop$total_pop
    )
  }
  
  ### Format NMCP reports  #####----------------------------------------------------------------------------------------------------------------------------------
  
  # set llins to zero in early years for which manufacturers didn't report any nets 
  # TODO: shouldn't model cap this anyway?
  this_nmcp[this_manufacturer_llins$llins==0, LLIN:=0]
  
  # find nets per person, drop NAs but track indices of non-null years for GP prior
  this_nmcp <- melt(this_nmcp, id.vars=c("MAP_Country_Name", "ISO3", "year"),
                    measure.vars = c("LLIN", "CITN"),
                    variable.name = "type", value.name = "nmcp_count")
  
  this_nmcp <- merge(this_nmcp, this_pop[, list(ISO3=iso3, year, total_pop)], by=c("ISO3", "year"), all=T)
  this_nmcp[, nmcp_nets_percapita := nmcp_count/total_pop]
  this_nmcp[, type:=tolower(type)]
  this_nmcp[, nmcp_year_indices:= year-start_year+1]
  
  # it happens sometimes (TCD, GNQ) that the NMCP time series is entirely NA for citns.
  # It's safe to assume that there were no citns distributed in the past year, so change 
  # this to zero to avoid breaking the script.
  if(nrow(this_nmcp[type=="citn" & !is.na(nmcp_count)])==0){
    this_nmcp[type=="citn" & year==end_year, nmcp_count:=0]
    this_nmcp[type=="citn" & year==end_year, nmcp_nets_percapita:=0]
  }
  
  # convert to list format for model
  nmcp_list <- lapply(c("llin", "citn"), function(net_type){
    subset <- dcast.data.table(this_nmcp[type==net_type &  !is.na(nmcp_count)], year ~ type,
                               value.var = c("nmcp_count", "nmcp_nets_percapita", "nmcp_year_indices"))
    subset[, year:=NULL]
    subset_list <- c(as.list(subset), year_count=nrow(subset))
    names(subset_list) <- c(names(subset), paste0("nmcp_year_count_", net_type))
    return(subset_list)
  })
  nmcp_list <- unlist(nmcp_list, recursive = F)
  
  main_input_list <- c(main_input_list, nmcp_list)
  
  ### Store population at risk parameters.  #####----------------------------------------------------------------------------------------------------------------------------------
  # store population at risk parameter 
  main_input_list$PAR <- mean(this_pop$prop_pop_at_risk_pf)
  
  ### create "counter" matrix that marks time since net distribution for each quarter   #####----------------------------------------------------------------------------------------------------------------------------------
  quarter_count <- main_input_list$quarter_count
  time_since_distribution <- matrix(rep(NA, quarter_count^2), ncol=quarter_count)
  for (i in 1:quarter_count){
    for (j in 1:quarter_count){
      time_since_distribution[i,j] <- ifelse(j>i, -9, ifelse(j==i, 0, time_since_distribution[i-1, j]+0.25)) 
    }
  }
  main_input_list$time_since_distribution <- time_since_distribution
  
  
  ### Prep moving average #####----------------------------------------------------------------------------------------------------------------------------------
  # binary matrix showing which years to average
  ncol <- length(years)
  rows <- lapply(1:(ncol-4), function(row_idx){
    c( rep(0, row_idx-1),
       rep(1, 5),
       rep(0, ncol-5-row_idx+1)
    )
  })
  movingavg_indicators <- do.call(rbind, rows)
  moving_avg_weights <- prop.table(movingavg_indicators, 2) # scale to one in each column
  
  # add to main_input_list list
  main_input_list$moving_avg_weights <- moving_avg_weights
  main_input_list$nrow_moving_avg <- nrow(moving_avg_weights)
  
  # Testing loss with two loss parameters (one before, one after a given year)
  pivot_year <- 2010
  main_input_list$loss_function_pivot_quarter <- which(years==pivot_year)*4 # change to a cutoff quarter because loss is calculated quarterly
  
  
  ### load indicator priors #####----------------------------------------------------------------------------------------------------------------------------------
  extract_prior <- function(varname, data){
    subset <- data[variable==varname]
    this_list <- list(mean=subset$mean, sd=subset$sd)
    names(this_list) <- c(paste0(varname, "_mean"), paste0(varname, "_sd"))
    return(this_list)
  }
  
  indicator_priors <- fread(file.path(main_dir, "indicator_priors.csv"))
  
  no_net_props <- dcast.data.table(indicator_priors[model_type=="no_net_prob"], sample  ~ variable, value.var = "value")
  
  mean_net_counts <- indicator_priors[model_type=="mean_net_count"]
  mean_net_counts[, variable:=factor(variable, levels=c(paste0("intercept_hhsize_", 1:10), paste0("nets_percapita_slope_hhsize_", 1:10)))]
  mean_net_counts <-   mean_net_counts[order(variable)]
  
  mean_net_counts_intercept <- dcast.data.table(  mean_net_counts[variable %like% "intercept"], sample  ~ variable, value.var = "value")
  mean_net_counts_slope <- dcast.data.table(  mean_net_counts[variable %like% "slope"], sample  ~ variable, value.var = "value")
  
  main_input_list <- c(main_input_list, as.list(no_net_props[,2:7]), 
                       list(mean_net_counts_intercept=as.matrix(mean_net_counts_intercept[,2:11]),
                            mean_net_counts_slope=as.matrix(mean_net_counts_slope[,2:11]), max_hhsize=10))
  
  ### Main model string  #####----------------------------------------------------------------------------------------------------------------------------------
  
  model_preface <- "model {"
  model_suffix <- "}"
  
  # see equations 5, and 17-22 of supplement
  annual_stock_and_flow <- "
					for(year_idx in 1:year_count){
						
						manufacturer_sigma[year_idx] ~ dunif(0, 0.075) 	 # error in llin manufacturer	
						manufacturer_llins_est[year_idx] ~ dnorm(manufacturer_llins[year_idx], ((manufacturer_llins[year_idx]+1e-12)*manufacturer_sigma[year_idx])^-2) T(0,)
						
						# error in percapita NMCP distributions
						nmcp_sigma_llin[year_idx] ~ dunif(0, 0.01) 	 			
						nmcp_sigma_citn[year_idx] ~ dunif(0, 0.01) 	 
						nmcp_nets_percapita_llin_est[year_idx] ~ dnorm(nmcp_nets_percapita_llin[year_idx], nmcp_sigma_llin[year_idx]^-2) T(0,)
						nmcp_nets_percapita_citn_est[year_idx] ~ dnorm(nmcp_nets_percapita_citn[year_idx], nmcp_sigma_citn[year_idx]^-2) T(0,)
						
            # start with priors from GP
						nmcp_count_llin_est[year_idx] <- max(0, nmcp_nets_percapita_llin_est[year_idx]*population[year_idx])
						nmcp_count_citn_est[year_idx] <- max(0, nmcp_nets_percapita_citn_est[year_idx]*population[year_idx])			
										
					}
							
					##### initialise with zero stock
					# initial distribution count: smaller of manufacturer count or nmcp count
					raw_llins_distributed[1] <- min(nmcp_count_llin_est[1], manufacturer_llins_est[1]) 
					
					# initial stock: number of nets from manufacturer 
					initial_stock[1] <- manufacturer_llins_est[1] 
					
					# add some uncertainty about additional nets distributed
					distribution_uncertainty_betapar[1] ~ dunif(20,24) # TEST: letting this time-vary, but over a much smaller range
					llin_distribution_noise[1] ~ dbeta(2, distribution_uncertainty_betapar[1]) T(0, 0.25) # TEST: bounding noise parameter
					# distribution_uncertainty_betapar ~ dunif(1,24)
					# llin_distribution_noise ~ dbeta(2,distribution_uncertainty_betapar) 
					
					# initial distribution count, with uncertainty
					adjusted_llins_distributed[1] <- raw_llins_distributed[1] + ((initial_stock[1]-raw_llins_distributed[1])*llin_distribution_noise[1]) 
					
					# final stock (initial stock minus distribution for the year)
					final_stock[1] <- initial_stock[1] - adjusted_llins_distributed[1]
				
					##### loop to get stocks and capped llins_distributeds
					for(year_idx in 2:year_count){
					  
					  # initial stock: last year's final stock + nets from manufacturer 
						initial_stock[year_idx] <- final_stock[year_idx-1] + manufacturer_llins_est[year_idx]
					  
					  # net distribution count: smaller of initial stock or nmcp count
						raw_llins_distributed[year_idx] <- min(nmcp_count_llin_est[year_idx] , initial_stock[year_idx])					
						
						# add some uncertainty about additional nets distributed
						distribution_uncertainty_betapar[year_idx]~dunif(20, 24) 
						llin_distribution_noise[year_idx]~dbeta(2, distribution_uncertainty_betapar[year_idx]) T(0, 0.25)
						
						# net distribution count, with uncertainty 
						adjusted_llins_distributed[year_idx] <- raw_llins_distributed[year_idx] + ((initial_stock[year_idx]-raw_llins_distributed[year_idx]) * llin_distribution_noise[year_idx])
						
						# final stock for the year (initial stock minus distribution for the year)
						final_stock[year_idx] <- initial_stock[year_idx]-adjusted_llins_distributed[year_idx]	
					}"
  
  #test_snippet(paste(model_preface, nmcp_llins, nmcp_citns, annual_stock_and_flow, model_suffix), test_data = main_input_list)
  
  # loss functions and quarterly distribution-- see section 3.2.2.3
  llin_quarterly <- 
          "
          #  stationary sigmoidal loss parameter
          k_llin <- 20 
          
          # allow rate of loss to vary before and after the cutoff loss_function_pivot_quarter, but only so much
          # TEST: only one llin loss rate
          L_llin[1] ~ dunif(4,20.7)
          # L_llin[2] ~ dunif(L_llin[1]-2.5, L_llin[1]+2.5)
          L_llin[2] <- L_llin[1]
          
          # find proportions for quarterly llin distributions
          for(j in 1:year_count){
            quarter_draws_llin[j,1] ~ dunif(0,1)
            quarter_draws_llin[j,2] ~ dunif(0,1)
            quarter_draws_llin[j,3] ~ dunif(0,1)
            quarter_draws_llin[j,4] ~ dunif(0,1)
            quarter_draws_llin[j,5] <- sum(quarter_draws_llin[j,1:4])
            
            quarter_fractions_llin[j,1] <- quarter_draws_llin[j,1]/quarter_draws_llin[j,5]
            quarter_fractions_llin[j,2] <- quarter_draws_llin[j,2]/quarter_draws_llin[j,5]
            quarter_fractions_llin[j,3] <- quarter_draws_llin[j,3]/quarter_draws_llin[j,5]
            quarter_fractions_llin[j,4] <- quarter_draws_llin[j,4]/quarter_draws_llin[j,5]
          }
          
          # distribute llins across quarters; calculate loss to find expected nets in homes per quarter
          # here '(round(j/4+0.3))' is a way of finding year index and '(round(j/4+0.3)-1))*4)' is a way of finding modulo 4 quarter index
          for (j in 1:quarter_count){
            llins_distributed_quarterly[j] <- adjusted_llins_distributed[(round(j/4+0.3))] * quarter_fractions_llin[(round(j/4+0.3)), (((j/4)-(round(j/4+0.3)-1))*4) ] # todo: find easier math
            for (i in 1:loss_function_pivot_quarter){
              # sigm:
              quarterly_nets_remaining_matrix_llin[i,j] <- ifelse(j>i, 0, ifelse(time_since_distribution[i,j] >= L_llin[1], 0, llins_distributed_quarterly[j] * exp(k_llin - k_llin/(1-(time_since_distribution[i,j]/L_llin[1])^2))))
            }
            for (i in (loss_function_pivot_quarter+1):quarter_count){
              # sigm:
              quarterly_nets_remaining_matrix_llin[i,j] <- ifelse(j>i, 0, ifelse(time_since_distribution[i,j] >= L_llin[2], 0, llins_distributed_quarterly[j] * exp(k_llin - k_llin/(1-(time_since_distribution[i,j]/L_llin[2])^2))))

            }
          }
            
          "

# test_snippet(paste( model_preface, nmcp_llins, nmcp_citns, annual_stock_and_flow, llin_quarterly, model_suffix), test_data = main_input_list)

citn_quarterly <- 
          " 
          #  stationary sigmoidal loss parameter
          k_citn <- 20 
          
          # TEST: only one citn loss rate
          L_citn[1] ~ dunif(4,20.7)
          # L_citn[2] ~ dunif(4,20.7)
          L_citn[2] <- L_citn[1]
            
          # find proportions for quarterly citn distributions
          for(j in 1:year_count){
              quarter_draws_citn[j,1] ~ dunif(0,1)
              quarter_draws_citn[j,2] ~ dunif(0,1)
              quarter_draws_citn[j,3] ~ dunif(0,1)
              quarter_draws_citn[j,4] ~ dunif(0,1)
              quarter_draws_citn[j,5] <- sum(quarter_draws_citn[j,1:4])
              
              quarter_fractions_citn[j,1] <- quarter_draws_citn[j,1]/quarter_draws_citn[j,5]
              quarter_fractions_citn[j,2] <- quarter_draws_citn[j,2]/quarter_draws_citn[j,5]
              quarter_fractions_citn[j,3] <- quarter_draws_citn[j,3]/quarter_draws_citn[j,5]
              quarter_fractions_citn[j,4] <- quarter_draws_citn[j,4]/quarter_draws_citn[j,5]
            }
            
            # distribute citns across quarters
            for (j in 1:quarter_count){
              citns_distributed_quarterly[j] <- nmcp_count_citn_est[(round(j/4+0.3))] * quarter_fractions_citn[(round(j/4+0.3)), (((j/4)-(round(j/4+0.3)-1))*4) ] # todo: find easier math
              for (i in 1:loss_function_pivot_quarter){
              # sigm:
              quarterly_nets_remaining_matrix_citn[i,j] <- ifelse(j>i, 0, ifelse(time_since_distribution[i,j] >= L_citn[1], 0, citns_distributed_quarterly[j] * exp(k_citn - k_citn/(1-(time_since_distribution[i,j]/L_citn[1])^2))))
              }
              for (i in (loss_function_pivot_quarter+1):quarter_count){
              # sigm:
              quarterly_nets_remaining_matrix_citn[i,j] <- ifelse(j>i, 0, ifelse(time_since_distribution[i,j] >= L_citn[2], 0, citns_distributed_quarterly[j] * exp(k_citn - k_citn/(1-(time_since_distribution[i,j]/L_citn[2])^2))))
              }
            }
  
        "

# test_snippet(paste( model_preface, nmcp_llins, nmcp_citns, annual_stock_and_flow, citn_quarterly, model_suffix), test_data = main_input_list)

accounting <- "for(i in 1:quarter_count){
				quarterly_nets_in_houses_llin[i]<-sum(quarterly_nets_remaining_matrix_llin[i,1:quarter_count])
				quarterly_nets_in_houses_citn[i]<-sum(quarterly_nets_remaining_matrix_citn[i,1:quarter_count])
				
				# total_percapita_nets is the percapita net count in the true population-at-risk
				total_percapita_nets[i] <- max( (quarterly_nets_in_houses_llin[i]+quarterly_nets_in_houses_citn[i])/(PAR*population[(round(i/4+0.3))]), 0) 
			}
  
      # for data in the final quarter of the final year
      quarterly_nets_in_houses_llin[quarter_count+1] <- quarterly_nets_in_houses_llin[quarter_count]
      quarterly_nets_in_houses_citn[quarter_count+1] <- quarterly_nets_in_houses_citn[quarter_count]
  
  "

# triggered if there are no nulls in survey data (survey_llin_sd or survey_citn_sd). pretty sure this only happens when there are no surveys, but need to confirm
surveys <- "for(i in 1:survey_count){
				survey_quarter_start_index[i] <- survey_quarter_start_indices[i]	 
				survey_quarter_end_index[i] <- survey_quarter_end_indices[i]	 	
				
				# to estimate # of nets at time of survey, linearly interpolate between the surrounding quartrly estimates 
				survey_llin_count_est[i] <- quarter_prop_completed[i] * quarterly_nets_in_houses_llin[survey_quarter_start_index[i]] + quarter_prop_remaining[i] * quarterly_nets_in_houses_llin[survey_quarter_end_index[i]]
				survey_citn_count_est[i] <- quarter_prop_completed[i] * quarterly_nets_in_houses_citn[survey_quarter_start_index[i]] + quarter_prop_remaining[i] * quarterly_nets_in_houses_citn[survey_quarter_end_index[i]]
				survey_total_est[i] <- survey_llin_count_est[i] + survey_citn_count_est[i] # TODO: never used
				
				survey_llin_count[i] ~ dnorm(survey_llin_count_est[i], survey_llin_sd[i]^-2)	T(survey_llin_lowerlim[i], survey_llin_upperlim[i])
				survey_citn_count[i] ~ dnorm(survey_citn_count_est[i], survey_citn_sd[i]^-2) T(survey_citn_lowerlim[i], survey_citn_upperlim[i])
			}"

indicators <- "

      nonet_trace ~ dunif(1,5000)
			nonet_sample <- round(nonet_trace)

			mean_net_trace ~ dunif(1,5000)
			mean_net_sample <- round(mean_net_trace)
      
      # priors for mean nets
      for(i in 1:max_hhsize){
			  alpha_mean_nets[i] <- mean_net_counts_intercept[mean_net_sample, i]
			  beta_mean_nets[i] <- mean_net_counts_slope[mean_net_sample, i]
			}
      
      for (i in 1:quarter_count){
        for (j in 1:max_hhsize){
          nonet_prop_est[i,j] <- alpha_nonet_prop[nonet_sample] + p1_nonet_prop[nonet_sample]*j + p2_nonet_prop[nonet_sample]*pow(j,2) + b1_nonet_prop[nonet_sample]*total_percapita_nets[i] + b2_nonet_prop[nonet_sample]*pow(total_percapita_nets[i],2) + b3_nonet_prop[nonet_sample]*pow(total_percapita_nets[i],3)
          mean_net_count_est[i,j] <- alpha_mean_nets[j] + beta_mean_nets[j]*total_percapita_nets[i]
        }
      }

"
# test_snippet(paste( model_preface, nmcp_llins, nmcp_citns, annual_stock_and_flow, llin_quarterly, citn_quarterly, accounting, indicators, model_suffix), test_data = main_input_list)

if(any(is.na(main_input_list$survey_llin_sd)) | any(is.na(main_input_list$survey_citn_sd))){
  full_model_string <- paste(model_preface, 
                             # nmcp_llins, 
                             # nmcp_citns, 
                             annual_stock_and_flow, 
                             llin_quarterly, 
                             citn_quarterly, 
                             accounting, 
                             indicators, 
                             model_suffix,
                             sep="\n")
}else{
  full_model_string <- paste(model_preface, 
                             # nmcp_llins, 
                             # nmcp_citns, 
                             annual_stock_and_flow, 
                             llin_quarterly, 
                             citn_quarterly, 
                             accounting, 
                             surveys,  # this is the only difference
                             indicators, 
                             model_suffix,
                             sep="\n")
  
}
  
# write to file. TODO: can write this to jags?
fileConn<-file(file.path(out_dir, paste0(this_country, "_model", outdir_suffix, ".txt")))
writeLines(full_model_string, fileConn)
close(fileConn)


### Run model  #####----------------------------------------------------------------------------------------------------------------------------------

tic <- Sys.time()

jags <- jags.model(file=textConnection(full_model_string),
                   data = main_input_list,
                   n.chains = 1,
                   n.adapt=n.adapt)

update(jags,n.iter=update)

names_to_extract <- c(
                      "nmcp_nets_percapita_llin_est",
                      "nmcp_nets_percapita_citn_est",
                      "manufacturer_llins_est",
                      "nmcp_count_llin_est",
                      "nmcp_count_citn_est",
                      "llin_distribution_noise",
                      "distribution_uncertainty_betapar",
                      "raw_llins_distributed",
                      "initial_stock",
                      "adjusted_llins_distributed",
                      "final_stock",
                      "k_llin",
                      "L_llin",
                      "llins_distributed_quarterly",
                      "quarterly_nets_remaining_matrix_llin",
                      "k_citn",
                      "L_citn",
                      "citns_distributed_quarterly",
                      "quarterly_nets_remaining_matrix_citn",
                      "quarterly_nets_in_houses_llin",
                      "quarterly_nets_in_houses_citn",
                      "total_percapita_nets",
                      "survey_llin_count_est",
                      "survey_citn_count_est",
                      "survey_llin_count",
                      "survey_citn_count",
                      "p1_nonet_prop",
                      "p2_nonet_prop",
                      "b1_nonet_prop",
                      "b2_nonet_prop",
                      "b3_nonet_prop",
                      "alpha_mean_nets",
                      "beta_mean_nets",
                      "nonet_prop_est",
                      "mean_net_count_est"
)

jdat <- coda.samples(jags,variable.names=names_to_extract,
                     n.iter=n.iter,thin=thin) 

toc <- Sys.time()

time_elapsed <- toc-tic
print(paste("Time elapsed for model fitting:", time_elapsed))

time_df <- data.table(iso3=this_country, time=time_elapsed)
write.csv(time_df, file=file.path(out_dir, paste0(this_country, "_time", outdir_suffix, ".csv")), row.names = F)

### Extract values  #####----------------------------------------------------------------------------------------------------------------------------------

raw_estimates <-colMeans(jdat[[1]])
model_estimates <- extract_jags(names_to_extract, raw_estimates)

# transformations
model_estimates[["nonet_prop_est"]] <- plogis(model_estimates[["nonet_prop_est"]])
model_estimates[["quarterly_nets_in_houses_llin"]] <- model_estimates[["quarterly_nets_in_houses_llin"]][1:quarter_count]
model_estimates[["quarterly_nets_in_houses_citn"]] <- model_estimates[["quarterly_nets_in_houses_citn"]][1:quarter_count]

# uncertainty for some values
raw_posterior_densities <- HPDinterval(jdat)[[1]]

uncertainty_vals <- c('llins_distributed_quarterly',
                      'citns_distributed_quarterly',
                      'quarterly_nets_in_houses_llin',
                      'quarterly_nets_in_houses_citn')

posterior_densities <- lapply(uncertainty_vals, function(this_name){
  posteriors <- raw_posterior_densities[rownames(raw_posterior_densities) %like% this_name,]
  posteriors <- data.table(posteriors)
  
  # remove the final interpolation of quarterly_nets_in_houses
  if (this_name %like% "quarterly_nets_in_houses" & nrow(posteriors)>length(quarter_timesteps)){
    posteriors <- posteriors[1:length(quarter_timesteps)]
  }
  
  if (nrow(posteriors)==length(quarter_timesteps)){
    posteriors[, year:=quarter_timesteps]
  }
  posteriors[, metric:=this_name]
  return(posteriors)
})
posterior_densities <- rbindlist(posterior_densities)



### Indicators  #####----------------------------------------------------------------------------------------------------------------------------------

## Actually, no indicators for now-- I don't think I want to maintain the same ones anyway


### Saving  #####----------------------------------------------------------------------------------------------------------------------------------

save(list = ls(all.names = TRUE), file = file.path(out_dir, paste0(this_country, "_all_output", outdir_suffix, ".RData")), envir = environment())

}

# DSUB FOR MAIN RUN
# dsub --provider google-v2 --project map-special-0001 --boot-disk-size 50 --image gcr.io/map-special-0001/map_rocker_jars:4-3-0 --regions europe-west1 --label "type=itn_stockflow" --machine-type n1-standard-4 --logging gs://map_users/amelia/itn/stock_and_flow/logs --input-recursive main_dir=gs://map_users/amelia/itn/stock_and_flow/input_data/01_input_data_prep/20191205 nmcp_manu_dir=gs://map_users/amelia/itn/stock_and_flow/input_data/00_survey_nmcp_manufacturer/nmcp_manufacturer_from_who CODE=gs://map_users/amelia/itn/code/stock_and_flow/ --output-recursive out_dir=gs://map_users/amelia/itn/stock_and_flow/results/20191205_new_surveydata --command 'cd ${CODE}; Rscript 03_stock_and_flow.r ${this_country}' --tasks gs://map_users/amelia/itn/code/stock_and_flow/for_gcloud/batch_country_list_TESTING.tsv

# DSUB FOR SENSITIVITY ANALYSIS
# dsub --provider google-v2 --project map-special-0001 --boot-disk-size 50 --image gcr.io/map-special-0001/map_rocker_jars:4-3-0 --regions europe-west1 --label "type=itn_stockflow" --machine-type n1-standard-4 --logging gs://map_users/amelia/itn/stock_and_flow/logs --input-recursive main_dir=gs://map_users/amelia/itn/stock_and_flow/input_data/01_input_data_prep/20191205 nmcp_manu_dir=gs://map_users/amelia/itn/stock_and_flow/input_data/00_survey_nmcp_manufacturer/nmcp_manufacturer_from_who CODE=gs://map_users/amelia/itn/code/stock_and_flow/ --output-recursive out_dir=gs://map_users/amelia/itn/stock_and_flow/results/20191207_sensitivity_test --command 'cd ${CODE}; Rscript 03_stock_and_flow.r ${this_country} ${survey_count} ${order_type}' --tasks gs://map_users/amelia/itn/code/stock_and_flow/for_gcloud/batch_sensitivity_TESTING.tsv


package_load <- function(package_list){
  # package installation/loading
  new_packages <- package_list[!(package_list %in% installed.packages()[,"Package"])]
  if(length(new_packages)) install.packages(new_packages)
  lapply(package_list, library, character.only=T)
}

package_load(c("data.table","raster","rjags", "zoo", "ggplot2"))

if(Sys.getenv("main_dir")=="") {
  nmcp_manu_dir <- "/Volumes/GoogleDrive/My Drive/stock_and_flow/input_data/00_survey_nmcp_manufacturer/nmcp_manufacturer_from_who"
  main_dir <- "/Volumes/GoogleDrive/My Drive/stock_and_flow/input_data/01_input_data_prep/20191205"
  out_dir <- "/Volumes/GoogleDrive/My Drive/stock_and_flow/results/testing"
  this_country <- "NGA"
  sensitivity_survey_count <- 3
  sensitivity_type <- "chron_order"
} else {
  main_dir <- Sys.getenv("main_dir")
  nmcp_manu_dir <- Sys.getenv("nmcp_manu_dir") 
  out_dir <- Sys.getenv("out_dir") 
  this_country <- commandArgs(trailingOnly=TRUE)[1]
  sensitivity_survey_count <- commandArgs(trailingOnly=TRUE)[2]
  sensitivity_type <- commandArgs(trailingOnly=TRUE)[3]
}

source("jags_functions.r")
start_year <- 2000
end_year<- 2018

gg_color_hue <- function(n) {
  hues = seq(15, 375, length = n + 1)
  hcl(h = hues, l = 65, c = 100)[1:n]
}

run_stock_and_flow(this_country, start_year, end_year, main_dir, out_dir)






###############################################################################################################
## 03_05_general_functions.r
## Amelia Bertozzi-Villa
## May 2019
## 
## Functions to accompany 03_access_dev.r 

## -emplogit: 1-value empirial logit. 
## -other_emplogit: compare to emplogit
## -emplogit2: 2-input empirical logit
## - ll.to.xyz: convert a set of lat-longs to cartesian gridpoints.

## -reposition.points: adjust impossibly-placed lat-longs
## -aggregate.data: sum to pixel level (TODO: fix column bug)
## -calc_access_matrix: calculate access metrics by household size from stock and flow outputs
##############################################################################################################


emplogit<-function(Y,tol){
  # Y: value to transform
  # tol: tolerance value to prevent zeros
  top=Y*tol+0.5
  bottom=tol*(1-Y)+0.5
  return(log(top/bottom))
}

other_emplogit <- function(Y, tol){
  top = tol + Y
  bottom = 1 - Y + tol
  return(log(top/bottom))
}

emplogit2<-function(Y,N){
  # approximation of a log odds
  # Y: # of occurrences of interest
  # N: # of tries
  top=Y+0.5
  bottom=N-Y+0.5
  return(log(top/bottom))
}


# Inverse Hyperbolic sin transform
ihs <- function(x, theta){  # function to IHS transform
  return(asinh(theta * x)/theta) 
}

# Inverse of the inverse hyperbolic sin transform
inv_ihs <- function(x, theta){
  (1/theta)*sinh(theta * x)
}

# Inverse hyperbolic sin transform-- log-likelihood
ihs_loglik <- function(theta,x){
  
  n <- length(x)
  xt <- ihs(x, theta)
  
  log.lik <- -n*log(sum((xt - mean(xt))^2))- sum(log(1+theta^2*x^2))
  return(log.lik)
}

ll_to_xyz<-function(ll){
  
  ## ll: data.table with columns "row_id", "longitude", "latitude"
  ll <- ll[, list(row_id, longitude, latitude,
                  longitude_rad=longitude*(pi/180),
                  latitude_rad=latitude*(pi/180))]
  
  xyz <- ll[, list(row_id,
                   x=cos(latitude_rad) * cos(longitude_rad),
                   y=cos(latitude_rad) * sin(longitude_rad),
                   z=sin(latitude_rad))]
  
  return(xyz)
}


run_inla <- function(data, outcome_var, start_year, end_year){
  
  # initialize inla
  INLA:::inla.dynload.workaround() 
  
  # generate spatial mesh using unique xyz values 
  # TODO: is this all xyz is used for?
  spatial_mesh = inla.mesh.2d(loc= unique(data[, list(x,y,z)]),
                              cutoff=0.006,
                              min.angle=c(25,25),
                              max.edge=c(0.06,500) )
  print(paste("New mesh constructed:", spatial_mesh$n, "vertices"))
  
  # generate spde matern model from mesh
  spde_matern =inla.spde2.matern(spatial_mesh,alpha=2) 
  
  # generate temporal mesh
  temporal_mesh=inla.mesh.1d(seq(start_year,end_year,by=2),interval=c(start_year,end_year),degree=2) 
  
  # prep data for model fitting
  cov_list<-data[, cov_names, with=F]
  cov_list$year <- data$yearqtr
  cov_list <-as.list(cov_list)
  
  # generate observation matrix
  A_est =
    inla.spde.make.A(spatial_mesh, 
                     loc=as.matrix(data[, list(x,y,z)]), 
                     group=data$yearqtr,
                     group.mesh=temporal_mesh)
  field_indices = inla.spde.make.index("field", n.spde=spatial_mesh$n,n.group=temporal_mesh$m)
  
  # Generate "stack"
  stack_est = inla.stack(data=list(response=data[[outcome_var]]),
                         A=list(A_est,1),
                         effects=
                           list(c(field_indices,
                                  list(Intercept=1)),
                                c(cov_list)),
                         tag="est", remove.unused=TRUE)
  stack_est<-inla.stack(stack_est)
  
  model_formula<- as.formula(paste(
    paste("response ~ -1 + Intercept  + "),
    paste("f(field, model=spde_matern, group=field.group, control.group=list(model='ar1')) + ",sep=""),
    paste(cov_names,collapse="+"),
    sep=""))
  
  #-- Call INLA and get results --#
  inla_model =   inla(model_formula,
                      data=inla.stack.data(stack_est),
                      family=c("gaussian"),
                      control.predictor=list(A=inla.stack.A(stack_est), compute=TRUE,quantiles=NULL),
                      control.compute=list(cpo=TRUE,waic=TRUE),
                      keep=FALSE, verbose=TRUE,
                      control.inla= list(strategy = "gaussian",
                                         int.strategy="ccd", # close composite design ?
                                         verbose=TRUE,
                                         step.factor=1,
                                         stupid.search=FALSE)
  )
  
  print(summary(inla_model))
  
  return(list(inla_model, spatial_mesh))
  
}





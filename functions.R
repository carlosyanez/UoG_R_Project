############################################################################################################
########################### ODL Masters in Data Analytics - University of Glasgow ########################## 
###########################  R Programming T1 2020/2021                           ########################## 
###########################  Assignment 4 (PROJECT) - Due Date 25 Jan 2021        ##########################
#####  AUTHOR: Carlos YÁÑEZ SANTIBÁÑEZ   ###################################################################


############################### FUNCTIONS USED ACROSS SHINY AND MARKDOWN ############################### 
### !!!!! WARNING !!!!! THE FOLLOWING SCRIPT WILL INSTALL PACKAGES
#### THIS WON'T WORK ON shinyapps.io - include shinyapps_io.R file when deploying

############################### 
### LOAD PACKAGES  - IT WILL INSTALL THEM IF NOT FOUND

packages <- c("lubridate",      #date manipulation (tidyverse)
              "leaflet",        # interactive maps
              "maps",           # used to create UK bounding box
              "paletteer",      # colour palette wrapper for ggplot
              "ggsci",          # colour palette
              "showtext",       # add fonts
              "ggiraph",        # interactive charts
              "data.table",     #  function rbdinlist
              "flextable",      # static table (for word document) 
              "officer",        # functions for word document
              "DT",             # interactive table
              "rmarkdown")      # knitting with markdown



loaded_packages <- paste0(search(),sep=" ",collapse = "")
packages <- tibble(package = packages)
packages <- packages %>% mutate(loaded=str_detect(loaded_packages, package, negate = FALSE)) %>% pull(package)

if(length(packages)>0 ){
  for(i in 1:length(packages)){
    result <- require(packages[i],character.only = TRUE)
    if(!result){
      install.packages(packages[i])
      library(packages[i],character.only = TRUE)
    }
  }
}
rm(packages,i,result)


############################### 
### LOAD FONTS USED IN PLOTS 

font_add_google("Roboto","Roboto")
#font_add("Arial Narrow","Arial Narrow")
showtext_auto()
colour_palette <- "ggsci::nrc_npg"


#############################
### Keys

meas_key <- tibble(key=c("Air Temperature","Relative Humidity","Wind Speed","Visibility"),
                   value=c("air_temperature","rltv_hum","wind_speed","visibility"))
period_key <- tibble(key=c("Daily","Monthly","Raw Data"),
                     value=c("daily","monthly","raw"))
stat_key <- tibble(key=c("Averages","Maxima","Minima","Raw"),
                   value=c("mean","max","min","raw"),
                   daily_filter=c(TRUE,TRUE,TRUE,FALSE),
                   monthly_filter=c(TRUE,FALSE,FALSE,FALSE),
                   raw_filter=c(FALSE,FALSE,FALSE,TRUE))
tl_key <-tibble(key=c("Calendar Date","Day of the Week","Day of the Month","Hour of the Day","Hour of the Week"),
                value=c("Date","day_of_week","day_of_month","hour_of_day","hour_of_week"),
                daily_filter=c(TRUE,TRUE,TRUE,FALSE,FALSE),
                monthly_filter=c(TRUE,FALSE,FALSE,FALSE,FALSE),
                raw_filter=c(TRUE,FALSE,FALSE,TRUE,TRUE))



############################### 
### CapStr function
#https://rstudio-pubs-static.s3.amazonaws.com/408658_512da947714740b99253228f084a08a9.html

#' Capitalise first letter of string
#' Copied from https://rstudio-pubs-static.s3.amazonaws.com/408658_512da947714740b99253228f084a08a9.html
#' @param  y string 
#' @return string with first letter in uppercase

CapStr <- function(y) {
  c <- strsplit(y, " ")[[1]]
  paste(toupper(substring(c, 1,1)), substring(c, 2),
        sep="", collapse=" ")
}


############################### 
### Hutton Criteria

#' Calculate the Hutton Criteria
#' @param  station_data "raw": station data vector
#' @return tibble with Date and logical value - TRUE if Hutton Criteria have been met
hutton_criteria <- function(station_data){
  
  result <- station_data                                   %>%  #get data
    mutate(hum90pc=(rltv_hum>=90))                         %>%  # check if humidity of hour is 90% or more
    group_by(Site,Site_Name,Date)                          %>% 
    summarise(min_temp=min(air_temperature),                    #determine min temperature
              hum90pc_count=sum(hum90pc),                       #determine 90% humidity condition
              .groups="drop")                              %>%
    ungroup()                                              %>%
    group_by(Site,Site_Name)                               %>%
    arrange(Date)                                          %>%  #arrange by date
    mutate(hutton_temp=(min_temp>=10),                          #temperature criterion
           hutton_hum=(hum90pc_count>=6))                  %>%  #humidity criterion
    select(Date, hutton_temp,hutton_hum)                   %>%  
    mutate(hutton_temp_yd = lag(hutton_temp,1),
           hutton_hum_yd  = lag(hutton_hum,1))             %>%  #get values for previous day
    mutate(hutton =  (hutton_temp & hutton_temp_yd)&
             (hutton_hum  & hutton_hum_yd))        %>%  #get result of hutton criteria
    filter(!is.na(hutton_temp_yd) & !is.na(hutton_hum_yd)) %>%  #remove first day
    ungroup()                                              %>%
    select(Date, Site,Site_Name,hutton)                         #extract only dates and hutton result
  
  
  return(result)
  
}

############################### 
### Load station data

#' Calculate the Hutton Criteria
#' @param  sites tibble with (subset) of stations of add (loaded from sites.csv)
#' @param  data  previously loaded dataset
#' @return tibble "raw" station data 
data_loader <- function(sites,data=1,time_zone="UTC",date_formats=c("YmdHMS", "dmYHMS","dmYHM")){
  
  site_data <- list()
  
  #if theere is a previous dataframe, determine if and how many stations are missing
  if(typeof(data)=="list"){
    sites_orig <- sites
    sites_covered <- data %>% select(Site_Name) %>% unique() %>% pull()
    sites <- sites %>% filter(!(Site_Name %in% sites_covered))
  }
  
  #only load files if there is any missing data, if not, just filter
  if(nrow(sites)>0){
    #get each file into one list item each
    for(i in 1:nrow(sites)){
      site_data[[i]] <- read_csv(paste("Data/Site_",sites[i,]$Site_ID,".csv",sep=""),
                                 col_types="cdddddddd")
      
      #get the average if same hour has more than one value
      
      site_data[[i]] <- site_data[[i]] %>% 
                        group_by(Site,ob_time,hour,day,month) %>%
                        summarise(wind_speed=mean(wind_speed,na.rm=TRUE),
                                  air_temperature=mean(air_temperature,na.rm=TRUE),
                                  rltv_hum=mean(rltv_hum,na.rm=TRUE),
                                  visibility=mean(visibility,na.rm=TRUE),
                                  .groups="drop")
      
      #there are at least two different date formats -  function to uniform
      site_data[[i]]$ob_time <-parse_date_time(site_data[[i]]$ob_time, orders=date_formats,tz=time_zone)
      site_data[[i]] <- site_data[[i]] %>%  
        mutate(Date=as_date(ob_time)) %>%
        mutate(Site_Name=sites[i,]$Site_Name)
    } 
    site_data <- rbindlist(site_data)          # collapse list into one tibble - 
    #from https://stackoverflow.com/questions/26177565/converting-nested-list-to-dataframe
    
    # check if there any pre-existing dataset and merge with it
    if(typeof(data)=="list"){
      data <- rbind(site_data,data) 
    }else{
      data <- site_data
      sites_orig <- sites 
    }
  }
  
  # retain listed sitenames only
  site_data <- data %>% filter(Site_Name %in% sites_orig$Site_Name)
  return(site_data)
  
}

############################### 
### Generate data aggregates

#' Create all daily and monthly stats, and hutton criteria in one list
#' @param  station_data "raw" station data
#' @return tibble "raw" station data, "daily" daily stats, "monthly" monthly stats , "hutton" hutton criteria results
aggregate_data <- function(station_data){
  
  result <- list()  
  
  result$raw <- station_data %>% 
    mutate(day_of_week=wday(Date),                                           #day of the week  
           hour_of_week=hour+(day_of_week-1)*24,                             #hour of the week
           day_of_month=day(Date),                                           # day of the month
           hour_of_day=hour)   %>%                                           #hour of day
    mutate(Date=ob_time)       %>%
          select(-hour)
           
  result$daily <-  station_data %>%  group_by(Site,Site_Name,Date)   %>% 
    summarise(mean_air_temperature=mean(air_temperature,na.rm = TRUE),              #calculate daily means
              mean_rltv_hum = mean(rltv_hum,na.rm = TRUE),
              mean_wind_speed = mean(wind_speed,na.rm = TRUE),
              mean_visibility = mean(visibility,na.rm = TRUE),
              max_air_temperature=max(air_temperature,na.rm = TRUE),                #calculate daily maxs
              max_rltv_hum = max(rltv_hum,na.rm = TRUE),
              max_wind_speed = max(wind_speed,na.rm = TRUE),
              max_visibility = max(visibility,na.rm = TRUE),  
              min_air_temperature=min(air_temperature,na.rm = TRUE),                #calculate daily mins
              min_rltv_hum = min(rltv_hum,na.rm = TRUE),
              min_wind_speed = min(wind_speed,na.rm = TRUE),
              min_visibility = min(visibility,na.rm = TRUE),
              .groups = "drop") %>%
    mutate(day_of_week=wday(Date),                                                  #day of the week
           day_of_month=day(Date))                                                  #day of the month
  
  result$monthly <- station_data %>% 
    mutate(Date=floor_date(Date, "month")) %>% group_by(Site,Site_Name,Date) %>%
    summarise(mean_air_temperature=mean(air_temperature,na.rm = TRUE),              #calculate daily means
              mean_rltv_hum = mean(rltv_hum,na.rm = TRUE),
              mean_wind_speed = mean(wind_speed,na.rm = TRUE),
              mean_visibility = mean(visibility,na.rm = TRUE),
              .groups = "drop")
  
  
  result$hutton <-   hutton_criteria(station_data) %>% 
                     mutate(Date=floor_date(Date, "month"))   %>%   
                     group_by(Site,Site_Name,Date) %>%
                     summarise(hutton_days=sum(hutton),.groups = "drop") %>%
                     ungroup()
  
  return(result)
  
}

############################### 
### Plotting Function

#' plotting function
#' @param  processed_data output of aggregate_data
#' @param  chart_value  type of plot: raw, daily or monthly
#' @param  stat_value   mean, max,min, none
#' @param  meas_value   wind_speed,air_temperature,rltv_hum, visibility
#' @param  time_value   Date,#day_of_week, #hour_of_week
#' @param  interactive_flag whether output is ggplot or ggiraph object (default FALSE)
#' @return plot
plot_data <- function(processed_data, chart_value,stat_value,meas_value,time_value, 
                      interactive_flag=FALSE,title_format="all",
                      size1=16,size2=10){

  if(chart_value=="raw") {
    stat_value<-"none"
  }
  if(chart_value=="monthly"){
    time_value<-"Date"  
    stat_value<-"mean"
  }
  
  #long from labels
  
  text_values <- tribble(~key,~text,~unit,
                         "raw","","",
                         "daily","daily","",
                         "monthly","monthly","",
                         "Date","Date","",
                         "hour_of_day","Hour of the day","",
                         "day_of_week","Day of the week","",
                         "hour","Hour of the week","",
                         "mean","average","",
                         "max","max.","",
                         "min","min.","",
                         "wind_speed","Wind Speed","kt",
                         "air_temperature","Air Temperature","C",
                         "rltv_hum","Relative Humidity","%",
                         "visibility","Visibility","m",
                         "Site_Name","Location",""
  )
  
  
  #Get all labels
  
  x.value<-time_value
  y.value<- ifelse(stat_value=="none",meas_value,paste(stat_value,meas_value,sep="_"))
  y.unit <- str_c(" [",text_values %>% filter(key==meas_value) %>% pull(unit),"]")
  
  colour.value <-"Site_Name"
  colour.text <- "Location"
  if(title_format=="patchwork"){
    title.text <- paste(text_values %>% filter(key==chart_value) %>% pull(text),
                        " ",
                        text_values %>% filter(key==stat_value) %>% pull(text),
                        sep="")
    
    title.text <- CapStr(title.text)
    
  }else{
    title.text <- str_c(text_values %>% filter(key==meas_value) %>% pull(text),
                        " (",
                        text_values %>% filter(key==chart_value) %>% pull(text),
                        " ",
                        text_values %>% filter(key==stat_value) %>% pull(text),
                        ")",sep="")
  }
  
  title.text <- str_replace(title.text,"\\( \\)","")
  
  x.text <- text_values %>% filter(key==x.value) %>% pull(text)
  y.text <- str_c(text_values %>% filter(key==chart_value) %>% pull(text) %>% CapStr(.),
                  text_values %>% filter(key==stat_value) %>% pull(text),
                  text_values %>% filter(key==meas_value) %>% pull(text) %>% tolower(.),
                  y.unit,
                  sep=" ")
  
  #obtain and format data to plot 
  
  plotting_data <- processed_data[[which(names(processed_data)==chart_value)]] %>% 
                   select(Date_value=Date,
                          x_value=matches(x.value),                                  # note that matches() may produce more than one result
                          y_value=matches(y.value),                                  # but in this case the attribute (column) names should be unique!
                          colour_value=matches(colour.value))   %>%
                    filter(!is.na(y_value)) 
  
  ### Format date for tooltip based on scale
  
  if(chart_value=="monthly"){
    plotting_data <- plotting_data %>%
                     mutate(Date_text = str_c(lubridate::month(Date_value,label=TRUE,abbr=TRUE),
                                              lubridate::year(Date_value),sep=" "))
  }else{
    plotting_data <- plotting_data %>%
                     mutate(Date_text = str_c(lubridate::day(Date_value),
                                              lubridate::month(Date_value,label=TRUE,abbr=TRUE),
                                              lubridate::year(Date_value),sep=" "))
  }
  if(chart_value=="raw" & time_value=="Date"){
    plotting_data <- plotting_data %>%
      mutate(Date_text = str_c(lubridate::day(Date_value),
                               lubridate::month(Date_value,label=TRUE,abbr=TRUE),
                               lubridate::year(Date_value),
                               str_c(lubridate::hour(Date_value),":00",sep=""),
                               sep=" "))
    
    
  }
  
  #create tooltip
  
  plotting_data <- plotting_data %>%
                    mutate(tooltip_value=str_c(plotting_data$colour_value,
                           "\n Date: ",
                           plotting_data$Date_text,
                            "\n",
                           text_values %>% filter(key==meas_value) %>% pull(text),
                            ": ",
                           round(plotting_data$y_value,2),y.unit)) %>%
                    select(-Date_text)
                    

  #base plot

  p <- plotting_data %>% ggplot(aes(x=x_value,y=y_value,colour=colour_value)) +
    theme_minimal() +
    theme(legend.position="right",
          plot.title = element_text(size=size1,face="bold",colour = "#272928",family="Roboto"),
          axis.text =  element_text(size=size2,colour = "#272928",family="Roboto"),
          axis.title = element_text(size=size2,colour = "#272928",family="Roboto"),
          legend.text = element_text(size=size2,colour = "#272928",family="Roboto")) +
    labs(title = title.text,
         x= x.text,
         y= y.text,
         colour=colour.text)
  

  # add lines with/without inteactivity
  
  if(time_value=="Date"){
    if(interactive_flag==FALSE){
      p<- p + geom_line()
    }else{
      p <-p + 
          geom_line_interactive(aes(tooltip=colour_value,data_id=colour_value)) +
          geom_point_interactive(aes(tooltip = tooltip_value,data_id=colour_value),size=.8)
    }
    p <- p + scale_colour_paletteer_d(colour_palette) 
    
  }else{
    if(interactive_flag==FALSE){
      p<- p + geom_point()
    }else{
      p<- p + geom_point_interactive(aes(tooltip = tooltip_value,data_id=colour_value))
    }
    p <- p +scale_fill_paletteer_d(colour_palette) 
  }
  
 ##Add message if no data is avaiable
  
 if(nrow(plotting_data)==0){
   
    p$data <- tibble(Date_value=as_date('1//1/1900'),
                                 x_value=1,
                                 y_value=1,
                                colour_value="no data available",
                                tooltip_value="No Data Available")
    p <- p + geom_text(aes(x_value, y_value, label=tooltip_value), colour="red", size=8)
  
 }
  
  return(p)
}

############################### 
### seven day data set

#' Create tibble with stats from last seven days
#' @param  processed_data output of aggregate_data
#' @param rounding_value rounding precision for stats
#' @return dataset
seven_day_dataset <-function(processed_data,rounding_value=2){
  
  table_data <- 
    processed_data$daily %>% group_by(Site,Site_Name) %>%
    filter(Date>(max(Date,na.rm = TRUE)-ddays(7))) %>%
    ungroup() %>%
    select(Site_Name,Date,
           colnames(processed_data$daily)[which(grepl("mean",colnames(processed_data$daily)))]) %>%
    mutate(across(where(is.numeric), round, rounding_value))  %>%
    arrange(Site_Name,Date)
  
  
  return(table_data)
  
}


############################### 
### seven day data table

#' Create table with stats from last seven days
#' @param  processed_data output of aggregate_data
#' @return table
seven_day_datatable <- function(processed_data){
  
  table_data <- seven_day_dataset(processed_data)
  
  result <- flextable(table_data)     %>%
    autofit()           %>%
    theme_booktabs()     %>%
    merge_v(j = ~ Site_Name) %>%
    set_header_labels( 
      Site_Name = "Site Name", 
      Date ="Date",
      mean_air_temperature="Avg. Air Temp",
      mean_rltv_hum="Avg. Rel Hum",
      mean_wind_speed="Avg. Wind Speed",
      mean_visibility="Avg Visibility") %>%
    font(fontname = "Roboto",part="all")   %>%
    fontsize(size = 12, part = "all")
  
  #from https://stackoverflow.com/questions/44700492/r-flextable-how-to-add-a-table-wide-horizontal-border-under-a-merged-cell
  
  row_loc <- rle(cumsum( result$body$spans$columns[,1] ))$values
  bigborder <- officer::fp_border(style = "solid", width=2)
  
  
  result <- result %>% 
    border(border.bottom = bigborder, i=row_loc, j = 2:6, part="body") 
  result <- result %>% 
    border(border.bottom = bigborder, 
           i = result$body$spans$columns[,1] > 1, j = 1, part="body") %>% 
    border(border.bottom = bigborder, border.top = bigborder, part = "header")
  
  result
  
  return(result)
  
}



############################### 
### seven day data table - DT

#' Create table with stats from last seven days
#' @param  processed_data output of aggregate_data
#' @return table
seven_day_DT <- function(processed_data){
  
  table_data <- seven_day_dataset(processed_data)
  
  result <- table_data %>% arrange(Site_Name,Date) %>%
    DT::datatable( colnames = c('Site Name', 'Date', 'Avg. Air Temperature', 'Avg. Relative Humidity', 'Avg. Wind Speed','Avg Visibility'),
               extensions = c('Buttons','Responsive','KeyTable'),
               options = list(                      
                 initComplete = JS(                                    #https://stackoverflow.com/questions/49782385/changing-font-in-dt-package/49966961
                   "function(settings, json) {",                       ## THIS CHANGES THE FONT FAMILY FOR ALL HTML COMPONENTS IN SHINY APP!!!!
                  "$('body').css({'font-family': 'Roboto'});",           
                   "}"
                  ),
                 pageLength = 14,
                 lengthMenu = c(3, 15, 15, 10,10,10,10),
                 dom = 'rtip',                                        # change to Bfrtip to add search box and buttons
                 keys=TRUE) )
  
  return(result)
  
}

############################### 
### Map with all locations

#' create leaflet map with all locations
#' @param  sites sites data frame loaded from sites.csv (or subset of)
#' #' @return leaflet map
location_map <- function(sites,height_value=300){
  
  bounds <- map("world", "UK", fill = TRUE, plot = FALSE) # create UK bounds  
  # https://stackoverflow.com/questions/49512240/how-to-assign-popup-on-map-polygon-that-corresponds-with-the-country-r-leaflet
  
  cp <- paletteer_d(colour_palette)
  sites_map <- sites %>% arrange(Site_Name)
  sites_map$colour <- cp[1:nrow(sites_map)]
  map <- sites_map %>%
         leaflet(height=height_value,
                 options=leafletOptions(dragging=FALSE,
                                        zoomControl = FALSE,
                                        minZoom = 4,
                                        maxZoom = 4)) %>%
         addProviderTiles("CartoDB") %>%
         addPolygons(data = bounds, group = "Countries", 
                    color = "red", 
                    weight = 2,
                    fillOpacity = 0.0) %>%
        addCircleMarkers(~Longitude, ~Latitude,
                         color=~colour,
                         radius=5,
                         fillOpacity = 0.9,
                         label = ~Site_Name) 
  
  
  sites
  return(map)
  
}


############################### 
### Plot Monthly Summary of Hutton Criteria

hutton_plot <-function(processed_data,interactive_flag=FALSE){
  
  p<-processed_data$hutton %>% filter(!is.na(hutton_days)) %>%
    mutate(Month=paste(lubridate::month(Date,label=TRUE,abbr=TRUE),year(Date),sep=" ")) %>%
    mutate(tooltip_text =paste0("Site: ",Site_Name,"\n Month: ",Month,"\n Hutton Days: ",hutton_days)) %>%
    ggplot(aes(x=Date,y=hutton_days,colour=Site_Name)) +
    theme_minimal() +
    theme(legend.position="right",
          plot.title = element_text(size=16,face="bold",colour = "#272928",family="Roboto"),
          plot.subtitle =element_text(size=10,colour = "azure4",family="Roboto"),
          plot.caption =  element_text(size=10,colour = "azure4",family="Roboto"),
          legend.text = element_text(size=10,colour = "#272928",family="Roboto")) +
          scale_fill_paletteer_d(colour_palette) +
    labs(title = "Summary of Days meeting the Hutton Criteria",
         x= "Date",
         y= "Number of Days",
         colour="Location") 
  
  if(interactive_flag==FALSE){
    p<- p + geom_point()
  }else{
    p <-p + geom_point_interactive(aes(tooltip=tooltip_text,data_id=Site_Name))
  }
  
  return(p)
}


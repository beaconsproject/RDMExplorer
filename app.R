library(sf)
library(dplyr)
library(terra)
library(raster)
library(leaflet)
library(shinydashboard)
library(rhandsontable)
library(shinyjs)
library(shinyWidgets)
library(shiny)
library(rgdal)
library(shinycssloaders)

ui = dashboardPage(skin="blue",
                   dashboardHeader(title = "Regional Disturbance"),
                   dashboardSidebar(
                     sidebarMenu(id = "tabs",
                                 menuItem("Overview", tabName = "overview", icon = icon("th")),
                                 menuItem("Footprint/intactness", tabName = "fri", icon = icon("th")),
                                 menuItem("Effects on landcover", tabName = "land", icon = icon("th")),
                                 menuItem("Effects on hydrology", tabName = "hydro", icon = icon("th")),
                                 menuItem("Upstream disturbances", tabName = "upstream", icon = icon("th"))
                                 #menuItem("Sensitivity analysis", tabName = "sa", icon = icon("th"))
                     ),
                     hr(),
                     
                     conditionalPanel(
                       condition = "input.tabs == 'fri' || input.tabs == 'land' || input.tabs == 'hydro' || input.tabs == 'upstream'",
                       selectInput("fda", label="Select FDA:", choices=c("10AB","09EA"))
                     ),
                     conditionalPanel(
                       condition = "input.tabs == 'fri' || input.tabs == 'land' || input.tabs == 'hydro' || input.tabs == 'upstream'",
                       sliderInput("buffer1", label="Linear buffer size (m):", min=0, max=2000, value = 1000, step=100, ticks=FALSE),
                       sliderInput("buffer2", label="Areal buffer size (m):", min=0, max=2000, value = 1000, step=100, ticks=FALSE),
                       sliderInput("area1", label="Minimum size of intact areas (km2):", min=0, max=2000, value = 500, step=100, ticks=FALSE),
                       actionButton("goButton", "Generate intactness map")
                     ),
                     conditionalPanel(
                       condition = "input.tabs == 'fri'",
                       hr(),
                       downloadButton("downloadFootprintMap","Download footprint/intactness")
                     ),
                     conditionalPanel(
                       condition = "input.tabs == 'upstream'",
                       hr(),
                       actionButton("goButtonUpstream", "View upstream disturbances")
                     )
                     
                     
                   ),
                   dashboardBody(
                     useShinyjs(),
                     tabItems(
                       tabItem(tabName="overview",
                               fluidRow(
                                 tabBox(
                                   id = "zero", width="12",
                                   tabPanel("Welcome!", htmlOutput("help")),
                                   #tabPanel("Footprint", includeMarkdown("../docs/footprint.md")),
                                   #tabPanel("Documentation", htmlOutput("datasets"))
                                 )
                               )
                       ),
                       tabItem(tabName="fri",
                               fluidRow(
                                 tabBox(
                                   id = "one", width="8",
                                   tabPanel("Map viewer", leafletOutput("map", height=750) %>% withSpinner()),
                                   tabPanel("Buffers", 
                                            tags$h2("Custom buffers"),
                                            tags$p("Buffer widths can specified by disturbance type using the table below. Otherwise buffer width is set using the 
                                    sliders on the map view."),
                                            materialSwitch("custom_buffer_switch",
                                                           label = "Use custom buffers",
                                                           value = FALSE, status = "primary",
                                                           inline = TRUE),
                                            rHandsontableOutput('buffer_table'))
                                 ),
                                 tabBox(
                                   id = "two", width="4",
                                   tabPanel("Intactness", tableOutput("tab1"))
                                 ),
                                 tabBox(
                                   id="three", width="4",
                                   tabPanel("Linear disturbances", tableOutput("tab2")),
                                   tabPanel("Areal disturbances", tableOutput("tab3"))
                                 ),
                               )
                       ),
                       tabItem(tabName="land",
                               fluidRow(
                                 tabBox(
                                   id = "one", width="8",
                                   tabPanel("Landcover", 
                                            leafletOutput("map2", height=750) %>% withSpinner())
                                 ),
                                 tabBox(
                                   id="two", width="4",
                                   #selectInput("year", label="Select year:", choices=c(2019,1984)),
                                   selectInput("type", label="Select class:", choices=c("all classes","bryoids","shrubs","wetland","wetland_treed","herbs","coniferous","broadleaf","mixedwood"),selected="all classes")
                                 ),
                                 tabBox(
                                   id = "two", width="4",
                                   tabPanel("Percent disturbed", tableOutput("tab4"))
                                 ),
                               )
                       ),
                       tabItem(tabName="hydro",
                               fluidRow(
                                 tabBox(
                                   id = "one", width="8",
                                   tabPanel("Hydrology", 
                                            leafletOutput("map3", height=750) %>% withSpinner())
                                 ),
                                 tabBox(
                                   id = "two", width="4",
                                   tabPanel("Percent disturbed", tableOutput("tab5"))
                                 ),
                               )
                       ),
                       tabItem(tabName="upstream",
                               fluidRow(
                                 tabBox(
                                   id = "one", width="8",
                                   tabPanel("Upstream", 
                                            leafletOutput("map4", height=750) %>% withSpinner())
                                 ),
                                 tabBox(
                                   id="two", width="4",
                                   tabPanel("Upstream disturbance description", htmlOutput("upstreamDesc"))
                                 ),
                                 tabBox(
                                   id = "two", width="4",
                                   tabPanel("Upstream disturbances", tableOutput("tab6"))
                                 ),            
                               )
                       )
                     )
                   ))


server = function(input, output) {
  
  output$help <- renderText({
    includeMarkdown("docs/overview.md")
  })
  
  ####################################################################################################
  # READ SPATIAL DATA
  ####################################################################################################
  fda <- reactive({
    paste0('www/fda_',tolower(input$fda),'.gpkg')
  })
  
  fda_hydro <- reactive({
    paste0('www/fda_',tolower(input$fda),'_hydro.gpkg')
  })
  
  bnd <- reactive({
    st_read(fda(), 'FDA', quiet=T)
  })
  
  lakesrivers <- reactive({
    st_read(fda_hydro(), 'lakes_rivers', quiet=T) %>% st_union()
  })
  
  streams <- reactive({
    st_read(fda_hydro(), 'streams', quiet=T) %>% st_union()
  })
  
  fires <- reactive({
    st_read(fda(), 'Fire_History', quiet=T)
  })
  
  ifl2000 <- reactive({
    st_read(fda(), 'IFL_2000', quiet=T)
  })
  
  ifl2020 <- reactive({
    st_read(fda(), 'IFL_2020', quiet=T)
  })
  
  linear <- reactive({
    if (input$fda=='10AB') {
      st_read(fda(), 'Linear_Features+', quiet=T)
    } else {
      st_read(fda(), 'Linear_Features', quiet=T)
    }
  })
  
  quartz <- reactive({
    st_read(fda(), 'Quartz_Claims', quiet=T)
  })
  
  areal <- reactive({
    if (input$fda=='10AB') {
      st_read(fda(), 'Areal_Features+', quiet=T)
    } else {
      st_read(fda(), 'Areal_Features', quiet=T)
    }
  })
  
  catch <- reactive({
    catch <- paste0('www/fda_',tolower(input$fda),'_catch.gpkg')
  })
  catchments <- reactive({
    catchments <- st_read(catch(), 'catchments', quiet=T)
  })
  
  upstream_catch <- reactive({
    upstream_catch <- readRDS(file = paste0('www/upstream_catch_',tolower(input$fda),'.rds'))
  })    
  
  ####################################################################################################
  # SET UP CUSTOM BUFFER TABLE
  ####################################################################################################
  
  # Activate grey out sliders if button selected. Note that disable doesn't seem to work on the table. Instead we can set it to read only mode when rendering.
  observe({
    
    if(input$custom_buffer_switch == TRUE){
      shinyjs::disable("buffer1")
      shinyjs::disable("buffer2")
    } else{
      shinyjs::enable("buffer1")
      shinyjs::enable("buffer2")
    }
  })
  
  reactive_vals <- reactiveValues() # This sets up a reactive element that will store the buffer width df
  
  # Make table of unique disturbance types in areal linear attribute tables
  output$buffer_table <- renderRHandsontable({
    
    linear_types_df <- linear() %>%
      st_drop_geometry() %>%
      group_by(TYPE_INDUSTRY, TYPE_DISTURBANCE) %>%
      summarise(Features = "Linear") %>%
      ungroup() %>%
      rename(Industry = TYPE_INDUSTRY, Disturbance = TYPE_DISTURBANCE) %>%
      relocate(Features, Industry, Disturbance)
    
    area_types_df <- areal() %>%
      st_drop_geometry() %>%
      group_by(TYPE_INDUSTRY, TYPE_DISTURBANCE) %>%
      summarise(Features = "Areal") %>%
      rename(Industry = TYPE_INDUSTRY, Disturbance = TYPE_DISTURBANCE) %>%
      relocate(Features, Industry, Disturbance)
    
    types_df <- rbind(linear_types_df, area_types_df) %>%
      arrange(Features, Industry, Disturbance) %>%
      mutate(Buffer = 1000)
    
    if(input$custom_buffer_switch == TRUE){
      rhandsontable(types_df) %>%
        hot_cols(columnSorting = TRUE) %>%
        hot_col("Features", readOnly = TRUE) %>%
        hot_col("Industry", readOnly = TRUE) %>%
        hot_col("Disturbance", readOnly = TRUE)
    } else{
      # grey out the table and make it read_only (this is a work around because shinyjs::disable doesn't work)
      rhandsontable(types_df, readOnly = TRUE) %>%
        hot_cols(renderer = "
           function (instance, td, row, col, prop, value, cellProperties) {
             Handsontable.renderers.NumericRenderer.apply(this, arguments);
              td.style.background = 'lightgrey';
              td.style.color = 'grey';
           }")
    }
  })
  
  observe({
    reactive_vals$buffer_tab <- hot_to_r(input$buffer_table)
  })
  
  ####################################################################################################
  # BUFFER DISTURBANCES AND CALCULATE FOOTPRINT AND INTACTNESS
  ####################################################################################################
  
  # Footprint
  footprint_sf <- eventReactive(input$goButton, {
    
    if(input$custom_buffer_switch == TRUE){
      # If custom buffer table requested, for each unique buffer width, extract all features and buffer
      # Then union all layers
      unique_buffers_linear <- unique(reactive_vals$buffer_tab$Buffer[reactive_vals$buffer_tab$Features == "Linear"]) # get unique buffers
      counter <- 1
      for(i in unique_buffers_linear){
        buff_sub <- reactive_vals$buffer_tab %>%
          filter(Features == "Linear", Buffer == i)
        linear_join <- right_join(linear(), buff_sub, by = c("TYPE_INDUSTRY" = "Industry", "TYPE_DISTURBANCE" = "Disturbance"))
        linear_buff <- st_union(st_buffer(linear_join, i))
        
        if(counter == 1){
          linear_final <- linear_buff
        } else{
          linear_final <- st_union(linear_final, linear_buff)
        }
        counter <- counter + 1
      }
      
      unique_buffers_areal <- unique(reactive_vals$buffer_tab$Buffer[reactive_vals$buffer_tab$Features == "Areal"]) # get unique buffers
      counter <- 1
      for(i in unique_buffers_areal){
        buff_sub <- reactive_vals$buffer_tab %>%
          filter(Features == "Areal", Buffer == i)
        areal_join <- right_join(areal(), buff_sub, by = c("TYPE_INDUSTRY" = "Industry", "TYPE_DISTURBANCE" = "Disturbance"))
        areal_buff <- st_union(st_buffer(areal_join, i))
        
        if(counter == 1){
          areal_final <- areal_buff
        } else{
          areal_final <- st_union(areal_final, areal_buff)
        }
        counter <- counter + 1
      }
      
      st_union(linear_final, areal_final)
      
    } else{
      v1 <- st_union(st_buffer(linear(), input$buffer1))
      v2 <- st_union(st_buffer(areal(), input$buffer2))
      st_intersection(st_union(v1, v2), bnd())
    }
  })
  
  # Intactness
  intactness_sf <- eventReactive(input$goButton, {
    ifl <- st_difference(bnd(), footprint_sf())
    x <- st_cast(ifl, "POLYGON")
    x <- mutate(x, area_km2=as.numeric(st_area(x)/1000000))
    y <- filter(x, area_km2 > input$area1)
  })
  
  
  ####################################################################################################
  # FOOTPRINT/INTACTNESS SECTION
  ####################################################################################################
  
  # Map viewer
  # Render the initial map
  output$map <- renderLeaflet({
    
    # Re-project
    bnd <- st_transform(bnd(), 4326)
    ifl2000 <- st_transform(ifl2000(), 4326)
    ifl2020 <- st_transform(ifl2020(), 4326)
    fires <- st_transform(fires(), 4326)
    quartz <- st_transform(quartz(), 4326)
    areal <- st_transform(areal(), 4326)
    linear <- st_transform(linear(), 4326)
    
    #pal <- colorBin("YlOrRd", domain = fires$FIRE_YEAR, bins = c(1950, 1960, 1970, 1980, 1990, 2000, 2010, 2020, Inf))
    labels <- sprintf("Fire year: %s<br/>Fire cause: %s", fires$FIRE_YEAR, fires$GENERAL_FIRE_CAUSE) %>% lapply(htmltools::HTML)
    
    map_bounds <- bnd %>% st_bbox() %>% as.character()
    
    m <- leaflet() %>% 
      
      addProviderTiles("Esri.NatGeoWorldMap", group="Esri.NatGeoWorldMap") %>%
      addProviderTiles("Esri.WorldImagery", group="Esri.WorldImagery") %>%
      
      addPolygons(data=bnd, color='black', fill=F, weight=2, group="FDA") %>%
      fitBounds(map_bounds[1], map_bounds[2], map_bounds[3], map_bounds[4]) %>% # set view to the selected FDA
      #addPolygons(data=fires, fillColor = ~pal(FIRE_YEAR), color='grey', weight=1, group="Fires", opacity=1, fillOpacity = 0.7,
      addPolygons(data=fires, fillColor="red", color='grey', weight=1, group="Fires", opacity=1, fillOpacity=0.5,
                  highlightOptions = highlightOptions(weight=2, color="black", bringToFront=T),
                  label = labels,
                  labelOptions = labelOptions(style = list("font-weight" = "normal", padding = "3px 8px"), textsize = "15px", direction = "auto")) %>%
      #addLegend(pal = pal, values = ~fires$FIRE_YEAR, opacity = 0.7, title = NULL, position = "bottomright") %>%
      addPolygons(data=quartz, color='yellow', fill=F, weight=1, group="Quartz") %>%
      addPolylines(data=linear, color='red', weight=1, group="Linear features", popup = ~paste("Industry: ", TYPE_INDUSTRY, "<br>", "Disturbance: ", TYPE_DISTURBANCE)) %>%
      addPolygons(data=areal, color='black', fill=T, stroke=F, group="Areal features", popup = ~paste("Industry: ", TYPE_INDUSTRY, "<br>", "Disturbance: ", TYPE_DISTURBANCE), fillOpacity=0.5) %>%
      addPolygons(data=ifl2020, color='darkgreen', fillOpacity=0.5, group="IFL 2020") %>%
      addPolygons(data=ifl2000, color='darkgreen', fillOpacity=0.5, group="IFL 2000") %>%
      
      #pal <- colorBin("PuOr", fires$GENERAL_FIRE_CAUSE, bins = c(0, .1, .4, .9, 1))
      addLayersControl(position = "topright",
                       baseGroups=c("Esri.NatGeoWorldMap", "Esri.WorldImagery"),
                       overlayGroups = c("IFL 2020","IFL 2000","Fires","Quartz","Areal features","Linear features"),
                       options = layersControlOptions(collapsed = FALSE)) %>%
      hideGroup(c("IFL 2020","IFL 2000","Fires","Quartz","Areal features","Linear features","Intactness"))
    #m <- m %>% addLegend(pal=pal, values=~fires$GENERAL_FIRE_CAUSE, position=c("bottomright"), title="Fire cause", opacity=0.8)
    
    # Add footprint if its already been made
    if(input$goButton > 0){
      v <- st_transform(intactness_sf(), 4326)
      vv <- st_transform(footprint_sf(), 4326)
      
      m <- m %>%
        addPolygons(data=v, color='blue', stroke=F, fillOpacity=0.5, group='Intactness') %>%
        addPolygons(data=vv, color='black', stroke=F, fillOpacity=0.5, group='Footprint') %>%
        addLayersControl(position = "topright",
                         baseGroups=c("Esri.NatGeoWorldMap", "Esri.WorldImagery"),
                         overlayGroups = c("IFL 2020","IFL 2000","Fires","Quartz","Areal features","Linear features","Footprint","Intactness"),
                         options = layersControlOptions(collapsed = FALSE))
    }
    m
  })
  
  # Intactness table
  output$tab1 <- renderTable({
    x <- tibble(Map=c("FDA (km2)","IFL 2000 (%)","IFL 2020 (%)","Intactness (%)","Footprint (%)"), Area=NA)
    x$Area[x$Map=="FDA (km2)"] <- round(st_area(bnd())/1000000,0)
    x$Area[x$Map=="IFL 2000 (%)"] <- round(sum(st_area(ifl2000()))/st_area(bnd())*100,1)
    x$Area[x$Map=="IFL 2020 (%)"] <- round(sum(st_area(ifl2020()))/st_area(bnd())*100,1)
    
    # If button has been pressed at least once, keep the intactness/footprint values updated
    if(input$goButton > 0) {
      x$Area[x$Map=="Intactness (%)"] <- round(sum(st_area(intactness_sf()))/st_area(bnd())*100,1)
      x$Area[x$Map=="Footprint (%)"] <- round(sum(st_area(footprint_sf()))/st_area(bnd())*100,1)
    }
    x
  })
  
  # Linear disturbances table
  output$tab2 <- renderTable({
    km <- group_by(linear(), TYPE_DISTURBANCE) %>%
      summarize(Length_km = sum(Length_km))
    x <- tibble(Disturbance_type=km$TYPE_DISTURBANCE, Length_km=km$Length_km, Length_pct=Length_km/sum(Length_km)*100)
  })
  
  # Areal disturbances table
  output$tab3 <- renderTable({
    ha <- group_by(areal(), TYPE_DISTURBANCE) %>%
      summarize(Area_ha = sum(Area_ha)/100)
    x <- tibble(Disturbance_type=ha$TYPE_DISTURBANCE, Area_ha=ha$Area_ha, Area_pct=Area_ha/sum(Area_ha)*100)
  })
  
  ####################################################################################################
  # LANDCOVER SECTION
  ####################################################################################################
  
  # load the landcover tif when the fda changes
  lcc2 <- reactive({
    dir1 <- substr(fda(),1,nchar(fda())-5)
    lcc <- rast(paste0(dir1,'/','lc_2019.tif'))
    subst(lcc, 0, NA)
  })
  
  # Make an aggreagated version for use in Leaflet
  lcc_agg <- reactive({
    #aggregate(lcc2(), 10, fun='modal')
    lcc2()
  })
  
  # Reclassify the aggregated raster depending on veg type selected
  lcc_rcl <- reactive({
    if (input$type=='bryoids') {
      r <- subst(lcc_agg(), c(20,31,32,33,40,50,80,81,100,210,220,230), c(NA,NA,NA,NA,1,NA,NA,NA,NA,NA,NA,NA))
    } else if (input$type=='shrubs') {
      r <- subst(lcc_agg(), c(20,31,32,33,40,50,80,81,100,210,220,230), c(NA,NA,NA,NA,NA,1,NA,NA,NA,NA,NA,NA))
    } else if (input$type=='wetland') {
      r <- subst(lcc_agg(), c(20,31,32,33,40,50,80,81,100,210,220,230), c(NA,NA,NA,NA,NA,NA,1,NA,NA,NA,NA,NA))
    } else if (input$type=='wetland_treed') {
      r <- subst(lcc_agg(), c(20,31,32,33,40,50,80,81,100,210,220,230), c(NA,NA,NA,NA,NA,NA,NA,1,NA,NA,NA,NA))
    } else if (input$type=='herbs') {
      r <- subst(lcc_agg(), c(20,31,32,33,40,50,80,81,100,210,220,230), c(NA,NA,NA,NA,NA,NA,NA,NA,1,NA,NA,NA))
    } else if (input$type=='coniferous') {
      r <- subst(lcc_agg(), c(20,31,32,33,40,50,80,81,100,210,220,230), c(NA,NA,NA,NA,NA,NA,NA,NA,NA,1,NA,NA))
    } else if (input$type=='broadleaf') {
      r <- subst(lcc_agg(), c(20,31,32,33,40,50,80,81,100,210,220,230), c(NA,NA,NA,NA,NA,NA,NA,NA,NA,NA,1,NA))
    } else if (input$type=='mixedwood') {
      r <- subst(lcc_agg(), c(20,31,32,33,40,50,80,81,100,210,220,230), c(NA,NA,NA,NA,NA,NA,NA,NA,NA,NA,NA,1))
    }
  })
  
  lcc_intact <- reactive({
    v <- vect(footprint_sf())
    #r2 <- crop(lcc2(), v)
    r2 <- crop(lcc_agg(), v)
    mask(r2, v)
  })
  
  output$tab4 <- renderTable({
    #r_freq <- as.data.frame(freq(lcc2()))
    r_freq <- as.data.frame(freq(lcc_agg()))
    cls <- c("water","snow_ice","rock_rubble","exposed_barren_land","bryoids","shrubs","wetland","wetland_treed","herbs","coniferous","broadleaf","mixedwood")
    
    if (input$goButton > 0) {
      x <- tibble(Class=cls, value=r_freq$value, count_fda=r_freq$count)
      r2_freq <- as.data.frame(freq(lcc_intact()))[,2:3] %>%
        rename(count_2019=count)
      xx <- left_join(x, r2_freq) %>%
        mutate(Area_ha=round(count_fda*30*30/10000,2),
               Disturb_pct=round(100-((count_fda-count_2019)/count_fda*100),2),
               count_fda=NULL, count_2019=NULL, value=NULL)
    } else {
      xx <- tibble(Class=cls, Count=r_freq$count) %>%
        mutate(Area_km2=round(Count*30*30/1000000,2),
               Count=NULL)
    }
    xx
  })
  
  # Set objects used in multiple places
  val <- c(20,31,32,33,40,50,80,81,100,210,220,230)
  cls <- c("water","snow_ice","rock_rubble","exposed_barren_land","bryoids","shrubs","wetland","wetland_treed","herbs","coniferous","broadleaf","mixedwood")
  lcc_cols <- read.csv('www/lc_cols.csv') %>%
    mutate(color=rgb(red,green,blue,maxColorValue=255)) %>%
    pull(color)
  
  # reactive to hold overlay groups depending on whether intactness has been added or not
  overlay_groups <- reactive({
    if(input$goButton > 0){
      c("FDA", input$type,"Linear features", "Areal features","Intactness","Footprint")
    } else{
      c("FDA", input$type,"Linear features", "Areal features")
    }
  })
  
  # Render the initial map
  # Note that there cannot be any reactive elements in the initial map, otherwise the map will redraw every time input$type changes
  output$map2 <- renderLeaflet({
    
    # Re-project
    bnd <- st_transform(bnd(), 4326)
    areal <- st_transform(areal(), 4326)
    linear <- st_transform(linear(), 4326)
    
    # Prep landcover raster
    r <- raster(lcc_agg())
    df <- data.frame(ID=val, CAT=cls)
    levels(r) <- df
    
    map_bounds <- bnd %>% st_bbox() %>% as.character()
    
    m <- leaflet() %>%
      addProviderTiles("Esri.NatGeoWorldMap", group="Esri.NatGeoWorldMap") %>%
      addProviderTiles("Esri.WorldImagery", group="Esri.WorldImagery") %>%
      addPolygons(data=bnd, color='black', fill=F, weight=2, group="FDA") %>%
      fitBounds(map_bounds[1], map_bounds[2], map_bounds[3], map_bounds[4]) %>% # set view to the selected FDA
      addPolylines(data=linear, color='red', weight=1, group="Linear features") %>%
      addPolygons(data=areal, color='black', fill=T, stroke=F, group="Areal features", fillOpacity=0.5) %>%
      hideGroup(c("Linear features","Areal features","Intactness")) %>%
      addLegend(colors=lcc_cols, labels=cls, position=c("bottomleft"), title="Landcover 2019", opacity=1)
    
    if(input$goButton > 0){
      v <- st_transform(intactness_sf(), 4326)
      vv <- st_transform(footprint_sf(), 4326)
      
      m <- m %>%
        addPolygons(data=v, color='blue', stroke=F, fillOpacity=0.5, group='Intactness') %>%
        addPolygons(data=vv, color='black', stroke=F, fillOpacity=0.5, group='Footprint')
    }
    m
  })
  
  # Change selected raster layer using proxy
  observe({
    
    # This prevents the code running on startup. Otherwise there's a pause to load the landing page because this code runs.
    req(input$tabs == "land")
    
    if (input$type=='all classes') {
      r <- raster(lcc_agg())
      df <- data.frame(ID=val, CAT=cls)
      levels(r) <- df
      selected_cols <- lcc_cols
    } else {
      r <- raster(lcc_rcl())
      selected_cols <- lcc_cols[match(input$type, cls)] # get the color from the legend
    }
    
    leafletProxy("map2") %>%
      clearImages() %>%
      addRasterImage(r, colors=selected_cols, opacity=1, group=input$type) %>%
      addLayersControl(position = "topright",
                       baseGroups=c("Esri.NatGeoWorldMap", "Esri.WorldImagery"),
                       overlayGroups = overlay_groups(),
                       options = layersControlOptions(collapsed = FALSE))
  })
  
  ####################################################################################################
  # HYDROLOGY SECTION
  ####################################################################################################
  
  output$map3 <- renderLeaflet({
    bnd <- st_transform(bnd(), 4326)
    lakesrivers <- st_transform(lakesrivers(), 4326)
    streams <- st_transform(streams(), 4326)
    areal <- st_transform(areal(), 4326)
    linear <- st_transform(linear(), 4326)
    
    map_bounds <- bnd %>% st_bbox() %>% as.character()
    
    m <- leaflet(bnd) %>% 
      addProviderTiles("Esri.NatGeoWorldMap", group="Esri.NatGeoWorldMap") %>%
      addProviderTiles("Esri.WorldImagery", group="Esri.WorldImagery") %>%
      addPolygons(data=bnd, color='black', fill=F, weight=2, group="FDA") %>%
      fitBounds(map_bounds[1], map_bounds[2], map_bounds[3], map_bounds[4]) %>% # set view to the selected FDA
      addPolygons(data=lakesrivers, color='blue', weight=1, group="LakesRivers") %>%
      addPolylines(data=streams, color='blue', weight=1, group="Streams") %>%
      addPolylines(data=linear, color='red', weight=1, group="Linear features") %>%
      addPolygons(data=areal, color='black', fill=T, stroke=F, group="Areal features", fillOpacity=0.5)
    if (input$goButton > 0) {
      v <- st_transform(intactness_sf(), 4326)
      vv <- st_transform(footprint_sf(), 4326)
      m <- m %>% addPolygons(data=v, color='blue', stroke=F, fillOpacity=0.5, group='Intactness') %>%
        addPolygons(data=vv, color='black', stroke=F, fillOpacity=0.5, group='Footprint')
    }
    m <- m %>% addLayersControl(position = "topright",
                                baseGroups=c("Esri.NatGeoWorldMap", "Esri.WorldImagery"),
                                overlayGroups = c("FDA","LakesRivers","Streams","Linear features","Areal features","Intactness","Footprint"),
                                options = layersControlOptions(collapsed = FALSE)) %>%
      hideGroup(c("Streams","Linear features","Areal features","Intactness","Footprint"))
  })
  
  dta5 <- reactive({
    if (input$goButton) {
      x <- tibble(Class=c('Streams','LakesRivers'), Length_km=c(0,NA), Area_km2=c(NA,0), Disturb_pct=0)
      #streams_intact <- st_intersection(streams(), intactness_sf())
      #lakesrivers_intact <- st_intersection(lakesrivers(), intactness_sf())
      streams_disturb <- st_intersection(streams(), footprint_sf())
      lakesrivers_disturb <- st_intersection(lakesrivers(), footprint_sf())
      
      streams_length <- sum(st_length(streams()))
      lakes_area <- sum(st_area(lakesrivers()))
      
      x$Length_km[x$Class=='Streams'] <- round(streams_length/1000,2)
      x$Area_km2[x$Class=='LakesRivers'] <- round(lakes_area/1000000,2)
      #x$Intact_pct[x$Class=='Streams'] <- round(sum(st_length(streams_intact))/sum(st_length(streams()))*100,2)
      #x$Intact_pct[x$Class=='LakesRivers'] <- round(sum(st_area(lakesrivers_intact))/sum(st_area(lakesrivers()))*100,2)
      x$Disturb_pct[x$Class=='Streams'] <- round(sum(st_length(streams_disturb))/streams_length*100,2)
      x$Disturb_pct[x$Class=='LakesRivers'] <- round(sum(st_area(lakesrivers_disturb))/lakes_area*100,2)
    } else {
      x <- tibble(Class=c('Streams','LakesRivers'), Length_km=c(0,NA), Area_km2=c(NA,0))
      x$Length_km[x$Class=='Streams'] <- round(streams_length/1000,2)
      x$Area_km2[x$Class=='LakesRivers'] <- round(lakes_area/1000000,2)
    }
    x
  })
  
  output$tab5 <- renderTable({
    dta5()
  })
  
  ####################################################################################################
  # UPSTREAM SECTION
  ####################################################################################################
  catch_out <- eventReactive(input$goButtonUpstream, {
    
    # Tabulate dist area per catchment
    dist <- st_union(footprint_sf())
    i <- st_intersection(catchments(), dist)
    distArea <- i %>% 
      mutate(area_dist = st_area(.)/1000000 %>% as.numeric()) %>%
      st_drop_geometry()
    catchs <- st_drop_geometry(catchments())
    catchs <-merge(catchs, distArea[,c("CATCHNUM", "area_dist")], by= "CATCHNUM", all.x = TRUE)
    catchs$area_dist[is.na(catchs$area_dist)] <- 0
    catchs$area_dist <- as.numeric(catchs$area_dist)
    feature_list <- unique(upstream_catch()$catchments)
    catch_list <- unique(catchments()$CATCHNUM)
    for(catch_id in catch_list){
      if(catch_id %in% feature_list){ 
        ## get list of catchments
        catchments_list <- {upstream_catch()[upstream_catch()$catchments == catch_id, "value"]}
        catchments_list <- c(catch_id, catchments_list)
        catch <- filter(catchs, catchs$CATCHNUM %in% catchments_list)
        # Total area upstreamn disturbed
        upad <- catch %>%
          dplyr::summarise(upstream_area_dist = sum(catch$area_dist)) %>%
          dplyr::mutate(id = catch_id) #%>%
        catchs$upadist[catchs$CATCHNUM ==upad$id] <- round(upad$upstream_area_dist, 4)
        uppd <- catch %>%
          dplyr::summarise(upstream_percent_dist = sum(.data$area_dist) / sum(.data$Area_Total/1000000)) %>%
          dplyr::mutate(id = catch_id) #%>%
        catchs$uppdist[catchs$CATCHNUM ==uppd$id] <- round(uppd$upstream_percent_dist, 2)
      } else { 
        catchs$upadist[catchs$CATCHNUM ==catch_id] <- round(catchs$area_dist[catchs$CATCHNUM == catch_id], 4)
        catchs$uppdist[catchs$CATCHNUM ==catch_id] <- round(catchs$area_dist[catchs$CATCHNUM == catch_id]/(catchs$Area_Total[catchs$CATCHNUM == catch_id]/1000000), 2)
      }
    }
    catch_out <- merge(catchments(), catchs[,c("CATCHNUM", "upadist", "uppdist", "area_dist")], by = "CATCHNUM", all.x = TRUE)
  })
  
  output$upstreamDesc <- renderText({
    includeMarkdown("docs/upstream.md")
  })
  
  output$map4 <- renderLeaflet({
    bnd <- st_transform(bnd(), 4326)
    catch_4326 <- st_transform(catchments(), 4326)
    
    map_bounds <- bnd %>% st_bbox() %>% as.character()
    
    m <- leaflet() %>% 
      addProviderTiles("Esri.NatGeoWorldMap", group="Esri.NatGeoWorldMap") %>%
      addPolygons(data=bnd, color='black', fill=F, weight=2, group="FDA") %>%
      fitBounds(map_bounds[1], map_bounds[2], map_bounds[3], map_bounds[4]) %>% # set view to the selected FDA
      addPolygons(data=catch_4326, color='black', fill=F, weight=1, group="Catchments") %>%
      addLayersControl(position = "topright",
                       overlayGroups = c("Esri.NatGeoWorldMap", "FDA", "Catchments"),
                       options = layersControlOptions(collapsed = FALSE)) %>%
      hideGroup(c("Catchments"))
  
    
    if(input$goButton > 0){
      v <- st_transform(intactness_sf(), 4326)
      vv <- st_transform(footprint_sf(), 4326)
      
      m <- m %>%
        addPolygons(data=vv, color='black', stroke=F, fillOpacity=0.5, group='Footprint') %>%
        addPolygons(data=v, color='blue', stroke=F, fillOpacity=0.5, group='Intactness') %>%
        addLayersControl(position = "topright",
                         overlayGroups = c("Esri.NatGeoWorldMap", "FDA", "Catchments", "Intactness","Footprint"),
                         options = layersControlOptions(collapsed = FALSE))
    }
    
    if (input$goButtonUpstream) {
      catch_out <- st_transform(catch_out(), 4326)
      stralher1 <- subset(catch_out, catch_out$STRAHLER == 1)
      stralher2 <- subset(catch_out, catch_out$STRAHLER == 2)
      
      ## Create a continuous palette function
      min <- min(catch_out$upadist)
      max <- max(catch_out$upadist)
      catchupadist <- colorNumeric(
        palette = "RdBu",
        domain = min:max,
        reverse = TRUE)
      
      ## Create bin palette function for percent
      catchuppdist = colorBin(
        palette = 'RdBu', 
        domain = catch_out$uppdist, 
        bins = 10,
        reverse = TRUE)
      
      m <- m %>% addPolygons(data=catch_out, color=~catchupadist(upadist), stroke=F, fillOpacity=1, group="Upstream area disturbed (sq km)") %>%
        addPolygons(data=catch_out, color=~catchuppdist(uppdist), stroke=F, fillOpacity=1, group="Upstream percent disturbed") %>%
        addPolygons(data=stralher1, fillColor="#ffff00", stroke=F, fillOpacity=0.8, group="Stralher 1") %>%
        addPolygons(data=stralher2, fillColor="#eec900", stroke=F, fillOpacity=0.8, group="Stralher 2") %>%
        addLegend(position = "bottomleft", pal = catchupadist, values = catch_out$upadist, opacity = 1,
                  title = "Upstream area disturbed (sq km)", 
                  group = "Upstream area disturbed (sq km)") %>%
        addLegend(position = "bottomleft", pal = catchuppdist, values = catch_out$uppdist, opacity = 1,
                  title = "Upstream percent disturbed", labFormat = labelFormat(
                    suffix = "%", 
                    transform = function(x) 100 * x
                  ), group = "Upstream percent disturbed") %>%
        addLayersControl(position = "topright",
                         baseGroups=c("Upstream area disturbed (sq km)", "Upstream percent disturbed"),
                         overlayGroups = c("Esri.NatGeoWorldMap", "FDA", "Catchments", "Footprint", "Stralher 1", "Stralher 2"),
                         #overlayGroups = c("Esri.NatGeoWorldMap", "FDA", "Catchments", "Footprint", "Upstream area disturbed", "Upstream percent disturbed"),
                         options = layersControlOptions(collapsed = FALSE)) %>%
        # control legend apparition (show/hide toggle)
        htmlwidgets::onRender("
          function(el, x) {
            var updateLegend = function () {
                var selectedGroup = document.querySelectorAll('input:checked')[0].nextSibling.innerText.substr(1);
      
                document.querySelectorAll('.legend').forEach(a => a.hidden=true);
                document.querySelectorAll('.legend').forEach(l => {
                  if (l.children[0].children[0].innerText == selectedGroup) l.hidden=false;
                });
            };
            updateLegend();
            this.on('baselayerchange', e => updateLegend());
          }") %>%
        hideGroup(c("Catchments", "Intactness", "Footprint", "Stralher 1", "Stralher 2"))
      
    }
    m
  })	
  dta6 <- reactive({
    if (input$goButtonUpstream) {
      stralher1 <- subset(catch_out(), catch_out()$STRAHLER == 1)
      stralher2 <- subset(catch_out(), catch_out()$STRAHLER == 2)
      
      x <- tibble(Class=c('Stralher1','Stralher2'), Area_km2=0, Disturb_area=0, Disturb_pct=0)
      x$Area_km2[x$Class=='Stralher1'] <- round(sum(stralher1$Area_Total/1000000,2))
      x$Area_km2[x$Class=='Stralher2'] <- round(sum(stralher2$Area_Total/1000000,2))
      x$Disturb_area[x$Class=='Stralher1'] <- round(sum(stralher1$area_dist,2))
      x$Disturb_area[x$Class=='Stralher2'] <- round(sum(stralher2$area_dist,2))
      x$Disturb_pct[x$Class=='Stralher1'] <- round(sum(stralher1$area_dist)/sum(stralher1$Area_Total/1000000)*100,2)
      x$Disturb_pct[x$Class=='Stralher2'] <- round(sum(stralher2$area_dist)/sum(stralher2$Area_Total/1000000)*100,2)
    } else {
      x <- tibble(Class=c('Stralher1','Stralher2'), Area_km2=c(0,0), Disturb_area=c(NA,NA), Disturb_pct=c(NA,NA))
      stralher1 <- subset(catchments(), catchments()$STRAHLER == 1)
      stralher2 <- subset(catchments(), catchments()$STRAHLER == 2)
      x$Area_km2[x$Class=='Stralher1'] <- round(sum(stralher1$Area_Total/1000000,2))
      x$Area_km2[x$Class=='Stralher2'] <- round(sum(stralher2$Area_Total/1000000,2))
    }
    x
  })
  
  output$tab6 <- renderTable({
    dta6()
  })
  ####################################################################################################
  # DOWNLOAD SHAPEFILE
  ####################################################################################################
  
  output$downloadFootprintMap <- downloadHandler(
    filename = function() {'data_download.gpkg'},
    content = function(file) {
      st_write(footprint_sf(), dsn=file, layer='footprint')
      st_write(intactness_sf(), dsn=file, layer='intactness', append = TRUE)
      st_write(bnd(), dsn=file, layer='fda_boundary', append = TRUE)
    }
  )
}

shinyApp(ui, server)
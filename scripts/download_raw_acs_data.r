#########################################################################
#
# DOWNLOAD, EXTRACT, AND SELECT DATA FOR CUSTOM DATA SETS AND GEOGRAPHIES
# Developed by Chapin Hall
# Authors: Nick Mader (nmader@chapinhall.org), ...
#
#########################################################################


### Set Up Workspace

  rm(list=ls())
  "%&%" <- function(...){ paste(..., sep="")}
  library(acs) # This package isn't (yet) used directly to download ACS data, since it generates pulls using the Census API, and 
    #   only a subset of Census data sets are available through the API. However, it has some useful helper functions to
    #   find codes for tables and geographies
  
  #myLocalUser <- "nmader.CHAPINHALL"
  myLocalUser <- "nmader"
  rootDir <- "C:/Users/nmader/Documents/GitHub/acs-shop-cook-serve/"
  dlDir <- rootDir %&% "data/raw-downloads/"
  saveDir <- rootDir %&% "data/prepped-data/"
  setwd(dlDir)

### Define Pulls

  # NSM: we will want to convert this to a function so that users can call on this multiple times for different types of pulls, either with separate years

  downloadData <- FALSE
  pullYear <- "2012"
  pullSpan  <- 1
  pullState <- "Illinois"
  pullSt <- "IL"
  pullCounty  <- c("Cook County", "Will County", "Lake County", "Kane County", "McHenry County", "DuPage County")
    CountyLookup <- geo.lookup(state=pullSt, county=pullCounty)
    pullCountyCodes <- CountyLookup$county[!is.na(CountyLookup$county)]
  pullTract <- "*"
  pullTables <- unlist(strsplit("B01001 B01001A B01001B B01001C B01001D B01001E B01001F B01001G B01001H B01001I B08006 B08008 B08011 B08012 B08013 B15001 B15002 B17001 B12001 B12002 B12006 B17003 B17004 B17005 B19215 B19216 B14004 B14005 B05003 B23001 B23018 B23022 B24012 B24022 B24042 B24080 B24082 B24090 C24010 C24020 C24040 B11001 B11003 B11004 B13002 B13012 B13014 B13016 B17022 B23007 B23008 B25115", split= " "))

#----------------------------
#----------------------------
### Download and Extract Data
#----------------------------
#----------------------------

  # For now, this is just a test run using a sample data set
  
  myPathFileName <- dlDir %&% "Illinois_All_Geographies.zip"
  remoteDataName <- paste0("http://www2.census.gov/acs", pullYear, "_", pullSpan, "yr/summaryfile/", pullYear, "_ACSSF_By_State_All_Tables/", pullState, "_All_Geographies.zip")

  Meta <- read.csv(url(paste0("http://www2.census.gov/acs", pullYear, "_", pullSpan, "yr/summaryfile/Sequence_Number_and_Table_Number_Lookup.txt")), header = TRUE)
  if (downloadData == TRUE) {
    download.file(remoteDataName, myPathFileName)
    unzip(zipfile = myPathFileName) # NSM: am having problems explicitly feeding an argument to "exdir" for this function.
                                    # For now, it's using the current working directory as the default
  }

#----------------------------
#----------------------------
### Set Up Metadata for Files
#----------------------------
#----------------------------

  # Identify the sequence number corresponding to each table that has been specified
    #myMeta <- Meta[Meta$Table.ID %in% pullTables, ]
    Meta$ElemName <- paste0(Meta$Table.ID, "_", Meta$Line.Number)
    myMeta <- Meta[!is.na(Meta$Line.Number) & Meta$Line.Number %% 1 == 0, ]

    geoLabels <- read.csv(paste0(rootDir, "data/prepped-data/geofile-fields.csv"), header=T)
    # Note--this file was created by hand from the labels in the SAS version of the data prep file. See ".../scripts/Summary file assembly script from Census.sas"
    geoFile <- read.csv(paste0(dlDir, "g", pullYear, pullSpan, tolower(pullSt), ".csv"), header=F)
    colnames(geoFile) <- geoLabels$geoField
    myLogRecNos <- geoFile$LOGRECNO[geoFile$COUNTY %in% pullCountyCodes & geoFile$SUMLEVEL == 50]
    # Note -- summary level 50 corresponds to county-level summary. See Appendix F of the ACS 1-year summary document for a full list of summary levels and components.

    seqFile.dict <- list(c("FILEID", "File Identification"),
                         c("FILETYPE", "File Type"),
                         c("STUSAB", "State/U.S.-Abbreviation (USPS)"),
                         c("CHARITER", "Character Iteration"),
                         c("SEQUENCE", "Sequence Number"),
                         c("LOGRECNO", "Logical Record Number"))
    seqFile.idVars <- sapply(seqFile.dict, function(m) m[1])
    seqFile.mergeVars <- c("FILEID", "FILETYPE", "STUSAB", "LOGRECNO")

  # Pull those sequence files

#-----------------------------------
#-----------------------------------
### Select Tables and Merge Together
#-----------------------------------
#-----------------------------------

    for (t in pullTables) {
      # Compile meta-data related to the table
      t.seqNum <- myMeta[myMeta$Table.ID == t, "Sequence.Number"][1] # We can take the first element, since all of the returned sequence numbers should be the same
        # t.seqNum_check <- names(table(myMeta[myMeta$Table.ID == t, "Sequence.Number"]))
        # t.seqNum == t.seqNum_check
      seqFile.elemNames <- myMeta$ElemName[   myMeta$Sequence.Number == t.seqNum]
      t.elemNames       <- myMeta$ElemName[   myMeta$Table.ID        == t       ]
      #t.dataLabels      <- myMeta$Table.Title[myMeta$Table.ID        == t       ] # ... This isn't working well since the hierarchy of table element labels is not easy to reconstruct.
      tableMeta <- acs.lookup(endyear = 2011, span = pullSpan, dataset = "acs", table.name = t) # using year 2011 since the ACS package hasn't been updated to expect 2012 and throws an error. 2011 gets us the same results in terms of table information.
      t.dataLabels <- tableMeta@results$variable.name
      mySeqColNames <- c(seqFile.idVars, seqFile.elemNames)
      t.dataDict    <- cbind(t.elemNames, t.dataLabels)
        
      # Identify the proper sequence table and pull the appropriate table columns
      mySeq <- read.csv(paste0(dlDir, "e", pullYear, pullSpan, pullSt, sprintf("%04d", t.seqNum), "000.txt"), header=FALSE)
      print("Working on table " %&% t)
      colnames(mySeq) <- mySeqColNames
      
      # Pull the tables and geographies of interest
      myTable <- mySeq[mySeq$LOGRECNO %in% myLogRecNos, c(seqFile.mergeVars, t.elemNames) ]
      
      # Compile all requested table information
      if (t == pullTables[1]) {
        myResults <- myTable
        myDataDict <- t.dataDict
      } else {
        myResults <- merge(x=myResults, y=myTable, by=c("FILEID", "FILETYPE", "STUSAB", "LOGRECNO"))
        myDataDict <- rbind(myDataDict, t.dataDict)
      }
    }

  rownames(myResults) <- pullCounty

  write.csv(myResults, paste0(saveDir, "ACS_", pullYear, "_", pullSpan, "Year_", pullSt, "_PreppedVars.csv"))
  
  ### *2* Go back and make this a function

# Note--should set up an option for selecting either "e"stimates, "m"argin of error, or both
# Note--could speed things up by first checking whether the data needs to be downloaded again, and by looping through sequence rather than table. Looping by table may mean that we open up the same sequence file many times, slowing down processing.
# Note--depending on how much we want to save space, we can delete all tables that were not requested for our use
# Note--the filenaming convention is unique across end-years, aggregations, and sequence numbers.

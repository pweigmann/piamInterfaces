#' Generates an IIASA submission from REMIND runs by applying a project-specific mapping
#'
#' @md
#' @author Falk Benke, Oliver Richters
#' @param mifs path to mif files or directories with mif files of a REMIND run,
#'             or quitte object
#' @param model name of model registered with IIASA
#' @param mapping mapping template names such as c("AR6", "AR6_NGFS"). If NULL, user is asked
#' @param mappingFile path to mapping. If NULL, mapping is generated based on param mapping
#' @param removeFromScen string to be removed from scenario name (optional)
#' @param addToScen string to be added as prefix to scenario name (optional)
#' @param outputDirectory path to directory for the generated submission (default: output)
#' @param logFile path to the logfile with warnings (default: output/missing.log)
#' @param outputFilename filename of the generated submission mif or xlsx file.
#' @param iiasatemplate optional filename of xlsx or yaml file provided by IIASA
#'        used to delete superfluous variables and adapt units
#' @param generatePlots boolean, whether to generate plots of failing summation checks
#' @param generateSingleOutput has no effect and is only kept for backwards-compatibility
#' @param timesteps timesteps that are accepted in final submission
#' @importFrom data.table :=
#' @importFrom quitte as.quitte write.IAMCxlsx write.mif
#' @importFrom dplyr filter mutate distinct inner_join
#' @importFrom magclass unitsplit
#' @importFrom stringr str_trim
#' @examples
#' \dontrun{
#' # Simple use. Generates submission file in output folder:
#' generateIIASASubmission(
#'   mifs = "/path/to/REMIMD/mifs",
#'   model = "REMIND-MAgPIE 2.1-4.2",
#'   mappingFile = "output/template_navigate.csv"
#' )
#' }
#' @export
generateIIASASubmission <- function(mifs = ".", mapping = NULL, model = "REMIND 3.1", # nolint cyclocomp_linter
                                    mappingFile = NULL,
                                    removeFromScen = NULL, addToScen = NULL,
                                    outputDirectory = "output",
                                    logFile = "output/missing.log",
                                    outputFilename = "submission.xlsx",
                                    iiasatemplate = NULL, generatePlots = FALSE,
                                    timesteps = c(seq(2005, 2060, 5), seq(2070, 2100, 10)),
                                    generateSingleOutput = TRUE) {

  if (isTRUE(timesteps == "all")) timesteps <- seq(1, 3000)
  if (!is.null(outputDirectory)) {
    dir.create(outputDirectory, showWarnings = FALSE)
  }

  # for each directory, include all mif files
  if (is.character(mifs)) {
    invalidElements <- intersect(mifs[!dir.exists(mifs)], mifs[!file.exists(mifs)])

    if (length(invalidElements) > 0) {
      stop(paste0("Invalid argument 'mifs'. Element(s) that are neither files nor paths: ",
                  paste0(invalidElements, collapse = ", ")))
    }

    for (m in mifs[dir.exists(mifs)]) {
      if (length(list.files(m, "*.mif")) == 0) {
        stop(paste0("No mif files found in folder ", m))
      }
    }

    flist <- unique(c(mifs[!dir.exists(mifs)], list.files(mifs[dir.exists(mifs)], "*.mif", full.names = TRUE)))
    message(paste0("# Reading in mifs ", paste0(flist, collapse = ", ")))
    mifdata <- droplevels(as.quitte(flist), na.rm = TRUE)
  } else {
    mifdata <- droplevels(as.quitte(mifs, na.rm = TRUE))
  }

  if (any(grepl("^Price\\|.*\\|Moving Avg$", levels(mifdata$variable))) &&
      ! any(grepl("^Price\\|.*\\|Rawdata$", levels(mifdata$variable)))) {
   warning("Your data contains no Price|*|Rawdata variables. If it is based on a remind2 version",
           " before 1.111.0 on 2023-05-26, please use piamInterfaces version 0.9.0 or earlier, see PR #128.")
  }

  # generate mapping file, if it doesn't exist yet
  if (length(mapping) > 0 || is.null(mappingFile) || !file.exists(mappingFile)) {
    mapData <- generateMappingfile(templates = mapping, outputDirectory = NULL,
                                   fileName = NULL, model = model, logFile = logFile,
                                   iiasatemplate = iiasatemplate)[["mappings"]]
  } else {
    mapData <- read.csv2(mappingFile)
  }

  mapData <- mapData %>%
    mutate(
      !!sym("factor") := as.numeric(!!sym("factor")),
      # this is not optimal and error-prone: we must dissect variable into variable and unit again
      # could be avoided, if we expect mappings with variable and unit fields
      # instead of having the unit as part of the variable name
      !!sym("piam_unit") := unitsplit(!!sym("piam_variable"))$unit, # nolint
      !!sym("piam_variable") := removePlus(unitsplit(!!sym("piam_variable"))$variable), # nolint
      !!sym("Unit") := unitsplit(!!sym("Variable"))$unit, # nolint
      !!sym("Variable") := unitsplit(!!sym("Variable"))$variable # nolint
    )

  message("\n### Generating submission file using mapping ", paste(c(mapping, mappingFile), collapse = ", "), ".")
  if (!is.null(model)) message("# Correct model name to '", model, "'.")
  message("# Adapt scenario names: '",
          addToScen, "' will be prepended, '", removeFromScen, "' will be removed.")
  message("# Apply mapping ", mappingFile)

  mifdata <- .setModelAndScenario(mifdata, model, removeFromScen, addToScen)

  submission <- mifdata %>%
    filter(!!sym("period") %in% timesteps) %>%
    mutate(
      !!sym("variable") := removePlus(str_trim(!!sym("variable"))),
      !!sym("unit") := str_trim(!!sym("unit"))
      ) %>%
    distinct() %>%
    inner_join(mapData, by = c("variable" = "piam_variable", "unit" = "piam_unit"),
               relationship = "many-to-many") %>%
    mutate(
      !!sym("value") := ifelse(is.na(!!sym("factor")), !!sym("value"), !!sym("factor") * !!sym("value"))
    ) %>%
    select("model", "scenario", "region", "period", "variable" = "Variable", "unit" = "Unit", "value")


  submission <- aggregate(value ~ model + region + scenario + period + variable + unit, data = submission, FUN = "sum")

  if (!is.null(iiasatemplate) && file.exists(iiasatemplate)) {
    submission <- priceIndicesIIASA(submission, iiasatemplate, scenBase = NULL)
    submission <- checkIIASASubmission(submission, iiasatemplate, logFile, failOnUnitMismatch = FALSE)
  } else {
    message("# iiasatemplate ", iiasatemplate, " does not exist, returning full list of variables.")
  }

  # perform summation checks
  prefix <- gsub("\\.[A-Za-z]+$", "", if (is.null(outputFilename)) "output" else basename(outputFilename))
  for (sumFile in intersect(mapping, names(summationsNames()))) {
    invisible(checkSummations(submission, template = mapData,
                            summationsFile = sumFile, logFile = basename(logFile), logAppend = TRUE,
                            outputDirectory = outputDirectory, generatePlots = generatePlots,
                            dataDumpFile = paste0(prefix, "_checkSummations.csv"), plotprefix = paste0(prefix, "_")))
  }

  if (is.null(outputFilename)) {
    return(submission)
  } else {
    if (grepl("\\.xlsx?$", outputFilename)) {
      quitte::write.IAMCxlsx(submission, file.path(outputDirectory, outputFilename))
    } else {
      submission <- submission %>% mutate(value = ifelse(is.na(!!sym("value")), "", !!sym("value")))
      quitte::write.mif(submission, file.path(outputDirectory, outputFilename))
    }
    message("\n\n### Output file written: ", outputFilename)
  }
}

.setModelAndScenario <- function(dt, modelname, scenRemove = NULL, scenAdd = NULL) {
    scenarioNames <- unique(dt$scenario)
    if (!is.null(modelname)) dt$model <- modelname
    if (!is.null(scenRemove)) dt$scenario <- gsub(scenRemove, "", dt$scenario)
    if (!is.null(scenAdd)) {
      if (all(grepl(scenAdd, unique(dt$scenario), fixed = TRUE))) {
        message("Prefix ", scenAdd, " already found in all scenario names. Skipping.")
      } else {
        dt$scenario <- paste0(scenAdd, dt$scenario)
      }
    }
    if (length(unique(dt$scenario)) < length(scenarioNames)) {
      message(length(scenarioNames), " scenario names before changes: ", paste(scenarioNames, collapse = ", "))
      message(length(unique(dt$scenario)), " scenario names after changes:  ",
              paste(unique(dt$scenario), collapse = ", "))
      stop("Changes to scenario names lead to duplicates. Adapt scenRemove='",
           scenRemove, "' and scenAdd='", scenAdd, "'!")
    }

    dt$scenario <- as.factor(dt$scenario)
    return(dt)
}

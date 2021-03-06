
#' MB-MDR based classifier
#'
#' Use the MB-MDR HLO classification of top models to predict the disease risk.
#'
#' @param formula       		    	[\code{formula}]\cr
#'                      		    	A formula of the form LHS ~ RHS, where LHS is the dependent
#'                      		    	variable and RHS are the features to enter the MB-MDR
#'                      		     	genotype classification.
#' @param data          			    [\code{data.frame}]\cr
#'                      			    The data object.
#' @param order         			    [\code{int} or \code{integer}]\cr
#'                      			    Single integer specifying the interaction depth used
#'                      			    in the MB-MDR algorithm. Possible options are
#'                      			    1 and 2.
#' @param min.cell.size           [\code{int}]\cr
#'                                Single integer specifying the minimum number of
#'                                observation in a genotype combination to be statistically
#'                                relevant.
#' @param alpha         			    [\code{double}]\cr
#'                      			    Single numeric as significance level used during HLO
#'                      			    classification of genotype combinations.
#' @param adjustment              [\code{string}]\cr
#'                                Adjust method to be used.
#'                                "CODOMINANT", "ADDITIVE" or "NONE" (default).
#' @param max.results   			    [\code{int}]\cr
#'                      			    Single integer specifying the number of top models to
#'                      			    report.
#' @param top.results   			    [\code{int}]\cr
#'                      			    Single integer specifying how many models shall be used
#'                      			    for prediction. If \code{folds} and \code{cv.loss} are
#'                      			    set, this value specifies the upper limit of top results
#'                      			    to assess in CV.
#' @param folds         			    [\code{int}]\cr
#'                      			    Single interger specifying how many folds for internal
#'                      			    cross validation to find optimal \code{top.results}
#'                      			    should be used.
#' @param cv.loss       			    [\code{character}]\cr
#'                      			    One of \code{auc} or \code{bac}, specifying which loss
#'                      			    should be used to find optimal \code{top.results}.
#' @param o.as.na                 [\code{bool}]\cr
#'                                Encode non informative cells with NA or with 0.5.
#' @param dependent.variable.name [\code{string}]\cr
#' 									              Name of dependent variable, needed if no formula given.
#' @param verbose                 [\code{int}]\cr
#' 									              Level of verbosity. Default is level 1 giving some basic
#' 									              information about progress. Level 0 will switch off any
#' 									              output.
#' @param ...                     Arguments passed from and to other functions.
#'
#' @return A S3 object of class \code{mbmdrc}.
#'
#' @details If the data type of the dependent variable is a factor, classification mode is started automatically. Otherwise MB-MDR will run in regression mode.
#' In classification mode, the first factor level is assumed to code for the negative class.
#'
#' @export
#' @import data.table
mbmdrc <- function(formula, data,
                   order = 2L,
                   min.cell.size = 10L,
                   alpha = 0.1,
                   adjustment = "NONE",
                   max.results = 1000L,
                   top.results = 1000L,
                   folds, cv.loss, o.as.na = FALSE,
                   dependent.variable.name,
                   verbose,
                   ...) {

  # Input checks
  assertions <- checkmate::makeAssertCollection()

  checkmate::assertDataFrame(data, min.cols = 2, min.rows = 2,
                             add = assertions)
  checkmate::assertInteger(order, lower = 1, upper = 2,
                           max.len = 2, min.len = 1,
                           any.missing = FALSE, unique = TRUE, null.ok = FALSE,
                           add = assertions)
  checkmate::assertInt(min.cell.size, lower = 0,
                       add = assertions)
  checkmate::assertNumber(alpha, lower = 0, upper = 1,
                          add = assertions)
  checkmate::assertFlag(o.as.na,
                        add = assertions)
  checkmate::assertChoice(adjustment, c("CODOMINANT", "ADDITIVE", "NONE"),
                          add = assertions)
  checkmate::assertInt(max.results, lower = 1, upper = 1e4)
  checkmate::assertInt(top.results, lower = 1, upper = max.results)

  if (missing(verbose)) {
    verbose <- 1
  } else {
    checkmate::assertInt(verbose, lower = 0, upper = 1,
                         add = assertions)
  }

  verbose <- switch(verbose,
                    "0" = BBmisc::suppressAll,
                    "1" = suppressMessages
  )

  # Formula interface ----
  if (missing(formula)) {
    if (missing(dependent.variable.name)) {
      assertions$push("Please give formula or dependent variable name.")
    }
    checkmate::assertString(dependent.variable.name,
                            add = assertions)
    checkmate::assertChoice(dependent.variable.name, choices = colnames(data),
                            add = assertions)

    response <- data[, dependent.variable.name]
    data_selected <- data.matrix(data[, -which(colnames(data) == dependent.variable.name)])
  } else {
    formula <- stats::as.formula(formula)
    checkmate::assertClass(formula, classes = "formula",
                           add = assertions)
    data_selected <- stats::model.frame(formula, data, na.action = stats::na.pass)
    response <- data_selected[[1]]
  }

  # Prediction type ----
  if (is.factor(response)) {
    checkmate::assertFactor(response, n.levels = 2,
                            add = assertions)
    model_type <- "binary" # classification
  } else {
    model_type <- "continuous" # regression
  }

  # Interaction depth ----
  dim <- sapply(order, function(o) {
    switch(o,
           "1" = "1D",
           "2" = "2D",
           "3" = "3D")
  })

  checkmate::reportAssertions(assertions)

  # Dependent variable name ----
  if (!missing(formula)) {
    dependent_variable_name <- names(data_selected)[1]
    independent_variable_names <- names(data_selected)[-1]
  } else {
    dependent_variable_name <- dependent.variable.name
    indepentend_variable_names <- colnames(data_selected)[colnames(data_selected) != dependent.variable.name]
  }

  # Input data and variable names, create final data matrix
  if (is.matrix(data_selected)) {
    data_final <- data_selected
  } else {
    data_final <- data.matrix(data_selected)[, -1]
  }
  variable_names <- colnames(data_final)

  # Write MB-MDR file ----
  file <- tempfile()
  y <- if (is.factor(response)) {
    as.integer(response) - 1
  } else {
    response
  }
  global_mean = mean(y)
  data.table::fwrite(data.frame("y" = y,
                                data_final),
                     file = file,
                     sep = " ",
                     append = FALSE,
                     na = "-9")

  # Clean up ----
  rm("data_selected")

  # Initialize output ----
  result <- list()

  # Data dependent max.results and top.results
  max_results <- min(sum(sapply(order, function(o) choose(ncol(data_final), o))), max.results)
  top_results <- min(max_results, top.results)

  # Internal cross validation ----
  if (!missing(folds) & !missing(cv.loss)) {
    checkmate::assertInt(folds, na.ok = TRUE, null.ok = TRUE, lower = 2, upper = 10,
                         add = assertions)
    checkmate::assertChoice(cv.loss, choices = c("auc", "bac"),
                            add = assertions)

    # Select prediction type
    pred_type <- switch(cv.loss,
                        "auc" = "prob",
                        "bac" = "response")

    # Select loss function
    measure <- switch(cv.loss,
                      "auc" = auc,
                      "bac" = bac)

    # Set search space for optimal top_results value
    if (length(top_results) == 1) {
      top_results <- 1:max(top_results)
    }

    if (model_type == "binary") {
      # Stratified resampling
      fold_idx <- integer(length(response))
      fold <- 1
      lapply(BBmisc::chunk(which(response == levels(response)[1]), n.chunks = folds, shuffle = TRUE),
             FUN = function(chunk) {
               fold_idx[chunk] <<- fold
               fold <<- fold + 1
             })
      fold <- 1
      lapply(BBmisc::chunk(which(response == levels(response)[2]), n.chunks = folds, shuffle = TRUE),
             FUN = function(chunk) {
               fold_idx[chunk] <<- fold
               fold <<- fold + 1
             })
    } else {
      fold_idx <- integer(length(response))
      fold <- 1
      lapply(BBmisc::chunk(1:length(response), n.chunks = folds, shuffle = TRUE),
             FUN = function(chunk) {
               fold_idx[chunk] <<- fold
               fold <<- fold + 1
             })
    }

    # Calculate the MB-MDR for each fold and assess current top_results value
    cv_performance <- verbose(rbindlist(lapply(1:folds, function(f) {
      # Generate MB-MDR models on CV training data
      data_cv_train <- data_final[fold_idx != f,]
      response_cv_train <- response[fold_idx != f]
      cv_file <- tempfile()
      y <- if (is.factor(response_cv_train)) {
        as.integer(response_cv_train) - 1
      } else {
        response_cv_train
      }
      cv_global_mean <- mean(y)
      data.table::fwrite(data.frame("y" = y,
                                    data_cv_train),
                         file = cv_file,
                         sep = " ",
                         append = FALSE,
                         na = "-9")

      mbmdr <- do.call('c', lapply(dim, function(d) {
        mbmdR::mbmdr(file = cv_file, trait = model_type,
                     cpus.topfiles = 1,
                     cpus.permutations = 1,
                     work.dir = tempdir(),
                     n.pvalues = max_results,
                     permutations = 0,
                     group.size = min.cell.size,
                     alpha = alpha,
                     dim = d,
                     multi.test.corr = "NONE",
                     adjustment = adjustment,
                     verbose = "MEDIUM",
                     clean = TRUE)$mdr_models
      }))
      file.remove(list.files(tempdir(), pattern = basename(cv_file),
                             full.names = TRUE))

      # Predict on CV testing data
      data_cv_test <- data_final[fold_idx == f,]
      pred <- predict.mdr_models(object = mbmdr, newdata = data_cv_test,
                                 all = TRUE,
                                 o.as.na = o.as.na,
                                 global.mean = cv_global_mean,
                                 type = pred_type)

      # Prepare CV loss for all top_result values
      response_cv_test <- response[fold_idx == f]
      pred <- melt(pred, id.vars = "ID",
                   variable.name = "top_results",
                   value.name = pred_type)
      pred[, list(cv_loss = measure(get(pred_type),
                                    response_cv_test,
                                    positive = levels(response_cv_test)[2],
                                    negative = levels(response_cv_test)[1])), by = "top_results"]
    }), idcol = "fold"))

    # Select top_results value with optimal loss
    mean_cv_loss <- NULL # hack to circumvent R CMD CHECK notes
    top_results <- cv_performance[, list(mean_cv_loss = mean(cv_loss)),
                                  by = "top_results"][, which.max(mean_cv_loss)]

    # Save CV results
    result$cv_performance <- cv_performance
  }

  # Call MB-MDR ----
  mbmdr <- verbose(do.call('c', lapply(dim, function(d) {
    mbmdR::mbmdr(file = file, trait = model_type,
                 work.dir = tempdir(),
                 cpus.topfiles = 1, cpus.permutations = 1,
                 n.pvalues = max_results,
                 permutations = 0,
                 group.size = min.cell.size, alpha = alpha,
                 dim = d,
                 multi.test.corr = "NONE",
                 adjustment = adjustment,
                 verbose = "MEDIUM",
                 clean = TRUE)$mdr_models
  })))
  file.remove(list.files(tempdir(), pattern = basename(file),
                         full.names = TRUE))
  result$mbmdr <- mbmdr

  result$call <- sys.call()
  result$num_samples <- nrow(data_final)
  result$num_features <- ncol(data_final)
  result$num_combinations <- choose(ncol(data_final), order)
  result$model_type <- model_type
  result$top_results <- top_results
  result$global_mean <- global_mean
  if (is.factor(response)) {
    result$levels <- levels(droplevels(response))
  }

  class(result) <- "mbmdrc"

  return(result)

}

#' MB-MDR classifier prediction
#'
#' Prediction with new data and saved MB-MDR classifier object.
#'
#' @param object        [\code{mbmdr}]\cr
#'                      MB-MDR models and HLO tables as output from \code{\link{mbmdrc}}.
#' @param newdata       [\code{newdata}]\cr
#'                      New data to predict class status for.
#' @param type          [\code{string}]\cr
#'                      Type of prediction. One of \code{response}, \code{prob},
#'                      \code{score} or \code{scoreprob}. See details.
#'                      Default is \code{response}.
#' @param top.results   [\code{int}]\cr
#'                      How many models are used for prediction.
#' @param all           [\code{bool}]\cr
#' 						          Output predictions for all possible top results.
#' @param o.as.na       [\code{bool}]\cr
#'                      Encode non informative cells with NA or with 0.5.
#' @param ...           Further arguments passed to or from other methods.
#'
#' @return A \code{data.table} object with an ID column and the prediction value.
#'
#' @details For \code{type='response'} (the default), the predicted classes, for
#' \code{type='prob'} the predicted case probabilities, for \code{type='score'}
#' the predicted risk scores and for \code{type='scoreprob'} the predicted risk
#' scores transformed to the [0, 1] interval are returned.
#'
#' For \code{type='score'} and \code{type='scoreprob'} genotypes classified as
#' H contribute +1, as L contribute -1 and as O contribute 0 to the score.
#'
#' If a genotype combination is classified as O by MB-MDR, the case probability
#' is not significantly different from the global mean. On the other hand, there
#' might have been just too few observations in the training data so that
#' \code{NA} might be more reasonable as contribution to \code{response} and
#' \code{prob} type predictions.
#'
#' @import data.table
predict.mdr_models <- function(object, newdata, type = "response", top.results, all = FALSE, o.as.na = TRUE, global.mean = 0.5, ...) {

  # data.table dummys
  PROB <- NULL
  MODEL <- NULL
  SCOREPROB <- NULL
  SCORE <- NULL
  ID <- NULL

  # Input checks ----
  assertions <- checkmate::makeAssertCollection()
  checkmate::assertClass(object, "mdr_models",
                         add = assertions)
  checkmate::assert(checkmate::checkDataFrame(newdata),
                    checkmate::checkMatrix(newdata),
                    combine = "or")
  features <- unique(unlist(sapply(object, function(model) model$features)))
  checkmate::assertSubset(features, colnames(newdata),
                          add = assertions)
  checkmate::assertChoice(type, c("response", "prob", "score", "scoreprob"),
                          add = assertions)
  checkmate::assertFlag(all,
                        add = assertions)
  checkmate::assertFlag(o.as.na,
                        add = assertions)
  checkmate::assertNumber(global.mean, finite = TRUE, null.ok = FALSE,
                          add = assertions)
  if (missing(top.results) & !all) {
    checkmate::reportAssertions(assertions)
    stop("Please specify the number of top results to enter predictions or set 'all=TRUE'")
  } else if (!missing(top.results)) {
    checkmate::assertInt(top.results,
                         lower = 0, upper = length(object),
                         na.ok = FALSE, null.ok = FALSE,
                         add = assertions)
  }

  checkmate::reportAssertions(assertions)

  # Get number of models and number of samples
  num_models <- if (all) {
    length(object)
  } else {
    top.results
  }
  num_samples <- nrow(newdata)

  # Iterate through MB-MDR models
  predictions <- rbindlist(lapply(1:num_models, function(m) {
    # Get genotypes
    genotypes <- apply(
      X = subset(newdata, select = object[[m]]$features),
      MARGIN = 2,
      FUN = function(col) {
        col <- factor(col)
        levels(col) <- 0:(length(levels(col))-1)
        return(col)
      }
    )
    storage.mode(genotypes) <- "integer"

    # Construct bases for indexing
    num_rows <- attr(object[[m]]$cell_labels, "num_rows")
    bases <- if (num_rows == 1) {
      length(object[[m]]$cell_labels)
    } else {
      c(length(object[[m]]$cell_labels)/num_rows, num_rows)
    }

    # Construct index as linear combination of bases and feature combination
    idx <- genotypes %*% bases^(0:(length(bases) - 1)) + 1

    # Get cell predictions
    prob <- object[[m]]$cell_predictions[idx]

    if (!o.as.na) {
      # Set cell predictions to global for non-informative cells or feature combinations not present in training data
      prob[object[[m]]$cell_labels[idx] %in% c("N", "O") | is.na(prob)] <- global.mean
    } else {
      # Set cell predictions to NA for non-informative cells or feature combinations not present in training data
      prob[object[[m]]$cell_labels[idx] %in% c("N", "O") | is.na(prob)] <- NA
    }

    data.table(ID = 1:num_samples, PROB = prob)
  }), idcol = "MODEL")

  if (all) {
    switch(type,
           # Round the mean case probability to 0 or 1 to return hard classification
           "response" = return(dcast(predictions[, list(RESPONSE = round(cumsum(PROB)/1:max(MODEL)),
                                                        TOPRESULTS = 1:max(MODEL)), by = c("ID")],
                                     ID~TOPRESULTS, value.var = "RESPONSE")),
           # Return mean case probability over all models for all top.results
           "prob" = return(dcast(predictions[, list(PROB = cumsum(PROB)/1:max(MODEL),
                                                    TOPRESULTS = 1:max(MODEL)), by = c("ID") ],
                                 ID~TOPRESULTS, value.var = "PROB")),
           # Return a risk score. Genotype combinations classified as H contribute +1,
           # genotype combinations classified as L contribute -1 and genotype combinations
           # classified as O contribute 0
           "score" = return(dcast(predictions[, list(SCORE = cumsum(sign(PROB - 0.5)),
                                                     TOPRESULTS = 1:max(MODEL)), by = c("ID") ],
                                  ID~TOPRESULTS, value.var = "SCORE")),
           # Return the score transformed to a [0, 1] interval
           "scoreprob" = return(dcast(predictions[, list(SCORE = cumsum(sign(PROB - 0.5)),
                                                         TOPRESULTS = 1:max(MODEL)), by = c("ID")][, SCOREPROB := range01(SCORE),
                                                                                                   by = c("TOPRESULTS")],
                                      ID~TOPRESULTS,
                                      value.var = "SCOREPROB")))
  } else {
    switch(type,
           # Round the mean case probability to 0 or 1 to return hard classification
           "response" = return(predictions[MODEL <= top.results, list(predictions = round(mean(PROB, na.rm = TRUE))),
                                           by = c("ID")]$predictions),
           # Return mean case probability over all models
           "prob" = return(predictions[MODEL <= top.results, list(predictions = mean(PROB, na.rm = TRUE)),
                                       by = c("ID")]$predictions),
           # Return a risk score. Genotype combinations classified as H contribute +1,
           # genotype combinations classified as L contribute -1 and genotype combinations
           # classified as O contribute 0
           "score" = return(predictions[MODEL <= top.results, list(predictions = sum(sign(PROB - 0.5), na.rm = TRUE)),
                                        by = c("ID")]$predictions),
           # Return the score transformed to a [0, 1] interval
           "scoreprob" = return(predictions[MODEL <= top.results, list(predictions = sum(sign(PROB - 0.5), na.rm = TRUE)),
                                            by = c("ID")][, list(ID, predictions = range01(predictions))]$predictions))
  }

}

#' @export
#' @rdname predict.mdr_models
predict.mbmdr <- function(object, newdata, ...) {
  predict(object$mdr_models, newdata, ...)
}

#' @rdname predict.mdr_models
#'
#' @export
predict.mbmdrc <- function(object, newdata, type = "response", top.results, o.as.na = TRUE, ...) {

  # Input checks ----
  assertions <- checkmate::makeAssertCollection()

  checkmate::assertClass(object, "mbmdrc",
                         add = assertions)
  checkmate::assertDataFrame(newdata,
                             add = assertions)
  checkmate::assertSubset(object$mbmdr$feature_names, colnames(newdata))
  checkmate::assertChoice(type, choices = c("response", "prob", "score", "scoreprob"),
                          add = assertions)
  if (!missing(top.results)) {
    checkmate::assertInt(top.results, lower = 1, upper = length(object$mbmdr),
                         add = assertions)
    top_results <- min(length(object$mbmdr), top.results)
  } else {
    top_results <- object$top_results
  }
  checkmate::assertFlag(o.as.na,
                        add = assertions)

  checkmate::reportAssertions(assertions)

  predictions <- stats::predict(object$mbmdr, newdata = newdata,
                                type = type,
                                top.results = top_results,
                                o.as.na = o.as.na,
                                global.mean = object$global_mean, ...)

  if (type %in% c("prob", "scoreprob")) {
    predictions <- cbind(1 - predictions, predictions)
    colnames(predictions) <- object$levels
  } else {
    predictions <- factor(predictions, levels = c(0, 1), labels = object$levels)
  }

  return(predictions)

}

range01 <- function(x, ...) {
  (x - min(x, ...)) / (max(x, ...) - min(x, ...))
}

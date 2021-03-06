#' Class for Storing Data and NPSEM for TMLE
#'
#' This class inherits from \code{\link[sl3]{sl3_Task}}. In addition to all the
#'  methods supported by \code{\link[sl3]{sl3_Task}}, it supports the following.
#'
#' @docType class
#'
#' @importFrom R6 R6Class
#' @importFrom sl3 sl3_Task
#' @import data.table
#'
#' @export
#'
#' @keywords data
#'
#' @return \code{tmle3_Task} object
#'
#' @format \code{\link{R6Class}} object.
#'
#' @template tmle3_Task_extra
#'
#' @export
#
tmle3_Task <- R6Class(
  classname = "tmle3_Task",
  portable = TRUE,
  class = TRUE,
  inherit = sl3_Task,
  public = list(
    initialize = function(data, npsem, ...) {
      super$initialize(data, covariates = c(), outcome = NULL, ...)
      node_names <- sapply(npsem, `[[`, "name")
      names(npsem) <- node_names
      for (node_name in node_names) {
        variables <- npsem[[node_name]]$variables
        variable_data <- super$get_data(, variables)
        if (ncol(variable_data) == 1) {
          variable_data <- unlist(variable_data, use.names = FALSE)
        }
        if (is.null(npsem[[node_name]]$variable_type)) {
          npsem[[node_name]]$guess_variable_type(variable_data)
        }
      }
      private$.npsem <- npsem
      private$.node_cache <- new.env()
    },
    get_tmle_node = function(node_name, bound = FALSE) {
      cache_key <- sprintf("%s_%s", node_name, bound)
      cached_data <- get0(cache_key, private$.node_cache, inherits = FALSE)
      if (!is.null(cached_data)) {
        return(cached_data)
      }
      tmle_node <- self$npsem[[node_name]]
      node_var <- tmle_node$variables

      data <- self$get_data(, node_var)

      if (bound) {
        bounds <- tmle_node$variable_type$bounds
        if (!is.null(bounds)) {
          scale <- bounds[2] - bounds[1]
          shift <- bounds[1]
          data <- data[, lapply(.SD, function(vals) (vals - shift) / scale)]
        }
      }


      if (ncol(data) == 1) {
        data <- unlist(data, use.names = FALSE)
      }

      assign(cache_key, data, private$.node_cache)

      return(data)
    },
    get_regression_task = function(target_node, bound = TRUE) {
      npsem <- self$npsem
      target_node_object <- npsem[[target_node]]
      parent_names <- target_node_object$parents
      parent_nodes <- npsem[parent_names]
      outcome <- target_node_object$variables
      covariates <- unlist(lapply(parent_nodes, `[[`, "variables"))

      # todo: consider if self$data isn't a better option here
      data <- self$internal_data

      # bound continuous outcome if bounds are specified to variable_type
      variable_type <- target_node_object$variable_type
      column_names <- self$column_names
      if ((variable_type$type == "continuous") &&
        (!is.null(variable_type$bounds)) &&
        bound) {
        # TODO: make quasibinomial, make more learners play nice with
        #       quasibinomial outcomes
        bounded_vals <- self$get_tmle_node(target_node, bound = TRUE)
        col_name <- sprintf("__%s_bounded", target_node)
        new_data <- data.table(bounded_vals)
        setnames(new_data, col_name)
        column_names <- self$add_columns(new_data, self$uuid)
        outcome <- col_name
      }

      nodes <- self$nodes
      nodes$outcome <- outcome
      nodes$covariates <- covariates


      regression_task <- sl3_Task$new(
        data,
        nodes = nodes,
        outcome_type = variable_type,
        column_names = column_names,
        folds = self$folds
      )

      return(regression_task)
    },
    generate_counterfactual_task = function(uuid, new_data) {
      # for current_factor, generate counterfactual values
      node_names <- names(new_data)
      node_variables <- sapply(
        node_names,
        function(node_name) {
          self$npsem[[node_name]]$variables
        }
      )
      setnames(new_data, node_names, node_variables)

      new_task <- self$clone()
      new_column_names <- new_task$add_columns(new_data, uuid)
      new_task$initialize(
        self$internal_data, self$npsem,
        column_names = new_column_names,
        folds = self$folds
      )
      return(new_task)
    },
    next_in_chain = function(...) {
      return(super$next_in_chain(npsem = self$npsem, ...))
    },
    print = function() {
      cat(sprintf("A sl3 Task with %d obs and these nodes:\n", self$nrow))
      print(self$npsem)
    }
  ),
  active = list(
    npsem = function() {
      return(private$.npsem)
    },
    data = function() {
      all_variables <- unlist(lapply(self$npsem, `[[`, "variables"))
      self$get_data(columns = all_variables)
    }
  ),
  private = list(
    .npsem = NULL,
    .node_cache = NULL
  )
)

#' @param ... Passes all arguments to the constructor. See documentation for the
#'  Constructor below.
#'
#' @rdname tmle3_Task
#'
#' @export
#
make_tmle3_Task <- tmle3_Task$new

#' @title Confusion matrix.
#'
#' @description
#' Calculates the confusion matrix for a (possibly resampled) prediction.
#' Rows indicate true classes, columns predicted classes. The marginal elements count the number of
#' classification errors for the respective row or column, i.e., the number of errors
#' when you condition on the corresponding true (rows) or predicted (columns) class.
#' The last bottom right element displays the total amount of errors.
#'
#' A list is returned that contains multiple matrices.
#' If \code{relative = TRUE} we compute three matrices, one with absolute values and two with relative.
#' The relative confusion matrices are normalized based on rows and columns respectively,
#' if \code{FALSE} we only compute the absolute value matrix.
#'
#' The \code{print} function returns the relative matrices in
#' a compact way so that both row and column marginals can be seen in one matrix.
#' For details see \code{\link{ConfusionMatrix}}.
#'
#' Note that for resampling no further aggregation is currently performed.
#' All predictions on all test sets are joined to a vector yhat, as are all labels
#' joined to a vector y. Then yhat is simply tabulated vs. y, as if both were computed on
#' a single test set. This probably mainly makes sense when cross-validation is used for resampling.
#'
#' @template arg_pred
#' @param relative [\code{logical(1)}]\cr
#'   If \code{TRUE} two additional matrices are calculated. One is normalized by rows and one by
#'   columns.
#' @param sums {\code{logical(1)}}\cr
#'   If \code{TRUE} add absolute number of observations in each group.
#' @return [\code{\link{ConfusionMatrix}}].
#' @family performance
#' @export
#' @examples
#' # get confusion matrix after simple manual prediction
#' allinds = 1:150
#' train = sample(allinds, 75)
#' test = setdiff(allinds, train)
#' mod = train("classif.lda", iris.task, subset = train)
#' pred = predict(mod, iris.task, subset = test)
#' print(calculateConfusionMatrix(pred))
#' print(calculateConfusionMatrix(pred, sums = TRUE))
#' print(calculateConfusionMatrix(pred, relative = TRUE))
#'
#' # now after cross-validation
#' r = crossval("classif.lda", iris.task, iters = 2L)
#' print(calculateConfusionMatrix(r$pred))

calculateConfusionMatrix = function(pred, relative = FALSE, sums = FALSE) {
  checkPrediction(pred, task.type = "classif", check.truth = TRUE, no.na = TRUE)
  assertFlag(relative)
  assertFlag(sums)
  cls = getTaskClassLevels(pred$task.desc)
  k = length(cls)
  n = getTaskSize(pred$task.desc)
  resp = getPredictionResponse(pred)
  truth = getPredictionTruth(pred)
  tab = table(truth, resp)
  # create table for margins, where only the off-diag errs are in
  mt = tab; diag(mt) = 0
  row.err = rowSums(mt)
  col.err = colSums(mt)
  result = rbind(cbind(tab, row.err), c(col.err, sum(col.err)))
  dimnames(result) = list(true = c(cls, "-err.-"), predicted = c(cls, "-err.-"))

  if (sums) {
    rowsum = rowSums(tab)
    colsum = colSums(tab)
    result = rbind(cbind(result, c(rowsum, NA)), c(colsum, NA, n))
    colnames(result)[k + 2] = "-n-"
    rownames(result)[k + 2] = "-n-"
  }

  result = list(result = result, task.desc = getTaskDescription(pred), relative = relative, sums = sums)

  js = 1:k # indexes for nonmargin cols

  if (relative) {

    normConfMatrix = function(r) {
      if (any(r[js] > 0))
        r / sum(r[js])
      else
        rep(0, k)
    }

    #normalize by rows and add margins as a new column
    result.rel.row = t(apply(tab, 1, normConfMatrix))
    result.rel.row = cbind(result.rel.row, "-err-" = rowSums(result.rel.row) - diag(result.rel.row))

    #normalize by columns and add margins as a new row
    result.rel.col = apply(tab, 2, normConfMatrix)
    result.rel.col = rbind(result.rel.col, "-err-" = colSums(result.rel.col) - diag(result.rel.col))

    result$relative.row = result.rel.row
    result$relative.col = result.rel.col
    result$relative.error = sum(result$result[k+1, 1:(k+1)])/n
  }

  addClasses(result, "ConfusionMatrix")
}

#' @export
#' @describeIn calculateConfusionMatrix
#'
#' @param x [\code{\link{ConfusionMatrix}}]\cr
#'   Object to print.
#' @param both [\code{logical(1)}]\cr
#'   If \code{TRUE} both the absolute and relative confusion matrices are printed.
#' @param digits [\code{integer(1)}]\cr
#'   How many numbers after the decimal point should be printed, only relevant for relative confusion matrices.
#' @param ... [any]\cr
#'  Currently not used.
print.ConfusionMatrix = function(x, both = TRUE, digits = 2, ...) {

  assertFlag(both)
  assertInt(digits, lower = 1)

  #formatting stuff, use digits after(!) the decimal point.
  nsmall = digits
  digits = nsmall - 1

  cls = getTaskDescription(x$task.desc)$class.levels
  k = length(cls)
  n = getTaskDescription(x$task.desc)$size


  if (x$relative) {
    js = 1:k
    res = paste(format(x$relative.row[js, js], digits = digits, nsmall = nsmall),
      format(x$relative.col[js, js], digits = digits, nsmall = nsmall), sep = "/")
    attributes(res) = attributes(x$relative.row[js, js])


    col.err = x$relative.col[k + 1,]
    row.err = x$relative.row[,k + 1]
    full.err = stri_pad_right(format(x$relative.error, digits = digits, nsmall = nsmall),
      width = nchar(res[1,1]))

    #bind marginal errors correctly formatted to rows and columns
    res = rbind(res, stri_pad_left(format(col.err, digits = digits, nsmall = nsmall),
      width = nchar(res[1,1])))
    res = cbind(res, c(format(row.err, digits = digits, nsmall = nsmall), full.err))

    #also bind the marginal sums to the relative confusion matrix for printing
    if (x$sums) {
      res = rbind(cbind(res, c(x$result["-n-", 1:k], NA)), c(x$result[1:k, "-n-"], NA, n))
      dimnames(res) = list(true = c(cls, "-err.-", "-n-"), predicted = c(cls, "-err.-", "-n-"))
    } else {
      dimnames(res) = list(true = c(cls, "-err.-"), predicted = c(cls, "-err.-"))
    }

    cat("Relative confusion matrix (normalized by row/column):\n")
    print(noquote(res))
    if (both) {
      cat("\n\nAbsolute confusion matrix:\n")
      print(x$result)
    }
  }
  else {
    print(x$result)
  }
}

#' @title Confusion matrix
#'
#' @description
#' The result of \code{\link{calculateConfusionMatrix}}.
#'
#' Object members:
#' \describe{
#' \item{result [\code{matrix}]}{Confusion matrix of absolute values and marginals. Can also contain
#'   row and column sums of observations.}
#' \item{task.desc [\code{\link{TaskDesc}}]}{Additional information about the task.}
#' \item{sums [\code{logical(1)}]}{Flag if marginal sums of observations are calculated.}
#' \item{relative [\code{logical(1)}]}{Flag if the relative confusion matrices are calculated.}
#' \item{relative.row [\code{matrix}]}{Confusion matrix of relative values and marginals normalized by row.}
#' \item{relative.col [\code{matrix}]}{Confusion matrix of relative values and marginals normalized by column.}
#' \item{relative.error [\code{numeric(1)}]}{Relative error overall.}
#' }
#' @name ConfusionMatrix
#' @family performance
NULL

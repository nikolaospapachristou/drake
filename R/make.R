#' @title Run your project (build the outdated targets).
#' \lifecycle{maturing}
#' @description This is the central, most important function
#' of the drake package. It runs all the steps of your
#' workflow in the correct order, skipping any work
#' that is already up to date.
#' See <https://github.com/ropensci/drake/blob/master/README.md#documentation>
#' for an overview of the documentation.
#' @section Interactive mode:
#' In interactive sessions, consider [r_make()], [r_outdated()], etc.
#' rather than [make()], [outdated()], etc. The `r_*()` `drake` functions
#' are more reproducible when the session is interactive.
#'
#' A serious drake workflow should be consistent and reliable,
#' ideally with the help of a master R script.
#' This script should begin in a fresh R session,
#' load your packages and functions in a dependable manner,
#' and then run `make()`. Example:
#' <https://github.com/wlandau/drake-examples/tree/master/gsp>.
#' Batch mode, especially within a container, is particularly helpful.
#'
#' Interactive R sessions are still useful,
#' but they easily grow stale.
#' Targets can falsely invalidate if you accidentally change
#' a function or data object in your environment.
#'
#' @section Self-invalidation:
#' It is possible to construct a workflow that tries to invalidate itself.
#' Example:
#' ```r
#' plan <- drake_plan(
#'   x = {
#'     data(mtcars)
#'     mtcars$mpg
#'   },
#'   y = mean(x)
#' )
#' ```
#' Here, because `data()` loads `mtcars` into the global environment,
#' the very act of building `x` changes the dependencies of `x`.
#' In other words, without safeguards, `x` would not be up to date at
#' the end of `make(plan)`.
#' Please try to avoid workflows that modify the global environment.
#' Functions such as `data()` belong in your setup scripts
#' prior to `make()`, not in any functions or commands that get called
#' during `make()` itself.
#'
#' For each target that is still problematic  (e.g.
#' <https://github.com/rstudio/gt/issues/297>)
#' you can safely run the command in its own special `callr::r()` process.
#' Example: <https://github.com/rstudio/gt/issues/297#issuecomment-497778735>. # nolint
#'
#' If that fails, you can run `make(plan, lock_envir = FALSE)`
#' to suppress environment-locking for all targets.
#' However, this is not usually recommended.
#' There are legitimate use cases for `lock_envir = FALSE`
#' (example: <https://books.ropensci.org/drake/hpc.html#parallel-computing-within-targets>) # nolint
#' but most workflows should stick with the default `lock_envir = TRUE`.
#'
#' @seealso
#'   [drake_plan()],
#'   [drake_config()],
#'   [vis_drake_graph()],
#'   [outdated()]
#' @export
#' @return nothing
#' @inheritParams drake_config
#' @param config Deprecated.
#' @examples
#' \dontrun{
#' isolate_example("Quarantine side effects.", {
#' if (suppressWarnings(require("knitr"))) {
#' load_mtcars_example() # Get the code with drake_example("mtcars").
#' config <- drake_config(my_plan)
#' outdated(my_plan) # Which targets need to be (re)built?
#' make(my_plan) # Build what needs to be built.
#' outdated(my_plan) # Everything is up to date.
#' # Change one of your imported function dependencies.
#' reg2 = function(d) {
#'   d$x3 = d$x^3
#'   lm(y ~ x3, data = d)
#' }
#' outdated(my_plan) # Some targets depend on reg2().
#' make(my_plan) # Rebuild just the outdated targets.
#' outdated(my_plan) # Everything is up to date again.
#' if (requireNamespace("visNetwork", quietly = TRUE)) {
#' vis_drake_graph(my_plan) # See how they fit in an interactive graph.
#' make(my_plan, cache_log_file = TRUE) # Write a CSV log file this time.
#' vis_drake_graph(my_plan) # The colors changed in the graph.
#' # Run targets in parallel:
#' # options(clustermq.scheduler = "multicore") # nolint
#' # make(my_plan, parallelism = "clustermq", jobs = 2) # nolint
#' }
#' clean() # Start from scratch next time around.
#' }
#' # Dynamic branching
#' # Get the mean mpg for each cyl in the mtcars dataset.
#' plan <- drake_plan(
#'   raw = mtcars,
#'   group_index = raw$cyl,
#'   munged = target(raw[, c("mpg", "cyl")], dynamic = map(raw)),
#'   mean_mpg_by_cyl = target(
#'     data.frame(mpg = mean(munged$mpg), cyl = munged$cyl[1]),
#'     dynamic = group(munged, .by = group_index)
#'   )
#' )
#' make(plan)
#' readd(mean_mpg_by_cyl)
#' })
#' }
make <- function(
  plan,
  targets = NULL,
  envir = parent.frame(),
  verbose = 1L,
  hook = NULL,
  cache = drake::drake_cache(),
  fetch_cache = NULL,
  parallelism = "loop",
  jobs = 1L,
  jobs_preprocess = 1L,
  packages = rev(.packages()),
  lib_loc = NULL,
  prework = character(0),
  prepend = NULL,
  command = NULL,
  args = NULL,
  recipe_command = NULL,
  log_progress = TRUE,
  skip_targets = FALSE,
  timeout = NULL,
  cpu = Inf,
  elapsed = Inf,
  retries = 0,
  force = FALSE,
  graph = NULL,
  trigger = drake::trigger(),
  skip_imports = FALSE,
  skip_safety_checks = FALSE,
  config = NULL,
  lazy_load = "eager",
  session_info = TRUE,
  cache_log_file = NULL,
  seed = NULL,
  caching = "master",
  keep_going = FALSE,
  session = NULL,
  pruning_strategy = NULL,
  makefile_path = NULL,
  console_log_file = NULL,
  ensure_workers = NULL,
  garbage_collection = FALSE,
  template = list(),
  sleep = function(i) 0.01,
  hasty_build = NULL,
  memory_strategy = "speed",
  layout = NULL,
  spec = NULL,
  lock_envir = TRUE,
  history = TRUE,
  recover = FALSE,
  recoverable = TRUE,
  curl_handles = list(),
  max_expand = NULL,
  log_build_times = TRUE,
  format = NULL,
  lock_cache = TRUE
) {
  force(envir)
  deprecate_arg(config, "config")
  config <- config %|||% drake_config(
    plan = plan,
    targets = targets,
    envir = envir,
    verbose = verbose,
    hook = hook,
    cache = cache,
    fetch_cache = fetch_cache,
    parallelism = parallelism,
    jobs = jobs,
    jobs_preprocess = jobs_preprocess,
    packages = packages,
    lib_loc = lib_loc,
    prework = prework,
    prepend = prepend,
    command = command,
    args = args,
    recipe_command = recipe_command,
    log_progress = log_progress,
    skip_targets = skip_targets,
    timeout = timeout,
    cpu = cpu,
    elapsed = elapsed,
    retries = retries,
    force = force,
    graph = graph,
    trigger = trigger,
    skip_imports = skip_imports,
    skip_safety_checks = skip_safety_checks,
    lazy_load = lazy_load,
    session_info = session_info,
    cache_log_file = cache_log_file,
    seed = seed,
    caching = caching,
    keep_going = keep_going,
    session = session,
    pruning_strategy = pruning_strategy,
    makefile_path = makefile_path,
    console_log_file = console_log_file,
    ensure_workers = ensure_workers,
    garbage_collection = garbage_collection,
    template = template,
    sleep = sleep,
    hasty_build = hasty_build,
    memory_strategy = memory_strategy,
    layout = layout,
    spec = spec,
    lock_envir = lock_envir,
    history = history,
    recover = recover,
    recoverable = recoverable,
    curl_handles = curl_handles,
    max_expand = max_expand,
    log_build_times = log_build_times,
    format = format,
    lock_cache = lock_cache
  )
  make_impl(config)
}

#' @title Internal function with a drake_config() argument
#' @export
#' @keywords internal
#' @description Not a user-side function.
#' @param config a [drake_config()] object.
make_impl <- function(config) {
  config$logger$minor("begin make()")
  on.exit(config$logger$minor("end make()"), add = TRUE)
  runtime_checks(config = config)
  if (config$lock_cache) {
    config$cache$lock()
    on.exit(config$cache$unlock(), add = TRUE)
  }
  config$running_make <- TRUE
  config$ht_dynamic <- ht_new()
  config$ht_dynamic_size <- ht_new()
  config$ht_is_subtarget <- ht_new()
  config$ht_target_exists <- ht_target_exists(config)
  config$envir_loaded <- new.env(hash = FALSE, parent = emptyenv())
  config$cache$reset_memo_hash()
  on.exit(config$cache$reset_memo_hash(), add = TRUE)
  config$cache$set(key = "seed", value = config$seed, namespace = "session")
  if (config$log_progress) {
    config$cache$clear(namespace = "progress")
  }
  drake_set_session_info(cache = config$cache, full = config$session_info)
  do_prework(config = config, verbose_packages = config$logger$verbose)
  if (!config$skip_imports) {
    process_imports(config)
  }
  if (is.character(config$parallelism)) {
    config$envir_graph <- new.env(parent = emptyenv())
    config$envir_graph$graph <- outdated_subgraph(config)
  }
  r_make_message(force = FALSE)
  if (!config$skip_targets) {
    process_targets(config)
  }
  drake_cache_log_file_(
    file = config$cache_log_file,
    cache = config$cache,
    jobs = config$jobs_preprocess
  )
  clear_make_memory(config)
  invisible()
}

process_targets <- function(config) {
  if (is.character(config$parallelism)) {
    run_native_backend(config)
  } else {
    run_external_backend(config)
  }
}

run_native_backend <- function(config) {
  parallelism <- match.arg(
    config$parallelism,
    c("loop", "clustermq", "future")
  )
  if (igraph::gorder(config$envir_graph$graph)) {
    class(config) <- c(class(config), parallelism)
    drake_backend(config)
  } else {
    config$logger$major("All targets are already up to date.", color = NULL)
  }
}

drake_backend <- function(config) {
  UseMethod("drake_backend")
}

run_external_backend <- function(config) {
  warning(
    "`drake` can indeed accept a custom scheduler function for the ",
    "`parallelism` argument of `make()` ",
    "but this is only for the sake of experimentation ",
    "and graceful deprecation. ",
    "Your own custom schedulers may cause surprising errors. ",
    "Use at your own risk.",
    call. = FALSE
  )
  config$parallelism(config = config)
}

outdated_subgraph <- function(config) {
  outdated <- outdated_impl(config, do_prework = FALSE, make_imports = FALSE)
  config$logger$minor("isolate oudated targets")
  igraph::induced_subgraph(graph = config$graph, vids = outdated)
}

drake_set_session_info <- function(
  path = NULL,
  search = NULL,
  cache = drake::drake_cache(path = path),
  verbose = NULL,
  full = TRUE
) {
  deprecate_verbose(verbose)
  if (is.null(cache)) {
    stop("No drake::make() session detected.")
  }
  if (full) {
    cache$set(
      key = "sessionInfo",
      value = utils::sessionInfo(),
      namespace = "session"
    )
  }
  cache$set(
    key = "drake_version",
    value = as.character(utils::packageVersion("drake")),
    namespace = "session"
  )
  invisible()
}

#' @title Do the prework in the `prework`
#'   argument to [make()].
#' \lifecycle{stable}
#' @export
#' @keywords internal
#' @description For internal use only.
#' The only reason this function is exported
#' is to set up parallel socket (PSOCK) clusters
#' without too much fuss.
#' @return Inivisibly returns `NULL`.
#' @param config A configured workflow from [drake_config()].
#' @param verbose_packages logical, whether to print
#'   package startup messages
#' @examples
#' \dontrun{
#' isolate_example("Quarantine side effects.", {
#' if (suppressWarnings(require("knitr"))) {
#' load_mtcars_example() # Get the code with drake_example("mtcars").
#' # Create a master internal configuration list with prework.
#' con <- drake_config(my_plan, prework = c("library(knitr)", "x <- 1"))
#' # Do the prework. Usually done at the beginning of `make()`,
#' # and for distributed computing backends like "future_lapply",
#' # right before each target is built.
#' do_prework(config = con, verbose_packages = TRUE)
#' # The `eval` element is the environment where the prework
#' # and the commands in your workflow plan data frame are executed.
#' identical(con$eval$x, 1) # Should be TRUE.
#' }
#' })
#' }
do_prework <- function(config, verbose_packages) {
  for (package in union(c("methods", "drake"), config$packages)) {
    expr <- as.call(c(
      quote(require),
      package = package,
      lib.loc = as.call(c(quote(c), config$lib_loc)),
      quietly = TRUE,
      character.only = TRUE
    ))
    if (verbose_packages) {
      expr <- as.call(c(quote(suppressPackageStartupMessages), expr))
    }
    eval(expr, envir = config$envir_targets)
  }
  if (is.character(config$prework)) {
    config$prework <- parse(text = config$prework)
  }
  if (is.language(config$prework)) {
    eval(config$prework, envir = config$envir_targets)
  } else if (is.list(config$prework)) {
    lapply(config$prework, eval, envir = config$envir_targets)
  } else if (length(config$prework)) {
    stop(
      "prework must be an expression ",
      "or a list of expressions",
      call. = FALSE
    )
  }
  invisible()
}

clear_make_memory <- function(config) {
  envirs <- c(
    "envir_graph",
    "envir_targets",
    "envir_dynamic",
    "envir_subtargets",
    "envir_loaded",
    "ht_dynamic",
    "ht_dynamic_size",
    "ht_is_subtarget",
    "ht_target_exists"
  )
  for (key in envirs) {
    remove(list = names(config[[key]]), envir = config[[key]])
  }
  config$cache$flush_cache()
  if (config$garbage_collection) {
    gc()
  }
}

# Generate a flat csv log file to represent the state of the cache.
drake_cache_log_file_ <- function(
  file = "drake_cache.csv",
  path = NULL,
  search = NULL,
  cache = drake::drake_cache(path = path),
  verbose = 1L,
  jobs = 1L,
  targets_only = FALSE
) {
  deprecate_search(search)
  if (!length(file) || identical(file, FALSE)) {
    return(invisible())
  } else if (identical(file, TRUE)) {
    file <- formals(drake_cache_log_file_)$file
  }
  out <- drake_cache_log(
    path = path,
    cache = cache,
    verbose = verbose,
    jobs = jobs,
    targets_only = targets_only
  )
  out <- as.data.frame(out)
  # Suppress partial arg match warnings.
  suppressWarnings(
    write.table(
      x = out,
      file = file,
      quote = FALSE,
      row.names = FALSE,
      sep = ","
    )
  )
}

runtime_checks <- function(config) {
  assert_config(config)
  if (identical(config$skip_safety_checks, TRUE)) {
    return(invisible())
  }
  missing_input_files(config = config)
  subdirectory_warning(config = config)
  assert_outside_cache(config = config)
}

missing_input_files <- function(config) {
  files <- parallel_filter(
    all_imports(config),
    f = is_encoded_path,
    jobs = config$jobs_preprocess
  )
  files <- config$cache$decode_path(x = files)
  missing_files <- files[!file_dep_exists(files)]
  if (length(missing_files)) {
    warning(
      "missing input files:\n",
      multiline_message(missing_files),
      call. = FALSE
    )
  }
  invisible()
}

file_dep_exists <- function(x) {
  file.exists(x) | is_url(x)
}

subdirectory_warning <- function(config) {
  if (identical(Sys.getenv("drake_warn_subdir"), "false")) {
    return()
  }
  dir <- normalizePath(dirname(config$cache$path), mustWork = FALSE)
  wd <- normalizePath(getwd(), mustWork = FALSE)
  if (!length(dir) || wd == dir || is.na(pmatch(dir, wd))) {
    return()
  }
  warning(
    "Running make() in a subdirectory of your project. \n",
    "This could cause problems if your ",
    "file_in()/file_out()/knitr_in() files ",
    "are relative paths.\n",
    "Please either\n",
    "  (1) run make() from your drake project root, or\n",
    "  (2) create a cache in your working ",
    "directory with new_cache('path_name'), or\n",
    "  (3) supply a cache of your own (e.g. make(cache = your_cache))\n",
    "      whose folder name is not '.drake'.\n",
    "  running make() from: ", wd, "\n",
    "  drake project root:  ", dir, "\n",
    "  cache directory:     ", config$cache$path,
    call. = FALSE
  )
}

assert_outside_cache <- function(config) {
  work_dir <- normalizePath(getwd(), mustWork = FALSE)
  cache_dir <- normalizePath(config$cache$path, mustWork = FALSE)
  if (identical(work_dir, cache_dir)) {
    stop(
      "cannot run make() from inside the cache: ", shQuote(cache_dir),
      ". The cache path must be different from your working directory. ",
      "If your drake project lives at ", shQuote("/your/project/root/"), # nolint
      " then you should run ", shQuote("make()"), " from this directory, ",
      "and your cache should be in a subfolder, e.g. ",
      shQuote("/your/project/root/.drake/") # nolint
    )
  }
}

r_make_message <- function(force) {
  r_make_message <- .pkg_envir[["r_make_message"]] %|||% TRUE
  on.exit(
    assign(
      x = "r_make_message",
      value = FALSE,
      envir = .pkg_envir,
      inherits = FALSE
    )
  )
  if (force || (r_make_message && sample.int(n = 10, size = 1) < 1.5)) {
    message(
      "In drake, consider r_make() instead of make(). ",
      "r_make() runs make() in a fresh R session ",
      "for enhanced robustness and reproducibility."
    )
  }
}

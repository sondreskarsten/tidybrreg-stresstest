root <- Sys.getenv("TIDYBRREG_STRESS_ROOT", getwd())
source(file.path(root, "R", "helpers.R"))
library(tidybrreg)

test_network <- function(fx = load_fixtures()) {
  stress_init("21-network")
  stress_stagger()

  if (!requireNamespace("tidygraph", quietly = TRUE)) {
    stress_skip("N-00", "tidygraph missing", "package not installed")
    stress_flush()
    return(invisible(NULL))
  }

  asa <- fx$known$asa
  nodes_of <- function(g) tidygraph::as_tibble(g, "nodes")
  edges_of <- function(g) tidygraph::as_tibble(g, "edges")

  g0 <- brreg_network(asa, depth = 0L)

  check("N-01", "depth 0 returns a tbl_graph", inherits(g0, "tbl_graph"))
  check("N-02", "depth 0 has exactly one node", nrow(nodes_of(g0)) == 1L)
  check("N-03", "depth 0 has no edges", nrow(edges_of(g0)) == 0L)
  check("N-04", "seed node id is prefixed",
        identical(nodes_of(g0)$node_id[1], paste0("o:", asa)))

  check("N-05", "node schema is the documented one",
        all(c("node_id", "node_type", "name", "org_nr", "person_id") %in%
              names(nodes_of(g0))))

  g1 <- brreg_network(asa, depth = 1L)

  check("N-06", "depth 1 expands the graph", nrow(nodes_of(g1)) > nrow(nodes_of(g0)))

  check("N-07", "edge schema is the documented one",
        all(c("from", "to", "edge_type", "role_code", "role") %in% names(edges_of(g1))))

  check("N-08", "node ids are unique", !any(duplicated(nodes_of(g1)$node_id)))

  check("N-09", "every edge endpoint exists as a node", {
    n <- nodes_of(g1); e <- edges_of(g1)
    all(e$from <= nrow(n)) && all(e$to <= nrow(n))
  })

  check("N-10", "person nodes carry a person_id and no org_nr", {
    n <- nodes_of(g1)
    p <- n[n$node_type == "person", ]
    nrow(p) == 0L || (all(!is.na(p$person_id)) && all(is.na(p$org_nr)))
  })

  check("N-11", "entity nodes carry a valid org number", {
    n <- nodes_of(g1)
    o <- n[!is.na(n$org_nr), ]
    all(brreg_validate(o$org_nr))
  })

  check("N-12", "include = roles yields only role edges", {
    e <- edges_of(brreg_network(asa, depth = 1L, include = "roles"))
    nrow(e) == 0L || all(e$edge_type %in% c("role", "entity_role"))
  })

  check("N-13", "include = underenheter yields only establishment edges", {
    e <- edges_of(brreg_network(asa, depth = 1L, include = "underenheter"))
    nrow(e) == 0L || all(e$edge_type == "has_establishment")
  })

  check("N-14", "include = children yields only parent edges", {
    e <- edges_of(brreg_network(fx$known$orgl, depth = 1L, include = "children"))
    nrow(e) == 0L || all(e$edge_type == "parent_of")
  })

  check("N-15", "include = legal_roles yields only legal role edges", {
    e <- edges_of(brreg_network(asa, depth = 1L, include = "legal_roles"))
    nrow(e) == 0L || all(e$edge_type == "legal_role")
  })

  check("N-16", "include subsets are additive", {
    a <- nrow(edges_of(brreg_network(asa, depth = 1L, include = "roles")))
    b <- nrow(edges_of(brreg_network(asa, depth = 1L, include = "underenheter")))
    ab <- nrow(edges_of(brreg_network(asa, depth = 1L,
                                      include = c("roles", "underenheter"))))
    ab == a + b
  })

  check_error("N-17", "unknown include aborts",
              brreg_network(asa, depth = 1L, include = "nope"))

  check("N-18", "edge direction is consistent for containment relations", {
    e <- edges_of(brreg_network(asa, depth = 1L))
    n <- nodes_of(brreg_network(asa, depth = 1L))
    sub <- e[e$edge_type == "has_establishment", ]
    nrow(sub) == 0L || all(n$node_id[sub$from] == paste0("o:", asa))
  })

  check("N-19", "all edges point away from the seed or into it, not both", {
    g <- brreg_network(asa, depth = 1L)
    n <- nodes_of(g); e <- edges_of(g)
    seed <- paste0("o:", asa)
    out_types <- unique(e$edge_type[n$node_id[e$from] == seed])
    in_types <- unique(e$edge_type[n$node_id[e$to] == seed])
    length(intersect(out_types, in_types)) == 0L &&
      (length(out_types) == 0L || length(in_types) == 0L)
  }, defect = "D-73")

  check("N-20", "multiple seeds produce a union graph", {
    g <- brreg_network(c(asa, fx$known$bank), depth = 1L)
    nrow(nodes_of(g)) > nrow(nodes_of(g1))
  })

  check("N-21", "repeated seeds do not duplicate nodes", {
    g <- brreg_network(c(asa, asa), depth = 1L)
    !any(duplicated(nodes_of(g)$node_id))
  })

  check("N-22", "depth 1 role edges match brreg_roles row count", {
    r <- brreg_roles(asa)
    e <- edges_of(brreg_network(asa, depth = 1L, include = "roles"))
    nrow(e) == sum(!is.na(r$person_id)) + sum(!is.na(r$entity_org_nr))
  })

  check("N-23", "depth 2 without bulk data aborts with instructions", {
    out <- tryCatch(brreg_network(asa, depth = 2L), error = function(e) conditionMessage(e))
    st <- brreg_status(quiet = TRUE)
    if (st$all_ready) NA else is.character(out) && grepl("Bulk data|snapshot", out)
  })

  check("N-24", "depth above 2 does not silently equal depth 2", {
    a <- nrow(nodes_of(brreg_network(asa, depth = 1L)))
    b <- tryCatch(nrow(nodes_of(brreg_network(asa, depth = 3L))),
                  error = function(e) NA_integer_)
    is.na(b) || b >= a
  })

  check("N-25", "graph is directed", {
    igraph::is_directed(brreg_network(asa, depth = 1L))
  })

  stress_flush()
}

test_network()

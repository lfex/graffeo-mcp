;;;; Graph query logic: navigation + learning algorithms.
;;;;
;;;; Pure functions over a graffeo graph handle (graph is always the first
;;;; argument). No MCP types, no formatting, no persistent_term access.
;;;;
;;;; Backend boundary (see Arc 2 Slice 01 ledger, Amendment A1): the runtime
;;;; graph is Mnesia-backed. The Mnesia (disk) backend supports the universal
;;;; read-half (vertices, neighbours, degrees, edge_meta, vertex_label, bfs,
;;;; topsort, reachable, reaching) but NOT the build-half (empty_like) that
;;;; constructive ops (filter_edges, subgraph, condensation) require. So any
;;;; algorithm needing a derived graph projects the relevant edges into an
;;;; in-memory map graph (graffeo:new/0) first and runs there.

(defmodule graffeo-mcp-query
  (export
   (dependents 3)
   (find-related 4)
   (get-node-data 2)
   (get-node-edges 3)
   (learning-path 2)
   (neighborhood 4)
   (prerequisites 2)
   (project-prerequisites 1)
   (topsort-prereqs 2)))

;;; ========================================
;;; Navigation
;;; ========================================

(defun get-node-data (graph id)
  "Return {ok, Data} for an abstract concept, or {error, not_found}.

  Data carries the vertex label, in/out degree, and the count of source
  vertices (cards) that link to the concept via membership edges."
  (case (graffeo:vertex_label graph id)
    ((tuple 'ok label) (when (is_map label))
     (let* ((in-d  (graffeo:in_degree graph id))
            (out-d (graffeo:out_degree graph id))
            (in-ns (graffeo:in_neighbours graph id))
            (srcs  (length (lc ((<- v in-ns) (is_tuple v)) v))))
       (tuple 'ok (map 'id         id
                       'label      label
                       'in_degree  in-d
                       'out_degree out-d
                       'sources    srcs))))
    (_ (tuple 'error 'not_found))))

(defun get-node-edges (graph id direction)
  "Return a list of edge-info maps for id in the requested direction.

  direction is one of #\"in\", #\"out\", #\"both\". Each edge-info is
  #(dir other type weight). Source (tuple) vertices are skipped unless the
  edge is a membership edge (which carries source-coverage context)."
  (let ((outs (if (orelse (=:= direction #"out") (=:= direction #"both"))
                (collect-edges graph id 'out)
                '()))
        (ins  (if (orelse (=:= direction #"in") (=:= direction #"both"))
                (collect-edges graph id 'in)
                '())))
    (++ outs ins)))

(defun find-related (graph id relationship limit)
  "Return up to limit {slug, type} pairs connected to id by relationship.

  relationship is an edge-type atom, or 'undefined for any type. Only
  abstract-to-abstract edges are considered (source vertices excluded)."
  (let* ((all     (++ (collect-edges graph id 'out)
                      (collect-edges graph id 'in)))
         (typed   (lc ((<- e all) (is_binary (mref e 'other))) e))
         (matched (lc ((<- e typed)
                       (orelse (=:= relationship 'undefined)
                               (=:= (mref e 'type) relationship)))
                      (tuple (mref e 'other) (mref e 'type))))
         (uniq    (lists:usort matched)))
    (lists:sublist uniq limit)))

(defun neighborhood (graph id radius relationship)
  "Return {slug, depth} pairs within radius hops of id via BFS.

  relationship restricts which edge types BFS follows ('undefined = any).
  Only abstract vertices are returned; id itself (depth 0) is excluded.

  Uses an arity-2 (abstract-only) BFS filter rather than a meta-aware arity-3
  filter: graffeo's arity-3 filter skips incoming edges, so a meta-aware filter
  with direction=both would only walk outgoing edges (Amendment A2). To filter
  by relationship type we instead BFS a type-projected map graph, where an
  arity-2 abstract filter suffices and traverses both directions correctly."
  (let* ((g      (if (=:= relationship 'undefined)
                   graph
                   (project-by-type graph relationship)))
         (filter (lambda (from to) (andalso (is_binary from) (is_binary to))))
         (result (graffeo:bfs g id (map 'direction 'both 'filter filter))))
    (lc ((<- (tuple v d) result)
         (is_binary v)
         (> d 0)
         (=< d radius))
        (tuple v d))))

;;; ========================================
;;; Learning (prerequisite structure)
;;; ========================================

(defun prerequisites (graph id)
  "Return {Direct, Transitive} prerequisite slug lists for id.

  Direct = id's immediate prerequisites; Transitive = the full dependency
  cone (excluding id, unless id sits in a cycle)."
  (let* ((pg (project-prerequisites graph))
         (direct     (lists:sort (graffeo:out_neighbours pg id)))
         (transitive (lists:sort (graffeo:reachable_neighbours pg (list id)))))
    (tuple direct transitive)))

(defun dependents (graph id depth)
  "Return {Direct, All} dependent slug lists for id.

  depth is 'all (full transitive closure) or a positive integer (BFS-bounded
  number of hops). Direct = concepts that list id as an immediate
  prerequisite."
  (let* ((pg (project-prerequisites graph))
         (direct (lists:sort (graffeo:in_neighbours pg id))))
    (case depth
      ('all
       (tuple direct (lists:sort (graffeo:reaching_neighbours pg (list id)))))
      (d (when (is_integer d))
       (tuple direct (dependents-to-depth pg id d))))))

(defun learning-path (graph id)
  "Return {ok, Path} — a foundations-first learning order ending at id.

  Path is the topological order of id's dependency cone, reversed so the
  deepest prerequisites come first. Cycles are handled via condensation.
  Returns {error, not_found} if id is not a vertex."
  (case (graffeo:vertex_label graph id)
    ((tuple 'ok _)
     (let* ((pg   (project-prerequisites graph))
            (cone (graffeo:reachable pg (list id)))
            (sg   (graffeo:subgraph pg cone)))
       (tuple 'ok (ordered-learning sg))))
    (_ (tuple 'error 'not_found))))

(defun topsort-prereqs (graph limit)
  "Return {ok, Order, Total} — the global foundations-first learning sequence.

  Order is the topological order of the whole prerequisite graph (cycles
  condensed), truncated to limit entries; Total is the untruncated length."
  (let* ((pg    (project-prerequisites graph))
         (order (ordered-learning pg))
         (total (length order)))
    (tuple 'ok (lists:sublist order limit) total)))

;;; ========================================
;;; Prerequisite projection (map-backed)
;;; ========================================

(defun project-prerequisites (graph)
  "Project the prerequisite subgraph into a fresh map-backed graffeo graph.

  graffeo:filter_edges/2 is unsupported on the Mnesia backend (Amendment A1),
  so the projection is built from the read-half instead. Downstream DAG ops run
  on the map result, which fully supports the build-half."
  (project-by-type graph 'prerequisites))

(defun project-by-type (graph type)
  "Project abstract-to-abstract edges of the given relationship type into a
  fresh map-backed graph (preserving direction and edge metadata)."
  (project-edges graph (lambda (meta) (has-edge-type? meta type))))

(defun project-edges (graph pred)
  "Build a map-backed graph from graph's abstract vertices plus every
  abstract-to-abstract edge whose metadata satisfies pred. Iterates the
  read-half (vertices + out_neighbours + edge_meta); the map graph is
  functional, so the accumulator is threaded rather than mutated in place."
  (let* ((abs-vs (lc ((<- v (graffeo:vertices graph)) (is_binary v)) v))
         (g0     (lists:foldl
                  (lambda (v acc) (graffeo:add_vertex acc v))
                  (graffeo:new)
                  abs-vs)))
    (lists:foldl
     (lambda (from acc)
       (lists:foldl
        (lambda (to acc2)
          (if (is_binary to)
            (case (graffeo:edge_meta graph from to)
              ((tuple 'ok meta)
               (if (funcall pred meta)
                 (graffeo:add_edge acc2 from to meta)
                 acc2))
              ('error acc2))
            acc2))
        acc
        (graffeo:out_neighbours graph from)))
     g0
     abs-vs)))

;;; ========================================
;;; Internal helpers
;;; ========================================

(defun collect-edges (graph id dir)
  "Edge-info maps for id's neighbours in dir ('out | 'in).

  Keeps abstract-to-abstract edges plus membership edges (whose other end is
  a source tuple); drops other source-involving edges."
  (let ((nbrs (if (=:= dir 'out)
                (graffeo:out_neighbours graph id)
                (graffeo:in_neighbours graph id))))
    (lists:filtermap
     (lambda (other)
       (let (((tuple from to) (if (=:= dir 'out)
                                (tuple id other)
                                (tuple other id))))
         (case (graffeo:edge_meta graph from to)
           ((tuple 'ok meta)
            (let ((type (primary-type meta)))
              (if (orelse (is_binary other) (=:= type 'membership))
                (tuple 'true (map 'dir    dir
                                  'other  other
                                  'type   type
                                  'weight (maps:get 'weight meta 0)))
                'false)))
           ('error 'false))))
     (lists:sort nbrs))))

(defun primary-type (meta)
  "The representative edge-type atom: 'membership for membership edges, else
  the first type in the typed-edge 'types list."
  (let ((label (maps:get 'label meta (map))))
    (case (maps:get 'type label 'undefined)
      ('undefined
       (case (maps:get 'types label '())
         ((cons t _) t)
         ('() 'unknown)))
      (mtype mtype))))

(defun has-edge-type? (meta type)
  "True if the edge metadata carries type, across both label shapes:
  membership #{type => membership} and typed #{types => [atom()]}."
  (let ((label (maps:get 'label meta (map))))
    (orelse (=:= (maps:get 'type label 'undefined) type)
            (lists:member type (maps:get 'types label '())))))

(defun dependents-to-depth (pg id d)
  "Dependent slugs within d hops of id in the prerequisite projection pg."
  (let ((result (graffeo:bfs pg id (map 'direction 'in))))
    (lists:sort
     (lc ((<- (tuple v dep) result) (> dep 0) (=< dep d)) v))))

(defun ordered-learning (g)
  "Foundations-first vertex order for prerequisite graph g.

  topsort gives dependent-first order, reversed here. If g has cycles,
  condensation yields a DAG of SCCs which is ordered and flattened (each SCC's
  members sorted) for deterministic output."
  (case (graffeo:topsort g)
    ((tuple 'ok order) (lists:reverse order))
    ('false (flatten-condensation g))))

(defun flatten-condensation (g)
  (let ((condensed (graffeo:condensation g)))
    (case (graffeo:topsort condensed)
      ((tuple 'ok sccs)
       (lists:append
        (lists:map (lambda (scc) (lists:sort scc)) (lists:reverse sccs))))
      ('false '()))))

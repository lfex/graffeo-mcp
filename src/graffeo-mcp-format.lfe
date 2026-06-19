;;;; Response formatting: graph data → text binaries for MCP content.

(defmodule graffeo-mcp-format
  (export
   (format-dependents 1)
   (format-info 1)
   (format-learning-path 1)
   (format-neighborhood 1)
   (format-node 1)
   (format-node-edges 1)
   (format-prerequisites 1)
   (format-related 1)
   (format-status 1)
   (format-topsort 1)))

;;; ========================================
;;; Public API
;;; ========================================

(defun format-status (graph)
  "Return a text binary summarising load state, vertex/edge counts, and backend."
  (let ((n (graffeo:no_vertices graph))
        (m (graffeo:no_edges graph)))
    (iolist_to_binary
     (io_lib:format
      "Erlang Knowledge Graph: loaded~nVertices: ~p | Edges: ~p~nBackend: Mnesia (disc_copies)"
      (list n m)))))

(defun format-info (graph)
  "Return a text binary with detailed statistics: counts, category and type distributions."
  (let* ((n-total (graffeo:no_vertices graph))
         (n-edges (graffeo:no_edges graph))
         (src-vs  (graffeo-mcp-ingest:source-vertices graph))
         (abs-vs  (graffeo-mcp-ingest:abstract-vertices graph))
         (n-src   (length src-vs))
         (n-abs   (length abs-vs))
         (cats    (count-categories graph abs-vs))
         (etypes  (count-edge-types graph))
         (n-cats  (maps:size cats)))
    (iolist_to_binary
     (list
      (io_lib:format
       "Graph Statistics~n~nVertices: ~p (source: ~p, abstract: ~p)~nEdges: ~p~n"
       (list n-total n-src n-abs n-edges))
      (io_lib:format "~nCategories (~p categories):~n" (list n-cats))
      (format-map-lines cats)
      #"~nRelationship Types:~n"
      (format-edge-type-lines etypes)))))

;;; ========================================
;;; Navigation + learning formatting
;;; ========================================

(defun format-node (data)
  "Format a get-node-data result map as a concept summary."
  (let* ((id    (mref data 'id))
         (label (mref data 'label))
         (concept  (maps:get 'concept  label id))
         (category (maps:get 'category label #"unknown"))
         (tier     (maps:get 'tier     label #"unknown")))
    (iolist_to_binary
     (io_lib:format
      "Concept: ~s~nSlug: ~s~nCategory: ~s | Tier: ~s~nIn-degree: ~p | Out-degree: ~p~nSources: ~p"
      (list concept id category tier
            (mref data 'in_degree) (mref data 'out_degree)
            (mref data 'sources))))))

(defun format-node-edges (data)
  "Format an edge listing — data is (tuple id edges), edges being edge-info
  maps #(dir other type weight) — grouped by direction."
  (let* (((tuple id edges) data)
         (outs (lc ((<- e edges) (=:= (mref e 'dir) 'out)) e))
         (ins  (lc ((<- e edges) (=:= (mref e 'dir) 'in)) e)))
    (iolist_to_binary
     (list
      (io_lib:format "Edges for ~s:~n~nOutgoing:~n" (list id))
      (format-edge-lines outs #"-> ")
      (io_lib:format "~nIncoming:~n" '())
      (format-edge-lines ins #"<- ")))))

(defun format-related (data)
  "Format related concepts — data is (tuple id relationship concepts), concepts
  being #(slug type) pairs."
  (let (((tuple id _relationship concepts) data))
    (iolist_to_binary
     (list
      (io_lib:format "Related to ~s (~p concepts):~n"
                     (list id (length concepts)))
      (lists:map
       (lambda (pair)
         (let (((tuple slug type) pair))
           (io_lib:format "  ~s (~s)~n" (list slug type))))
       concepts)))))

(defun format-neighborhood (data)
  "Format a neighborhood walk — data is (tuple id radius verts), verts being
  #(slug depth) pairs — grouped by BFS depth."
  (let* (((tuple id radius verts) data)
         (by-depth (group-by-depth verts)))
    (iolist_to_binary
     (list
      (io_lib:format "Neighborhood of ~s (radius ~p, ~p concepts):~n"
                     (list id radius (length verts)))
      (lists:map
       (lambda (depth)
         (io_lib:format "  Depth ~p: ~s~n"
                        (list depth
                              (join-slugs
                               (lists:sort (maps:get depth by-depth))))))
       (lists:sort (maps:keys by-depth)))))))

(defun format-prerequisites (data)
  "Format prerequisites — data is (tuple id direct transitive)."
  (let (((tuple id direct transitive) data))
    (iolist_to_binary
     (list
      (io_lib:format "Prerequisites for ~s:~n" (list id))
      (io_lib:format "  Direct (~p): ~s~n"
                     (list (length direct) (join-slugs (lists:sort direct))))
      (io_lib:format "  Transitive (~p total): ~s~n"
                     (list (length transitive)
                           (join-slugs (lists:sort transitive))))))))

(defun format-dependents (data)
  "Format dependents — data is (tuple id direct all)."
  (let (((tuple id direct all) data))
    (iolist_to_binary
     (list
      (io_lib:format "Dependents of ~s:~n" (list id))
      (io_lib:format "  Direct (~p): ~s~n"
                     (list (length direct) (join-slugs (lists:sort direct))))
      (io_lib:format "  All (~p total): ~s~n"
                     (list (length all) (join-slugs (lists:sort all))))))))

(defun format-learning-path (data)
  "Format a learning path — data is (tuple id path) — as numbered steps."
  (let (((tuple id path) data))
    (iolist_to_binary
     (list
      (io_lib:format "Learning path to ~s (~p steps):~n" (list id (length path)))
      (format-numbered path)))))

(defun format-topsort (data)
  "Format a global topological order — data is (tuple order total)."
  (let (((tuple order total) data))
    (iolist_to_binary
     (list
      (io_lib:format "Topological order (~p of ~p concepts):~n"
                     (list (length order) total))
      (format-numbered order)))))

;;; ========================================
;;; Internal helpers
;;; ========================================

(defun format-edge-lines (edges arrow)
  (lists:map
   (lambda (e)
     (io_lib:format "  ~s~s (~s, weight ~p)~n"
                    (list arrow (vertex-display (mref e 'other))
                          (mref e 'type) (mref e 'weight))))
   edges))

(defun vertex-display (v)
  "A binary suitable for ~s: bare slug for abstract vertices, an inspected
  form for source (tuple) vertices."
  (if (is_binary v)
    v
    (iolist_to_binary (io_lib:format "~p" (list v)))))

(defun group-by-depth (verts)
  (lists:foldl
   (lambda (pair acc)
     (let (((tuple slug depth) pair))
       (maps:update_with depth (lambda (xs) (cons slug xs)) (list slug) acc)))
   (map)
   verts))

(defun join-slugs (slugs)
  (case slugs
    ('() #"(none)")
    (_   (lists:join #", " slugs))))

(defun format-numbered (items)
  (lists:map
   (lambda (pair)
     (let (((tuple n slug) pair))
       (io_lib:format "  ~p. ~s~n" (list n slug))))
   (lists:zip (lists:seq 1 (length items)) items)))

(defun count-categories (graph abs-vs)
  (lists:foldl
   (lambda (v acc)
     (case (graffeo:vertex_label graph v)
       ((tuple 'ok label) (when (is_map label))
        (let ((cat (maps:get 'category label #"unknown")))
          (maps:update_with cat (lambda (n) (+ n 1)) 1 acc)))
       (_ acc)))
   (map)
   abs-vs))

(defun count-edge-types (graph)
  ;; graffeo:edges/1 is not in the facade; derive edges via vertices + out_neighbours.
  (let ((vs   (graffeo:vertices graph))
        (init (map 'membership 0
                   'prerequisites 0
                   'extends 0
                   'related 0
                   'contrasts_with 0)))
    (lists:foldl
     (lambda (v acc)
       (let ((nbrs (graffeo:out_neighbours graph v)))
         (lists:foldl
          (lambda (n acc2)
            (case (graffeo:edge_meta graph v n)
              ((tuple 'ok meta)
               (let ((etype (edge-type-from-meta meta)))
                 (maps:update_with etype (lambda (cnt) (+ cnt 1)) 1 acc2)))
              ('error acc2)))
          acc nbrs)))
     init
     vs)))

(defun edge-type-from-meta (meta)
  (let ((label (mref meta 'label)))
    (case (maps:get 'type label 'undefined)
      ('membership 'membership)
      ('undefined
       (case (maps:get 'types label '())
         ((cons t _) t)
         ('() 'prerequisites))))))

(defun format-map-lines (m)
  (lists:map
   (lambda (pair)
     (let (((tuple k v) pair))
       (io_lib:format "  ~s: ~p~n" (list k v))))
   (lists:sort (maps:to_list m))))

(defun format-edge-type-lines (et)
  (list
   (io_lib:format "  membership: ~p (weight 0.5)~n"
                  (list (maps:get 'membership et 0)))
   (io_lib:format "  prerequisites: ~p (weight 1.0)~n"
                  (list (maps:get 'prerequisites et 0)))
   (io_lib:format "  extends: ~p (weight 1.0)~n"
                  (list (maps:get 'extends et 0)))
   (io_lib:format "  related: ~p (weight 2.0)~n"
                  (list (maps:get 'related et 0)))
   (io_lib:format "  contrasts_with: ~p (weight 3.0)~n"
                  (list (maps:get 'contrasts_with et 0)))))

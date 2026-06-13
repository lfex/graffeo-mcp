;;;; Response formatting: graph data → text binaries for MCP content.

(defmodule graffeo-mcp-format
  (export
   (format-info 1)
   (format-status 1)))

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
;;; Internal helpers
;;; ========================================

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

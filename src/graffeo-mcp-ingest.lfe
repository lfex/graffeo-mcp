;;;; Five-phase graph construction pipeline (Mnesia backend).
;;;;
;;;; Phases:
;;;;   1. source layer   — one {src-slug, concept-slug} vertex per card
;;;;   2. abstract layer — one concept-slug binary vertex per unique slug
;;;;   3. membership     — source vertex → abstract vertex (weight 0.5)
;;;;   4. source edges   — typed edges between source vertices within a source
;;;;   5. abstract edges — typed edges between abstract vertices across all cards
;;;;
;;;; Unlike the map-backend prototype, mutations are in-place; the graph handle
;;;; is passed in and is not threaded as an accumulator.

(defmodule graffeo-mcp-ingest
  (export
   (abstract-vertices 1)
   (build 2)
   (build-from-dir 2)
   (source-vertices 1)))

;;; ========================================
;;; Public API
;;; ========================================

(defun build (cards graph)
  "Populate graph from a list of parsed concept cards (in-place, transactional)."
  (let ((sorted (lists:sort
                 (lambda (a b) (=< (mref a 'slug) (mref b 'slug)))
                 cards)))
    (case (graffeo_mnesia:transaction
           (lambda ()
             (add-source-layer sorted graph)
             (add-abstract-layer sorted graph)
             (add-membership sorted graph)
             (add-source-edges sorted graph)
             (add-abstract-edges sorted graph)))
      ((tuple 'atomic _) 'ok)
      ((tuple 'aborted reason) (tuple 'error reason)))))

(defun build-from-dir (base-dir graph)
  "Parse all .md cards under base-dir and build into graph. Skips unparseable files."
  (let* ((dirs (filelib:wildcard (++ base-dir "/*")))
         (files (lists:sort
                 (lists:flatmap
                  (lambda (dir) (filelib:wildcard (++ dir "/*.md")))
                  dirs)))
         (cards (lists:filtermap
                 (lambda (f)
                   (case (graffeo-mcp-parser:parse-file f)
                     ((tuple 'ok c) (tuple 'true c))
                     (_ 'false)))
                 files)))
    (build cards graph)))

(defun source-vertices (g)
  "Return all source-layer (tuple) vertices from graph g."
  (lc ((<- v (graffeo:vertices g)) (is_tuple v)) v))

(defun abstract-vertices (g)
  "Return all abstract-layer (binary) vertices from graph g."
  (lc ((<- v (graffeo:vertices g)) (is_binary v)) v))

;;; ========================================
;;; Phase 1: Source layer
;;; ========================================

(defun add-source-layer (cards graph)
  (lists:foreach
   (lambda (card)
     (graffeo_mnesia:add_vertex graph (source-vertex card) card))
   cards))

(defun source-vertex (card)
  (tuple (mref card 'source_slug) (mref card 'slug)))

;;; ========================================
;;; Phase 2: Abstract layer
;;; ========================================

(defun add-abstract-layer (cards graph)
  (maps:foreach
   (lambda (slug slug-cards)
     (let* ((card  (car slug-cards))
            (label (map 'concept  (mref card 'concept)
                        'category (mref card 'category)
                        'tier     (mref card 'tier))))
       (graffeo_mnesia:add_vertex graph slug label)))
   (group-by-slug cards)))

;;; ========================================
;;; Phase 3: Membership edges
;;; ========================================

(defun add-membership (cards graph)
  (lists:foreach
   (lambda (card)
     (graffeo_mnesia:add_edge graph
                              (source-vertex card)
                              (mref card 'slug)
                              (map 'weight 0.5
                                   'label (map 'type 'membership))))
   cards))

;;; ========================================
;;; Phase 4: Source-internal edges
;;; ========================================

(defun add-source-edges (cards graph)
  (maps:foreach
   (lambda (src src-cards)
     (let ((all-slugs (sets:from_list
                       (lc ((<- c src-cards)) (mref c 'slug))
                       '(#(version 2)))))
       (lists:foreach
        (lambda (card)
          (add-card-source-edges src card all-slugs graph))
        src-cards)))
   (group-by-source cards)))

(defun add-card-source-edges (src card all-slugs graph)
  (let* ((from-slug (mref card 'slug))
         (from      (tuple src from-slug))
         (rel-types (list (tuple 'prerequisites   (mref card 'prerequisites))
                          (tuple 'extends         (mref card 'extends))
                          (tuple 'related         (mref card 'related))
                          (tuple 'contrasts_with  (mref card 'contrasts_with)))))
    (lists:foreach
     (lambda (type-and-targets)
       (let (((tuple type targets) type-and-targets))
         (lists:foreach
          (lambda (target-slug)
            (if (sets:is_element target-slug all-slugs)
              (add-typed-edge graph from (tuple src target-slug) type src)))
          (lists:sort targets))))
     rel-types)))

;;; ========================================
;;; Phase 5: Abstract edges
;;;;
;;;; Directly adds abstract-to-abstract typed edges from card relationships,
;;;; without the filter_edges/contract projection used in the map-backend
;;;; prototype (those operations are unsupported on Mnesia).
;;; ========================================

(defun add-abstract-edges (cards graph)
  (lists:foreach
   (lambda (card)
     (let* ((from-slug (mref card 'slug))
            (src       (mref card 'source_slug))
            (rel-types (list (tuple 'prerequisites   (mref card 'prerequisites))
                             (tuple 'extends         (mref card 'extends))
                             (tuple 'related         (mref card 'related))
                             (tuple 'contrasts_with  (mref card 'contrasts_with)))))
       (lists:foreach
        (lambda (type-and-targets)
          (let (((tuple type targets) type-and-targets))
            (lists:foreach
             (lambda (to-slug)
               (if (=/= to-slug from-slug)
                 (add-typed-edge graph from-slug to-slug type src)))
             (lists:sort targets))))
        rel-types)))
   cards))

;;; ========================================
;;; Helpers
;;; ========================================

(defun add-typed-edge (graph from to type src)
  ;; graffeo_mnesia:add_edge auto-creates missing vertices (ghost vertices).
  (let ((weight (type-weight type)))
    (case (graffeo:edge_meta graph from to)
      ((tuple 'ok (map 'weight old-w
                       'label (map 'types types 'asserted_by asserted-by)))
       (graffeo_mnesia:add_edge
        graph from to
        (map 'weight (erlang:min weight old-w)
             'label (map 'types      (lists:usort (cons type types))
                         'asserted_by (lists:usort (cons src asserted-by))))))
      (_
       (graffeo_mnesia:add_edge
        graph from to
        (map 'weight weight
             'label (map 'types       (list type)
                         'asserted_by (list src))))))))

(defun type-weight
  (('prerequisites)  1.0)
  (('extends)        1.0)
  (('related)        2.0)
  (('contrasts_with) 3.0))

(defun group-by-slug (cards)
  (lists:foldl
   (lambda (card acc)
     (let ((slug (mref card 'slug)))
       (maps:update_with slug
                         (lambda (existing) (lists:append existing (list card)))
                         (list card)
                         acc)))
   (map)
   cards))

(defun group-by-source (cards)
  (lists:foldl
   (lambda (card acc)
     (let ((src (mref card 'source_slug)))
       (maps:update_with src
                         (lambda (existing) (lists:append existing (list card)))
                         (list card)
                         acc)))
   (map)
   cards))

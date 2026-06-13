;;;; Tests for graffeo-mcp-ingest.
;;;;
;;;; Uses 4 hand-crafted cards:
;;;;   concept-a  (source-1)  prereqs: [concept-b], related: [concept-c]
;;;;   concept-b  (source-1)  no relationships
;;;;   concept-c  (source-1)  no relationships
;;;;   concept-a  (source-2)  no relationships   ← same slug, different source
;;;;
;;;; Expected counts after full build:
;;;;   vertices: 4 source + 3 abstract = 7
;;;;   edges:    4 membership + 2 source-internal + 2 abstract = 8

(defmodule graffeo-mcp-ingest-tests
  (behaviour ltest-unit))

(include-lib "ltest/include/ltest-macros.lfe")

;;; ========================================
;;; Test card fixtures
;;; ========================================

(defun make-card (slug concept src-slug prereqs related)
  (map 'slug          slug
       'concept       concept
       'category      #"test"
       'tier          #"basic"
       'source        src-slug
       'source_slug   src-slug
       'prerequisites prereqs
       'extends       '()
       'related       related
       'contrasts_with '()))

(defun test-cards ()
  (list
   (make-card #"concept-a" #"Concept A" #"source-1"
              (list #"concept-b") (list #"concept-c"))
   (make-card #"concept-b" #"Concept B" #"source-1" '() '())
   (make-card #"concept-c" #"Concept C" #"source-1" '() '())
   (make-card #"concept-a" #"Concept A" #"source-2" '() '())))

;;; ========================================
;;; Tests
;;; ========================================

(deftest vertex-counts
  "build/2 produces the expected total vertex count."
  (let ((graph (graffeo_mnesia:new)))
    (try
      (progn
        (graffeo-mcp-ingest:build (test-cards) graph)
        (is-equal 7 (graffeo:no_vertices graph)))
      (after (graffeo_mnesia:delete graph)))))

(deftest edge-counts
  "build/2 produces the expected total edge count."
  (let ((graph (graffeo_mnesia:new)))
    (try
      (progn
        (graffeo-mcp-ingest:build (test-cards) graph)
        (is-equal 8 (graffeo:no_edges graph)))
      (after (graffeo_mnesia:delete graph)))))

(deftest source-vertices-are-tuples
  "Source-layer vertices are {src-slug, concept-slug} tuples."
  (let ((graph (graffeo_mnesia:new)))
    (try
      (progn
        (graffeo-mcp-ingest:build (test-cards) graph)
        (let ((sv (graffeo-mcp-ingest:source-vertices graph)))
          (is-equal 4 (length sv))
          (is (lists:all (lambda (v) (is_tuple v)) sv))))
      (after (graffeo_mnesia:delete graph)))))

(deftest abstract-vertices-are-binaries
  "Abstract-layer vertices are bare binary slugs."
  (let ((graph (graffeo_mnesia:new)))
    (try
      (progn
        (graffeo-mcp-ingest:build (test-cards) graph)
        (let ((av (graffeo-mcp-ingest:abstract-vertices graph)))
          (is-equal 3 (length av))
          (is (lists:all (lambda (v) (is_binary v)) av))))
      (after (graffeo_mnesia:delete graph)))))

(deftest membership-edges-connect-source-to-abstract
  "Each source vertex has a membership edge to its abstract vertex."
  (let ((graph (graffeo_mnesia:new)))
    (try
      (progn
        (graffeo-mcp-ingest:build (test-cards) graph)
        (let ((edge (graffeo:edge_meta graph
                                       (tuple #"source-1" #"concept-a")
                                       #"concept-a")))
          (case edge
            ((tuple 'ok meta)
             (is-equal 0.5 (mref meta 'weight)))
            (other
             (is-equal (tuple 'ok 'meta) other)))))
      (after (graffeo_mnesia:delete graph)))))

(deftest edge-weights-match-spec
  "Prerequisite edges carry weight 1.0; related edges carry weight 2.0."
  (let ((graph (graffeo_mnesia:new)))
    (try
      (progn
        (graffeo-mcp-ingest:build (test-cards) graph)
        (case (graffeo:edge_meta graph #"concept-a" #"concept-b")
          ((tuple 'ok meta) (is-equal 1.0 (mref meta 'weight)))
          (other (is-equal (tuple 'ok 'meta) other)))
        (case (graffeo:edge_meta graph #"concept-a" #"concept-c")
          ((tuple 'ok meta) (is-equal 2.0 (mref meta 'weight)))
          (other (is-equal (tuple 'ok 'meta) other))))
      (after (graffeo_mnesia:delete graph)))))

(deftest typed-edges-carry-types-metadata
  "Abstract edges carry a types list in their label metadata."
  (let ((graph (graffeo_mnesia:new)))
    (try
      (progn
        (graffeo-mcp-ingest:build (test-cards) graph)
        (case (graffeo:edge_meta graph #"concept-a" #"concept-b")
          ((tuple 'ok meta)
           (let ((label (mref meta 'label)))
             (is (lists:member 'prerequisites (mref label 'types)))))
          (other (is-equal (tuple 'ok 'meta) other))))
      (after (graffeo_mnesia:delete graph)))))

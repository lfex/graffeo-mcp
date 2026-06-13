;;;; Tests for graffeo-mcp-ingest.
;;;;
;;;; Uses 4 hand-crafted cards:
;;;;   concept-a  (source-1)  prereqs: [concept-b], related: [concept-c]
;;;;   concept-b  (source-1)  no relationships
;;;;   concept-c  (source-1)  no relationships
;;;;   concept-a  (source-2)  related: [concept-b]  ← same slug; forces merge on a→b edge
;;;;
;;;; concept-a→concept-b is asserted by source-1 as prerequisites (weight 1.0)
;;;; AND by source-2 as related (weight 2.0).  After merge: weight=1.0 (min),
;;;; types=[prerequisites,related], asserted_by=[source-1,source-2].
;;;;
;;;; Expected counts after full build:
;;;;   vertices: 4 source + 3 abstract = 7  (source-2 related target is already abstract)
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
   (make-card #"concept-a" #"Concept A" #"source-2" '() (list #"concept-b"))))

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

(deftest edge-merge-multi-source
  "When two sources assert the same abstract edge with different types, add-typed-edge
  merges: weight = min, types = union, asserted_by = both sources listed."
  (let ((graph (graffeo_mnesia:new)))
    (try
      (progn
        (graffeo-mcp-ingest:build (test-cards) graph)
        ;; source-1 asserts concept-a→concept-b as prerequisites (weight 1.0)
        ;; source-2 asserts concept-a→concept-b as related (weight 2.0)
        (case (graffeo:edge_meta graph #"concept-a" #"concept-b")
          ((tuple 'ok meta)
           (let ((label (mref meta 'label)))
             (is-equal 1.0 (mref meta 'weight))
             (is (lists:member 'prerequisites (mref label 'types)))
             (is (lists:member 'related (mref label 'types)))
             (is (lists:member #"source-1" (mref label 'asserted_by)))
             (is (lists:member #"source-2" (mref label 'asserted_by)))))
          (other (is-equal (tuple 'ok 'meta) other))))
      (after (graffeo_mnesia:delete graph)))))

(deftest build-from-dir-populates-graph
  "build-from-dir/2 parses .md files from a directory tree and builds the graph."
  (let ((graph (graffeo_mnesia:new)))
    (try
      (progn
        (graffeo-mcp-ingest:build-from-dir "test/fixtures/cards" graph)
        ;; 2 cards → 2 source + 2 abstract = 4 vertices, 2 membership edges
        (is-equal 4 (graffeo:no_vertices graph))
        (is-equal 2 (graffeo:no_edges graph)))
      (after (graffeo_mnesia:delete graph)))))

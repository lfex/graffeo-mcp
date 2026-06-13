;;;; Tests for graffeo-mcp-format.
;;;;
;;;; Fixture: 1 source vertex, 2 abstract vertices (1 explicit + 1 ghost),
;;;; 2 edges (1 membership + 1 prerequisite).
;;;;
;;;;   {src-a, concept-a}  source vertex  (no label)
;;;;   concept-a           abstract vertex (category: test-cat-a)
;;;;   concept-b           abstract vertex (category: test-cat-b, explicit)
;;;;   {src-a,ca} → ca     membership, weight 0.5
;;;;   ca → cb             prerequisite,  weight 1.0

(defmodule graffeo-mcp-format-tests
  (behaviour ltest-unit))

(include-lib "ltest/include/ltest-macros.lfe")

;;; ========================================
;;; Fixture
;;; ========================================

(defun setup-graph ()
  (let ((graph (graffeo_mnesia:new)))
    (graffeo_mnesia:add_vertex graph (tuple #"src-a" #"concept-a")
                               (map 'source_slug #"src-a" 'slug #"concept-a"))
    (graffeo_mnesia:add_vertex graph #"concept-a"
                               (map 'concept #"Concept A"
                                    'category #"test-cat-a"
                                    'tier #"basic"))
    (graffeo_mnesia:add_vertex graph #"concept-b"
                               (map 'concept #"Concept B"
                                    'category #"test-cat-b"
                                    'tier #"basic"))
    (graffeo_mnesia:add_edge graph (tuple #"src-a" #"concept-a") #"concept-a"
                             (map 'weight 0.5
                                  'label (map 'type 'membership)))
    (graffeo_mnesia:add_edge graph #"concept-a" #"concept-b"
                             (map 'weight 1.0
                                  'label (map 'types (list 'prerequisites)
                                              'asserted_by (list #"src-a"))))
    graph))

;;; ========================================
;;; Tests
;;; ========================================

(deftest format-status-includes-counts
  "format-status/1 returns a binary containing vertex and edge counts."
  (let ((graph (setup-graph)))
    (try
      (let ((text (graffeo-mcp-format:format-status graph)))
        (is (is_binary text))
        (is-not-equal 'nomatch (binary:match text #"3")))
      (after (graffeo_mnesia:delete graph)))))

(deftest format-status-says-loaded
  "format-status/1 text includes the loaded state and backend."
  (let ((graph (setup-graph)))
    (try
      (let ((text (graffeo-mcp-format:format-status graph)))
        (is-not-equal 'nomatch (binary:match text #"loaded"))
        (is-not-equal 'nomatch (binary:match text #"Mnesia")))
      (after (graffeo_mnesia:delete graph)))))

(deftest format-info-includes-categories
  "format-info/1 text includes category names from abstract vertex labels."
  (let ((graph (setup-graph)))
    (try
      (let ((text (graffeo-mcp-format:format-info graph)))
        (is (is_binary text))
        (is-not-equal 'nomatch (binary:match text #"test-cat-a"))
        (is-not-equal 'nomatch (binary:match text #"test-cat-b")))
      (after (graffeo_mnesia:delete graph)))))

(deftest format-info-includes-relationship-types
  "format-info/1 text includes the relationship type breakdown section."
  (let ((graph (setup-graph)))
    (try
      (let ((text (graffeo-mcp-format:format-info graph)))
        (is-not-equal 'nomatch (binary:match text #"Relationship Types"))
        (is-not-equal 'nomatch (binary:match text #"membership"))
        (is-not-equal 'nomatch (binary:match text #"prerequisites")))
      (after (graffeo_mnesia:delete graph)))))

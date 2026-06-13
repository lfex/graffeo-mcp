;;;; Tests for graffeo-mcp-tools handle_tool/3 dispatch.
;;;;
;;;; Each test:
;;;;   1. Creates a small Mnesia graph with known content
;;;;   2. Stores it in persistent_term under {graffeo_mcp, graph}
;;;;   3. Calls handle_tool/3 directly
;;;;   4. Cleans up in (after ...)

(defmodule graffeo-mcp-tools-tests
  (behaviour ltest-unit))

(include-lib "ltest/include/ltest-macros.lfe")

;;; ========================================
;;; Fixture helpers
;;; ========================================

(defun test-ctx ()
  (erlmcp_ctx:new (map 'session (self) 'request_id 1)))

(defun setup-graph ()
  ;; 1 source vertex, 1 abstract vertex, 1 membership edge
  (let ((graph (graffeo_mnesia:new)))
    (graffeo_mnesia:add_vertex graph (tuple #"src" #"concept")
                               (map 'source_slug #"src" 'slug #"concept"))
    (graffeo_mnesia:add_vertex graph #"concept"
                               (map 'concept #"Concept"
                                    'category #"test-cat"
                                    'tier #"basic"))
    (graffeo_mnesia:add_edge graph (tuple #"src" #"concept") #"concept"
                             (map 'weight 0.5
                                  'label (map 'type 'membership)))
    graph))

(defun with-graph (f)
  (let ((graph (setup-graph)))
    (persistent_term:put (tuple 'graffeo_mcp 'graph) graph)
    (try
      (funcall f graph)
      (after
        (try
          (persistent_term:erase (tuple 'graffeo_mcp 'graph))
          (catch ((tuple _ _ _) 'ok)))
        (graffeo_mnesia:delete graph)))))

;;; ========================================
;;; Tests
;;; ========================================

(deftest tools-returns-two-specs
  "tools/0 returns exactly 2 tool specs each with required discoverability keys."
  (let ((specs (graffeo-mcp-tools:tools)))
    (is-equal 2 (length specs))
    (lists:foreach
     (lambda (spec)
       (is (maps:is_key 'name spec))
       (is (maps:is_key 'category spec))
       (is (maps:is_key 'when_to_use spec))
       (is (maps:is_key 'annotations spec))
       (is (maps:is_key 'entry_point spec))
       (is (maps:is_key 'next spec)))
     specs)))

(deftest status-entry-point-true-info-false
  "status is entry_point true; info is entry_point false."
  (let* ((specs  (graffeo-mcp-tools:tools))
         (names  (lists:map (lambda (s) (mref s 'name)) specs))
         (status-spec (lists:nth 1 specs))
         (info-spec   (lists:nth 2 specs)))
    (is-equal #"status" (mref status-spec 'name))
    (is-equal 'true  (mref status-spec 'entry_point))
    (is-equal #"info" (mref info-spec 'name))
    (is-equal 'false (mref info-spec 'entry_point))))

(deftest status-returns-ok-with-counts
  "handle_tool status returns {ok, Content} whose text includes vertex and edge counts."
  (with-graph
   (lambda (_graph)
     (case (graffeo-mcp-tools:handle_tool #"status" (map) (test-ctx))
       ((tuple 'ok content)
        (let ((text (mref content #"text")))
          (is (is_binary text))
          (is-not-equal 'nomatch (binary:match text #"loaded"))))
       (other
        (is-equal (tuple 'ok 'content) other))))))

(deftest info-returns-ok-with-distribution
  "handle_tool info returns {ok, Content} whose text includes categories."
  (with-graph
   (lambda (_graph)
     (case (graffeo-mcp-tools:handle_tool #"info" (map) (test-ctx))
       ((tuple 'ok content)
        (let ((text (mref content #"text")))
          (is (is_binary text))
          (is-not-equal 'nomatch (binary:match text #"test-cat"))
          (is-not-equal 'nomatch (binary:match text #"Relationship Types"))))
       (other
        (is-equal (tuple 'ok 'content) other))))))

(deftest unknown-tool-returns-error
  "handle_tool with an unknown name returns {error, -32601, _}."
  (case (graffeo-mcp-tools:handle_tool #"nonexistent" (map) (test-ctx))
    ((tuple 'error -32601 _) (is 'true))
    (other (is-equal (tuple 'error -32601 '_) other))))

(deftest status-handles-missing-graph
  "handle_tool status returns {error, -32603, _} when persistent_term is not set."
  (try
    (persistent_term:erase (tuple 'graffeo_mcp 'graph))
    (catch ((tuple _ _ _) 'ok)))
  (case (graffeo-mcp-tools:handle_tool #"status" (map) (test-ctx))
    ((tuple 'error -32603 _) (is 'true))
    (other (is-equal (tuple 'error -32603 '_) other))))

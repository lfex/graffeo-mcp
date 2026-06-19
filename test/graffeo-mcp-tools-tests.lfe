;;;; Tests for graffeo-mcp-tools handle_tool/3 dispatch.
;;;;
;;;; Each dispatch test:
;;;;   1. Creates a Mnesia graph with known content
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

(defun setup-rich-graph ()
  ;; Same fixture as graffeo-mcp-query-tests: 4 concepts, 3 sources, 7 edges.
  ;;   concept-b -> concept-a  prerequisites   concept-d -> concept-b prerequisites
  ;;   concept-c -> concept-a  extends         concept-a -> concept-c related
  (let ((g (graffeo_mnesia:new)))
    (graffeo_mnesia:add_vertex g #"concept-a"
                               (map 'concept #"Concept A"
                                    'category #"concurrency" 'tier #"basic"))
    (graffeo_mnesia:add_vertex g #"concept-b"
                               (map 'concept #"Concept B"
                                    'category #"concurrency" 'tier #"intermediate"))
    (graffeo_mnesia:add_vertex g #"concept-c"
                               (map 'concept #"Concept C"
                                    'category #"otp" 'tier #"basic"))
    (graffeo_mnesia:add_vertex g #"concept-d"
                               (map 'concept #"Concept D"
                                    'category #"otp" 'tier #"advanced"))
    (graffeo_mnesia:add_vertex g (tuple #"src-a" #"concept-a")
                               (map 'source_slug #"src-a" 'slug #"concept-a"))
    (graffeo_mnesia:add_vertex g (tuple #"src-a" #"concept-b")
                               (map 'source_slug #"src-a" 'slug #"concept-b"))
    (graffeo_mnesia:add_vertex g (tuple #"src-a" #"concept-c")
                               (map 'source_slug #"src-a" 'slug #"concept-c"))
    (graffeo_mnesia:add_edge g (tuple #"src-a" #"concept-a") #"concept-a"
                             (map 'weight 0.5 'label (map 'type 'membership)))
    (graffeo_mnesia:add_edge g (tuple #"src-a" #"concept-b") #"concept-b"
                             (map 'weight 0.5 'label (map 'type 'membership)))
    (graffeo_mnesia:add_edge g (tuple #"src-a" #"concept-c") #"concept-c"
                             (map 'weight 0.5 'label (map 'type 'membership)))
    (rich-typed-edge g #"concept-b" #"concept-a" 'prerequisites 1.0)
    (rich-typed-edge g #"concept-d" #"concept-b" 'prerequisites 1.0)
    (rich-typed-edge g #"concept-c" #"concept-a" 'extends 1.0)
    (rich-typed-edge g #"concept-a" #"concept-c" 'related 2.0)
    g))

(defun rich-typed-edge (g from to type weight)
  (graffeo_mnesia:add_edge
   g from to
   (map 'weight weight
        'label (map 'types (list type) 'asserted_by (list #"src-a")))))

(defun with-graph (f)
  (run-with-graph (setup-graph) f))

(defun with-rich-graph (f)
  (run-with-graph (setup-rich-graph) f))

(defun run-with-graph (graph f)
  (persistent_term:put (tuple 'graffeo_mcp 'graph) graph)
  (try
    (funcall f graph)
    (after
      (try
        (persistent_term:erase (tuple 'graffeo_mcp 'graph))
        (catch ((tuple _ _ _) 'ok)))
      (graffeo_mnesia:delete graph))))

(defun ok-text (name input)
  "Dispatch name with input, assert {ok, Content} and return the text binary."
  (case (graffeo-mcp-tools:handle_tool name input (test-ctx))
    ((tuple 'ok content)
     (let ((text (mref content #"text")))
       (is (is_binary text))
       text))
    (other
     (is-equal (tuple 'ok 'content) other)
     #"")))

;;; ========================================
;;; Catalog / metadata
;;; ========================================

(deftest tools-returns-ten-specs
  "tools/0 returns exactly 10 tool specs each with the discoverability keys."
  (let ((specs (graffeo-mcp-tools:tools)))
    (is-equal 10 (length specs))
    (lists:foreach
     (lambda (spec)
       (is (maps:is_key 'name spec))
       (is (maps:is_key 'description spec))
       (is (maps:is_key 'input_schema spec))
       (is (maps:is_key 'category spec))
       (is (maps:is_key 'when_to_use spec))
       (is (maps:is_key 'returns spec))
       (is (maps:is_key 'next spec))
       (is (maps:is_key 'entry_point spec))
       (is (maps:is_key 'annotations spec)))
     specs)))

(deftest entry-point-correctness
  "status, get_node, learning_path are entry points; all others are not."
  (let* ((specs    (graffeo-mcp-tools:tools))
         (entries  (lists:sort
                    (lc ((<- s specs) (=:= (mref s 'entry_point) 'true))
                        (mref s 'name)))))
    (is-equal (list #"get_node" #"learning_path" #"status") entries)))

(deftest next-chains-name-existing-tools
  "Every tool's next list names only tools that exist, and every non-entry-point
  tool is named in at least one other tool's next (no orphans)."
  (let* ((specs (graffeo-mcp-tools:tools))
         (names (lc ((<- s specs)) (mref s 'name)))
         (nexts (lists:append (lc ((<- s specs)) (mref s 'next))))
         (non-entries (lc ((<- s specs) (=:= (mref s 'entry_point) 'false))
                          (mref s 'name))))
    ;; no next entry points at a non-existent tool
    (is (lists:all (lambda (n) (lists:member n names)) nexts))
    ;; every non-entry tool is reachable via some next
    (is (lists:all (lambda (n) (lists:member n nexts)) non-entries))))

;;; ========================================
;;; Meta tool dispatch
;;; ========================================

(deftest status-returns-ok-with-counts
  "handle_tool status returns {ok, Content} whose text mentions load state."
  (with-graph
   (lambda (_g)
     (let ((text (ok-text #"status" (map))))
       (is-not-equal 'nomatch (binary:match text #"loaded"))))))

(deftest info-returns-ok-with-distribution
  "handle_tool info returns {ok, Content} whose text includes categories."
  (with-graph
   (lambda (_g)
     (let ((text (ok-text #"info" (map))))
       (is-not-equal 'nomatch (binary:match text #"test-cat"))
       (is-not-equal 'nomatch (binary:match text #"Relationship Types"))))))

(deftest unknown-tool-returns-error
  "handle_tool with an unknown name returns {error, -32601, _}."
  (case (graffeo-mcp-tools:handle_tool #"nonexistent" (map) (test-ctx))
    ((tuple 'error -32601 _) (is 'true))
    (other (is-equal (tuple 'error -32601 '_) other))))

(deftest status-handles-missing-graph
  "handle_tool status returns {error, -32603, _} when persistent_term is unset."
  (try
    (persistent_term:erase (tuple 'graffeo_mcp 'graph))
    (catch ((tuple _ _ _) 'ok)))
  (case (graffeo-mcp-tools:handle_tool #"status" (map) (test-ctx))
    ((tuple 'error -32603 _) (is 'true))
    (other (is-equal (tuple 'error -32603 '_) other))))

;;; ========================================
;;; Navigation + learning tool dispatch
;;; ========================================

(deftest get-node-returns-ok
  "get_node returns concept data text for a known vertex."
  (with-rich-graph
   (lambda (_g)
     (let ((text (ok-text #"get_node" (map #"id" #"concept-a"))))
       (is-not-equal 'nomatch (binary:match text #"concurrency"))))))

(deftest get-node-unknown-returns-error
  "get_node returns {error, -32602, _} for an unknown vertex."
  (with-rich-graph
   (lambda (_g)
     (case (graffeo-mcp-tools:handle_tool
            #"get_node" (map #"id" #"concept-z") (test-ctx))
       ((tuple 'error -32602 _) (is 'true))
       (other (is-equal (tuple 'error -32602 '_) other))))))

(deftest get-node-edges-returns-ok
  "get_node_edges returns edge text including a relationship type."
  (with-rich-graph
   (lambda (_g)
     (let ((text (ok-text #"get_node_edges" (map #"id" #"concept-a"))))
       (is-not-equal 'nomatch (binary:match text #"related"))))))

(deftest related-returns-ok
  "related returns connected-concept text filtered by relationship."
  (with-rich-graph
   (lambda (_g)
     (let ((text (ok-text #"related"
                          (map #"id" #"concept-a" #"relationship" #"related"))))
       (is-not-equal 'nomatch (binary:match text #"concept-c"))))))

(deftest neighborhood-returns-ok
  "neighborhood returns BFS-walk text within the radius."
  (with-rich-graph
   (lambda (_g)
     (let ((text (ok-text #"neighborhood"
                          (map #"id" #"concept-a" #"radius" 1))))
       (is-not-equal 'nomatch (binary:match text #"Neighborhood"))))))

(deftest prerequisites-returns-ok
  "prerequisites returns direct/transitive text for a concept."
  (with-rich-graph
   (lambda (_g)
     (let ((text (ok-text #"prerequisites" (map #"id" #"concept-d"))))
       (is-not-equal 'nomatch (binary:match text #"concept-a"))))))

(deftest dependents-returns-ok
  "dependents returns dependent-concept text for a concept."
  (with-rich-graph
   (lambda (_g)
     (let ((text (ok-text #"dependents" (map #"id" #"concept-a"))))
       (is-not-equal 'nomatch (binary:match text #"concept-d"))))))

(deftest learning-path-returns-ok
  "learning_path returns an ordered path ending at the target."
  (with-rich-graph
   (lambda (_g)
     (let ((text (ok-text #"learning_path" (map #"id" #"concept-d"))))
       (is-not-equal 'nomatch (binary:match text #"Learning path"))
       (is-not-equal 'nomatch (binary:match text #"concept-a"))))))

(deftest topsort-returns-ok
  "topsort returns a global ordering text."
  (with-rich-graph
   (lambda (_g)
     (let ((text (ok-text #"topsort" (map))))
       (is-not-equal 'nomatch (binary:match text #"Topological order"))))))

(deftest new-tools-handle-missing-graph
  "All 8 navigation/learning tools return {error, -32603, _} with no graph."
  (try
    (persistent_term:erase (tuple 'graffeo_mcp 'graph))
    (catch ((tuple _ _ _) 'ok)))
  (let ((calls (list
                (tuple #"get_node"       (map #"id" #"concept-a"))
                (tuple #"get_node_edges" (map #"id" #"concept-a"))
                (tuple #"related"        (map #"id" #"concept-a"))
                (tuple #"neighborhood"   (map #"id" #"concept-a"))
                (tuple #"prerequisites"  (map #"id" #"concept-a"))
                (tuple #"dependents"     (map #"id" #"concept-a"))
                (tuple #"learning_path"  (map #"id" #"concept-a"))
                (tuple #"topsort"        (map)))))
    (lists:foreach
     (lambda (call)
       (let (((tuple name input) call))
         (case (graffeo-mcp-tools:handle_tool name input (test-ctx))
           ((tuple 'error -32603 _) (is 'true))
           (other (is-equal (tuple name (tuple 'error -32603 '_)) other)))))
     calls)))

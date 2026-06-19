;;;; Tests for graffeo-mcp-query (navigation + learning algorithms).
;;;;
;;;; Rich fixture (4 abstract concepts, 3 source cards, 7 edges):
;;;;
;;;;   concept-a  concurrency / basic
;;;;   concept-b  concurrency / intermediate
;;;;   concept-c  otp / basic
;;;;   concept-d  otp / advanced        (ghost: no source card)
;;;;
;;;;   {src-a,concept-a} -> concept-a   membership   0.5
;;;;   {src-a,concept-b} -> concept-b   membership   0.5
;;;;   {src-a,concept-c} -> concept-c   membership   0.5
;;;;   concept-b -> concept-a           prerequisites 1.0   (b requires a)
;;;;   concept-d -> concept-b           prerequisites 1.0   (d requires b)
;;;;   concept-c -> concept-a           extends       1.0
;;;;   concept-a -> concept-c           related       2.0
;;;;
;;;; Each test builds and tears down its own Mnesia graph in try/after.

(defmodule graffeo-mcp-query-tests
  (behaviour ltest-unit))

(include-lib "ltest/include/ltest-macros.lfe")

;;; ========================================
;;; Fixture
;;; ========================================

(defun setup-rich-graph ()
  (let ((g (graffeo_mnesia:new)))
    ;; abstract vertices
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
    ;; source vertices
    (graffeo_mnesia:add_vertex g (tuple #"src-a" #"concept-a")
                               (map 'source_slug #"src-a" 'slug #"concept-a"))
    (graffeo_mnesia:add_vertex g (tuple #"src-a" #"concept-b")
                               (map 'source_slug #"src-a" 'slug #"concept-b"))
    (graffeo_mnesia:add_vertex g (tuple #"src-a" #"concept-c")
                               (map 'source_slug #"src-a" 'slug #"concept-c"))
    ;; membership edges (source -> abstract)
    (add-membership g (tuple #"src-a" #"concept-a") #"concept-a")
    (add-membership g (tuple #"src-a" #"concept-b") #"concept-b")
    (add-membership g (tuple #"src-a" #"concept-c") #"concept-c")
    ;; typed abstract edges
    (add-typed g #"concept-b" #"concept-a" 'prerequisites 1.0)
    (add-typed g #"concept-d" #"concept-b" 'prerequisites 1.0)
    (add-typed g #"concept-c" #"concept-a" 'extends       1.0)
    (add-typed g #"concept-a" #"concept-c" 'related       2.0)
    g))

(defun add-membership (g from to)
  (graffeo_mnesia:add_edge g from to
                           (map 'weight 0.5 'label (map 'type 'membership))))

(defun add-typed (g from to type weight)
  (graffeo_mnesia:add_edge
   g from to
   (map 'weight weight
        'label (map 'types (list type) 'asserted_by (list #"src-a")))))

(defun with-rich-graph (f)
  (let ((g (setup-rich-graph)))
    (try
      (funcall f g)
      (after (graffeo_mnesia:delete g)))))

;;; ========================================
;;; Navigation
;;; ========================================

(deftest get-node-returns-concept-data
  "get-node-data returns label, degrees, and source count for a known vertex."
  (with-rich-graph
   (lambda (g)
     (case (graffeo-mcp-query:get-node-data g #"concept-a")
       ((tuple 'ok data)
        (let ((label (mref data 'label)))
          (is-equal #"concept-a" (mref data 'id))
          (is-equal #"concurrency" (mref label 'category))
          (is-equal #"basic" (mref label 'tier))
          ;; in: b->a, c->a, src->a = 3 ; out: a->c = 1 ; sources: 1
          (is-equal 3 (mref data 'in_degree))
          (is-equal 1 (mref data 'out_degree))
          (is-equal 1 (mref data 'sources))))
       (other (is-equal (tuple 'ok 'data) other))))))

(deftest get-node-unknown-returns-error
  "get-node-data returns {error, not_found} for an unknown vertex."
  (with-rich-graph
   (lambda (g)
     (is-equal (tuple 'error 'not_found)
               (graffeo-mcp-query:get-node-data g #"concept-z")))))

(deftest get-node-edges-returns-typed-edges
  "get-node-edges surfaces edges with relationship type and weight."
  (with-rich-graph
   (lambda (g)
     (let* ((edges (graffeo-mcp-query:get-node-edges g #"concept-a" #"both"))
            (related (lc ((<- e edges) (=:= (mref e 'type) 'related)) e)))
       ;; a -> c related, weight 2.0
       (is-equal 1 (length related))
       (let ((e (car related)))
         (is-equal 'out (mref e 'dir))
         (is-equal #"concept-c" (mref e 'other))
         (is-equal 2.0 (mref e 'weight)))))))

(deftest get-node-edges-direction-filter
  "Direction filter narrows to outgoing-only vs incoming-only edges."
  (with-rich-graph
   (lambda (g)
     (let ((outs (graffeo-mcp-query:get-node-edges g #"concept-a" #"out"))
           (ins  (graffeo-mcp-query:get-node-edges g #"concept-a" #"in")))
       ;; out: only a->c related
       (is-equal 1 (length outs))
       (is (lists:all (lambda (e) (=:= (mref e 'dir) 'out)) outs))
       ;; in: b->a prereq, c->a extends, src->a membership
       (is-equal 3 (length ins))
       (is (lists:all (lambda (e) (=:= (mref e 'dir) 'in)) ins))
       (is (lists:any (lambda (e) (=:= (mref e 'type) 'prerequisites)) ins))
       (is (lists:any (lambda (e) (=:= (mref e 'type) 'membership)) ins))))))

(deftest related-filters-by-type
  "find-related returns only concepts linked by the requested relationship."
  (with-rich-graph
   (lambda (g)
     ;; a is 'related' to c (a->c) only
     (is-equal (list (tuple #"concept-c" 'related))
               (graffeo-mcp-query:find-related g #"concept-a" 'related 20))
     ;; with no relationship filter, c shows up under multiple types
     (let ((all (graffeo-mcp-query:find-related g #"concept-a" 'undefined 20)))
       (is (lists:member (tuple #"concept-c" 'related) all))
       (is (lists:member (tuple #"concept-b" 'prerequisites) all))
       (is (lists:member (tuple #"concept-c" 'extends) all))))))

(deftest neighborhood-respects-radius
  "neighborhood returns concepts within the given BFS radius, abstract only."
  (with-rich-graph
   (lambda (g)
     (let* ((r1     (graffeo-mcp-query:neighborhood g #"concept-a" 1 'undefined))
            (slugs1 (lists:sort (lc ((<- (tuple v _) r1)) v)))
            (r2     (graffeo-mcp-query:neighborhood g #"concept-a" 2 'undefined))
            (slugs2 (lists:sort (lc ((<- (tuple v _) r2)) v))))
       ;; radius 1: direct abstract neighbours b and c (not d, 2 hops away)
       (is-equal (list #"concept-b" #"concept-c") slugs1)
       ;; radius 2: d is now reachable (d -> b -> a)
       (is (lists:member #"concept-d" slugs2))))))

;;; ========================================
;;; Learning
;;; ========================================

(deftest prerequisites-returns-chain
  "prerequisites returns direct and transitive prerequisite slugs."
  (with-rich-graph
   (lambda (g)
     (let (((tuple direct transitive)
            (graffeo-mcp-query:prerequisites g #"concept-d")))
       ;; d requires b ; b requires a
       (is-equal (list #"concept-b") direct)
       (is-equal (list #"concept-a" #"concept-b") transitive)))))

(deftest dependents-returns-deps
  "dependents returns the concepts that depend on a given concept."
  (with-rich-graph
   (lambda (g)
     (let (((tuple direct all)
            (graffeo-mcp-query:dependents g #"concept-a" 'all)))
       ;; b requires a directly ; d requires b which requires a
       (is-equal (list #"concept-b") direct)
       (is-equal (list #"concept-b" #"concept-d") all)))))

(deftest learning-path-foundations-first
  "learning-path orders foundations first, target last."
  (with-rich-graph
   (lambda (g)
     (is-equal (tuple 'ok (list #"concept-a" #"concept-b" #"concept-d"))
               (graffeo-mcp-query:learning-path g #"concept-d")))))

(deftest topsort-valid-ordering
  "topsort yields a valid foundations-first ordering of the prerequisite graph."
  (with-rich-graph
   (lambda (g)
     (case (graffeo-mcp-query:topsort-prereqs g 50)
       ((tuple 'ok order _total)
        ;; among the constrained nodes, a must precede b, which precedes d
        (let ((constrained
               (lc ((<- s order)
                    (lists:member s (list #"concept-a" #"concept-b"
                                          #"concept-d")))
                   s)))
          (is-equal (list #"concept-a" #"concept-b" #"concept-d")
                    constrained)))
       (other (is-equal (tuple 'ok 'order '_) other))))))

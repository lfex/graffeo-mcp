;;;; erlmcp_server_handler behaviour: tool catalog and dispatch.
;;;;
;;;; Ten tools across three categories:
;;;;   meta       — status (entry point), info
;;;;   navigation — get_node (entry point), get_node_edges, related, neighborhood
;;;;   learning   — prerequisites, dependents, learning_path (entry point), topsort
;;;;
;;;; Graph handle is read from persistent_term — no gen_server call on the hot
;;;; path. Query logic lives in graffeo-mcp-query; formatting in
;;;; graffeo-mcp-format. This module is dispatch + discoverability metadata only.

(defmodule graffeo-mcp-tools
  (behaviour erlmcp_server_handler)
  (export
   (handle_tool 3)
   (tools 0)))

;;; ========================================
;;; erlmcp_server_handler callbacks
;;; ========================================

(defun tools ()
  "Return all ten tool specs with full discoverability metadata."
  (list
   (map 'name        #"status"
        'description #"Report whether the Erlang knowledge graph is loaded and show basic vertex and edge counts."
        'input_schema (erlmcp_schema:object '())
        'category     #"meta"
        'when_to_use  #"Call this first to verify the graph is loaded and get a size overview before exploring concepts."
        'returns      #"Loaded state, total vertex count, total edge count, and backend type."
        'next         (list #"info")
        'entry_point  'true
        'annotations  (map 'readOnlyHint 'true 'idempotentHint 'true))
   (map 'name        #"info"
        'description #"Get detailed graph statistics: vertex and edge counts, category distribution, and relationship type breakdown."
        'input_schema (erlmcp_schema:object '())
        'category     #"meta"
        'when_to_use  #"Call this when you need deeper statistics beyond what status shows, such as how many concepts exist per category or how edges are distributed across relationship types."
        'returns      #"Vertex counts (total, source, abstract), edge count, per-category concept counts, and per-relationship-type edge counts with weights."
        'next         (list #"get_node" #"learning_path")
        'entry_point  'false
        'annotations  (map 'readOnlyHint 'true 'idempotentHint 'true))
   (map 'name        #"get_node"
        'description #"Look up an Erlang concept by slug and get its category, tier, degree counts, and source coverage."
        'input_schema (erlmcp_schema:object
                       (list (erlmcp_schema:field
                              #"id" (erlmcp_schema:string)
                              (list 'required
                                    (tuple 'doc #"Concept slug, e.g. gen-server")))))
        'category     #"navigation"
        'when_to_use  #"Use this to inspect a single concept you already know the slug for: its category, learning tier, how connected it is, and how many source cards mention it. Start here when drilling into a specific concept."
        'returns      #"The concept name, slug, category, tier, in-degree, out-degree, and the number of source cards linked via membership edges."
        'next         (list #"get_node_edges" #"prerequisites" #"related")
        'entry_point  'true
        'annotations  (map 'readOnlyHint 'true 'idempotentHint 'true))
   (map 'name        #"get_node_edges"
        'description #"List all edges (prerequisites, extends, related, contrasts_with, membership) for a concept, optionally filtered by direction."
        'input_schema (erlmcp_schema:object
                       (list (erlmcp_schema:field
                              #"id" (erlmcp_schema:string)
                              (list 'required (tuple 'doc #"Concept slug")))
                             (erlmcp_schema:field
                              #"direction"
                              (erlmcp_schema:enum (list #"in" #"out" #"both"))
                              (list (tuple 'default #"both")
                                    (tuple 'doc #"Which edges to include")))))
        'category     #"navigation"
        'when_to_use  #"Use this after get_node when you want the concrete relationships a concept participates in, including edge types and weights. Filter by direction to see only what a concept points to (out) or what points to it (in)."
        'returns      #"Outgoing and incoming edges grouped by direction, each with the other concept's slug, relationship type, and weight."
        'next         (list #"related" #"neighborhood")
        'entry_point  'false
        'annotations  (map 'readOnlyHint 'true 'idempotentHint 'true))
   (map 'name        #"related"
        'description #"Find concepts connected to a given concept through a specific relationship type."
        'input_schema (erlmcp_schema:object
                       (list (erlmcp_schema:field
                              #"id" (erlmcp_schema:string)
                              (list 'required (tuple 'doc #"Concept slug")))
                             (erlmcp_schema:field
                              #"relationship"
                              (erlmcp_schema:enum
                               (list #"prerequisites" #"extends"
                                     #"related" #"contrasts_with"))
                              (list (tuple 'doc #"Relationship type to filter by; omit for any type")))
                             (erlmcp_schema:field
                              #"limit" (erlmcp_schema:integer)
                              (list (tuple 'default 20)
                                    (tuple 'doc #"Maximum concepts to return")))))
        'category     #"navigation"
        'when_to_use  #"Use this when you want concepts linked by one particular relationship — e.g. everything related to or that extends a concept — rather than the full edge list. Omit relationship to get connections of every type."
        'returns      #"A list of connected concept slugs with their relationship type, limited to the requested count."
        'next         (list #"get_node" #"neighborhood")
        'entry_point  'false
        'annotations  (map 'readOnlyHint 'true 'idempotentHint 'true))
   (map 'name        #"neighborhood"
        'description #"Explore the local neighborhood around a concept via breadth-first search, limited to a specified radius."
        'input_schema (erlmcp_schema:object
                       (list (erlmcp_schema:field
                              #"id" (erlmcp_schema:string)
                              (list 'required (tuple 'doc #"Concept slug")))
                             (erlmcp_schema:field
                              #"radius" (erlmcp_schema:integer)
                              (list (tuple 'default 2) (tuple 'max 5)
                                    (tuple 'doc #"Maximum BFS depth (hops)")))
                             (erlmcp_schema:field
                              #"relationship"
                              (erlmcp_schema:enum
                               (list #"prerequisites" #"extends"
                                     #"related" #"contrasts_with"))
                              (list (tuple 'doc #"Restrict the walk to one relationship type; omit for any")))))
        'category     #"navigation"
        'when_to_use  #"Use this to see the cluster of concepts surrounding a starting concept within a few hops. Good for understanding a concept's local context; narrow by relationship type or shrink the radius to stay focused."
        'returns      #"Concepts reachable within the radius, grouped by their BFS depth from the starting concept."
        'next         (list #"get_node" #"related")
        'entry_point  'false
        'annotations  (map 'readOnlyHint 'true 'idempotentHint 'true))
   (map 'name        #"prerequisites"
        'description #"List the direct and transitive prerequisites for a concept — what you need to learn first."
        'input_schema (erlmcp_schema:object
                       (list (erlmcp_schema:field
                              #"id" (erlmcp_schema:string)
                              (list 'required (tuple 'doc #"Concept slug")))))
        'category     #"learning"
        'when_to_use  #"Use this when you want to know what a concept depends on. Direct prerequisites are the immediate dependencies; transitive prerequisites are the full chain down to foundations."
        'returns      #"The direct prerequisites and the full transitive set of prerequisite concept slugs."
        'next         (list #"learning_path" #"dependents")
        'entry_point  'false
        'annotations  (map 'readOnlyHint 'true 'idempotentHint 'true))
   (map 'name        #"dependents"
        'description #"Find concepts that depend on a given concept — what builds on top of it."
        'input_schema (erlmcp_schema:object
                       (list (erlmcp_schema:field
                              #"id" (erlmcp_schema:string)
                              (list 'required (tuple 'doc #"Concept slug")))
                             (erlmcp_schema:field
                              #"depth" (erlmcp_schema:integer)
                              (list (tuple 'doc #"Bound the search to this many hops; omit for the full transitive closure")))))
        'category     #"learning"
        'when_to_use  #"Use this to find what a concept unlocks: the concepts that list it (directly or transitively) as a prerequisite. The inverse of prerequisites. Pass a depth to bound how many hops out to look."
        'returns      #"The direct dependents and the broader set of concepts that depend on this concept (bounded by depth if given)."
        'next         (list #"prerequisites" #"learning_path")
        'entry_point  'false
        'annotations  (map 'readOnlyHint 'true 'idempotentHint 'true))
   (map 'name        #"learning_path"
        'description #"Get a topologically sorted learning path for a concept, starting from foundational prerequisites."
        'input_schema (erlmcp_schema:object
                       (list (erlmcp_schema:field
                              #"id" (erlmcp_schema:string)
                              (list 'required (tuple 'doc #"Target concept slug")))))
        'category     #"learning"
        'when_to_use  #"Use this to get an ordered study plan for reaching a target concept: foundations first, the target last. Prefer this over prerequisites when you want a teachable sequence rather than just the dependency set."
        'returns      #"An ordered, numbered list of concept slugs from foundational prerequisites up to the target concept."
        'next         (list #"get_node" #"prerequisites" #"topsort")
        'entry_point  'true
        'annotations  (map 'readOnlyHint 'true 'idempotentHint 'true))
   (map 'name        #"topsort"
        'description #"Get a topological ordering of the entire prerequisite graph — the global learning sequence."
        'input_schema (erlmcp_schema:object
                       (list (erlmcp_schema:field
                              #"limit" (erlmcp_schema:integer)
                              (list (tuple 'default 50) (tuple 'max 200)
                                    (tuple 'doc #"Maximum concepts to return")))))
        'category     #"learning"
        'when_to_use  #"Use this for a whole-graph learning order across every concept, foundations first, rather than the path to one target. Apply a limit to preview the leading foundational concepts."
        'returns      #"A numbered topological ordering of prerequisite concepts (foundations first), truncated to the limit, with the total count."
        'next         (list #"learning_path" #"get_node")
        'entry_point  'false
        'annotations  (map 'readOnlyHint 'true 'idempotentHint 'true))))

;;; ========================================
;;; Dispatch
;;; ========================================

(defun handle_tool
  ((#"status" _input _ctx)
   (with-graph
    (lambda (graph)
      (tuple 'ok (erlmcp:text (graffeo-mcp-format:format-status graph))))))
  ((#"info" _input _ctx)
   (with-graph
    (lambda (graph)
      (tuple 'ok (erlmcp:text (graffeo-mcp-format:format-info graph))))))
  ((#"get_node" input _ctx)
   (with-node input
    (lambda (graph id)
      (case (graffeo-mcp-query:get-node-data graph id)
        ((tuple 'ok data)
         (tuple 'ok (erlmcp:text (graffeo-mcp-format:format-node data))))
        (_ (unknown-concept-error id))))))
  ((#"get_node_edges" input _ctx)
   (with-node input
    (lambda (graph id)
      (let* ((direction (maps:get #"direction" input #"both"))
             (edges     (graffeo-mcp-query:get-node-edges graph id direction)))
        (tuple 'ok (erlmcp:text
                    (graffeo-mcp-format:format-node-edges
                     (tuple id edges))))))))
  ((#"related" input _ctx)
   (with-node input
    (lambda (graph id)
      (let* ((rel      (relationship-atom
                        (maps:get #"relationship" input 'undefined)))
             (limit    (maps:get #"limit" input 20))
             (concepts (graffeo-mcp-query:find-related graph id rel limit)))
        (tuple 'ok (erlmcp:text
                    (graffeo-mcp-format:format-related
                     (tuple id rel concepts))))))))
  ((#"neighborhood" input _ctx)
   (with-node input
    (lambda (graph id)
      (let* ((radius (maps:get #"radius" input 2))
             (rel    (relationship-atom
                      (maps:get #"relationship" input 'undefined)))
             (verts  (graffeo-mcp-query:neighborhood graph id radius rel)))
        (tuple 'ok (erlmcp:text
                    (graffeo-mcp-format:format-neighborhood
                     (tuple id radius verts))))))))
  ((#"prerequisites" input _ctx)
   (with-node input
    (lambda (graph id)
      (let (((tuple direct transitive)
             (graffeo-mcp-query:prerequisites graph id)))
        (tuple 'ok (erlmcp:text
                    (graffeo-mcp-format:format-prerequisites
                     (tuple id direct transitive))))))))
  ((#"dependents" input _ctx)
   (with-node input
    (lambda (graph id)
      (let* ((depth (maps:get #"depth" input 'all))
             ((tuple direct all)
              (graffeo-mcp-query:dependents graph id depth)))
        (tuple 'ok (erlmcp:text
                    (graffeo-mcp-format:format-dependents
                     (tuple id direct all))))))))
  ((#"learning_path" input _ctx)
   (with-node input
    (lambda (graph id)
      (case (graffeo-mcp-query:learning-path graph id)
        ((tuple 'ok path)
         (tuple 'ok (erlmcp:text
                     (graffeo-mcp-format:format-learning-path
                      (tuple id path)))))
        (_ (unknown-concept-error id))))))
  ((#"topsort" input _ctx)
   (with-graph
    (lambda (graph)
      (let ((limit (maps:get #"limit" input 50)))
        (case (graffeo-mcp-query:topsort-prereqs graph limit)
          ((tuple 'ok order total)
           (tuple 'ok (erlmcp:text
                       (graffeo-mcp-format:format-topsort
                        (tuple order total))))))))))
  ((name _input _ctx)
   (tuple 'error -32601
          (iolist_to_binary (list #"Unknown tool: " name)))))

;;; ========================================
;;; Internal helpers
;;; ========================================

(defun graph-handle ()
  (persistent_term:get (tuple 'graffeo_mcp 'graph) 'undefined))

(defun no-graph-error ()
  (tuple 'error -32603 #"Graph not loaded. The server is still starting."))

(defun unknown-concept-error (id)
  (tuple 'error -32602 (iolist_to_binary (list #"Unknown concept: " id))))

(defun with-graph (fun)
  "Run fun with the loaded graph, or return the not-loaded error."
  (case (graph-handle)
    ('undefined (no-graph-error))
    (graph (funcall fun graph))))

(defun with-node (input fun)
  "Run fun with the graph and a validated #\"id\", or the appropriate error
  (-32603 if no graph, -32602 if the concept does not exist)."
  (with-graph
   (lambda (graph)
     (let ((id (maps:get #"id" input #"")))
       (case (graffeo:vertex_label graph id)
         ((tuple 'ok _) (funcall fun graph id))
         (_ (unknown-concept-error id)))))))

(defun relationship-atom
  "Map a relationship enum binary from tool input to its atom, safely (closed
  set — never mints atoms from arbitrary input). Anything else is 'undefined."
  ((#"prerequisites")  'prerequisites)
  ((#"extends")        'extends)
  ((#"related")        'related)
  ((#"contrasts_with") 'contrasts_with)
  ((_)                 'undefined))

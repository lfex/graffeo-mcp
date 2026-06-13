;;;; erlmcp_server_handler behaviour: tool catalog and dispatch.
;;;;
;;;; Two meta tools: status (entry point) and info.
;;;; Graph handle is read from persistent_term — no gen_server call on the
;;;; hot path.

(defmodule graffeo-mcp-tools
  (behaviour erlmcp_server_handler)
  (export
   (handle_tool 3)
   (tools 0)))

;;; ========================================
;;; erlmcp_server_handler callbacks
;;; ========================================

(defun tools ()
  "Return the two meta tool specs with full discoverability metadata."
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
        'annotations  (map 'readOnlyHint 'true 'idempotentHint 'true))))

(defun handle_tool
  ((#"status" _input _ctx)
   (case (persistent_term:get (tuple 'graffeo_mcp 'graph) 'undefined)
     ('undefined
      (tuple 'error -32603 #"Graph not loaded. The server is still starting."))
     (graph
      (tuple 'ok (erlmcp:text (graffeo-mcp-format:format-status graph))))))
  ((#"info" _input _ctx)
   (case (persistent_term:get (tuple 'graffeo_mcp 'graph) 'undefined)
     ('undefined
      (tuple 'error -32603 #"Graph not loaded. The server is still starting."))
     (graph
      (tuple 'ok (erlmcp:text (graffeo-mcp-format:format-info graph))))))
  ((name _input _ctx)
   (tuple 'error -32601
          (iolist_to_binary (list #"Unknown tool: " name)))))

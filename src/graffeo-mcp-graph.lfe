;;;; gen_server managing the Mnesia graph lifecycle.
;;;;
;;;; On init: opens (or reconnects to) the erlang_concepts Mnesia graph,
;;;; runs ingest if the graph is empty, then stores the handle in
;;;; persistent_term so tool handlers can reach it without going through
;;;; this server on every query.

(defmodule graffeo-mcp-graph
  (behaviour gen_server)
  (export
   (get-graph 0)
   (graph-stats 0)
   (start-link 0)
   (init 1)
   (handle_call 3)
   (handle_cast 2)
   (handle_info 2)
   (terminate 2)
   (code_change 3)))

;;; ========================================
;;; Public API
;;; ========================================

(defun start-link ()
  "Start and register the graph gen_server."
  (gen_server:start_link (tuple 'local 'graffeo-mcp-graph)
                         'graffeo-mcp-graph
                         '()
                         '()))

(defun get-graph ()
  "Return {ok, Graph} from the running gen_server."
  (gen_server:call 'graffeo-mcp-graph 'get_graph))

(defun graph-stats ()
  "Return {ok, #{vertices => N, edges => M}} from the running gen_server."
  (gen_server:call 'graffeo-mcp-graph 'graph_stats))

;;; ========================================
;;; gen_server callbacks
;;; ========================================

(defun init (_args)
  "Open Mnesia graph; ingest if empty; store handle in persistent_term."
  (let* ((graph (graffeo_mnesia:open "erlang_concepts"
                                     (map 'storage 'disc_copies)))
         (cards-dir (++ (code:priv_dir 'graffeomcp) "/concept-cards")))
    (if (=:= (graffeo:no_vertices graph) 0)
      (graffeo-mcp-ingest:build-from-dir cards-dir graph))
    (persistent_term:put (tuple 'graffeo_mcp 'graph) graph)
    (tuple 'ok (map 'graph graph))))

(defun handle_call
  (('get_graph _from state)
   (tuple 'reply (tuple 'ok (mref state 'graph)) state))
  (('graph_stats _from state)
   (let* ((graph (mref state 'graph))
          (stats (map 'vertices (graffeo:no_vertices graph)
                      'edges    (graffeo:no_edges graph))))
     (tuple 'reply (tuple 'ok stats) state)))
  ((_request _from state)
   (tuple 'reply (tuple 'error 'unknown_call) state)))

(defun handle_cast (_msg state)
  (tuple 'noreply state))

(defun handle_info (_info state)
  (tuple 'noreply state))

(defun terminate (_reason _state)
  'ok)

(defun code_change (_old-vsn state _extra)
  (tuple 'ok state))

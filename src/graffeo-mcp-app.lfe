;;;; OTP application callback for the graffeo-mcp application.
;;;;
;;;; start/2 brings up our supervision tree first (which populates the
;;;; Mnesia graph into persistent_term), then wires the erlmcp stdio
;;;; server and registers graffeo-mcp-tools as the handler.

(defmodule graffeo-mcp-app
  (behaviour application)
  (export
   (start 2)
   (stop 1)))

(defun start (_type _args)
  "Start the supervision tree, then wire the erlmcp stdio server."
  (case (graffeo-mcp-sup:start-link)
    ((= (tuple 'ok _) result)
     (start-mcp)
     result)
    (error error)))

(defun stop (_state)
  "Stop the graffeo-mcp application."
  'ok)

;;; ========================================
;;; Internal
;;; ========================================

(defun start-mcp ()
  "Start the erlmcp stdio server with graffeo-mcp-tools as handler."
  (erlmcp:start_stdio_setup
   'graffeomcp
   (map 'name    #"graffeo-mcp"
        'version #"0.1.0"
        'purpose #"Erlang knowledge graph for LLM-driven concept exploration"
        'handler 'graffeo-mcp-tools)))

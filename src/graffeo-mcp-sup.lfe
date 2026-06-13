;;;; Supervisor for the graffeo-mcp application.

(defmodule graffeo-mcp-sup
  (behaviour supervisor)
  (export
   (init 1)
   (start-link 0)))

(defun start-link ()
  "Start and register the graffeo-mcp supervisor."
  (supervisor:start_link (tuple 'local 'graffeo-mcp-sup)
                         'graffeo-mcp-sup
                         '()))

(defun init (_args)
  "one_for_one supervisor with a single permanent graph worker child."
  (let ((sup-flags (map 'strategy 'one_for_one
                        'intensity 5
                        'period 10))
        (graph-child (map 'id      'graffeo-mcp-graph
                          'start   (tuple 'graffeo-mcp-graph 'start-link '())
                          'restart 'permanent
                          'type    'worker
                          'modules (list 'graffeo-mcp-graph))))
    (tuple 'ok (tuple sup-flags (list graph-child)))))

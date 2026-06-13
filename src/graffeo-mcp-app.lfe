;;;; OTP application callback for the graffeo-mcp application.

(defmodule graffeo-mcp-app
  (behaviour application)
  (export
   (start 2)
   (stop 1)))

(defun start (_type _args)
  "Start the graffeo-mcp supervision tree."
  (graffeo-mcp-sup:start-link))

(defun stop (_state)
  "Stop the graffeo-mcp application."
  'ok)

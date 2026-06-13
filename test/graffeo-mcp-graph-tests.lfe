;;;; Tests for graffeo-mcp-graph gen_server.
;;;;
;;;; F-17/F-18 (full 1,664-card ingest) are deferred — they require
;;;; `make fetch-cards` to populate priv/concept-cards/ first.

(defmodule graffeo-mcp-graph-tests
  (behaviour ltest-unit))

(include-lib "ltest/include/ltest-macros.lfe")

;;; ========================================
;;; Tests
;;; ========================================

(deftest start-stores-graph-in-persistent-term
  "Starting the gen_server stores a graph handle in persistent_term."
  (let ((_ (case (erlang:whereis 'graffeo-mcp-graph)
              ('undefined 'ok)
              (pid (gen_server:stop pid)))))
    (try
      (progn
        (graffeo-mcp-graph:start-link)
        (let ((graph (persistent_term:get (tuple 'graffeo_mcp 'graph)
                                          'not-set)))
          (is-not-equal 'not-set graph)))
      (after
        (case (erlang:whereis 'graffeo-mcp-graph)
          ('undefined 'ok)
          (pid (gen_server:stop pid)))))))

(deftest get-graph-returns-handle
  "get-graph/0 returns {ok, Graph} with the stored handle."
  (let ((_ (case (erlang:whereis 'graffeo-mcp-graph)
              ('undefined 'ok)
              (pid (gen_server:stop pid)))))
    (try
      (progn
        (graffeo-mcp-graph:start-link)
        (case (graffeo-mcp-graph:get-graph)
          ((tuple 'ok _graph) (is 'true))
          (other (is-equal (tuple 'ok 'graph) other))))
      (after
        (case (erlang:whereis 'graffeo-mcp-graph)
          ('undefined 'ok)
          (pid (gen_server:stop pid)))))))

(deftest graph-stats-returns-counts
  "graph-stats/0 returns {ok, #{vertices => N, edges => M}}."
  (let ((_ (case (erlang:whereis 'graffeo-mcp-graph)
              ('undefined 'ok)
              (pid (gen_server:stop pid)))))
    (try
      (progn
        (graffeo-mcp-graph:start-link)
        (case (graffeo-mcp-graph:graph-stats)
          ((tuple 'ok stats)
           (progn
             (is (maps:is_key 'vertices stats))
             (is (maps:is_key 'edges stats))))
          (other (is-equal (tuple 'ok 'stats) other))))
      (after
        (case (erlang:whereis 'graffeo-mcp-graph)
          ('undefined 'ok)
          (pid (gen_server:stop pid)))))))

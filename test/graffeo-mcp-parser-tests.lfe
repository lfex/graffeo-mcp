;;;; Tests for graffeo-mcp-parser.

(defmodule graffeo-mcp-parser-tests
  (behaviour ltest-unit))

(include-lib "ltest/include/ltest-macros.lfe")

;;; ========================================
;;; Helpers
;;; ========================================

(defun fixture-path ()
  "test/fixtures/test-card.md")

(defun no-frontmatter ()
  #"# Just a heading\n\nNo frontmatter here.")

(defun missing-field ()
  #"---\nslug: gen-server\nconcept: gen_server Behaviour\n---\n")

;;; ========================================
;;; Tests
;;; ========================================

(deftest parse-file-ok
  "parse-file returns {ok, Card} with all required fields for a valid card."
  (case (graffeo-mcp-parser:parse-file (fixture-path))
    ((tuple 'ok card)
     (progn
       (is-equal #"gen-server"       (mref card 'slug))
       (is-equal #"gen_server Behaviour" (mref card 'concept))
       (is-equal #"otp-behaviours"   (mref card 'category))
       (is-equal #"foundational"     (mref card 'tier))
       (is-equal #"OTP Design Principles" (mref card 'source))
       (is-equal #"otp-design-principles" (mref card 'source_slug))
       (is (lists:member #"behaviour" (mref card 'prerequisites)))
       (is (lists:member #"gen-statem" (mref card 'contrasts_with)))))
    (other
     (is-equal (tuple 'ok 'card) other))))

(deftest parse-string-no-frontmatter
  "parse-string returns {error, _} when the input has no frontmatter delimiter."
  (case (graffeo-mcp-parser:parse-string (no-frontmatter))
    ((tuple 'error _) (is 'true))
    (other            (is-equal (tuple 'error 'something) other))))

(deftest parse-string-missing-required-field
  "parse-string returns {error, {missing-field, _}} when a required field is absent."
  (case (graffeo-mcp-parser:parse-string (missing-field))
    ((tuple 'error (tuple 'missing-field _)) (is 'true))
    (other (is-equal (tuple 'error (tuple 'missing-field '_)) other))))

(deftest parse-file-nonexistent-returns-error
  "parse-file returns {error, {read-failed, _, _}} for a path that does not exist."
  (case (graffeo-mcp-parser:parse-file "test/fixtures/no-such-file.md")
    ((tuple 'error (tuple 'read-failed _ _)) (is 'true))
    (other (is-equal (tuple 'error (tuple 'read-failed '_ '_)) other))))

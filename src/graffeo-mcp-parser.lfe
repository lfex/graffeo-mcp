;;;; Concept card YAML frontmatter parser.

(defmodule graffeo-mcp-parser
  (export
   (parse-file 1)
   (parse-string 1)))

(defun parse-file (path)
  "Read path and parse it as a concept card. Returns {ok, Card} | {error, Reason}."
  (case (file:read_file path)
    ((tuple 'ok bin) (parse-string bin))
    ((tuple 'error reason)
     (tuple 'error (tuple 'read-failed path reason)))))

(defun parse-string (bin)
  "Parse a binary containing a concept card. Returns {ok, Card} | {error, Reason}."
  (let ((lines (binary:split bin #"\n" '(global))))
    (case (extract-frontmatter lines)
      ((tuple 'ok fm-lines)
       (let ((props (parse-fm-lines fm-lines)))
         (build-card props)))
      ((= (tuple 'error _) err)
       err))))

;;; ========================================
;;; Frontmatter extraction
;;; ========================================

(defun extract-frontmatter
  (((cons (binary "---" (_tail binary)) rest))
   (collect-until-closing rest '()))
  ((_)
   (tuple 'error 'no-opening-delimiter)))

(defun collect-until-closing
  ((() acc)
   (tuple 'error (tuple 'no-closing-delimiter (length acc))))
  (((cons (binary "---" (_tail binary)) _) acc)
   (tuple 'ok (lists:reverse acc)))
  (((cons line rest) acc)
   (collect-until-closing rest (cons line acc))))

;;; ========================================
;;; Line classification
;;; ========================================

(defun classify-line
  ((#"")             'empty)
  (((binary "# ===" (_rest binary))) 'section-header)
  (((binary "- " (item-raw binary)))
   (tuple 'list-item (unquote-bin (string:trim item-raw))))
  ((line)
   (case (binary:split line #": ")
     ((list key value)
      (parse-kv (string:trim key) (string:trim value)))
     ((list maybe-kv)
      (case (binary:split maybe-kv #":")
        ((list key #"") (tuple 'kv key '()))
        (_ 'empty))))))

(defun parse-kv
  ((key #"[]") (tuple 'kv key '()))
  ((key value) (tuple 'kv key (unquote-bin value))))

(defun unquote-bin
  (((binary "\"" (rest binary)))
   (case (binary:last rest)
     (34 (binary:part rest 0 (- (byte_size rest) 1)))
     (_ rest)))
  ((bin) bin))

;;; ========================================
;;; Frontmatter key-value accumulation
;;; ========================================

(defun parse-fm-lines (lines)
  (parse-fm-lines lines 'undefined (map)))

(defun parse-fm-lines
  ((() _current-key acc) acc)
  (((cons line rest) current-key acc)
   (let ((trimmed (string:trim line)))
     (case (classify-line trimmed)
       ('empty (parse-fm-lines rest current-key acc))
       ('section-header (parse-fm-lines rest current-key acc))
       ((tuple 'list-item value)
        (case current-key
          ('undefined (parse-fm-lines rest current-key acc))
          (key
           (let* ((existing (maps:get key acc '()))
                  (new-list (case (is_list existing)
                              ('true (lists:append existing (list value)))
                              ('false (list value)))))
             (parse-fm-lines rest key (mset acc key new-list))))))
       ((tuple 'kv key value)
        (parse-fm-lines rest key (mset acc key value)))))))

;;; ========================================
;;; Card construction
;;; ========================================

(defun build-card (props)
  "Validate required fields and return {ok, Card} or {error, {missing-field, Key}}."
  (let ((required (list #"slug" #"concept" #"category"
                        #"tier" #"source" #"source_slug")))
    (case (check-required required props)
      ('ok
       (tuple 'ok
              (map 'slug          (get-bin #"slug" props)
                   'concept       (get-bin #"concept" props)
                   'category      (get-bin #"category" props)
                   'tier          (get-bin #"tier" props)
                   'source        (get-bin #"source" props)
                   'source_slug   (get-bin #"source_slug" props)
                   'prerequisites (get-list #"prerequisites" props)
                   'extends       (get-list #"extends" props)
                   'related       (get-list #"related" props)
                   'contrasts_with (get-list #"contrasts_with" props))))
      ((= (tuple 'error _) err) err))))

(defun check-required
  ((() _props) 'ok)
  (((cons key rest) props)
   (case (maps:is_key key props)
     ('true (check-required rest props))
     ('false (tuple 'error (tuple 'missing-field key))))))

(defun get-bin (key props)
  (let ((v (maps:get key props #"")))
    (case v
      (b (when (is_binary b)) b)
      (l (when (is_list l)) (iolist_to_binary (lists:join #", " l)))
      (_ #""))))

(defun get-list (key props)
  (let ((v (maps:get key props '())))
    (case v
      (l (when (is_list l)) l)
      (b (when (andalso (is_binary b) (=/= b #""))) (list b))
      (_ '()))))

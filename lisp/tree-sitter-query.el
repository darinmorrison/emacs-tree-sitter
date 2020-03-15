;; tree-sitter-query.el --- tools for running queries live -*- lexical-binding: t; coding: utf-8 -*-

;; Copyright (C) 2020  Tuấn-Anh Nguyễn
;;
;; Author: Jorge Javier Araya Navarro <jorgejavieran@yahoo.com.mx>

;; This file contains other debug utilities for building queries and see
;; results in a target buffer

;; Code:

(require 'scheme)
(require 'cl-lib)
(require 'tree-sitter)
(require 'tree-sitter-query-faces)

(define-derived-mode tree-sitter-query-mode prog-mode "ts-query-builder"
  "Major mode for building tree-sitter queries and testing them live"
  :syntax-table scheme-mode-syntax-table
  :abbrev-table scheme-mode-abbrev-table)

(defconst tree-sitter-query-builder-buffer-name "*tree-sitter-query-builder*"
  "Name of the builder buffer")

(defvar tree-sitter-query--target-buffer nil
  "Target buffer to run the queries against.")

(defvar tree-sitter-query--match-highlight-number -1
  "Counter that keeps track of the number of the match color face.")

(defun tree-sitter-query--get-next-match-highlight-color ()
  "Return the symbol for the next highlight match face in number order."
  (setq tree-sitter-query--match-highlight-number
        (mod (cl-incf tree-sitter-query--match-highlight-number) tree-sitter-query-faces-list-length))
  (elt tree-sitter-query-faces-match-list tree-sitter-query--match-highlight-number))

(defun tree-sitter-query--highlight-node (node match-face)
  "Highlight a NODE match in the current buffer with face MATCH-FACE."
  (let* ((capture-name (car node))
         (captured-node (cdr node))
         (node-start (ts-node-start-position captured-node))
         (node-end (ts-node-end-position captured-node))
         (overlay-added (make-overlay node-start node-end)))
    ;; ensure it is deleted automatically when the overlay becomes empty
    (overlay-put overlay-added 'evaporate t)
    ;; set the match-face as the face of the overlay
    (overlay-put overlay-added 'face match-face)
    ;; put the name of the capture in the help-echo, if any
    (unless (string= capture-name "")
      (overlay-put overlay-added 'help-echo capture-name))))

(defun tree-sitter-query--eval-query (patterns)
  "Evaluate a query PATTERNS against the target buffer."
  (with-current-buffer tree-sitter-query--target-buffer
    ;; clean the target buffer of overlays
    (remove-overlays)
    (let* ((query (ts-make-query tree-sitter-language patterns))
           (root-node (ts-root-node tree-sitter-tree))
           (matches (ts-query-captures query root-node nil nil))
           (nextface))
      (if (= (length matches) 0)
          (message "no matches found")
        ;; reset counter
        (setq tree-sitter-query--match-highlight-number -1)
        ;; iterate all matches and highlight them with an underline
        (cl-loop
         for submatches across matches
         do (cl-loop
             for match on submatches
             do (setq nextface (tree-sitter-query--get-next-match-highlight-color))
             (tree-sitter-query--highlight-node match nextface)))))))

(defun tree-sitter-query--after-change (&rest args)
  "Run evaluation of pattern in current buffer for every change made by the user, ignoring ARGS."
  (with-current-buffer (get-buffer tree-sitter-query-builder-buffer-name)
    (let ((pattern (buffer-substring-no-properties (point-min) (point-max))))
      (with-demoted-errors
          (tree-sitter-query--eval-query pattern)))))

(defun tree-sitter-query--clean-target-buffer ()
  "Remove all overlays if the builder buffer happens to be killed"
  (with-current-buffer tree-sitter-query--target-buffer
    (remove-overlays)))

(defun tree-sitter-query-builder ()
  "Provide means for developers to write and test tree-sitter queries.

The buffer on focus when the command is called is set as the target buffer"
  (interactive)
  (let* ((target-buffer (current-buffer))
         (builder-buffer (get-buffer-create tree-sitter-query-builder-buffer-name))
         (builder-window-is-visible (get-buffer-window builder-buffer)))
    (when (eq target-buffer builder-buffer)
      (user-error "This buffer cannot be use as target buffer"))
    (unless builder-window-is-visible
      (unless (display-buffer-in-side-window
               builder-buffer
               '((side . bottom)
                 (window-height . 7))))
      (user-error "No enough space available for query builder window"))
    (with-current-buffer target-buffer
      (unless tree-sitter-mode
        (tree-sitter-mode))
      (add-hook 'after-change-functions 'tree-sitter-query--after-change nil :local)
      (setq tree-sitter-query--target-buffer target-buffer))
    (with-current-buffer builder-buffer
      (erase-buffer)
      (tree-sitter-query-mode)
      (add-hook 'after-change-functions 'tree-sitter-query--after-change nil :local)
      (add-hook 'kill-buffer-hook 'tree-sitter-query--clean-target-buffer nil :local))
    (setf tree-sitter-query--target-buffer target-buffer)
    ;; switch focus to the query builder window
    (select-window (get-buffer-window builder-buffer))))

(provide 'tree-sitter-query)
;;; tree-sitter-query.el ends here

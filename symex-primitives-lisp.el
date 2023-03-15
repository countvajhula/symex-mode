;;; symex-primitives-lisp.el --- An evil way to edit Lisp symbolic expressions as trees -*- lexical-binding: t -*-

;; URL: https://github.com/drym-org/symex.el

;; This program is "part of the world," in the sense described at
;; https://drym.org.  From your perspective, this is no different than
;; MIT or BSD or other such "liberal" licenses that you may be
;; familiar with, that is to say, you are free to do whatever you like
;; with this program.  It is much more than BSD or MIT, however, in
;; that it isn't a license at all but an idea about the world and how
;; economic systems could be set up so that everyone wins.  Learn more
;; at drym.org.
;;
;; This work transcends traditional legal and economic systems, but
;; for the purposes of any such systems within which you may need to
;; operate:
;;
;; This is free and unencumbered software released into the public domain.
;; The authors relinquish any copyright claims on this work.
;;

;;; Commentary:

;; Primitive navigations using third party libraries.  This layer of primitives
;; can be swapped out without changing the higher-level functionality provided
;; by the Symex DSL.  In the future it may make sense to directly operate on
;; an annotated representation of the AST here containing a mapping to buffer
;; positions and other metadata relevant for editing purposes.

;;; Code:


(require 'paredit)
(require 'symex-data)

;;;;;;;;;;;;;;;;;;
;;; PRIMITIVES ;;;
;;;;;;;;;;;;;;;;;;

;;; User Interface

(defun symex-lisp--adjust-point ()
  "Helper to adjust point to indicate the correct symex."
  (unless (or (bobp)
              (symex-lisp--point-at-start-p)
              (looking-back "[,'`]" (line-beginning-position))
              (save-excursion (backward-char)  ; just inside symex
                              (or (symex-left-p)
                                  ;; this is to exclude the case where
                                  ;; we're inside a string, "|abc"
                                  ;; which "inverts" the code structure
                                  ;; and causes unexpected behavior when
                                  ;; navigating using Emacs's built-in
                                  ;; primitive symex motions. Unlike normal
                                  ;; forms, opening and closing delimiters
                                  ;; are not distinguished for strings and
                                  ;; so we can't specifically check for
                                  ;; "open quote," with the result that
                                  ;; in the case "abc"|, we don't always
                                  ;; select the right symex the way we
                                  ;; would with (abc)|.
                                  (symex-string-p))))
    (condition-case nil
        (backward-sexp)
      (error nil))))

;;; Predicates

(defmacro symex-lisp--if-stuck (do-what operation &rest body)
  "Attempt OPERATION and if it fails, then do DO-WHAT."
  (let ((orig-pt (gensym)))
    `(let ((,orig-pt (point)))
       ,operation
       (if (= ,orig-pt (point))
           ,do-what
         ,@body))))

(defun symex-lisp--point-at-root-symex-p ()
  "Check if point is at a root symex."
  (save-excursion
    (symex-lisp--if-stuck t
                          (symex-lisp--go-down)
                          nil)))

(defun symex-lisp--point-at-first-symex-p ()
  "Check if point is at the first symex at some level."
  (save-excursion
    (symex-lisp--if-stuck t
                          (symex-lisp--backward)
                          nil)))

(defun symex-lisp--point-at-last-symex-p ()
  "Check if point is at the last symex at some level."
  (save-excursion
    (symex-lisp--if-stuck t
                          (symex-lisp--forward)
                          nil)))

(defun symex-lisp--point-at-final-symex-p ()
  "Check if point is at the last symex in the buffer."
  (and (symex-lisp--point-at-last-symex-p)
       (symex-lisp--point-at-root-symex-p)))

(defun symex-lisp--point-at-initial-symex-p ()
  "Check if point is at the first symex in the buffer."
  ;; this is used in the primitive motions, so it cannot
  ;; be defined in terms of them, as the other predicates
  ;; above are
  (save-excursion
    (condition-case nil
        (or (bobp)
            (progn (backward-sexp 1)
                   (not (thing-at-point 'sexp))))
      (error nil))))

(defun symex-lisp--point-at-start-p ()
  "Check if point is at the start of a symex."
  (and (not (eolp))
       (not (looking-at-p symex--re-right))
       (or (symex-left-p)                           ; |(*
           (symex--special-left-p)                  ; |'(*
           ;; looking at the start of any non-whitespace:
           (and (not (looking-at-p "[[:space:]]"))
                (or (bolp)                          ; ^|.
                    (looking-back "[[:space:]]"     ; _|.
                                  (line-beginning-position))
                    (save-excursion (backward-char)
                                    (symex-string-p))
                    (looking-back symex--re-left    ; (*|.
                                  (line-beginning-position)))))))

(defun symex-lisp--point-at-end-p ()
  "Check if point is at the end of a symex."
  (condition-case nil
      (save-excursion
        (forward-char)
        (symex-right-p))
    (error nil)))

;; From Lispy
(defvar symex--re-left "[([{]"
  "Opening delimiter.")

;; From Lispy
(defvar symex--re-right "[])}]"
  "Closing delimiter.")

(defvar symex--re-comment-line "^[[:space:]]*;"
  "A comment line.")

(defvar symex--re-empty-line "^$"
  "An empty line.")

(defvar symex--re-blank-line "^[[:space:]]*$"
  "A blank line, either empty or containing only whitespace.")

(defvar symex--re-whitespace "[[:space:]|\n]*"
  "Whitespace that may extend over many lines.")

(defvar symex--re-symex-line "^[[:space:]]*[^;[:space:]\n]"
  "A line that isn't blank and isn't a comment line.")

(defvar symex--re-racket-syntax-object
  (concat "#['`]" symex--re-left))

(defvar symex--re-splicing-unquote
  (concat ",@" symex--re-left))

(defvar symex--re-racket-unquote-syntax
  (concat "#," symex--re-left))

(defvar symex--re-racket-splicing-unsyntax
  (concat "#,@" symex--re-left))

(defvar symex--re-quoted-list
  (concat "['`]" symex--re-left))

(defvar symex--re-unquoted-list
  (concat "," symex--re-left))

(defvar symex--re-clojure-deref-reader-macro
  (concat "@" symex--re-left))

(defvar symex--re-clojure-literal-lambda
  (concat "#" symex--re-left))

;; based on lispy-left-p
(defun symex-left-p ()
  "Check if we're at (i.e. after) an opening delimiter."
  (looking-at symex--re-left))

;; based on lispy-right-p
(defun symex-right-p ()
  "Check if we're at (i.e. after) a closing delimiter."
  (looking-back symex--re-right
                (line-beginning-position)))

;; From https://www.gnu.org/software/emacs/manual/html_node/efaq/Matching-parentheses.html
(defun symex-other ()
  "Move point to the other delimiter in a matching pair."
  (cond ((looking-at "\\s(") (forward-list 1) (backward-char 1))
        ((looking-at "\\s)") (forward-char 1) (backward-list 1))))

(defun symex-comment-line-p ()
  "Check if we're currently at the start of a comment line."
  (save-excursion
    (back-to-indentation)
    (looking-at-p ";")))

(defun symex-inline-comment-p ()
  "Check if there is an inline comment following point."
  (looking-at-p "[[:space:]]*;"))

(defun symex-string-p ()
  "Check if the symex is a string."
  (looking-at-p "\""))

(defun symex-opening-round-p ()
  "Check if point is at an opening parenthesis."
  (looking-at-p "("))

(defun symex-opening-square-p ()
  "Check if point is at an opening square bracket."
  (looking-at-p "\\["))

(defun symex-opening-curly-p ()
  "Check if point is at an opening curly bracket."
  (looking-at-p "{"))

(defun symex-empty-list-p ()
  "Check if we're looking at an empty list."
  (looking-at-p
   (concat symex--re-left
           symex--re-whitespace
           symex--re-right)))

(defun symex-empty-string-p ()
  "Check if we're looking at an empty list."
  (save-excursion
    (and (symex-string-p)
         (progn (forward-char 1)
                (symex-string-p)))))

(defun symex--racket-syntax-object-p ()
  "Check if the symex is a racket syntax object."
  (looking-at-p symex--re-racket-syntax-object))

(defun symex--splicing-unquote-p ()
  "Check if the symex is a spliced unquoted list."
  (looking-at-p symex--re-splicing-unquote))

(defun symex--racket-unquote-syntax-p ()
  "Check if the symex is a racket unquoted syntax list."
  (looking-at-p symex--re-racket-unquote-syntax))

(defun symex--racket-splicing-unsyntax-p ()
  "Check if the symex is a racket spliced unsyntaxed list."
  (looking-at-p symex--re-racket-splicing-unsyntax))

(defun symex--quoted-list-p ()
  "Check if the symex is a quoted list."
  (looking-at-p symex--re-quoted-list))

(defun symex--unquoted-list-p ()
  "Check if the symex is an unquoted list."
  (looking-at-p symex--re-unquoted-list))

(defun symex--clojure-deref-reader-macro-p ()
  "Check if the symex is a Clojure deref reader macro."
  (looking-at-p symex--re-clojure-deref-reader-macro))

(defun symex--clojure-literal-lambda-p ()
  "Check if the symex is a Clojure anonymous function literal."
  (looking-at-p symex--re-clojure-literal-lambda))

(defun symex--special-left-p ()
  "Check if point is at a \"special\" opening delimiter.

This includes any special cases that should be treated as lists for
the purpose of movement, such as quoted lists and Lisp flavor-specific
special forms.  This may be the sort of information that's best
obtained from an AST-aware primitives layer, rather than parsed
as special cases here."
  (or (symex--quoted-list-p)
      (symex--unquoted-list-p)
      (symex--racket-syntax-object-p)
      (symex--splicing-unquote-p)
      (symex--racket-splicing-unsyntax-p)
      (symex--racket-unquote-syntax-p)
      (symex--clojure-deref-reader-macro-p)
      (symex--clojure-literal-lambda-p)))

(defun symex--re-or (&rest args)
  "An OR combinator for regular expression strings."
  (concat (string-join args "\\|") ))

(defun symex--form-offset ()
  "Get the offset for entry into the form."
  (cond ((symex--racket-splicing-unsyntax-p) 4)
        ((or (symex--racket-syntax-object-p)
             (symex--racket-unquote-syntax-p)
             (symex--splicing-unquote-p))
         3)
        ((or (symex--quoted-list-p)
             (symex--unquoted-list-p)
             (symex--clojure-deref-reader-macro-p)
             (symex--clojure-literal-lambda-p))
         2)
        ((or (symex-form-p)
             (symex-string-p)) 1)
        (t 0)))

(defun symex--special-empty-list-p ()
  "Check if we're looking at a \"special\" empty list."
  (or (save-excursion
        (and (symex--racket-splicing-unsyntax-p)
             (progn (forward-char 4)
                    (looking-at-p (concat symex--re-whitespace symex--re-right)))))
      (save-excursion
        (and (or (symex--racket-syntax-object-p)
                 (symex--racket-unquote-syntax-p)
                 (symex--splicing-unquote-p))
             (progn (forward-char 3)
                    (looking-at-p (concat symex--re-whitespace symex--re-right)))))
      (save-excursion
        (and (or (symex--quoted-list-p)
                 (symex--unquoted-list-p)
                 (symex--clojure-deref-reader-macro-p)
                 (symex--clojure-literal-lambda-p))
             (progn (forward-char 2)
                    (looking-at-p (concat symex--re-whitespace symex--re-right)))))))

(defun symex-atom-p ()
  "Check if the symex is an atom."
  (not (symex-left-p)))

(defun symex-form-p ()
  "Check if the symex is a composite expression, i.e. a nonatom."
  (not (symex-atom-p)))

(defun symex--intervening-comment-line-p (start end)
  "Check if there is a comment line between the positions START and END."
  (save-excursion
    (goto-char start)
    (catch 'stop
      (when (symex-comment-line-p)
        (throw 'stop (progn (back-to-indentation)
                            (point))))
      (while (not (= (line-number-at-pos)
                     (line-number-at-pos end)))
        (forward-line 1)
        (when (symex-comment-line-p)
          (throw 'stop (progn (back-to-indentation)
                              (point))))))))

;;; Navigation

(defun symex-lisp-select-nearest ()
  "Select the appropriate symex nearest to point."
  (cond ((and (not (eobp))
              (save-excursion (forward-char) (symex-right-p))) ; |)
         (symex-other))
        ((condition-case nil  ; (thing-at-point string) raises error at EOB
             (thing-at-point 'string)
           (error nil))       ; "som|e string"
         (beginning-of-thing 'string))
        ((thing-at-point 'sexp)       ; som|ething
         (beginning-of-thing 'sexp))
        (t (symex-lisp--if-stuck (symex-lisp--backward)
                                 (symex-lisp--forward)))))

(defun symex-lisp--get-starting-point ()
  "Get the point value at the start of the current symex."
  (save-excursion
    (unless (symex--point-at-start-p)
      (condition-case nil
          (backward-sexp)
        (error nil)))
    (point)))

(defun symex-lisp--get-end-point-helper (count)
  "Helper to get the point value after COUNT symexes.

If the containing expression terminates earlier than COUNT
symexes, returns the end point of the last one found.

Note that this mutates point - it should not be called directly."
  (if (= count 0)
      (point)
    (condition-case nil
        (forward-sexp)
      (error (point)))
    (symex-lisp--get-end-point-helper (1- count))))

(defun symex-lisp--get-end-point (count)
  "Get the point value after COUNT symexes.

If the containing expression terminates earlier than COUNT
symexes, returns the end point of the last one found."
  (save-excursion
    (symex-lisp--get-end-point-helper count)))

(defun symex-lisp--point-height-offset ()
  "Compute the height offset of the current symex.

This is measured from the lowest symex indicated by point. For
symex-oriented languages like Lisp, this is always zero."
  0)

(defun symex-lisp--forward-one ()
  "Forward one symex."
  (let ((original-location (point))
        (result 0))
    (if (and (thing-at-point 'sexp)
             (not (or (eolp)
                      (looking-at-p "[[:space:]]"))))
        (condition-case nil
            (progn (forward-sexp 2)
                   (setq result 2))
          (error (condition-case nil
                     (progn (forward-sexp 1)
                            (setq result 1))
                   (error (setq result 0)))))
      (condition-case nil
          (progn (forward-sexp 1)
                 (setq result 1))
        (error (setq result 0))))
    (condition-case nil
        (progn (backward-sexp 1)
               (setq result (1- result)))
      (error nil))
    (let ((current-location (point)))
      (when (= original-location current-location)
        ;; happens at end of buffer
        (setq result 0))
      (when (< current-location original-location)
        ;; happens in whitespace at end of buffer
        ;; where forward-sexp goes to eob
        ;; better to revise the above logic so that
        ;; point does not go backwards.
        (goto-char original-location)
        (setq result 0))
      (when (and (< original-location current-location)
                 (= result 0))
        ;; happens when point is in whitespace like
        ;; a |  b
        ;; and the result is
        ;; a   |b
        ;; but the logic above concludes there has been
        ;; no movement.
        ;; probably better to revise the above logic to
        ;; explicitly reason about the source text instead
        ;; of relying on implicit assumptions about the
        ;; behavior of forward-sexp - maybe use thing-at-point
        (setq result 1)))
    result))

(defun symex-lisp--forward (&optional count)
  "Forward symex.

Go forward COUNT times, defaulting to one.

This is a primitive operation that is provided below the public
abstraction level of symex.el.  It currently uses built-in Emacs
commands and third party tools like paredit to perform its function.
This procedure is not to be used except in the low-level internals
of symex mode (use the public `symex-go-forward` instead)."
  (interactive)
  (let ((count (or count 1))
        (result 0))
    (dotimes (_ count)
      (let ((res (symex-lisp--forward-one)))
        (setq result (+ res result))))
    (when (> result 0)
      (symex-make-move result 0))))

(defun symex-lisp--backward-one ()
  "Backward one symex."
  (let ((result 0))
    (unless (symex-lisp--point-at-initial-symex-p)
      (condition-case nil
          (progn (backward-sexp 1)
                 (setq result (1+ result)))
        (error nil)))
    result))

(defun symex-lisp--backward (&optional count)
  "Backward symex.

Go backward COUNT times, defaulting to one.

This is a primitive operation that is provided below the public
abstraction level of symex.el.  It currently uses built-in Emacs
commands and third party tools like paredit to perform its function.
This procedure is not to be used except in the low-level internals
of symex mode (use the public `symex-go-backward` instead)."
  (interactive)
  (let ((count (or count 1))
        (result 0))
    (dotimes (_ count)
      (let ((res (symex-lisp--backward-one)))
        (setq result (+ res result))))
    (when (> result 0)
      (symex-make-move (- result) 0))))

(defun symex--find-next ()
  "Find the next symex."
  (re-search-forward symex--re-symex-line)
  (back-to-indentation))

(defun symex-lisp--go-to-next-non-whitespace-char ()
  "Move point to the next non-whitespace character.

If the current character is non-whitespace, point is not moved."
  (unless (looking-at-p "[^[:space:]\n]")
    (re-search-forward "[^[:space:]\n]")
    ;; since the re search goes to the end of the match
    (backward-char)))

(defun symex-lisp--go-up-by-one ()
  "Go up one level."
  (let ((result 1))
    (if (or (symex-empty-list-p)
            (symex--special-empty-list-p))
        (setq result 0)
      (cond ((symex-left-p) (forward-char))
            ;; note that at least some symex features would benefit by
            ;; treating these special cases as "symex-left-p" but it
            ;; would likely be too much special case handling to be
            ;; worth it to support those cases naively, without an AST
            ((or (symex--racket-syntax-object-p)
                 (symex--splicing-unquote-p)
                 (symex--racket-unquote-syntax-p))
             (forward-char 3))
            ((symex--racket-splicing-unsyntax-p)
             (forward-char 4))
            ((or (symex--quoted-list-p)
                 (symex--unquoted-list-p)
                 (symex--clojure-deref-reader-macro-p)
                 (symex--clojure-literal-lambda-p))
             (forward-char 2))
            (t (setq result 0)))
      ;; find first non-whitespace character
      (symex-lisp--go-to-next-non-whitespace-char))
    result))

(defun symex-lisp--go-up (&optional count)
  "Go up to a higher level.

Go up COUNT times, defaulting to one.

This is a primitive operation that is provided below the public
abstraction level of symex.el.  It currently uses built-in Emacs
commands and third party tools like paredit to perform its function.
This procedure is not to be used except in the low-level internals
of symex mode (use the public `symex-go-up` instead)."
  (interactive)
  (let ((count (or count 1))
        (result 0))
    (dotimes (_ count)
      (let ((res (symex-lisp--go-up-by-one)))
        (setq result (+ res result))))
    (when (> result 0)
      (symex-make-move 0 result))))

(defun symex-lisp--go-down-by-one ()
  "Go down one level."
  (condition-case nil
      (progn (paredit-backward-up 1)
             ;; one-off - better to recognize these as delimiters
             ;; at the AST level
             (cond ((looking-back "#['`,]" (line-beginning-position))
                    (backward-char 2))
                   ((looking-back "[#'`,]" (line-beginning-position))
                    (backward-char))
                   ((looking-back "#,@" (line-beginning-position))
                    (backward-char 3))
                   ((looking-back ",@" (line-beginning-position))
                    (backward-char 2))
                   ((looking-back "@" (line-beginning-position))
                    (backward-char)))
             1)
    (error 0)))

(defun symex-lisp--go-down (&optional count)
  "Go down to a lower level.

Go down COUNT times, defaulting to one.

This is a primitive operation that is provided below the public
abstraction level of symex.el.  It currently uses built-in Emacs
commands and third party tools like paredit to perform its function.
This procedure is not to be used except in the low-level internals
of symex mode (use the public `symex-go-down` instead)."
  (interactive)
  (let ((count (or count 1))
        (result 0))
    (dotimes (_ count)
      (let ((res (symex-lisp--go-down-by-one)))
        (setq result (+ res result))))
    (when (> result 0)
      (symex-make-move 0 (- result)))))

;;; Transformations

(defun symex--join-to-next ()
  "Join current position to the next symex, eliminating whitespace.

If there is an intervening comment line, then join only up to that
line."
  (let* ((start (point))
         (end (save-excursion (symex-lisp--forward)
                              (point)))
         (comment-line-position
          (symex--intervening-comment-line-p start end)))
    (if comment-line-position
        (delete-region start comment-line-position)
      (delete-region start end))))

(defun symex--join-to-match (pattern)
  "Join current position to the next position matching PATTERN.

This eliminates whitespace between the original position and the found
match."
  (condition-case nil
      (let* ((start (point))
             (end (save-excursion (re-search-forward pattern)
                                  (match-beginning 0))))
        (delete-region start end))))

;;; Utilities

(defun symex-lisp-exit ()
  "Take necessary actions upon Symex mode exit.

There are no Lisp-specific actions to take, at the present time, so
this function does nothing. It is only here for completeness and
symmetry with the tree-sitter primitives."
  nil)


(provide 'symex-primitives-lisp)
;;; symex-primitives-lisp.el ends here

;;; symex-primitives.el --- An evil way to edit Lisp symbolic expressions as trees -*- lexical-binding: t -*-

;; URL: https://github.com/countvajhula/symex.el

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


(require 'lispy)
(require 'paredit)
(require 'symex-data)

;;;;;;;;;;;;;;;;;;
;;; PRIMITIVES ;;;
;;;;;;;;;;;;;;;;;;

;;; Predicates

(defmacro symex-if-stuck (do-what operation &rest body)
  "Attempt OPERATION and if it fails, then do DO-WHAT."
  `(let ((orig-pt (point)))
     ,operation
     (if (= orig-pt (point))
         ,do-what
       ,@body)))

(defun symex--point-at-root-symex-p ()
  "Check if point is at a root symex."
  (save-excursion
    (symex-if-stuck t
                    (symex--exit)
                    nil)))

(defun symex--point-at-first-symex-p ()
  "Check if point is at the first symex at some level."
  (save-excursion
    (symex-if-stuck t
                    (symex--backward)
                    nil)))

(defun symex--point-at-last-symex-p ()
  "Check if point is at the last symex at some level."
  (save-excursion
    (symex-if-stuck t
                    (symex--forward)
                    nil)))

(defun symex--point-at-final-symex-p ()
  "Check if point is at the last symex in the buffer."
  (save-excursion
    (symex-if-stuck (progn (symex-if-stuck t
                                           (symex--exit)
                                           nil))
                    (symex--forward)
                    nil)))

(defun symex--point-at-initial-symex-p ()
  "Check if point is at the first symex in the buffer."
  (save-excursion
    (condition-case nil
        (or (bobp)
            (progn (backward-sexp 1)
                   (not (thing-at-point 'sexp))))
      (error nil))))

(defun symex--point-at-start-p ()
  "Check if point is at the start of a symex."
  (and (not (eolp))
       (not (looking-at-p lispy-right))
       (or (lispy-left-p)                           ; |(*
           (symex--special-left-p)                  ; |'(*
           ;; looking at the start of any non-whitespace:
           (and (not (looking-at-p "[[:space:]]"))
                (or (bolp)                          ; ^|.
                    (looking-back "[[:space:]]"     ; _|.
                                  (line-beginning-position))
                    (looking-back lispy-left        ; (*|.
                                  (line-beginning-position)))))))

(defvar symex--re-comment-line "^[[:space:]]*;"
  "A comment line.")

(defvar symex--re-empty-line "^$"
  "An empty line.")

(defvar symex--re-blank-line "^[[:space:]]*$"
  "A blank line, either empty or containing only whitespace.")

(defvar symex--re-symex-line "^[[:space:]]*[^;[:space:]\n]"
  "A line that isn't blank and isn't a comment line.")

(defun symex-comment-line-p ()
  "Check if we're currently at the start of a comment line."
  (save-excursion
    (back-to-indentation)
    (looking-at-p ";")))

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
  (save-excursion
    (and (lispy-left-p)
         (progn (forward-char 2) ;; need to go forward by 2 for some reason
                (lispy-right-p)))))

(defun symex-empty-string-p ()
  "Check if we're looking at an empty list."
  (save-excursion
    (and (symex-string-p)
         (progn (forward-char 1)
                (symex-string-p)))))

(defun symex--racket-syntax-object-p ()
  "Check if the symex is a racket syntax object."
  (looking-at (concat "#['`]" lispy-left)))

(defun symex--splicing-unquote-p ()
  "Check if the symex is a spliced unquoted list."
  (looking-at (concat ",@" lispy-left)))

(defun symex--racket-unquote-syntax-p ()
  "Check if the symex is a racket unquoted syntax list."
  (looking-at (concat "#," lispy-left)))

(defun symex--racket-splicing-unsyntax-p ()
  "Check if the symex is a racket spliced unsyntaxed list."
  (looking-at (concat "#,@" lispy-left)))

(defun symex--quoted-list-p ()
  "Check if the symex is a quoted list."
  (looking-at (concat "['`]" lispy-left)))

(defun symex--unquoted-list-p ()
  "Check if the symex is an unquoted list."
  (looking-at (concat "," lispy-left)))

(defun symex--clojure-deref-reader-macro-p ()
  "Check if the symex is a Clojure deref reader macro."
  (looking-at (concat "@" lispy-left)))

(defun symex--clojure-literal-lambda-p ()
  "Check if the symex is a Clojure anonymous function literal."
  (looking-at (concat "#" lispy-left)))

(defun symex--special-left-p ()
  "Check if point is at a 'special' opening delimiter.

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

(defun symex--special-empty-list-p ()
  "Check if we're looking at a 'special' empty list."
  (or (save-excursion
        (and (symex--racket-splicing-unsyntax-p)
             (progn (forward-char 5)
                    (lispy-right-p))))
      (save-excursion
        (and (or (symex--racket-syntax-object-p)
                 (symex--racket-unquote-syntax-p)
                 (symex--splicing-unquote-p))
             (progn (forward-char 4)
                    (lispy-right-p))))
      (save-excursion
        (and (or (symex--quoted-list-p)
                 (symex--unquoted-list-p)
                 (symex--clojure-deref-reader-macro-p)
                 (symex--clojure-literal-lambda-p))
             (progn (forward-char 3)
                    (lispy-right-p))))))

(defun symex-atom-p ()
  "Check if the symex is an atom."
  (not (lispy-left-p)))

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

(defun symex--get-end-point (count)
  "Get the point value after COUNT symexes.

If the containing expression terminates earlier than COUNT
symexes, returns the end point of the last one found."
  (save-excursion
    (if (= count 0)
        (point)
      (condition-case nil
          (forward-sexp)
        (error (point)))
      (symex--get-end-point (1- count)))))

(defun symex--forward-one ()
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
        (setq result 0)))
    result))

(defun symex--forward (&optional count)
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
      (let ((res (symex--forward-one)))
        (setq result (+ res result))))
    (when (> result 0)
      (symex-make-move result 0))))

(defun symex--backward-one ()
  "Backward one symex."
  (let ((result 0))
    (unless (symex--point-at-initial-symex-p)
      (condition-case nil
          (progn (backward-sexp 1)
                 (setq result (1+ result)))
        (error nil)))
    result))

(defun symex--backward (&optional count)
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
      (let ((res (symex--backward-one)))
        (setq result (+ res result))))
    (when (> result 0)
      (symex-make-move (- result) 0))))

(defun symex--find-next ()
  "Find the next symex."
  (re-search-forward symex--re-symex-line)
  (back-to-indentation))

(defun symex--enter-one ()
  "Enter one level."
  (let ((result 1))
    (cond ((or (symex-empty-list-p)
               (symex--special-empty-list-p))
           (setq result 0))
          ((lispy-left-p) (forward-char))
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
    result))

(defun symex--enter (&optional count)
  "Enter higher symex level.

Enter COUNT times, defaulting to one.

This is a primitive operation that is provided below the public
abstraction level of symex.el.  It currently uses built-in Emacs
commands and third party tools like paredit to perform its function.
This procedure is not to be used except in the low-level internals
of symex mode (use the public `symex-go-out` instead)."
  (interactive)
  (let ((count (or count 1))
        (result 0))
    (dotimes (_ count)
      (let ((res (symex--enter-one)))
        (setq result (+ res result))))
    (when (> result 0)
      (symex-make-move 0 result))))

(defun symex--exit-one ()
  "Exit one level."
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

(defun symex--exit (&optional count)
  "Exit to lower symex level.

Exit COUNT times, defaulting to one.

This is a primitive operation that is provided below the public
abstraction level of symex.el.  It currently uses built-in Emacs
commands and third party tools like paredit to perform its function.
This procedure is not to be used except in the low-level internals
of symex mode (use the public `symex-go-in` instead)."
  (interactive)
  (let ((count (or count 1))
        (result 0))
    (dotimes (_ count)
      (let ((res (symex--exit-one)))
        (setq result (+ res result))))
    (when (> result 0)
      (symex-make-move 0 (- result)))))

;;; Transformations

(defun symex--join-to-next ()
  "Join current position to the next symex, eliminating whitespace.

If there is an intervening comment line, then join only up to that
line."
  (let* ((start (point))
         (end (save-excursion (symex--go-forward)
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


(provide 'symex-primitives)
;;; symex-primitives.el ends here

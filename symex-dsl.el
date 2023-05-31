;;; symex-dsl.el --- An evil way to edit Lisp symbolic expressions as trees -*- lexical-binding: t -*-

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

;; Syntax specification for the Symex DSL

;;; Code:


(defun symex--compile-traversal-helper (traversal)
  "Helper function to compile a TRAVERSAL.

This is useful for mapping a compiler macro over a list of
traversal specifications."
  `(symex-traversal ,traversal))

(defmacro symex--compile-protocol (&rest options)
  "Compile a protocol from Symex DSL -> Lisp.

OPTIONS - see underlying Lisp implementation."
  `(symex-make-protocol
    ,@(mapcar #'symex--compile-traversal-helper options)))

(defmacro symex--compile-maneuver (&rest phases)
  "Compile a maneuver from Symex DSL -> Lisp.

PHASES - see underlying Lisp implementation."
  `(symex-make-maneuver
    ,@(mapcar #'symex--compile-traversal-helper phases)))

(defmacro symex--compile-venture (&rest phases)
  "Compile a venture from Symex DSL -> Lisp.

PHASES - see underlying Lisp implementation."
  `(symex-make-venture
    ,@(mapcar #'symex--compile-traversal-helper phases)))

(defmacro symex--compile-detour (reorientation traversal)
  "Compile a detour from Symex DSL -> Lisp.

REORIENTATION - see underlying Lisp implementation.
TRAVERSAL - see underlying Lisp implementation."
  `(symex-make-detour (symex-traversal ,reorientation)
                      (symex-traversal ,traversal)))

(defmacro symex--compile-circuit (traversal &optional times)
  "Compile a circuit from Symex DSL -> Lisp.

TRAVERSAL - see underlying Lisp implementation.
TIMES - see underlying Lisp implementation."
  `(symex-make-circuit (symex-traversal ,traversal)
                       ,times))

(defun symex--rewrite-condition (condition)
  "Rewrite a condition expression into a lambda expression.

CONDITION - a condition specified in DSL syntax, which is to
be rewritten into a lambda expression in terms of an existing
predicate procedure, or left unmodified if it is already a
procedure."
  (cond ((symbolp condition)
         (cond ((equal 'final condition)
                (function 'symex--point-at-final-symex-p))
               ((equal 'initial condition)
                (function 'symex--point-at-initial-symex-p))
               ((equal 'first condition)
                (function 'symex--point-at-first-symex-p))
               ((equal 'last condition)
                (function 'symex--point-at-last-symex-p))
               ((equal 'root condition)
                (function 'symex--point-at-root-symex-p))
               (t condition)))
        ((equal 'not (car condition))
         `(lambda () (not (funcall ,(symex--rewrite-condition (cadr condition))))))
        ((equal 'at (car condition))
         (symex--rewrite-condition (cadr condition)))
        (t condition)))

(defun symex--rewrite-precaution-condition-spec (condition-spec)
  "Rewrite DSL syntax to Lisp syntax in a precaution specification.

CONDITION-SPEC - a condition written in DSL syntax.  See underlying Lisp
implementation for more on precaution conditions."
  (cond ((or (equal 'before (car condition-spec))
             (equal 'beforehand (car condition-spec)))
         `(:pre-condition ,(symex--rewrite-condition (cadr condition-spec))))
        ((or (equal 'after (car condition-spec))
             (equal 'afterwards (car condition-spec)))
         `(:post-condition ,(symex--rewrite-condition (cadr condition-spec))))))

(defmacro symex--compile-precaution (traversal &rest condition-specs)
  "Compile a precaution from Symex DSL -> Lisp.

TRAVERSAL - see underlying Lisp implementation.
CONDITION-SPECS - conditions to be checked either before or after executing
the traversal -- see underlying Lisp implementation.  The conditions may
either be specified purely using the DSL, or could also include custom
lambdas which will be used verbatim.

Conditions to be checked before executing the traversal are specified as:

  (beforehand ...)

Conditions to be checked after executing the traversal are specified as:

  (afterwards ...)

Checking that we are at a particular node is done via:

  (at root/first/last/initial/final)

where root is the root of the current tree, first and last are the first
and last symexes at the current level, and initial and final refer to the
first and last symex in the buffer.  These conditions may also be negated:

  (not (at ...)).

Alternatively, if a custom condition is desired, it may be specified
directly, e.g.:

  (beforehand <procedure>)."
  (append `(symex-make-precaution (symex-traversal ,traversal))
          (apply #'append
                 (mapcar #'symex--rewrite-precaution-condition-spec condition-specs))))

(defmacro symex--compile-decision (condition consequent alternative)
  "Compile a decision from Symex DSL -> Lisp.

CONDITION - The condition on which the decision to choose either the
CONSEQUENT or the ALTERNATIVE traversal is based (see underlying Lisp
implementation).

The conditions may either be specified purely using the DSL, or could
also include custom lambdas which will be used verbatim.

Checking that we are at a particular node is done via:

  (at root/first/last/initial/final)

where root is the root of the current tree, first and last are the
first and last symexes at the current level, and initial and final
refer to the first and last symex in the buffer.  These conditions may
also be negated:

  (not (at ...)).

Alternatively, if a custom condition is desired, it may be specified
directly, e.g.:

  (decision <procedure> ...)."
  `(symex-make-decision ,(symex--rewrite-condition condition)
                        (symex-traversal ,consequent)
                        (symex-traversal ,alternative)))

(defmacro symex--compile-move (direction)
  "Compile a move from Symex DSL -> Lisp.

DIRECTION - the direction to move in, which could be one of:
forward, backward, up, or down."
  (cond ((equal 'forward direction)
         '(symex-make-move 1 0))
        ((equal 'backward direction)
         '(symex-make-move -1 0))
        ((equal 'up direction)
         '(symex-make-move 0 1))
        ((equal 'down direction)
         '(symex-make-move 0 -1))))

(defmacro symex--compile-delete (&optional what)
  "Compile a deletion from Symex -> Lisp.

WHAT - what to delete, either this, previous, next, remaining or until."
  (let ((what (or what 'this)))
    `'(delete ,what)))

(defmacro symex--compile-paste (side)
  "Compile a paste from Symex -> Lisp.

SIDE - the side to paste on, either before or after."
  `'(paste ,side))

(defmacro symex--compile-effect (traversal side-effect)
  "Compile an effect from Symex -> Lisp.

TRAVERSAL - the traversal to perform. This could be any traversal.
SIDE-EFFECT - the side effect to perform. This is any Lisp expression."
  `(symex-make-effect (symex-traversal ,traversal)
                      (lambda () ,side-effect)))

;; TODO: support args here like lambda / defun (i.e. as a list in the
;; binding form -- not passed in but syntactically inserted)
;; try a lambda / defun with args to see what I mean
;; and implement symex--traversal-goto-index as a first instance

(defmacro symex-traversal (traversal)
  "Compile a traversal from Symex DSL -> Lisp.

This defines an anonymous traversal, much like `lambda` defines an
anonymous function.  To give the traversal a name, either assign it to
a variable, or use the `symex-deftraversal` form (analogous to `defun`).

TRAVERSAL could be any traversal specification, e.g. a maneuver,
a detour, a move, etc., which is specified using the Symex DSL."
  (cond ((not (listp traversal)) traversal)  ; e.g. a variable containing a traversal
        ((equal 'protocol (car traversal))
         `(symex--compile-protocol ,@(cdr traversal)))
        ((equal 'maneuver (car traversal))
         `(symex--compile-maneuver ,@(cdr traversal)))
        ((equal 'venture (car traversal))
         `(symex--compile-venture ,@(cdr traversal)))
        ((equal 'detour (car traversal))
         `(symex--compile-detour ,@(cdr traversal)))
        ((equal 'circuit (car traversal))
         `(symex--compile-circuit ,@(cdr traversal)))
        ((equal 'precaution (car traversal))
         `(symex--compile-precaution ,@(cdr traversal)))
        ((equal 'decision (car traversal))
         `(symex--compile-decision ,@(cdr traversal)))
        ((equal 'move (car traversal))
         `(symex--compile-move ,@(cdr traversal)))
        ((equal 'delete (car traversal))
         `(symex--compile-delete ,@(cdr traversal)))
        ((equal 'paste (car traversal))
         `(symex--compile-paste ,@(cdr traversal)))
        ((equal 'effect (car traversal))
         `(symex--compile-effect ,@(cdr traversal)))
        ;; TODO: instead of an implicit escape, it may be better
        ;; to use an explicit one like (esc ...) or (lisp ...)
        (t traversal)))  ; function-valued symbols wind up here

(defmacro symex-deftraversal (name traversal &optional docstring)
  "Define a symex traversal using the Symex DSL.

NAME is the name of the traversal.  The defined traversal will be
assigned to a variable with this name.
TRAVERSAL is the specification of the traversal in the Symex DSL.
This can be thought of as the \"program\" written in the DSL, which
will be compiled into Lisp and can be executed when needed.
An optional DOCSTRING will be used as documentation for the variable
NAME to which the traversal is assigned."
  (declare (indent 1))
  `(defvar ,name (symex-traversal ,traversal) ,docstring))


(provide 'symex-dsl)
;;; symex-dsl.el ends here

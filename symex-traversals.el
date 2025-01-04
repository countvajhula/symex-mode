;;; symex-traversals.el --- An evil way to edit Lisp symbolic expressions as trees -*- lexical-binding: t -*-

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

;; Common traversals for symexes.

;;; Code:


(require 'symex-data)
(require 'symex-primitives-lisp)
(require 'symex-evaluator)
(require 'symex-dsl)

;;;;;;;;;;;;;;;;;;
;;; TRAVERSALS ;;;
;;;;;;;;;;;;;;;;;;

(defun symex-go-forward (count)
  "Move forward COUNT symexes."
  (interactive "p")
  ;; TODO: these should be compiled
  ;; so that the actual executed traversal
  ;; is (move N 0) rather than
  ;; (move 1 0) executed N times
  (symex-execute-traversal
   (symex-traversal (circuit (move forward)
                             count))))

(defun symex-go-backward (count)
  "Move backward COUNT symexes."
  (interactive "p")
  (symex-execute-traversal
   (symex-traversal (circuit (move backward)
                             count))))

(defun symex-go-up (count)
  "Move up COUNT symexes."
  (interactive "p")
  (symex-execute-traversal
   (symex-traversal (circuit (move up)
                             count))))

(defun symex-go-down (count)
  "Move down COUNT symexes."
  (interactive "p")
  (symex-execute-traversal
   (symex-traversal (circuit (move down)
                             count))))

(symex-deftraversal symex--traversal-goto-first
  (circuit (move backward))
  "Go to first symex on the present branch.")

(symex-deftraversal symex--traversal-goto-last
  (circuit (move forward))
  "Go to last symex on the present branch.")

(symex-deftraversal symex--traversal-goto-lowest
  (circuit
   (precaution (move down)
               (beforehand (not (at root)))))
  "Go to lowest (root) symex in present tree.")

(defmacro symex-define-motion (name
                               args
                               docstring
                               interactive-decl
                               &rest
                               body)
  "Define a symex motion."
  (declare (indent defun))
  (eldoc-add-command name)
  `(defun ,name ,args
     ,docstring
     ,interactive-decl
     ,@body))

(symex-define-motion symex-goto-first ()
  "Select first symex at present level."
  (interactive)
  (symex-execute-traversal symex--traversal-goto-first)
  (point))


(symex-define-motion symex-goto-last ()
  "Select last symex at present level."
  (interactive)
  (symex-execute-traversal symex--traversal-goto-last)
  (point))

(symex-define-motion symex-goto-lowest ()
  "Select lowest symex."
  (interactive)
  (symex-execute-traversal symex--traversal-goto-lowest)
  (point))

(symex-define-motion symex-goto-highest ()
  "Select highest symex."
  (interactive)
  (symex-execute-traversal (symex-traversal
                            (circuit (venture (move up)
                                              (circuit (move forward))))))
  (point))

;; TODO: consider compiling `(move down)` to this?
(symex-deftraversal symex--traversal-go-down
  (maneuver (circuit (move backward))
            (move down))
  "A traversal to go down the \"proper,\" squirrel-approved
way. Generally, we could just (move down) in any traversal and that
would be fine in a lot of cases. But if we did that, then the
information about the distance we've traversed along the branch is
lost for any computations that might want to leverage it. This
traversal is careful to explicitly \"undo\" any movements in the
x-direction, the same way we implicitly do when going up and down
(i.e. in the y-direction). This is the way a squirrel would do it,
after all -- in order to get down from a high branch, we first need to
traverse all the way to the base of the branch, back the way we
came.")

(symex-deftraversal symex--traversal-preorder
  (protocol (move up)
            (move forward)
            (detour
             (precaution symex--traversal-go-down
                         (afterwards (not (at final))))
             (move forward)))
  "Pre-order tree traversal, continuing to other trees.")

(symex-deftraversal symex--traversal-preorder-in-tree
  (protocol (move up)
            (move forward)
            (detour
             (precaution symex--traversal-go-down
                         (afterwards (not (at root))))
             (move forward)))
  "Pre-order tree traversal.")

(symex-deftraversal symex--traversal-postorder
  (protocol
   (venture (move backward)
            (circuit
             (venture (move up)
                      (circuit (move forward)))))
   symex--traversal-go-down)
  "Post-order tree traversal, continuing to other trees.")

(symex-deftraversal symex--traversal-postorder-in-tree
  (protocol
   (precaution
    (venture (move backward)
             (circuit
              (venture (move up)
                       (circuit (move forward)))))
    (beforehand (not (at root))))
   symex--traversal-go-down)
  "Post-order tree traversal.")

(symex-deftraversal symex--traversal-skip-forward
  (protocol (move forward)
            (detour (precaution (move down)
                                (afterwards (not (at final))))
                    (move forward)))
  "Tree traversal focused on moving forward, leveraging preorder backtracking
when the way is blocked.")

(symex-deftraversal symex--traversal-skip-backward
  (protocol (move backward)
            (move down))
  "Tree traversal focused on moving backwards, leveraging postorder backtracking
when the way is blocked.")

(symex-deftraversal symex--traversal-climb-branch
  (protocol (move up)
            (venture (circuit (move forward))
                     (move up))))

(symex-deftraversal symex--traversal-descend-branch
  (protocol (precaution symex--traversal-goto-first
                        (beforehand (not (at root))))
            (venture (move down)
                     (precaution symex--traversal-goto-first
                                 (beforehand (not (at root)))))))

(symex-define-motion symex-traverse-forward (count)
  "Traverse symex as a tree, using pre-order traversal.

Executes the motion COUNT times."
  (interactive "p")
  (dotimes (_ count)
    (symex-execute-traversal symex--traversal-preorder)))

(symex-define-motion symex-traverse-forward-more (count)
  "Traverse symex as a tree, using pre-order traversal.

Moves more steps at a time.  Executes the motion COUNT times."
  (interactive "p")
  (dotimes (_ count)
    (symex-traverse-forward 3)))

(symex-define-motion symex-traverse-forward-in-tree (count)
  "Traverse symex forward using pre-order traversal, stopping at end of tree.

Executes the motion COUNT times."
  (interactive "p")
  (dotimes (_ count)
    (symex-execute-traversal symex--traversal-preorder-in-tree)))

(symex-define-motion symex-traverse-forward-skip (count)
  "Traverse symex as a tree, skipping forward.

Executes the motion COUNT times."
  (interactive "p")
  (dotimes (_ count)
    (symex-execute-traversal symex--traversal-skip-forward)))

(symex-define-motion symex-traverse-backward (count)
  "Traverse symex as a tree, using converse post-order traversal.

Executes the motion COUNT times."
  (interactive "p")
  (dotimes (_ count)
    (symex-execute-traversal symex--traversal-postorder)))

(symex-define-motion symex-traverse-backward-more (count)
  "Traverse symex as a tree, using pre-order traversal.

Moves more steps at a time.  Executes the motion COUNT times."
  (interactive "p")
  (dotimes (_ count)
    (symex-traverse-backward 3)))

(symex-define-motion symex-traverse-backward-in-tree (count)
  "Traverse symex backward using post-order traversal, stopping at root of tree.

Executes the motion COUNT times."
  (interactive "p")
  (dotimes (_ count)
    (symex-execute-traversal symex--traversal-postorder-in-tree)))

(symex-define-motion symex-traverse-backward-skip (count)
  "Traverse symex as a tree, skipping backwards.

Executes the motion COUNT times."
  (interactive "p")
  (dotimes (_ count)
    (symex-execute-traversal symex--traversal-skip-backward)))

(symex-define-motion symex-climb-branch (count)
  "Climb up.

Executes the motion COUNT times."
  (interactive "p")
  (dotimes (_ count)
    (symex-execute-traversal symex--traversal-climb-branch)))

(symex-define-motion symex-descend-branch (count)
  "Descend the tree.

Executes the motion COUNT times."
  (interactive "p")
  (dotimes (_ count)
    (symex-execute-traversal symex--traversal-descend-branch)))

(defun symex--do-while-traversing (operation traversal)
  "Traverse a symex using TRAVERSAL and do OPERATION at each step."
  ;; do it once first since it will be executed as a side-effect
  ;; _after_ each step in the traversal
  (funcall operation)
  (symex-execute-traversal
   (symex-traversal
    (circuit
     (effect (funcall operation)
             ;; TODO: the semantics of effect is already to
             ;; wrap the operation with a lambda and then
             ;; invoke that during evaluation. It may make
             ;; sense to avoid this double-wrapping.
             traversal)))
   nil))


(provide 'symex-traversals)
;;; symex-traversals.el ends here

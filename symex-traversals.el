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

(symex-deftraversal symex--traversal-preorder
  (protocol (protocol (move up)
                      (move forward))
            (detour (precaution (move down)
                                (afterwards (not (at final))))
                    (move forward)))
  "Pre-order tree traversal, continuing to other trees.")

(symex-deftraversal symex--traversal-preorder-in-tree
  (protocol (protocol (move up)
                      (move forward))
            (detour (precaution (move down)
                                (afterwards (not (at root))))
                    (move forward)))
  "Pre-order tree traversal.")

(symex-deftraversal symex--traversal-postorder
  (protocol (venture (move backward)
                     (circuit (venture (move up)
                                       (circuit (move forward)))))
            (move down))
  "Post-order tree traversal, continuing to other trees.")

(symex-deftraversal symex--traversal-postorder-in-tree
  (protocol (precaution (venture (move backward)
                                 (circuit (venture (move up)
                                                   (circuit (move forward)))))
                        (beforehand (not (at root))))
            (move down))
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

(symex-deftraversal symex--traversal-emit-backward
  (maneuver (move up)
            (delete)
            (move down)
            (paste before))
  "Emit backward.")

(symex-deftraversal symex--traversal-emit-forward
  (maneuver (move up)
            (circuit (move forward))
            (delete)
            (move down)
            (paste after))
  "Emit forward.")

(symex-deftraversal symex--traversal-capture-backward
  (maneuver (delete previous)
            (move up)
            (paste before)
            (move down))
  "Capture backward.")

(symex-deftraversal symex--traversal-capture-forward
  (maneuver (delete next)
            (move up)
            (circuit (move forward))
            (paste after)
            (move down))
  "Capture forward.")

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
  (let ((result (symex-execute-traversal traversal
                                         nil
                                         operation)))
    (message "%s" result)
    (when result
      (symex--do-while-traversing operation
                                  traversal))))


(provide 'symex-traversals)
;;; symex-traversals.el ends here

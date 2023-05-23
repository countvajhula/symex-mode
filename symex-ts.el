;;; symex-ts.el --- Primitive navigations using Tree Sitter -*- lexical-binding: t; coding: utf-8 -*-

;; Author: Simon Pugnet <simon@polaris64.net>
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

;; This module defines a set of movement primitives which use Tree
;; Sitter to navigate a buffer's abstract syntax tree.
;;
;; A hydra is also provided, however this is intended for debugging
;; purposes. It allows the primitives to be used directly without the
;; rest of Symex.

;;; Code:

(require 'tree-sitter)
(require 'tsc)
(require 'symex-transformations-ts)
(require 'symex-utils-ts)


(defvar-local symex-ts--current-node nil "The current Tree Sitter node.")

(defun symex-ts--set-current-node (node)
  "Set the current node to NODE and update internal references."
  (setq-local symex-ts--current-node node)
  (goto-char (tsc-node-start-position node)))

(defun symex-ts--get-topmost-node (node)
  "Return the highest node in the tree starting from NODE.

The returned node is the highest possible node that has the same
start position as NODE."
  (let ((node-start-pos (tsc-node-start-position node))
        (parent (tsc-get-parent node)))
    (if parent
        (let ((parent-pos (tsc-node-start-position parent)))
          (if (eq node-start-pos parent-pos)
              (symex-ts--get-topmost-node parent)
            node))
      node)))

(defun symex-ts--get-nth-sibling-from-node (src-node traversal-fn n)
  "Return the N-th sibling node from SRC-NODE.

TRAVERSAL-FN should be a function which returns the next node in
the chain. For example, to get the node two positions prior to
SRC-NODE, use `tsc-get-prev-named-sibling'.

If N traversals cannot be completed (e.g. if N is 3 but there are
only two more nodes), the last node is returned instead."
  (let ((next-node (funcall traversal-fn src-node)))
    (if (or (eq n 1) (not next-node))
        src-node
      (symex-ts--get-nth-sibling-from-node next-node traversal-fn (1- n)))))

(defun symex-ts--node-has-sibling-p (node)
  "Check if NODE has a sibling."
  (or (tsc-get-prev-named-sibling node)
      (tsc-get-next-named-sibling node)))

(defun symex-ts--descend-to-child-with-sibling (node)
  "Descend from NODE to the first child recursively.

Recursion will end when the child node has a sibling or is a
leaf."
  (let ((child (tsc-get-nth-named-child node 0)))
    (if child
        (if (or (symex-ts--node-has-sibling-p child)
                (not (= (tsc-node-start-position node)
                        (tsc-node-start-position child))))
            child
          (symex-ts--descend-to-child-with-sibling child))
      nil)))

(defun symex-ts--ascend-to-parent-with-sibling (node &optional initial)
  "Ascend from NODE to parent recursively.

Recursion will end when the parent node has a sibling or is the
root. The INITIAL node is used to ensure that a parent is selected
even if it doesn't have siblings if it changes point (TODO: clarify)."
  (let ((parent (tsc-get-parent node))
        (initial (or initial node)))
    (if parent
        ;; visit node if it either has no siblings or changes point,
        ;; for symmetry with "descend" behavior
        (cond ((and (not (= (tsc-node-start-position node)
                            (tsc-node-start-position parent)))
                    (not (tsc-node-eq node initial)))
               node)
              ((symex-ts--node-has-sibling-p parent) parent)
              (t (symex-ts--ascend-to-parent-with-sibling parent node)))
      node)))

(defun symex-ts--move-with-count (fn move-delta &optional count)
  "Move the point from the current node if possible.

Movement is defined by FN, which should be a function which
returns the appropriate neighbour node.

MOVE-DELTA is a Symex \"move\" describing the desired x and y
point movement (e.g. `(move -1 0)' for a move \"upward\").

Move COUNT times, defaulting to 1.

Return a Symex move (list with x,y node offsets tagged with
`move') or nil if no movement was performed."
  (let ((target-node nil)
        (move symex--move-zero)
        (cursor (symex-ts-get-current-node)))
    (dotimes (_ (or count 1))
      (let ((new-node (funcall fn cursor)))
        (when (and new-node (not (tsc-node-eq new-node cursor)))
          (setq move (symex--add-moves (list move move-delta)))
          (setq cursor new-node
                target-node cursor))))
    (when target-node (symex-ts--set-current-node target-node))

    ;; Return the Symex move that was executed, or nil to signify that
    ;; the movement failed
    (when (not (symex--are-moves-equal-p move symex--move-zero)) move)))

(defun symex-ts-current-node-sexp ()
  "Print the current node as an s-expression."
  (interactive)
  (message (tsc-node-to-sexp symex-ts--current-node)))

(defun symex-ts-get-current-node ()
  "Return the current node.
Automatically set it to the node at point if necessary."
  (unless symex-ts--current-node
    (symex-ts-set-current-node-from-point))
  symex-ts--current-node)

(defun symex-ts-set-current-node-from-point ()
  "Set the current node to the top-most node at point."
  (symex-ts--set-current-node (symex-ts-get-topmost-node-at-point)))

(defun symex-ts-get-topmost-node-at-point ()
  "Return the top-most node at the current point."
  (let ((root (tsc-root-node tree-sitter-tree))
        (p (point)))
    (symex-ts--get-topmost-node (tsc-get-named-descendant-for-position-range root p p))))

;;; User Interface

(defun symex-ts--adjust-point ()
  "Helper to adjust point to indicate the correct symex."
  nil)

;;; Predicates

(defmacro symex-ts--if-stuck (do-what operation &rest body)
  "Attempt OPERATION and if it fails, then do DO-WHAT."
  (let ((orig (gensym))
        (cur (gensym)))
    `(let ((,orig (symex-ts-get-current-node)))
       ,operation
       (let ((,cur (symex-ts-get-current-node)))
         (if (tsc-node-eq ,cur ,orig)
             ,do-what
           ,@body)))))

(defun symex-ts--at-root-p ()
  "Check whether the current node is the global root node."
  (let ((root (tsc-root-node tree-sitter-tree))
        (cur (symex-ts-get-current-node)))
    (tsc-node-eq cur root)))

(defun symex-ts--at-tree-root-p ()
  "Check whether the current node is the root node of a tree.

Note that this does not consider global root to be a tree root."
  (let ((root (tsc-root-node tree-sitter-tree))
        (cur (symex-ts-get-current-node)))
    (let ((parent (tsc-get-parent cur)))
      (or (not parent) (tsc-node-eq parent root)))))

(defun symex-ts--at-first-p ()
  "Check if the current node is the first one at some level."
  (symex-ts--if-stuck t
                      (symex-ts-move-prev-sibling)
                      (symex-ts-move-next-sibling)
                      nil))

(defun symex-ts--at-last-p ()
  "Check if the current node is at the last one at some level."
  (symex-ts--if-stuck t
                      (symex-ts-move-next-sibling)
                      (symex-ts-move-prev-sibling)
                      nil))

(defun symex-ts--at-final-p ()
  "Check if the current node is at the last one in the buffer."
  (and (symex-ts--at-tree-root-p)
       (symex-ts--at-last-p)))

(defun symex-ts--at-initial-p ()
  "Check if the current node is at the first one in the buffer."
  (and (symex-ts--at-tree-root-p)
       (symex-ts--at-first-p)))

(defun symex-ts--point-at-start-p ()
  "Check if point is at the start of a node."
  (let ((cur (symex-ts-get-current-node)))
    (= (point) (tsc-node-start-position cur))))

(defun symex-ts--previous-p ()
  "Check if a preceding symex exists at this level."
  (symex-ts-save-excursion (symex-ts-move-prev-sibling)))

(defun symex-ts--next-p ()
  "Check if a succeeding symex exists at this level."
  (symex-ts-save-excursion (symex-ts-move-next-sibling)))

;;; Navigations

(defun symex-ts-move-prev-sibling (&optional count)
  "Move the point to the current node's previous sibling if possible.

Move COUNT times, defaulting to 1."
  (interactive "p")
  (symex-ts--move-with-count #'tsc-get-prev-named-sibling (symex-make-move -1 0) count))

(defun symex-ts-move-next-sibling (&optional count)
  "Move the point to the current node's next sibling if possible.

Move COUNT times, defaulting to 1."
  (interactive "p")
  (symex-ts--move-with-count #'tsc-get-next-named-sibling (symex-make-move 1 0) count))

(defun symex-ts-move-parent (&optional count)
  "Move the point to the current node's parent if possible.

Move COUNT times, defaulting to 1."
  (interactive "p")
  (symex-ts--move-with-count #'symex-ts--ascend-to-parent-with-sibling (symex-make-move 0 -1) count))

(defun symex-ts-move-child (&optional count)
  "Move the point to the current node's first child if possible.

Move COUNT times, defaulting to 1."
  (interactive "p")
  (symex-ts--move-with-count #'symex-ts--descend-to-child-with-sibling (symex-make-move 0 1) count))

;;; Utilities

(defmacro symex-ts-save-excursion (&rest body)
  "Execute BODY while preserving position in the tree.

Like `save-excursion`, but in addition to preserving the point
position, this also preserves the structural position in the tree, for
languages where point position doesn't uniquely identify a tree
location (e.g. non-symex-based languages like Python).

This is tree-sitter specific and meant for internal, primitive use."
  (let ((offset (gensym))
        (result (gensym)))
    `(let ((,offset (symex-ts--point-height-offset)))
       (let ((,result
              (save-excursion
                ,@body)))
         (symex-ts-set-current-node-from-point)
         (symex-ts-move-child ,offset)
         ,result))))

(defun symex-ts--get-starting-point ()
  "Get the point value at the start of the current symex."
  (tsc-node-start-position symex-ts--current-node))

(defun symex-ts--get-end-point (count)
  "Get the point value after COUNT symexes.

If the containing expression terminates earlier than COUNT
symexes, returns the end point of the last one found."
  (symex-ts-save-excursion
   (symex-ts-move-next-sibling (1- count))
   (tsc-node-end-position symex-ts--current-node)))

(defun symex-ts--point-height-offset-helper (orig-pos)
  "A helper to compute the height offset of the current symex.

The height offset is determined as soon as point differs from the
original point position ORIG-POS upon repeatedly going down."
  (cond ((symex-ts--at-tree-root-p)
         (if (= orig-pos (point))
             0
           -1))
        ((not (= (point) orig-pos)) -1)
        (t (symex-ts-move-parent)
           (1+ (symex-ts--point-height-offset-helper orig-pos)))))

(defun symex-ts--point-height-offset ()
  "Compute the height offset of the current symex.

This is measured from the lowest symex indicated by point."
  ;; TODO: probably make this a tree-sitter utility instead, so that
  ;; it uses tree-sitter APIs to determine point-height offset instead
  ;; of doing it at the level of traversals.
  ;; don't attempt to calculate offset at the "real" root
  ;; since offsets are typically computed while ignoring it
  ;; i.e. they are wrt. "tree root"
  (cond ((symex-ts--at-root-p) 0)
        ;; at the "tree root" of the first symex in the buffer,
        ;; point-height offset must account for "true" root
        ;; and so it's 1 rather than 0 here
        ((symex-ts--at-initial-p) 1)
        ;; aside from the above special cases, compute point-height
        ;; offset by just descending as long as point does not change,
        ;; and counting the number of steps taken
        (t (let* ((orig-pos (point))
                  (offset (symex-ts--point-height-offset-helper orig-pos)))
             ;; return to original tree position
             ;; before returning the result
             (goto-char orig-pos)
             (symex-ts-set-current-node-from-point)
             (symex-ts-move-child offset)
             offset))))

(defun symex-ts-exit ()
  "Take necessary tree-sitter related actions upon exiting Symex mode."
  (setq-local symex-ts--current-node nil))


(provide 'symex-ts)
;;; symex-ts.el ends here

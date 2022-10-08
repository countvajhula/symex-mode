;;; symex-evaluator.el --- An evil way to edit Lisp symbolic expressions as trees -*- lexical-binding: t -*-

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

;; An interpreter to execute symex traversals.

;;; Code:

(require 'cl-lib)

(require 'symex-data)
(require 'symex-primitives)
(require 'symex-computations)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; EVALUATION AND EXECUTION ;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun symex--execute-tree-move (move &optional computation)
  "Execute the specified MOVE at the current point location in the tree.

Evaluates to the actual move executed or nil if no move was executed.
Optional argument COMPUTATION currently unused.

This interface is an 'abstraction barrier' to keep the details of the
elementary navigation of symexes as a black box.  The implementation
of these elementary operations could be changed in the future (e.g. to
incorporate an explicit AST representation for greater precision) without
requiring changes to higher-level code that uses the present interface."
  (ignore computation)
  (let ((move-x (symex--move-x move))
        (move-y (symex--move-y move)))
    (cond ((> move-x 0)
           (symex--forward move-x))
          ((< move-x 0)
           (symex--backward (abs move-x)))
          ((> move-y 0)
           (symex--enter move-y))
          ((< move-y 0)
           (symex--exit (abs move-y))))))

(defun symex-execute-move (move &optional computation)
  "Execute the MOVE as a traversal.

This returns a list of moves (singleton, in this case) rather than the
executed move itself.  TODO: not sure this is needed anymore.
Optional argument COMPUTATION currently unused."
  (let ((executed-move (symex--execute-tree-move move computation)))
    (when executed-move
      (list executed-move))))

(cl-defun symex--go-forward (&optional (count 1))
  "Move forward COUNT symexes.

This is an internal utility that avoids any user-level concerns
such as symex selection via advice.  This should be used in all
internal operations that are not primarily user-directed."
  (symex--execute-tree-move (symex-make-move count 0)))

(cl-defun symex--go-backward (&optional (count 1))
  "Move backwards COUNT symexes.

This is an internal utility that avoids any user-level concerns
such as symex selection via advice.  This should be used in all
internal operations that are not primarily user-directed."
  (symex--execute-tree-move (symex-make-move (- count) 0)))

(cl-defun symex--go-out (&optional (count 1))
  "Move up COUNT symexes.

This is an internal utility that avoids any user-level concerns
such as symex selection via advice.  This should be used in all
internal operations that are not primarily user-directed."
  (symex--execute-tree-move (symex-make-move 0 (- count))))

(cl-defun symex--go-in (&optional (count 1))
  "Move down COUNT symexes.

This is an internal utility that avoids any user-level concerns
such as symex selection via advice.  This should be used in all
internal operations that are not primarily user-directed."
  (symex--execute-tree-move (symex-make-move 0 count)))

(cl-defun symex-go-forward (&optional (count 1))
  "Move forward COUNT symexes."
  (interactive)
  (symex--execute-tree-move (symex-make-move count 0)))

(cl-defun symex-go-backward (&optional (count 1))
  "Move backward COUNT symexes."
  (interactive)
  (symex--execute-tree-move (symex-make-move (- count) 0)))

(cl-defun symex-go-out (&optional (count 1))
  "Move up COUNT symexes."
  (interactive)
  (symex--execute-tree-move (symex-make-move 0 (- count))))

(defalias 'symex-go-up 'symex-go-out)

(cl-defun symex-go-in (&optional (count 1))
  "Move down COUNT symexes."
  (interactive)
  (symex--execute-tree-move (symex-make-move 0 count)))

(defalias 'symex-go-down 'symex-go-in)

(defun symex--compute-results (a b computation)
  "Combine component computed results A and B into an aggregate result.

The aggregate result is constructed according to the specified COMPUTATION."
  ;; TODO: ruminate here
  ;; a and b should each have as many elements as the number of components
  ;; in the computation
  ;; later, a and b could be generators instead of lists of results
  (funcall (symex--computation-act computation)
           a
           b))

(defun symex-execute-maneuver (maneuver computation)
  "Attempt to execute a given MANEUVER.

Attempts the maneuver in the order of its phases, accepting partial completion
of phases.  If any phase fails entirely, then the maneuver it is part of is
terminated at that step.

Evaluates to a COMPUTATION on the maneuver actually executed."
  (let ((phases (symex--maneuver-phases maneuver)))
    (when phases
      (let ((current-phase (car phases))
            (remaining-phases (cdr phases)))
        (let ((executed-phase (symex-execute-traversal current-phase
                                                       computation)))
          (when executed-phase
            (let ((executed-remaining-phases
                   (symex-execute-traversal (apply #'symex-make-maneuver
                                                   remaining-phases)
                                            computation)))
              (symex--compute-results executed-phase
                                      executed-remaining-phases
                                      computation))))))))

(defun symex-execute-circuit (circuit computation)
  "Execute a CIRCUIT.

This repeats some traversal as specified.

Evaluates to a COMPUTATION on the maneuver actually executed."
  (let ((traversal (symex--circuit-traversal circuit))
        (times (symex--circuit-times circuit)))
    (when (or (not times)  ; loop indefinitely
              (> times 0))
      (let ((result (symex-execute-traversal traversal
                                             computation)))
        (when result
          (let ((times (if times
                           (1- times)
                         times)))
            (let ((remaining-circuit
                   (symex-execute-traversal (symex-make-circuit traversal
                                                                times)
                                            computation)))
              (symex--compute-results result
                                      remaining-circuit
                                      computation))))))))

(defun symex-execute-detour (detour computation)
  "Execute the DETOUR.

Apply a reorientation and then attempt the traversal.

If the traversal fails, then the reorientation is attempted as many times as
necessary until either it succeeds, or the reorientation fails.

Evaluates to a COMPUTATION on the maneuver actually executed."
  (let ((reorientation (symex--detour-reorientation detour))
        (traversal (symex--detour-traversal detour)))
    (let ((executed-reorientation (symex-execute-traversal reorientation)))
      (when executed-reorientation
        (let ((path (symex-make-protocol traversal
                                         detour)))
          (let ((executed-path (symex-execute-traversal path
                                                        computation)))
            (when executed-path
              (symex--compute-results executed-reorientation
                                      executed-path
                                      computation))))))))

(defun symex-execute-precaution (precaution computation)
  "Attempt to execute a given PRECAUTION.

The traversal is only executed if PRE-CONDITION holds, and is reversed if
POST-CONDITION does not hold after the provisional execution of the traversal.

Evaluates to a COMPUTATION on the maneuver actually executed."
  (let ((traversal (symex--precaution-traversal precaution))
        (pre-condition (symex--precaution-pre-condition precaution))
        (post-condition (symex--precaution-post-condition precaution)))
    (when (funcall pre-condition)
      (let ((executed-traversal (symex-execute-traversal traversal
                                                         computation)))
        (when (funcall post-condition)
          executed-traversal)))))

(defun symex-execute-protocol (protocol computation)
  "Attempt to execute a given PROTOCOL.

Given a protocol including a set of options, attempt to execute them
in order until one succeeds.

Evaluates to a COMPUTATION on the maneuver actually executed."
  (let ((options (symex--protocol-options protocol)))
    (when options
      (let ((option (car options))
            (remaining-options (cdr options)))
        (let ((executed-option (symex-execute-traversal option
                                                        computation)))
          (if executed-option
              executed-option
            (symex-execute-traversal (apply #'symex-make-protocol
                                            remaining-options)
                                     computation)))))))

(defun symex-execute-decision (decision computation)
  "Attempt to execute a given DECISION.

The consequent traversal is executed if the condition holds, and the
alternative traversal is executed if the condition does not hold.

Evaluates to a COMPUTATION on the traversal actually executed."
  (let ((condition (symex--decision-condition decision))
        (consequent (symex--decision-consequent decision))
        (alternative (symex--decision-alternative decision)))
    (if (funcall condition)
        (symex-execute-traversal consequent
                                 computation)
      (symex-execute-traversal alternative
                               computation))))

(defun symex-execute-traversal (traversal &optional computation side-effect)
  "Execute a tree TRAVERSAL.

SIDE-EFFECT is the operation to perform as part of the traversal
\(none by default).

Evaluates to a COMPUTATION on the traversal actually executed."
  (let ((computation (if computation
                         computation
                       symex--computation-default))
        (side-effect (if side-effect
                         side-effect
                       #'symex--side-effect-noop)))
    (let ((original-location (point))
          (executed-traversal (cond ((symex-maneuver-p traversal)
                                     (symex-execute-maneuver traversal
                                                             computation))
                                    ((symex-circuit-p traversal)
                                     (symex-execute-circuit traversal
                                                            computation))
                                    ((symex-protocol-p traversal)
                                     (symex-execute-protocol traversal
                                                             computation))
                                    ((symex-precaution-p traversal)
                                     (symex-execute-precaution traversal
                                                               computation))
                                    ((symex-detour-p traversal)
                                     (symex-execute-detour traversal
                                                           computation))
                                    ((symex-decision-p traversal)
                                     (symex-execute-decision traversal
                                                             computation))
                                    ((symex-move-p traversal)
                                     (symex-execute-move traversal
                                                         computation))
                                    (t (funcall traversal)))))
      (let ((result (funcall (symex--computation-perceive computation)
                             executed-traversal)))
        (if result
            (progn (funcall side-effect)
                   result)
          (goto-char original-location)
          result)))))


(provide 'symex-evaluator)
;;; symex-evaluator.el ends here

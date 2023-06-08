;;; symex-evaluator.el --- An evil way to edit Lisp symbolic expressions as trees -*- lexical-binding: t -*-

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

;; An interpreter to execute symex traversals.

;;; Code:

(require 'cl-lib)

(require 'symex-data)
(require 'symex-primitives)
(require 'symex-computations)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; EVALUATION AND EXECUTION ;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun symex--execute-tree-move (move)
  "Execute the specified MOVE at the current point location in the tree.

Evaluates to the actual move executed or nil if no move was executed.

This interface is an \"abstraction barrier\" to keep the details of the
elementary navigation of symexes as a black box.  The implementation
of these elementary operations could be changed in the future (e.g. to
incorporate an explicit AST representation for greater precision) without
requiring changes to higher-level code that uses the present interface."
  (let ((move-x (symex--move-x move))
        (move-y (symex--move-y move)))
    (cond ((> move-x 0)
           (symex--go-forward move-x))
          ((< move-x 0)
           (symex--go-backward (abs move-x)))
          ((> move-y 0)
           (symex--go-up move-y))
          ((< move-y 0)
           (symex--go-down (abs move-y)))
          (t symex--move-zero))))

(defun symex-execute-move (move &optional computation result)
  "Execute the MOVE as a traversal.

This returns a list of moves (singleton, in this case) rather than the
executed move itself.  TODO: not sure this is needed anymore.
Optional argument COMPUTATION currently unused."
  (let ((executed-move (symex--execute-tree-move move))
        (result (or result
                    (funcall (symex--computation-perceive computation)
                             symex--move-zero))))
    (when executed-move
      (symex-compute-results result
                             (funcall (symex--computation-perceive computation)
                                      executed-move)
                             computation))))

(defun symex-execute-maneuver (maneuver computation result)
  "Attempt to execute a given MANEUVER.

Attempts the maneuver in the order of its phases.  The maneuver
succeeds only if all of the phases succeed, and otherwise fails.

Evaluates to a COMPUTATION on the traversal actually executed."
  (if (symex--maneuver-null-p maneuver)
      result
    (let ((current-phase (symex--maneuver-first maneuver))
          (remaining-maneuver (symex--maneuver-rest maneuver)))
      (let ((executed-phase (symex-execute-traversal current-phase
                                                     computation
                                                     result)))
        (when executed-phase
          (symex-execute-maneuver remaining-maneuver
                                  computation
                                  executed-phase))))))

(defun symex-execute-venture (venture computation result)
  "Attempt to execute a given VENTURE.

Similar to maneuver execution, except that it accepts partial
completion.  That is, this attempts the venture in the order of its
phases.  If any phase fails, then the venture is terminated at that
step.  In general, the venture succeeds if at least one phase
succeeds, and otherwise fails.  In the special case where nothing is
ventured, then even though nothing is gained, it is considered to have
succeeded.  In particular, venturing nothing is a base case in venture
evaluation.

Evaluates to a COMPUTATION on the traversal actually executed."
  (if (symex--venture-null-p venture)
      result
    (let ((current-phase (symex--venture-first venture))
          (remaining-venture (symex--venture-rest venture)))
      (let ((executed-phase (symex-execute-traversal current-phase
                                                     computation
                                                     result)))
        (when executed-phase
          (let ((accumulated-result
                 (symex-execute-venture remaining-venture
                                        computation
                                        executed-phase)))
            (if accumulated-result
                accumulated-result
              executed-phase)))))))

(defun symex-execute-circuit (circuit computation result)
  "Execute a CIRCUIT.

This repeats some traversal as specified.

Evaluates to a COMPUTATION on the traversal actually executed."
  (if (symex--circuit-null-p circuit)
      result
    (let ((traversal (symex--circuit-traversal circuit))
          (times (symex--circuit-times circuit))
          (remaining-circuit (symex--circuit-rest circuit)))
      (let ((executed-phase (symex-execute-traversal traversal
                                                     computation
                                                     result)))
        (if executed-phase
            (symex-execute-circuit remaining-circuit
                                   computation
                                   executed-phase)
          (when (not times)
            ;; if looping indefinitely, then count 0
            ;; times executed as success
            result))))))

;; TODO: we could probably avoid having a separate conditional
;; recursion form by passing the computation result to all predicates
;; used with Symex, e.g. in precautions, decisions, etc.  Then this
;; could be implemented as a circuit repeating a precaution on an
;; underlying traversal.
(defun symex-execute-loop (loop computation result)
  "Execute a LOOP.

This repeats some traversal according to a condition on the computation.

Evaluates to a COMPUTATION on the traversal actually executed."
  (let ((traversal (symex--loop-traversal loop))
        (condition (symex--loop-condition loop)))
    (let ((accumulated-result (symex-execute-traversal traversal
                                                       computation
                                                       result)))
      (when accumulated-result
        (if (funcall condition accumulated-result)
            accumulated-result
          (symex-execute-loop loop
                              computation
                              accumulated-result))))))

(defun symex-execute-detour (detour computation result)
  "Execute the DETOUR.

Apply a reorientation and then attempt the traversal.

If the traversal fails, then the reorientation is attempted as many times as
necessary until either it succeeds, or the reorientation fails.

Evaluates to a COMPUTATION on the traversal actually executed."
  (let ((reorientation (symex--detour-reorientation detour))
        (traversal (symex--detour-traversal detour)))
    (let ((executed-reorientation (symex-execute-traversal reorientation
                                                           computation
                                                           result)))
      (when executed-reorientation
        (let ((path (symex-make-protocol traversal
                                         detour)))
          (symex-execute-traversal path
                                   computation
                                   executed-reorientation))))))

(defun symex-execute-precaution (precaution computation result)
  "Attempt to execute a given PRECAUTION.

The traversal is only executed if PRE-CONDITION holds, and is reversed if
POST-CONDITION does not hold after the provisional execution of the traversal.

Evaluates to a COMPUTATION on the traversal actually executed."
  (let ((traversal (symex--precaution-traversal precaution))
        (pre-condition (symex--precaution-pre-condition precaution))
        (post-condition (symex--precaution-post-condition precaution)))
    (when (funcall pre-condition)
      (let ((executed-traversal (symex-execute-traversal traversal
                                                         computation
                                                         result)))
        (when (funcall post-condition)
          executed-traversal)))))

(defun symex-execute-protocol (protocol computation result)
  "Attempt to execute a given PROTOCOL.

Given a protocol including a set of options, attempt to execute them
in order until one succeeds.

Evaluates to a COMPUTATION on the traversal actually executed."
  (unless (symex--protocol-null-p protocol)
    (let ((option (symex--protocol-first protocol))
          (remaining-protocol (symex--protocol-rest protocol)))
      (let ((executed-option (symex-execute-traversal option
                                                      computation
                                                      result)))
        (if executed-option
            executed-option
          (symex-execute-protocol remaining-protocol
                                  computation
                                  result))))))

(defun symex-execute-decision (decision computation result)
  "Attempt to execute a given DECISION.

The consequent traversal is executed if the condition holds, and the
alternative traversal is executed if the condition does not hold.

Evaluates to a COMPUTATION on the traversal actually executed."
  (let ((condition (symex--decision-condition decision))
        (consequent (symex--decision-consequent decision))
        (alternative (symex--decision-alternative decision)))
    (if (funcall condition)
        (symex-execute-traversal consequent
                                 computation
                                 result)
      (symex-execute-traversal alternative
                               computation
                               result))))

(defun symex-execute-deletion (deletion computation result)
  "Attempt to execute a given DELETION.

This could delete `this`, `previous` or `next`. Of these, favor the
latter two as those are explicit that the placement of point is
unaffected by the transformation. On the other hand, the first is
provided as a convenience for cases where posterior placement of point
is irrelevant for the purposes of the traversal, because, indeed,
there is no fixed rule on where it will be placed.

TODO: either there should be no guarantee and either next or previous
could be selected, or it should leave a void and have point indicate
the whitespace there rather than explicitly select either the next or
previous expression.

Evaluates to a COMPUTATION on the traversal actually executed."
  (let ((what (symex--deletion-what deletion)))
    (let ((this-result (symex-prim-delete what)))
      ;; TODO: compute based on an appropriate result here
      (when this-result
        result))))

(defun symex-execute-paste (paste computation result)
  "Attempt to execute a given PASTE.

Evaluates to a COMPUTATION on the traversal actually executed."
  (let ((side (symex--paste-side paste)))
    (let ((this-result (symex-prim-paste side)))
      ;; TODO: compute based on an appropriate result here
      (when this-result
        result))))

(defun symex-execute-effect (effect computation result)
  "Attempt to execute a given EFFECT.

Evaluates to a COMPUTATION on the traversal actually executed."
  (let ((traversal (symex--effect-traversal effect))
        (effect (symex--effect-effect effect)))
    (let ((executed-traversal (symex-execute-traversal traversal
                                                       computation
                                                       result)))
      (when executed-traversal
        (let ((executed-effect (funcall effect)))
          ;; ignore the result of the effect
          executed-traversal)))))

(defun symex--execute-traversal (traversal computation result)
  "Helper to execute TRAVERSAL and perform COMPUTATION."
  (cond ((symex-maneuver-p traversal)
         (symex-execute-maneuver traversal
                                 computation
                                 result))
        ((symex-venture-p traversal)
         (symex-execute-venture traversal
                                computation
                                result))
        ((symex-circuit-p traversal)
         (symex-execute-circuit traversal
                                computation
                                result))
        ((symex-loop-p traversal)
         (symex-execute-loop traversal
                             computation
                             result))
        ((symex-protocol-p traversal)
         (symex-execute-protocol traversal
                                 computation
                                 result))
        ((symex-precaution-p traversal)
         (symex-execute-precaution traversal
                                   computation
                                   result))
        ((symex-detour-p traversal)
         (symex-execute-detour traversal
                               computation
                               result))
        ((symex-decision-p traversal)
         (symex-execute-decision traversal
                                 computation
                                 result))
        ((symex-move-p traversal)
         (symex-execute-move traversal
                             computation
                             result))
        ((symex-delete-p traversal)
         (symex-execute-deletion traversal
                                 computation
                                 result))
        ((symex-paste-p traversal)
         (symex-execute-paste traversal
                              computation
                              result))
        ((symex-effect-p traversal)
         (symex-execute-effect traversal
                               computation
                               result))
        ;; TODO: return accumulated result
        ;; and ignore result of function invocation
        (t (funcall traversal))))

(defun symex-execute-traversal (traversal
                                &optional
                                computation
                                result)
  "Execute a tree TRAVERSAL.

TRAVERSAL could be a move, a maneuver, or any other Symex traversal.
If it is not a Symex expression, then it is assumed to be an ELisp
function, and the rule for interpretation is to apply the function.

Evaluates to a COMPUTATION on the traversal actually executed."
  (let* ((computation (if computation
                         computation
                       symex--computation-default))
         (result (or result
                     (symex-execute-move symex--move-zero
                                         computation))))
    ;; TODO: a macro similar to `symex-save-excursion`
    ;; where it conditionally returns to the original
    ;; point / node depending on whether BODY succeeds
    ;; or which tests for success before moving point
    (let ((original-location (point))
          (original-point-height-offset
           (symex--point-height-offset))
          (new-result (symex--execute-traversal traversal
                                                computation
                                                result)))
      (if new-result
          new-result
        ;; TODO: simply returning to the original location
        ;; isn't enough when the traversal might include
        ;; transformations. It may be necessary to execute
        ;; traversals in a temporary buffer.
        (goto-char original-location)
        (symex-select-nearest)
        (let* ((current-point-height-offset (symex--point-height-offset))
               (height-differential (- original-point-height-offset
                                       current-point-height-offset)))
          ;; necessary because point does not uniquely identify
          ;; a node for non-symex (i.e. tree-sitter) languages
          (symex--go-up height-differential))
        new-result))))


(provide 'symex-evaluator)
;;; symex-evaluator.el ends here

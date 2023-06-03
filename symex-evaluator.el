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

(defun symex--execute-tree-move (move &optional computation)
  "Execute the specified MOVE at the current point location in the tree.

Evaluates to the actual move executed or nil if no move was executed.
Optional argument COMPUTATION currently unused.

This interface is an \"abstraction barrier\" to keep the details of the
elementary navigation of symexes as a black box.  The implementation
of these elementary operations could be changed in the future (e.g. to
incorporate an explicit AST representation for greater precision) without
requiring changes to higher-level code that uses the present interface."
  (ignore computation)
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

(defun symex-execute-move (move &optional computation)
  "Execute the MOVE as a traversal.

This returns a list of moves (singleton, in this case) rather than the
executed move itself.  TODO: not sure this is needed anymore.
Optional argument COMPUTATION currently unused."
  (let ((executed-move (symex--execute-tree-move move computation)))
    (when executed-move
      (list executed-move))))

(defun symex--compute-results (a b computation)
  "Combine component computed results A and B into an aggregate result.

The aggregate result is constructed according to the specified COMPUTATION."
  ;; TODO: ruminate here
  ;; a and b should each have as many elements as the number of components
  ;; in the computation
  ;; later, a and b could be generators instead of lists of results
  (funcall (symex--computation-act computation)
           (funcall (symex--computation-perceive computation) a)
           (funcall (symex--computation-perceive computation) b)))

(defun symex-execute-maneuver (maneuver computation)
  "Attempt to execute a given MANEUVER.

Attempts the maneuver in the order of its phases.  The maneuver
succeeds only if all of the phases succeed, and otherwise fails.

Evaluates to a COMPUTATION on the traversal actually executed."
  (if (symex--maneuver-null-p maneuver)
      (list symex--move-zero)
    (let ((current-phase (symex--maneuver-first maneuver))
          (remaining-maneuver (symex--maneuver-rest maneuver)))
      (let ((executed-phase (symex-execute-traversal current-phase
                                                     computation)))
        (when executed-phase
          (let ((executed-remaining-phases
                 (symex-execute-maneuver remaining-maneuver
                                         computation)))
            (when executed-remaining-phases
              (symex--compute-results executed-phase
                                      (if (equal executed-remaining-phases
                                                 (list symex--move-zero))
                                          nil
                                          executed-remaining-phases)
                                      computation))))))))

(defun symex-execute-venture (venture computation)
  "Attempt to execute a given VENTURE.

Similar to maneuver execution, except that it accepts partial
completion.  That is, this attempts the venture in the order of its
phases.  If any phase fails, then the venture is terminated at that
step.  The venture succeeds if at least one phase succeeds, and
otherwise fails.

Evaluates to a COMPUTATION on the traversal actually executed."
  (unless (symex--venture-null-p venture)
    (let ((current-phase (symex--venture-first venture))
          (remaining-venture (symex--venture-rest venture)))
      (let ((executed-phase (symex-execute-traversal current-phase
                                                     computation)))
        (when executed-phase
          (let ((executed-remaining-phases
                 (symex-execute-venture remaining-venture
                                        computation)))
            (symex--compute-results executed-phase
                                    executed-remaining-phases
                                    computation)))))))

(defun symex-execute-circuit (circuit computation)
  "Execute a CIRCUIT.

This repeats some traversal as specified.

Evaluates to a COMPUTATION on the traversal actually executed."
  (let ((traversal (symex--circuit-traversal circuit))
        (times (symex--circuit-times circuit))
        (remaining-circuit (symex--circuit-rest circuit)))
    (when (or (not times)  ; loop indefinitely
              (> times 0))
      (let ((result (symex-execute-traversal traversal
                                             computation)))
        (if result
            (let ((executed-remaining-circuit
                   (symex-execute-circuit remaining-circuit
                                          computation)))
              (symex--compute-results result
                                      executed-remaining-circuit
                                      computation))
          (when (not times)
            ;; if looping indefinitely, then count 0
            ;; times executed as success
            (symex--compute-results (list symex--move-zero)
                                    nil
                                    computation)))))))

(defun symex-execute-detour (detour computation)
  "Execute the DETOUR.

Apply a reorientation and then attempt the traversal.

If the traversal fails, then the reorientation is attempted as many times as
necessary until either it succeeds, or the reorientation fails.

Evaluates to a COMPUTATION on the traversal actually executed."
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

Evaluates to a COMPUTATION on the traversal actually executed."
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

Evaluates to a COMPUTATION on the traversal actually executed."
  (unless (symex--protocol-null-p protocol)
    (let ((option (symex--protocol-first protocol))
          (remaining-protocol (symex--protocol-rest protocol)))
      (let ((executed-option (symex-execute-traversal option
                                                      computation)))
        (if executed-option
            executed-option
          (symex-execute-protocol remaining-protocol
                                  computation))))))

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

(defun symex-execute-deletion (deletion computation)
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
    (let ((result (symex-prim-delete what)))
      ;; TODO: compute based on an appropriate result here
      (when result
        (symex--compute-results (list symex--move-zero)
                                nil
                                computation)))))

(defun symex-execute-paste (paste computation)
  "Attempt to execute a given PASTE.

Evaluates to a COMPUTATION on the traversal actually executed."
  (let ((side (symex--paste-side paste)))
    (let ((result (symex-prim-paste side)))
      ;; TODO: compute based on an appropriate result here
      (when result
        (symex--compute-results (list symex--move-zero)
                                nil
                                computation)))))

(defun symex-execute-effect (effect computation)
  "Attempt to execute a given EFFECT.

Evaluates to a COMPUTATION on the traversal actually executed."
  (let ((traversal (symex--effect-traversal effect))
        (effect (symex--effect-effect effect)))
    (let ((executed-traversal (symex-execute-traversal traversal
                                                       computation)))
      (when executed-traversal
        (let ((executed-effect (funcall effect)))
          (symex--compute-results executed-traversal
                                  nil
                                  computation))))))

(defun symex--execute-traversal (traversal computation)
  "Helper to execute TRAVERSAL and perform COMPUTATION."
  (cond ((symex-maneuver-p traversal)
         (symex-execute-maneuver traversal
                                 computation))
        ((symex-venture-p traversal)
         (symex-execute-venture traversal
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
        ((symex-delete-p traversal)
         (symex-execute-deletion traversal
                                 computation))
        ((symex-paste-p traversal)
         (symex-execute-paste traversal
                              computation))
        ((symex-effect-p traversal)
         (symex-execute-effect traversal
                               computation))
        (t (funcall traversal))))

(defun symex-execute-traversal (traversal &optional computation)
  "Execute a tree TRAVERSAL.

TRAVERSAL could be a move, a maneuver, or any other Symex traversal.
If it is not a Symex expression, then it is assumed to be an ELisp
function, and the rule for interpretation is to apply the function.

Evaluates to a COMPUTATION on the traversal actually executed."
  (let ((computation (if computation
                         computation
                       symex--computation-default)))
    ;; TODO: a macro similar to `symex-save-excursion`
    ;; where it conditionally returns to the original
    ;; point / node depending on whether BODY succeeds
    ;; or which tests for success before moving point
    (let ((original-location (point))
          (original-point-height-offset
           (symex--point-height-offset))
          (executed-traversal (symex--execute-traversal traversal
                                                        computation)))
      (let ((result (symex--compute-results executed-traversal
                                            nil
                                            computation)))
        (if result
            result
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
          result)))))


(provide 'symex-evaluator)
;;; symex-evaluator.el ends here

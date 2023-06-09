;;; symex-computations.el --- An evil way to edit Lisp symbolic expressions as trees -*- lexical-binding: t -*-

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

;; Standard computations that can be performed as part of traversing symexes.

;;; Code:


(require 'cl-lib)

(require 'symex-data)

;;;;;;;;;;;;;;;;;;;;
;;; COMPUTATIONS ;;;
;;;;;;;;;;;;;;;;;;;;

(cl-defun symex-make-computation (&key
                                  components
                                  (perceive #'identity)
                                  (select #'identity)
                                  (filter #'identity)
                                  (synthesize #'identity)
                                  (express #'identity)
                                  (act #'identity))
  "A computation to be performed as part of a traversal.

COMPONENTS - a list of nested computations that will each process the
input independently and produce a result.  These results will then be
filtered and finally considered collectively to produce a decision.
PERCEIVE - the function to be applied to the result of each traversal step,
which transforms it to the perceived type.
SELECT - a predicate function that is applied to perceived values in order
to select the subset of perceptions that will be operated on by nested
computations.
FILTER - a predicate function to be applied to results from nested computations
to select those that will factor into the decision.
SYNTHESIZE - a binary function to be applied in combining results from nested
computations (each of the \"perceived\" type) to yield the provisional result
\(also of the perceived type).
EXPRESS - a function to transform data of the perceived type (e.g. the
type produced by the decision) to the application type (the type that can be
used by the application).
ACT - a binary function to be applied in combining results from the overall
computation (each of the \"expressed\" type) to yield the final result
\(also of the expressed type)."
  (list 'computation
        components
        perceive
        select
        filter
        synthesize
        express
        act))

(defun symex--computation-components (computation)
  "The components of the COMPUTATION."
  (nth 1 computation))

(defun symex--computation-perceive (computation)
  "The perception procedure of the COMPUTATION."
  (nth 2 computation))

(defun symex--computation-select (computation)
  "The selection procedure of the COMPUTATION."
  (nth 3 computation))

(defun symex--computation-filter (computation)
  "The filtration/redaction procedure of the COMPUTATION."
  (nth 4 computation))

(defun symex--computation-synthesize (computation)
  "The synthesize procedure of the COMPUTATION."
  (nth 5 computation))

(defun symex--computation-express (computation)
  "The expression procedure of the COMPUTATION."
  (nth 6 computation))

(defun symex--computation-act (computation)
  "The act procedure of the COMPUTATION."
  (nth 7 computation))

(defun symex-compute-results (a b computation)
  "Compose traversal results according to COMPUTATION.

Combine the result of a traversal computation A with the accumulated
computation B into an aggregate result."
  ;; TODO: ruminate here
  (when (and a b)
    (funcall (symex--computation-synthesize computation)
             a
             b)))

(defun symex--ruminate (computation components input)
  "Helper to process input in nested computations.

COMPUTATION - the computation
COMPONENTS - the components of the computation
INPUT - the input."
  (let ((current (car components))
        (remaining (cdr components)))
    (if current
        (funcall (symex--computation-decide computation)
                 (symex-ruminate current
                                 input)
                 (symex--ruminate computation
                                  remaining
                                  input))
      input)))

(defun symex-ruminate (computation input)
  "Have the COMPUTATION process the INPUT and produce a result."
  (let ((perceived-input (funcall (symex--computation-perceive computation)
                                  input)))
    (let ((components (symex--computation-components computation)))
      (funcall (symex--computation-express computation)
               (symex--ruminate computation components perceived-input)))))

(defconst symex--computation-default
  (symex-make-computation :perceive #'list
                          :synthesize #'append)
  "Each move is wrapped in a list. These are concatenated using list
concatenation.")

(defun symex--const-1 (_x)
  "A constant function return 1 regardless of the input."
  1)

(defconst symex--computation-count-moves
  (symex-make-computation :perceive #'symex--const-1
                          :synthesize #'+)
  "Each move is counted as 1, even zero moves.  The results are
concatenated by addition.")

(defconst symex--computation-traversal-length
  (symex-make-computation :perceive #'symex--move-length
                          :synthesize #'+)
  "Each move that actually moves is counted as 1.  The results are
concatenated by addition.")

(defconst symex--computation-net-traversal-dimensions
  (symex-make-computation :perceive #'identity
                          :synthesize #'symex--move-+)
  "X-axis (forward/backward) and y-axis (up/down) moves are added
separately. The results are concatenated by vector addition.")

(defconst symex--computation-traversal-dimensions
  (symex-make-computation :perceive #'identity
                          :synthesize #'symex--move-abs-+)
  "X-axis (forward/backward) and y-axis (up/down) moves are added
separately as absolute (non-negative) values.  The results are
concatenated by vector addition and represent how many total up/down
steps and how many total forward/backward steps were taken.")

(defun symex--move-delta-+ (a b)
  "Add moves A and B using vector addition accounting for height changes.

The index only participates in the addition when we are at the same
height as the original position."
  (let ((x1 (symex--move-x a))
        (y1 (symex--move-y a))
        (x2 (symex--move-x b))
        (y2 (symex--move-y b)))
    (let ((x (+ x1 x2))
          (y (+ y1 y2)))
      (cond ((symex--zero-move-p a) b)
            ((= 0 y)
             ;; we're at the height we started the traversal at
             ;; so it makes sense to add movement in the x-direction
             (symex-make-move x y))
            (t
             ;; don't modify the accumulated value of x
             ;; as we are at a different height
             (symex-make-move x1 y))))))

(defconst symex--computation-node-distance
  (symex-make-computation :perceive #'identity
                          :synthesize #'symex--move-delta-+)
  "X-axis (forward/backward) and y-axis (up/down) moves are added
separately. The results are concatenated by vector addition. Index
deltas are only added together when at the same height as the original
position.")

(defun symex--traversal-account (obj)
  "Represents the result OBJ of a traversal as a traversal."
  (cond ((symex-traversal-p obj)
         obj)
        (t (apply #'symex-make-maneuver obj))))

;; (defconst computation-account
;;   ;; each result is cast as a maneuver and wrapped in a list for composition
;;   ;; the results are concatenated using list concatenation
;;   (symex-make-computation :f-to-aggregation #'symex--type-list
;;                           :map #'symex--traversal-account
;;                           :reduce #'append
;;                           :f-from-aggregation #'car))

(defun symex--simplify-maneuver-phases (phases)
  "Helper to flatten maneuver PHASES to moves."
  (when phases
    (let ((phase (car phases))
          (remaining-phases (cdr phases)))
      (let ((moves (if (symex-move-p phase)
                       (list phase)
                     (let ((simplified-phase (symex--simplify-maneuver phase)))
                       (symex--maneuver-phases simplified-phase)))))
        (append moves
                (symex--simplify-maneuver-phases remaining-phases))))))

(defun symex--simplify-maneuver (maneuver)
  "Reduce a complex MANEUVER to a flat maneuver whose phases are moves."
  (let ((phases (symex--maneuver-phases maneuver)))
    (let* ((simplified-phases (symex--simplify-maneuver-phases phases))
           (maneuver-length (length simplified-phases)))
      (cond ((= maneuver-length 1)
             ;; just return the move
             (nth 0 simplified-phases))
            ((> maneuver-length 1)
             (apply #'symex-make-maneuver simplified-phases))))))

(defun symex--interpret-simple-traversal (traversal)
  "Interpret a TRAVERSAL as a single, flat maneuver or move."
  (cond ((symex-maneuver-p traversal)
         (symex--simplify-maneuver traversal))
        ((symex-move-p traversal)
         traversal)
        (t (error "Syntax error: unrecognized traversal type!"))))

;; (defconst computation-simple-account
;;   ;; each result is cast as a maneuver and wrapped in a list for composition
;;   ;; the results are concatenated using list concatenation
;;   (symex-make-computation :f-to-aggregation #'symex--type-list
;;                           :map (-compose #'symex--interpret-simple-traversal
;;                                          #'symex--traversal-account)
;;                           :reduce #'append
;;                           :f-from-aggregation #'car))

(defun symex--streamline-to-maneuver (maneuver-or-move)
  "Streamline traversal to a representation as a maneuver.

If MANEUVER-OR-MOVE is a maneuver, leave as is.
If it is a move, convert to the equivalent maneuver (via simple casting)."
  (if (symex-move-p maneuver-or-move)
      (symex-make-maneuver maneuver-or-move)
    maneuver-or-move))

(defun symex--add-numbers (&rest numbers)
  "Sum NUMBERS."
  (apply #'+ numbers))

;; (defconst computation-length
;;   ;; each result is interpreted down to a simple maneuver
;;   ;; the phases of this maneuver are extracted and summed using
;;   ;; move addition.
;;   ;; the results are accumulated using addition of numbers
;;   (symex-make-computation :f-to-aggregation #'symex--type-integer
;;                           :map (-compose #'symex--move-length
;;                                          #'symex--add-moves
;;                                          #'symex--maneuver-phases
;;                                          #'symex--streamline-to-maneuver
;;                                          #'symex--interpret-simple-traversal
;;                                          #'symex--traversal-account)
;;                           :reduce #'symex--add-numbers
;;                           :f-from-aggregation #'car))


(provide 'symex-computations)
;;; symex-computations.el ends here

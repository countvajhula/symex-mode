;;; symex-transformations.el --- An evil way to edit Lisp symbolic expressions as trees -*- lexical-binding: t -*-

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

;; Standard mutative operations to be performed on symexes.

;;; Code:

(require 'cl-lib)

(require 'symex-transformations-lisp)
(require 'symex-transformations-ts)

;; TODO: Remove dependencies after moving to symex-transformations-lisp.el
(require 'paredit)
(require 'evil)
(require 'evil-surround)
(require 'symex-misc)
(require 'symex-primitives)
(require 'symex-primitives-lisp)
(require 'symex-utils)
(require 'symex-traversals)
(require 'symex-evaluator)
(require 'symex-interop)

;;;;;;;;;;;;;;;;;;;;;;;
;;; TRANSFORMATIONS ;;;
;;;;;;;;;;;;;;;;;;;;;;;

;; TODO: `symex-define-command` macro
;; - write the wrapping code before and after without needing advice
;; - select-nearest etc. after, and remove the ad hoc cases
;; - this would also allow more fine-grained handling, e.g. different types of commands
;; - this would also avoid the need for `symex--evil-repeatable-commands`, so that we could `(evil-add-command-properties fn :repeat t)` directly -- this would also support users defining new symex commands and having them be repeatable without a manual registration process
;; TODO: dot operator disrupts scroll margins
;; TODO: maybe identify "non-disorienting" commands and define a new macro for them. E.g. symex-tidy is itself a command. it that bad?

(defmacro symex-define-command (name
                                args
                                docstring
                                interactive-decl
                                &rest
                                body)
  "Define a symex command."
  (declare (indent defun))
  (let ((result (gensym)))
    `(defun ,name ,args
       ,docstring
       ,interactive-decl
       (let ((,result (progn ,@body)))
         (symex-user-select-nearest)
         ;; Note that the built-in `fixup-whitespace` that's used in
         ;; `symex-tidy` causes the buffer to reflect as modified even
         ;; if it doesn't actually make any modifications.  In such
         ;; cases, a null change is also pushed onto the undo stack,
         ;; meaning that executing `undo` results in a no-op at first,
         ;; and we need to hit `u` again to undo the real change we
         ;; meant to undo.  We could fix this on the Symex side by
         ;; only invoking tidy if we see that the buffer has been
         ;; modified, but it would be better to fix `fixup-whitespace`
         ;; so it doesn't mark the buffer as modified if no changes
         ;; were made.
         (symex--tidy 1)
         ,result))))

(defmacro symex-define-insertion-command (name
                                          args
                                          docstring
                                          interactive-decl
                                          &rest
                                          body)
  "Define a symex command that enters an insertion state."
  (declare (indent defun))
  `(defun ,name ,args
     ,docstring
     ,interactive-decl
     (evil-start-undo-step)
     ,@body
     (symex-enter-lowest)))

(defun symex--delete (count)
  "Delete COUNT symexes."
  ;; if we attempt to just (delete this) count times, if there happen
  ;; to be fewer than count expressions following, then we may delete
  ;; preceding expressions too. But we typically mean to delete only
  ;; the succeeding expressions here.
  ;;
  ;; In lieu of doing it in two traversals, we could potentially
  ;; either introduce a new traversal type that always executes every
  ;; subexpression even if any of them fail, or, we could first
  ;; compute (either in symex or in Elisp) the number of succeeding
  ;; expressions or count, whichever is lower, and then execute the
  ;; deletion traversal on that modified count.
  (symex-execute-traversal
   (symex-traversal
    (circuit (delete next)
             (1- count))))
  (symex-execute-traversal
   (symex-traversal
    (delete this))))

(symex-define-command symex-delete (count)
  "Delete COUNT symexes."
  (interactive "p")
  (symex--delete count))

(symex-define-command symex-delete-backwards (count)
  "Delete COUNT symexes backwards."
  (interactive "p")
  (symex-execute-traversal
   (symex-traversal
    (circuit (delete previous)
             count))))

(symex-define-command symex-delete-remaining ()
  "Delete remaining symexes at this level."
  (interactive)
  (let ((count (symex--remaining-length)))
    (symex--delete count)))

(symex-define-insertion-command symex-change (count)
  "Change COUNT symexes."
  (interactive "p")
  (symex--remove count))

(symex-define-insertion-command symex-change-remaining ()
  "Change remaining symexes at this level."
  (interactive)
  (let ((count (symex--remaining-length)))
    (symex--remove count)))

(symex-define-insertion-command symex-replace ()
  "Replace contents of symex."
  (interactive)
  (if (symex-tree-sitter-p)
      (symex-ts-replace)
    (symex-lisp-replace)))

(symex-define-command symex-clear ()
  "Clear contents of symex."
  (interactive)
  (if (symex-tree-sitter-p)
      (symex-ts-clear)
    (symex-lisp-clear)))

(defun symex--emit-backward (count)
  "Emit backward."
  (dotimes (_ count)
    (symex-execute-traversal symex--traversal-emit-backward)))

(symex-define-command symex-emit-backward (count)
  "Emit backward, COUNT times."
  (interactive "p")
  (symex--emit-backward count))

(defun symex--emit-forward (count)
  "Emit forward."
  (dotimes (_ count)
    (symex-execute-traversal symex--traversal-emit-forward)))

(symex-define-command symex-emit-forward (count)
  "Emit forward, COUNT times."
  (interactive "p")
  (symex--emit-forward count))

(defun symex--capture-backward (count)
  "Capture from behind."
  (dotimes (_ count)
    (symex-execute-traversal symex--traversal-capture-backward)))

(symex-define-command symex-capture-backward (count)
  "Capture from behind, COUNT times."
  (interactive "p")
  (symex--capture-backward count))

(defun symex--capture-forward (count)
  "Capture from the front."
  (dotimes (_ count)
    (symex-execute-traversal symex--traversal-capture-forward)))

(symex-define-command symex-capture-forward (count)
  "Capture from the front, COUNT times."
  (interactive "p")
  (symex--capture-forward count))

(symex-define-command symex-split ()
  "Split symex into two."
  (interactive)
  (paredit-split-sexp)
  (forward-char))

(defun symex--join ()
  "Merge symexes at the same level."
  (save-excursion
    (when (symex--go-forward)
      (paredit-join-sexps))))

(symex-define-command symex-join (count)
  "Merge COUNT symexes at the same level."
  (interactive "p")
  (dotimes (_ count)
    (symex--join)))

(symex-define-command symex-join-lines (count)
  "Join COUNT lines inside symex."
  (interactive "p")
  (dotimes (_ count)
    (symex--join-lines)))

(symex-define-command symex-join-lines-backwards (count)
  "Join COUNT lines backwards inside symex."
  (interactive "p")
  (dotimes (_ count)
    (symex--join-lines t)))

(defun symex--same-line-tidy-affected ()
  "Tidy symexes affected by line-oriented operations.

This assumes that point is at the end of whatever change has been
made, and tidies the next symex if it is on the same line. Then, it
continues tidying symexes as long as the next one begins on the same
line that the preceding one ends on."
  (symex--save-point-excursion
    ;; assume point is at the end of the triggering change
    (let ((affected (or (symex-lisp--point-at-start-p)
                        (= (line-number-at-pos)
                           ;; does the next symex start on the same line?
                           (if (symex--go-forward)
                               (line-number-at-pos)
                             -1)))))
      (while affected
        (symex--tidy 1)
        (setq affected
              (= (save-excursion  ; does the symex end on the same line
                   (forward-sexp) ; that the next one begins on?
                   (line-number-at-pos))
                 (if (symex--go-forward)
                     (line-number-at-pos)
                   -1)))))))

(defun symex--join-lines (&optional backwards)
  "Join lines inside symex.

If BACKWARDS is true, then joins current symex to previous one, otherwise,
by default, joins next symex to current one."
  (if backwards
      (when (symex--point-at-indentation-p)
        (join-line)
        (when (looking-at-p "[[:space:]]")
          (symex--go-to-next-non-whitespace-char)))
    (unless (symex--point-on-last-line-p)
      (save-excursion
        (forward-sexp)
        (join-line t))
      ;; every subsequent symex that begins on
      ;; the same line that the preceding one ends on
      ;; should be indented
      (symex--same-line-tidy-affected))))

(defun symex-yank (count)
  "Yank (copy) COUNT symexes."
  (interactive "p")
  (if (symex-tree-sitter-p)
    (symex-ts-yank count)
    (symex-lisp-yank count)))

(defun symex-yank-remaining ()
  "Yank (copy) remaining symexes at this level."
  (interactive)
  (let ((count (symex--remaining-length)))
    (symex-yank count)))

(symex-define-command symex-paste-before (count)
  "Paste before symex, COUNT times."
  (interactive "p")
  (setq this-command 'evil-paste-before)
  ;; typically (e.g. to follow the convention in evil), we
  ;; want to select the start of the pasted text after
  ;; pasting.
  ;; TODO: make this post-paste selection a defcustom
  (symex-execute-traversal
   (symex-traversal
    (decision (at first)
              (maneuver (circuit (paste before)
                                 count)
                        (circuit (move backward)))
              (maneuver (move backward)
                        (circuit (paste after)
                                 count)
                        (move forward))))))

(symex-define-command symex-paste-after (count)
  "Paste after symex, COUNT times."
  (interactive "p")
  (setq this-command 'evil-paste-after)
  (symex-execute-traversal
   (symex-traversal
    (maneuver (circuit (paste after)
                       count)
              ;; select the start of pasted text.
              (move forward)))))

(symex-define-insertion-command symex-open-line-after ()
  "Open new line after symex."
  (interactive)
  (if (symex-tree-sitter-p)
      (symex-ts-open-line-after)
    (symex-lisp-open-line-after)))

(symex-define-insertion-command symex-open-line-before ()
  "Open new line before symex."
  (interactive)
  (if (symex-tree-sitter-p)
      (symex-ts-open-line-before)
    (symex-lisp-open-line-before)))

(symex-define-insertion-command symex-append-after ()
  "Append after symex (instead of vim's default of line)."
  (interactive)
  (if (symex-tree-sitter-p)
      (symex-ts-append-after)
    (symex-lisp-append-after)))

(symex-define-insertion-command symex-insert-before ()
  "Insert before symex (instead of vim's default at the start of line)."
  (interactive)
  (if (symex-tree-sitter-p)
      (symex-ts-insert-before)
    (symex-lisp-insert-before)))

(symex-define-insertion-command symex-insert-at-beginning ()
  "Insert at beginning of symex."
  (interactive)
  (if (symex-tree-sitter-p)
      (symex-ts-insert-at-beginning)
    (symex-lisp-insert-at-beginning)))

(symex-define-insertion-command symex-insert-at-end ()
  "Insert at end of symex."
  (interactive)
  (if (symex-tree-sitter-p)
      (symex-ts-insert-at-end)
    (symex-lisp-insert-at-end)))

(defun symex--create (type)
  "Create new symex (list).

New list delimiters are determined by the TYPE."
  (save-excursion
    (cond ((equal type 'round)
           (insert "()"))
          ((equal type 'square)
           (insert "[]"))
          ((equal type 'curly)
           (insert "{}"))
          ((equal type 'angled)
           (insert "<>")))))

(symex-define-command symex-create-round ()
  "Create new symex with round delimiters."
  (interactive)
  (symex--create 'round))

(symex-define-command symex-create-square ()
  "Create new symex with square delimiters."
  (interactive)
  (symex--create 'square))

(symex-define-command symex-create-curly ()
  "Create new symex with curly delimiters."
  (interactive)
  (symex--create 'curly))

(symex-define-command symex-create-angled ()
  "Create new symex with angled delimiters."
  (interactive)
  (symex--create 'angled))

(symex-define-command symex-insert-newline (count)
  "Insert COUNT newlines before symex."
  (interactive "p")
  (newline-and-indent count))

(symex-define-command symex-append-newline (count)
  "Append COUNT newlines after symex."
  (interactive "p")
  (save-excursion
    (forward-sexp)
    (newline-and-indent count)
    (fixup-whitespace))
  (symex--same-line-tidy-affected))

(symex-define-command symex-swallow ()
  "Swallow the head of the symex.

This consumes the head of the symex, putting the rest of its contents
in the parent symex."
  (interactive)
  (save-excursion
    (symex--go-up)
    (symex--go-forward)
    (paredit-splice-sexp-killing-backward)))

(symex-define-command symex-swallow-tail ()
  "Swallow the tail of the symex.

This consumes the tail of the symex, putting the head
in the parent symex."
  (interactive)
  (save-excursion
    (symex--go-up)
    (symex--go-forward)
    (paredit-splice-sexp-killing-forward)
    (symex--go-backward)))

(symex-define-command symex-splice ()
  "Splice or \"clip\" symex.

If the symex is a nested list, this operation eliminates the symex,
putting its contents in the parent symex.  If the symex is an atom,
then no action is taken."
  (interactive)
  (when (or (symex-left-p) (symex-string-p))
    (if (or (symex-empty-list-p)
            (symex-empty-string-p))
        (symex--delete 1)
      (save-excursion
        (evil-surround-delete (char-after))
        (symex--go-down)))))

(symex-define-command symex-wrap-round ()
  "Wrap with ()."
  (interactive)
  (paredit-wrap-round)
  (symex--go-down))

(symex-define-command symex-wrap-square ()
  "Wrap with []."
  (interactive)
  (paredit-wrap-square)
  (symex--go-down))

(symex-define-command symex-wrap-curly ()
  "Wrap with {}."
  (interactive)
  (paredit-wrap-curly)
  (evil-find-char-backward nil 123))

(symex-define-command symex-wrap-angled ()
  "Wrap with <>."
  (interactive)
  (paredit-wrap-angled)
  (evil-find-char-backward nil 60))

(symex-define-insertion-command symex-wrap ()
  "Wrap with containing symex."
  (interactive)
  (symex-wrap-round)
  (symex--go-up))

(symex-define-insertion-command symex-wrap-and-append ()
  "Wrap with containing symex and append."
  (interactive)
  (symex-wrap-round)
  (symex--go-up)
  (forward-sexp))

(defun symex--shift-forward ()
  "Move symex forward in current tree level."
  (unless (symex--point-at-last-symex-p)
    (forward-sexp)
    (condition-case nil
        (progn (transpose-sexps 1)
               (backward-sexp)
               t)
      (error (backward-sexp)
             nil))))

(symex-define-command symex-shift-forward (count)
  "Move symex forward COUNT times in current tree level."
  (interactive "p")
  (dotimes (_ count)
    (symex--shift-forward)))

(symex-define-command symex-shift-forward-most ()
  "Move symex backward COUNT times in current tree level."
  (interactive)
  (let ((col (current-column))
        (row (line-number-at-pos))
        (result t))
    (while (and result
                (or (= col (current-column))
                    (= row (line-number-at-pos))))
      (setq result (symex--shift-forward)))
    (unless (or (= col (current-column))
                (= row (line-number-at-pos)))
      (symex--shift-backward))))

(defun symex--shift-backward ()
  "Move symex backward in current tree level."
  (let ((move (symex--go-backward)))
    (when move
      (symex--shift-forward)
      (symex--go-backward)
      t)))

(symex-define-command symex-shift-backward (count)
  "Move symex backward COUNT times in current tree level."
  (interactive "p")
  (dotimes (_ count) (symex--shift-backward)))

(symex-define-command symex-shift-backward-most ()
  "Move symex backward COUNT times in current tree level."
  (interactive)
  (let ((col (current-column))
        (row (line-number-at-pos))
        (result t))
    (while (and result
                (or (= col (current-column))
                    (= row (line-number-at-pos))))
      (setq result (symex--shift-backward)))
    (unless (or (= col (current-column))
                (= row (line-number-at-pos)))
      (symex--shift-forward))))

(symex-define-command symex-change-delimiter ()
  "Change delimiter enclosing current symex, e.g. round -> square brackets."
  (interactive)
  (if (or (symex-left-p) (symex-string-p))
      (evil-surround-change (following-char))
    (let ((bounds (bounds-of-thing-at-point 'sexp)))
      (evil-surround-region (car bounds) (cdr bounds) 'inclusive 40))))

(symex-define-command symex-comment (count)
  "Comment out COUNT symexes."
  (interactive "p")
  (if (symex-tree-sitter-p)
      (symex-ts-comment count)
    (progn
      (mark-sexp count)
      (comment-dwim nil))))

(symex-define-command symex-comment-remaining ()
  "Comment out remaining symexes at this level."
  (interactive)
  (let ((count (symex--remaining-length)))
    (symex-comment count)))

(defun symex--delete-prefix-helper (prefix-list)
  "Delete the first prefix in PREFIX-LIST that matches the text at point.

The index of the deleted prefix is returned, or a negative value if no prefix
matched."
  (if (null prefix-list)
      -9999
    (let ((prefix (car prefix-list))
          (remaining-prefixes (cdr prefix-list)))
      (if (looking-at-p prefix)
          (progn
            (delete-char (length prefix))
            0)
        (1+ (symex--delete-prefix-helper remaining-prefixes))))))

(defun symex--delete-prefix (prefix-list)
  "Delete the longest prefix in PREFIX-LIST that matches the text at point.

The index of the deleted prefix is returned, or a negative value if no prefix
matched."
  ;; sort the prefix list by length so that we match the longest prefix
  ;; when there are many possible matches, e.g. ,@(...) should match
  ;; ,@ rather than ,
  (let* ((sorted-prefix-list (sort (cl-copy-list prefix-list)
                                   (lambda (a b)
                                     (> (length a) (length b)))))
         (sorted-idx (symex--delete-prefix-helper sorted-prefix-list)))
    (if (>= sorted-idx 0)
        ;; since the sorted list is a permutation of the original
        ;; prefix list, map the returned sorted index to the
        ;; corresponding index on the original list
        (cl-position (elt sorted-prefix-list sorted-idx)
                     prefix-list)
      sorted-idx)))

(defun symex--insert-prefix (prefix-list index)
  "Insert a prefix at point selected from a user-customized list of prefixes.

Inserts the prefix at position INDEX in PREFIX-LIST into the buffer at
point.  If INDEX exceeds the length of the prefix list, then nothing
is inserted.  This has the effect, when used in succession to
`symex--delete-prefix`, of returning the content to an unprefixed state
after it has cycled once through the prefixes."
  (unless (>= index (length prefix-list))
    (insert (elt prefix-list (max 0 index)))))

(defun symex--cycle-prefix (prefix-list index)
  "Cycle through (and insert into the buffer) prefixes in PREFIX-LIST.

If INDEX is provided, insert the prefix at INDEX instead of cycling."
  (save-excursion
    (let ((deleted-index (symex--delete-prefix prefix-list)))
      (if index
          (symex--insert-prefix prefix-list index)
        (symex--insert-prefix prefix-list (1+ deleted-index))))))

(symex-define-command symex-cycle-quote (index)
  "Cycle through configured quoting prefixes in `symex-quote-prefix-list`.

If an INDEX is provided, then this replaces the existing prefix (if
any) with the prefix at position INDEX in the quoting prefix list
\(`symex-quote-prefix-list`).  If no index is specified, this replaces
the existing prefix (if any) with the one that comes next in the
prefix list.  If it goes past the end of the prefix list, the prefix is
removed entirely, restarting the cycle.

The INDEX begins at the 1st position in the prefix list, so the first
prefix in the list should be indicated with 1 rather than 0.  This is
because 0 has a different meaning in symex mode, and is an unusual
prefix argument to use in Emacs functions.  1-indexed behavior is also
the more natural choice here in any case."
  (interactive "P")
  (symex--cycle-prefix symex-quote-prefix-list (and index (1- index))))

(symex-define-command symex-cycle-unquote (index)
  "Cycle through configured quoting prefixes in `symex-unquote-prefix-list`.

If an INDEX is provided, then this replaces the existing prefix (if
any) with the prefix at position INDEX in the unquoting prefix list
\(`symex-unquote-prefix-list`).  If no index is specified, this
replaces the existing prefix (if any) with the one that comes next in
the prefix list.  If it goes past the end of the prefix list, the
prefix is removed entirely, restarting the cycle.

The INDEX begins at the 1st position in the prefix list, so the first
prefix in the list should be indicated with 1 rather than 0.  This is
because 0 has a different meaning in symex mode, and is an unusual
prefix argument to use in Emacs functions.  1-indexed behavior is also
the more natural choice here in any case."
  (interactive "P")
  (symex--cycle-prefix symex-unquote-prefix-list (and index (1- index))))

(symex-define-command symex-remove-quoting-level ()
  "Remove any quoting prefix at point, if present.

This removes either quoting or unquoting prefixes, and removes up to one
layer of quoting."
  (interactive)
  (symex--delete-prefix (append symex-quote-prefix-list
                                symex-unquote-prefix-list)))

(symex-define-command symex-add-quoting-level ()
  "Add a quoting level."
  (interactive)
  (insert "'"))

(symex-define-command symex-quasiquote ()
  "Quasiquote symex."
  (interactive)
  (insert "`"))

(symex-define-command symex-escape-quote ()
  "Escape quote in quoted symex."
  (interactive)
  (insert ","))

(symex-define-command symex-tidy (count)
  "Auto-indent symex and fix any whitespace."
  (interactive "p")
  (symex--tidy count))

(cl-defun symex--transform-in-isolation (traversal side-effect &key pre-traversal)
  "Transform a symex in a temporary buffer and replace the original with it.

First traverses using PRE-TRAVERSAL if non-nil, then traverses using
TRAVERSAL and performs SIDE-EFFECT at each step.  Note that the side
effect is not performed during the pre-traversal."
  (kill-sexp 1)
  (kill-new
   (let (original-syntax-table)
     ;; In using a temp buffer to do the transformation here, we need to
     ;; ensure that it uses the syntax table of the original buffer, since
     ;; otherwise it doesn't necessarily treat characters the same way
     ;; as the original buffer does, separating, for example, characters like
     ;; `?` and `#` from the rest of the symbol during recursive indentation.
     ;;
     ;; The with-temp-buffer macro doesn't see the original syntax table
     ;; when it is lexically defined here, not sure why. Defining a
     ;; lexical scope here and then setting it dynamically via `setq`
     ;; seems to work
     (setq original-syntax-table (syntax-table))
     (with-temp-buffer
       (with-syntax-table original-syntax-table
         (yank)
         (goto-char 0)
         (symex-execute-traversal pre-traversal)
         ;; do it once first since it will be executed as a side-effect
         ;; _after_ each step in the traversal
         (condition-case nil
             (funcall side-effect)
           (error nil))
         (condition-case nil
             (symex--do-while-traversing
              side-effect
              traversal)
           (error nil))
         (buffer-string)))))
  (save-excursion (yank))
  (symex--tidy 1))

(symex-define-command symex-tidy-proper ()
  "Properly tidy things up.

This operates on the subtree indicated by the selection, rather than
on the entire tree.  Ordinarily this would require \"remembering\" the
initial location on the tree while traversing and collapsing the
subexpressions, a feature (memory) that is absent in the Symex DSL.
But the present implementation gets around the need for memory by
copying the subtree into a temporary buffer and indenting it as a
complete tree, and then replacing the original symex with the
indented version from the temporary buffer.

When memory is added to the DSL, this would probably have a simpler
implementation."
  (interactive)
  (symex--transform-in-isolation
   symex--traversal-postorder-in-tree
   (apply-partially #'symex--tidy 1)
   :pre-traversal (symex-traversal (circuit symex--traversal-preorder-in-tree))))

(symex-define-command symex-collapse ()
  "Collapse a symex to a single line.

This operates on the subtree indicated by the selection, rather than
on the entire tree.  Ordinarily this would require \"remembering\" the
initial location on the tree while traversing and collapsing the
subexpressions, a feature (memory) that is absent in the Symex DSL.
But the present implementation gets around the need for memory by
copying the subtree into a temporary buffer and collapsing it as a
complete tree, and then replacing the original symex with the
collapsed version from the temporary buffer.

When memory is added to the DSL, this would probably have a simpler
implementation."
  (interactive)
  (symex--transform-in-isolation
   (symex-traversal
    (precaution symex--traversal-postorder-in-tree
                (afterwards (not (at root)))))
   (apply-partially #'symex--join-lines t)
   :pre-traversal (symex-traversal (circuit symex--traversal-preorder-in-tree))))

(symex-define-command symex-collapse-remaining ()
  "Collapse the remaining symexes to the current line."
  (interactive)
  (save-excursion
    (let ((line (line-number-at-pos)))
      (symex--do-while-traversing (lambda ()
                                    (unless (= line (line-number-at-pos))
                                      (symex--join-lines t)))
                                  (symex-make-move 1 0)))))

(symex-define-command symex-unfurl-remaining ()
  "Unfurl the remaining symexes so they each occupy separate lines."
  (interactive)
  (save-excursion
    (symex--go-forward)
    ;; do it once first since it will be executed as a side-effect
    ;; _after_ each step in the traversal
    (symex-insert-newline 1)
    (symex--do-while-traversing (apply-partially #'symex-insert-newline 1)
                                (symex-make-move 1 0))))

(symex-define-command symex-tidy-remaining ()
  "Tidy the remaining symexes."
  (interactive)
  (symex--save-point-excursion
    ;; do it once first since it will be executed as a side-effect
    ;; _after_ each step in the traversal
    (symex--tidy 1)
    (symex--do-while-traversing (apply-partially #'symex--tidy 1)
                                (symex-make-move 1 0))))

(symex-define-command symex-unfurl ()
  "Unfurl the constituent symexes so they each occupy separate lines."
  (interactive)
  (save-excursion
    (symex--go-up)
    ;; TODO: should this be a private version instead?
    (symex-unfurl-remaining)))

(provide 'symex-transformations)
;;; symex-transformations.el ends here

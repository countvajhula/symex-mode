Symex DSL
=========

.. contents:: :depth: 1

Introduction
------------

The Symex.el Emacs package consists of three things: (1) A high-level language (or DSL) for tree operations, (2) A low-level tree abstraction layer, and (3) An Evil modal UI. The modal UI is documented in the `README <https://github.com/drym-org/symex.el/blob/master/README.rst>`_, and the low-level abstraction layer is fulfilled by third party packages like Paredit and Tree-Sitter. This is the documentation for the DSL.

The Symex DSL allows you to specify arbitrary tree traversals in a cursor-oriented manner. That is, instead of describing traversals from an absolute reference point such as a root node, it allows you to describe traversals from the first-person vantage point of the cursor -- what would you do if you were where this cursor is right now? It allows you to describe what you'd like to do in intuitive terms that make sense for movement in a tree. Symex is the language a squirrel might use to describe a traversal to another squirrel.

Usage
-----

The main entry point to Symex from ELisp is the ``symex-traversal`` form, which can also be used via the definition form, ``symex-deftraversal``. Within these forms, traversals may be specified using the Symex language. Traversals defined this way may be executed via ``symex-execute-traversal`` and would affect the active Emacs cursor. Side effects may be attached to traversals, so that an action (which could be any function) may be repeatedly taken as part of traversal execution. Some Symex features are implemented this way.

Language
--------

Movement
^^^^^^^^

Any action that moves your cursor from one node in the tree to another is called a traversal. Symex gives you several linguistic forms with which to describe traversals.

Each form of the language has its own syntax, and typically the clauses of these forms are expected to be traversals themselves. For instance, the ``maneuver`` form specifies a traversal as a sequence of other traversals to be executed in order.

In general, if a traversal succeeds, it returns a list of executed moves which if replayed manually from the starting position would have the same effect as running the traversal did. If the traversal fails, it returns ``nil``.

.. contents:: :local:
    :depth: 2

move
~~~~

Syntax
``````

``(move forward|backward|up|down)``

Description
```````````

The most basic movement, a move simply takes a single step in a particular direction, to a neighboring node in the tree.

Examples
````````

"Move forward."

::

  (symex-execute-traversal
    (symex-traversal
      (move forward)))

"Move backward."

::

  (symex-execute-traversal
    (symex-traversal
      (move backward)))

"Move up."

::

  (symex-execute-traversal
    (symex-traversal
      (move up)))

"Move down."

::

  (symex-execute-traversal
    (symex-traversal
      (move down)))

Note that in the Symex language, "up" and "down" are defined in relation to the root node being considered the bottom of the tree and increasingly nested expressions as being higher. We "go down towards the root and up towards the nest."

maneuver
~~~~~~~~

Syntax
``````

``(maneuver traversal ...)``

Description
```````````

Execute a sequence of traversals in order. The maneuver succeeds if *all* of the traversals succeed. If any of them fail, then the entire maneuver is aborted and nothing happens. In other words, the maneuver has "all or nothing" semantics. To accept partial completion, use ``venture`` instead.

Examples
````````

"Go forward, then up, and then forward again."

::

  (symex-execute-traversal
    (symex-traversal
      (maneuver (move forward)
                (move up)
                (move forward))))

"Go up and then keep going forward, and then go up again."

::

  (symex-execute-traversal
    (symex-traversal
      (maneuver (move up)
                (circuit (move forward))
                (move up))))

venture
~~~~~~~

Syntax
``````

``(venture traversal ...)``

Description
```````````

Execute a sequence of traversals in order. If the venture is partially completed, i.e. if at least one traversal was executed, then the venture is treated as successful. Otherwise it is considered to have failed.

Examples
````````

"Venture to go forward, then up, and then forward again."

::

  (symex-execute-traversal
    (symex-traversal
      (venture (move forward)
               (move up)
               (move forward))))

"Venture to go up and then keep going forward, and then go up again."

::

  (symex-execute-traversal
    (symex-traversal
      (venture (venture (move up)
                        (circuit (move forward)))
               (move up))))

protocol
~~~~~~~~

Syntax
``````

``(protocol traversal ...)``

Description
```````````

Try executing traversals, in order, until one succeeds (and then stop).

Examples
````````

"Try going forward, if that doesn't work try going backward."

::

  (symex-execute-traversal
    (symex-traversal
      (protocol (move forward)
                (move backward))))

"Try going forward and up, if that doesn't work try going backward and down."

::

  (symex-execute-traversal
    (symex-traversal
      (protocol (maneuver (move forward)
                          (move up))
                (maneuver (move backward)
                          (move down)))))

detour
~~~~~~

Syntax
``````

``(detour reorientation-traversal main-traversal)``

Description
```````````

Try executing a traversal by first reorienting yourself. If the main traversal fails, reorient yourself ("take a detour") and then try again. Keep repeating this until either the main traversal succeeds, or the reorientation fails. Both the main traversal as well as the reorientation can be any traversal.

Note that the reorientation is always executed prior to trying the main traversal, even the first time.

Examples
````````

"Attempt to go forward by first going down, and keep going down to try again."

::

  (symex-execute-traversal
    (symex-traversal
      (detour (move down)
              (move forward))))

"Attempt to go forward by first going down, and keep going down to try again as long as we don't descend to the root of the tree."

::

  (symex-execute-traversal
    (symex-traversal
      (detour (precaution (move down)
                          (afterwards (not (at root))))
              (move forward))))

decision
~~~~~~~~

Syntax
``````

``(decision condition traversal-A traversal-B)``

Description
```````````

Do either traversal A or traversal B, depending on whether a condition holds.

The condition can be any predicate -- either a built-in predicate form, or an arbitrary lambda. See `Predicates`_ for details.

Examples
````````

"If we're at the root of the tree, then go forward, otherwise go down."

::

  (symex-execute-traversal
    (symex-traversal
      (decision (at root)
                (move forward)
                (move down))))

"If we are somewhere before a previously stored position in the buffer, then go forward, otherwise don't move."

::

  (symex-execute-traversal
    (symex-traversal
      (decision (lambda () (< (point) previously-stored-position))
                (move forward)
                symex--move-zero)))

``symex--move-zero`` is just a convenient traversal for cases where you need to indicate a traversal but would like to not move at all. It is defined as ``(symex-make-move 0 0)``.

circuit
~~~~~~~

Syntax
``````

``(circuit traversal [times])``

Description
```````````

Repeat a traversal a given number of times or as long as it succeeds. When it fails, stop.

Examples
````````

"Move forward three times."

::

  (symex-execute-traversal
    (symex-traversal
      (circuit (move forward) 3)))

"Keep moving forward."

::

  (symex-execute-traversal
    (symex-traversal
      (circuit (move forward))))

"Keep moving down and forward, as long as we don't descend to the root node."

::

  (symex-execute-traversal
    (symex-traversal
      (circuit
        (precaution
          (venture (move down)
                   (move forward))
          (afterwards (not (at root)))))))

precaution
~~~~~~~~~~

Syntax
``````

``(precaution traversal [(beforehand condition)|(afterwards condition)])``

Description
```````````

Execute a traversal, but ensure that certain conditions hold either before or after executing the traversal (or both). If a condition does not hold, then abort the traversal, considering it to have failed.

Each of the conditions can be any predicate -- either a built-in predicate form, or an arbitrary lambda. See `Predicates`_ for details.

Examples
````````

"Go down but don't descend to the root node."

::

  (symex-execute-traversal
    (symex-traversal
      (precaution (move down)
                  (afterwards (not (at root))))))

"Go backward as long as we aren't at the first node at this level."

::

  (symex-execute-traversal
    (symex-traversal
      (precaution (move backward)
                  (beforehand (not (at first))))))

Note that this executes a *single* traversal while taking precautions. It is not repeated unless wrapped in a circuit or employed as a detour.

Predicates
^^^^^^^^^^

Symex offers a few standard predicates to use as conditions. In addition to these, you may also use any lambda as a predicate, so that you can specify arbitrary conditions to use in e.g. the ``decision`` and ``precaution`` forms.

* ``(at root)`` -- Are we (i.e. is the cursor) at the root node? Any toplevel form in the source file is considered to be a root node.
* ``(at first)`` -- Are we at the first node at the present level / on the current branch of the tree?
* ``(at last)`` -- Are we at the last node at the present level / on the current branch of the tree?
* ``(at initial)`` -- Are we at the first root-level node in the entire file?
* ``(at final)`` -- Are we at the last root-level node in the entire file?

There is also the modifier ``not`` which can be used with any of the above predicates (or with arbitrary lambdas). E.g. ``(not (at root))`` returns true if cursor is not at the root node of the tree.

Evaluation Model
----------------

Evaluation of Symex traversals involves:

1. Executing the traversal

2. Performing any side effects at each step of traversal execution

3. Performing a computation while traversing

Traversal Execution
^^^^^^^^^^^^^^^^^^^

See `Language`_.

Side Effects
^^^^^^^^^^^^

Traversals may be executed with arbitrary side effects. A side effect is simply a function (e.g. specified via a lambda expression) that is executed *after* the conclusion of a traversal, if that traversal succeeds.

Typically, we are interested in attaching such side effects to a repeated traversal so that the side effect is performed at each step of the traversal as long as it succeeds. For this purpose, you can use the ``symex--do-while-traversing`` function, which simply takes care of calling ``symex-execute-traversal`` repeatedly with your specified traversal and side effect.

Examples
~~~~~~~~

"Evaluate the remaining expressions at this level in the tree." (e.g. if at the root level, this will evaluate the remaining top-level expressions in the file).

::

  (symex--do-while-traversing #'symex--evaluate
                              symex--move-forward)

``symex--move-forward`` used here is a traversal provided for convenience that simply moves forward by one step. It is defined as ``(symex-make-move 1 0)`` and is equivalent to ``(symex-traversal (move forward))``.

Computations
^^^^^^^^^^^^

At the moment, executing a traversal returns a list of `moves <move>`_ performed, which can be thought of as a simple computation performed as part of traversal execution. In the future we may be interested in supporting other types of computations, such as returning the *number* of steps taken, or perhaps something related to the contents of traversed nodes and not just the structure.

As an analogy, a squirrel could explore a tree and then, upon returning, could relate the exact trajectory of its explorations which could convey the structure of the tree to another squirrel, or it could report on the number of pine cones it found along the way. The ``computation`` argument in ``symex-execute-traversal`` is reserved for this purpose, to modulate the return value. But it is currently unused - it may be left out entirely, or you could pass ``nil`` here.

Debugging
---------

Directly Evaluating Expressions
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

You can always run traversals in a source buffer by using ``M-:`` to evaluate an ELisp expression. This can be a cumbersome way to try things out, however.

Using a REPL
^^^^^^^^^^^^

Another strategy is to open a REPL in an adjacent window and run code in the REPL while having it take effect in the source buffer alongside.

To do this, open an ielm buffer in a window next to a source buffer, and use this snippet in the REPL:

::

  (with-current-buffer (window-buffer (other-window 1))
    (symex-execute-traversal
     (symex-traversal
      (maneuver (move forward)
                (move up))))
    (other-window 1))

Here, you can substitute the contents of ``(symex-traversal ...)`` with whatever traversal you like.

Using a Debugger (EDebug)
^^^^^^^^^^^^^^^^^^^^^^^^^

Another way is to use the ELisp Debugger, EDebug. This allows you to see the exact steps the DSL evaluator goes through in executing a traversal and the effects it has on the code, and can be helpful if you want to understand why a traversal isn't doing what you think it should be doing (or even if you just want to understand how the DSL works). A good debugger isn't just for debugging problems, it's also an exploratory tool for quick feedback at the creative stage when you're implementing new functionality. It can help you be more efficient at every stage of development.

To use it, first evaluate the relevant traversal evaluator (for instance, the ``symex-execute-traversal`` function) for debugging by placing point somewhere within it and then invoking ``M-x edebug-defun`` (I personally have this bound in an ELisp specific leader / Hydra). Now, if you execute a traversal (e.g. via the REPL as in the recipe above, with a test expression in the Scratch buffer -- or even just by invoking the relevant feature on source code while in Symex mode), it will put you in the debugger and allow you to step through the code. Handy commands for EDebug:

* ``s`` -- step forward
* ``i`` -- step in
* ``o`` -- step out
* ``g`` -- go until next breakpoint
* ``q`` -- quit

There are also lots of other features like setting and unsetting breakpoints (``b`` and ``u``), seeing a backtrace (``d``), evaluating expressions in the evaluation context (``e``), and lots more, making it an indispensible tool for ELisp debugging.

When you're done debugging, you can remove the debugger hooks by just evaluating the debugged functions in the usual way (e.g. via ``M-x eval-defun`` or ``M-x eval-buffer``).

Also see `this series on ELisp debugging <https://endlessparentheses.com/debugging-emacs-lisp-part-1-earn-your-independence.html>`__ for more tips.

Troubleshooting
~~~~~~~~~~~~~~~

Debugging Macros vs Functions
`````````````````````````````

If you are attempting to debug a feature implemented as a macro like ``symex-define-command``, you would need to evaluate the primitive functions for debugging, rather than the macro, or if necessary, copy the contents of the command to a new function and call that function from the macro, in order to be able to debug it. To be clear, you would need to evaluate the *function* for debugging rather than the macro. Naively, if you attempt to debug the macro, the debugger is triggered at compile time (i.e. as soon as you attempt to evaluate it for debugging!) and not at runtime when you're actually interested in using it. For the same reason, if you attempt to "step into" a macro invocation while the debugger is active, it won't do anything. You can only debug functions. If what you are interested in debugging is not a function, then put it in a function and debug that.

"Buffer is read-only"
`````````````````````

Sometimes, the debugger appears to get overridden by Evil keybindings, complaining that the "Buffer is read-only" when you attempt to ``s`` to step forward. Saving the buffer (as opposed to debugging an unsaved buffer) seems to solve these issues, and if not, killing and reopening the buffer does.

Print Statements and Asserts
^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Don't hesitate to add print statements (e.g. ``message``) to trace the execution path. Such trace logs can also serve as evidence from which to form hypotheses about bugs. You could also use ``cl-assert`` to assert assumptions at specific points.

Minimizing Complexity
^^^^^^^^^^^^^^^^^^^^^

Symex uses `advice <https://www.gnu.org/software/emacs/manual/html_node/elisp/Advising-Functions.html>`_ to implement some features such as branch memory. To minimize complexity while debugging, it may be advisable (so to speak) to disable such advice. To do this, find the place in the code where the advice is added and execute the corresponding function to remove it, something like ``(advice-remove #'symex-go-down #'symex--remember-branch-position)``. Of course, if disabling the advice causes the error to go away, then you can focus your efforts on debugging the advice itself in isolation.

It may also be advisable to comment out macros like ``symex-save-excursion`` to see if the problem persists. Commenting out macros like ``symex--with-undo-collapse`` will also help you use the debugger in code wrapped by such macros.

Gotchas
^^^^^^^

The ``symex-traversal`` form accepts a *single* traversal argument. If you'd like to do more than one thing, then wrap the steps in a `maneuver`_ or a `venture`_.

``symex-deftraversal`` is equivalent to ``(defvar name (symex-traversal traversal))``. As it uses ``defvar``, once defined, you cannot use the same form to redefine the traversal (e.g. if you are debugging it). You will need to use ``setq`` directly -- e.g. replace ``defvar`` with ``setq`` in the expanded version of this form.

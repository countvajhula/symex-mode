.. image:: https://github.com/drym-org/symex.el/actions/workflows/test.yml/badge.svg
    :target: https://github.com/drym-org/symex.el/actions

.. image:: https://melpa.org/packages/symex-badge.svg
    :alt: MELPA
    :target: https://melpa.org/#/symex

.. image:: https://stable.melpa.org/packages/symex-badge.svg
    :alt: MELPA Stable
    :target: https://stable.melpa.org/#/symex

*Symex (pron. "sym-ex", pl. symexes): A Lisp symbolic expression, which describes a computation to be performed.*

symex.el
========

An intuitive way to edit Lisp symbolic expressions ("symexes") structurally in Emacs.

.. raw:: html

  <p align="center">
    <img src="https://user-images.githubusercontent.com/401668/98453162-e3ca2f00-210a-11eb-8669-c1048ff4547c.jpg" width="618" height="410" alt="Symex the Squirrel" title="Symex the Squirrel" style="cursor:default;"/>
  </p>

.. contents:: :depth: 2

Introduction
============

Symex (pronounced sym-ex, as in symbolic expression) is a modal (like Vim but simpler) way of editing Lisp code as trees. Entering symex mode allows you to reason about your code in terms of its structure, similar to other tools like `paredit <https://www.emacswiki.org/emacs/ParEdit>`_ and `lispy <https://github.com/abo-abo/lispy>`_. But while those packages provide a curated number of useful tree operations, Symex treats the tree structure explicitly so that arbitrary tree navigations and operations can be described using an expressive DSL, and invoked conveniently via a simple ("point-free") modal interface. As a consequence of this:

- Symex provides many novel features, such as "leap branch," "climb/descend branch," "goto highest/lowest," "skip forward/backward", recursive indent, recursive evaluate, among many others
- Implementing new structure-related features in general is easy [1]_.
- Keybindings are short and memorable

At the moment, symex mode uses ``paredit``, ``lispy``, and `evil-cleverparens <https://github.com/luxbock/evil-cleverparens>`_ to provide much of its low level functionality. In the future, this layer of primitives may be replaced with a layer that explicitly uses the abstract syntax tree, for still greater precision.

As of Jan 2023, there is "alpha" support for non-Lisp languages via ``tree-sitter``. While motions and a couple of basic transformations should work across languages (i.e. not only Lisp), it should be considered an early preview rather than production-worthy. Full support is planned for completion as part of the `2.0 release coming in Spring '23 <https://github.com/drym-org/symex.el/pull/71>`__.

.. raw:: html

  <p align="center">
    <img src="https://user-images.githubusercontent.com/401668/59328521-6db96280-8ca1-11e9-8b32-24574a0af676.png" alt="Screenshot" title="Screenshot" style="cursor:default;"/>
  </p>

.. [1] As long as, from a theoretical perspective, the intended traversal can be accomplished using a `finite automaton <https://en.wikipedia.org/wiki/Deterministic_finite_automaton>`_. More complex traversals can be implemented (such as "leap branch"), but not as easily. Symex may be made Turing-complete at some point in the future, if there is interest in a feature that cannot be implemented in the DSL in its current form.

Installation
============

1. Install the package the usual way via MELPA (e.g. :code:`M-x package-install`).

2. Then, assuming you're using `use-package <https://github.com/jwiegley/use-package>`__ to manage your configuration, add the following config to your ``init.d`` (note these instructions have changed as of `version 0.9 <https://github.com/drym-org/symex.el/releases/tag/0.9>`__):

::

  (use-package symex
    :config
    (symex-initialize)
    (global-set-key (kbd "s-;") 'symex-mode-interface))  ; or whatever keybinding you like

This provides a keybinding to load the symex editing interface, and also enables the symex minor mode in all recognized lisp modes (the minor mode ensures that manual edits respect the tree structure, e.g. keeps parens balanced like paredit).

Usage and Customization
=======================

The Animated Guide
------------------

The best way to learn how to use Symex is to read the `Animated Guide <https://countvajhula.com/2021/09/25/the-animated-guide-to-symex/>`_. Besides animations, it also contains lots of helpful field notes. Go check it out!

Symex and Evil
--------------

At the moment, Symex uses an Evil state to implement its modal interface. Does that mean it's only for Evil users? No! It's just an implementation detail that you needn't be aware of, as Symex does not assume that you are an actual user of Evil.

If you do happen to be an Evil user, using Symex should feel familiar, but while there are many similarities to Evil, it's also fairly different.

Symex has a modal interface, but one that's simpler than Evil. In Evil, the paradigm is composing verbs with nouns (or operators with motions, in Vim parlance), whereas Symex has a "point free" design where the noun is fixed (i.e. it assumes you mean to perform operations on symexes) so you only need to worry about what you are trying to do without bothering about composition. For more on this style of UI, see `Rigpa <https://github.com/countvajhula/rigpa>`_.

Key Bindings
------------

The table below lists the key bindings in Symex mode. You can also always use Emacs's ``C-h k`` to learn what a key does, as another way of learning the bindings.

Movement
~~~~~~~~

.. list-table::
   :header-rows: 1

   * - Key
     - Action
     - Remarks

   * - ``h``, ``j``, ``k``, ``l``
     - backwards, down, up, forwards
     -

   * - ``gj``, ``gk``
     - linewise down, up
     - don't rely too heavily on these -- e.g. "leap branch" is often better

   * - ``f``, ``b``
     - traverse forwards, backwards
     -

   * - ``C-f``, ``C-b``
     - traverse forwards, backwards more
     - quicker ways to get around

   * - ``F``, ``B``
     - skip forwards, backwards
     - quick ways to move forwards and backwards -- traverse without entering nested expressions

   * - ``{``, ``}``
     - leap backwards, forwards
     - "leap" to adjacent branches in the current tree, preserving position on branch

   * - ``M-{``, ``M-}``
     - soar backwards, forwards
     - leap, but crossing trees if necessary

   * - ``C-k``, ``C-j``
     - climb, descend
     - a quick way to go up and down a tree

   * - ``0`` / ``M-h``
     - go to first symex at this level
     -

   * - ``$``, ``M-l``
     - go to last symex at this level
     -

   * - ``M-j``, ``M-k``
     - go to lowest, highest symex in the tree
     -

Editing
~~~~~~~

.. list-table::

   * - ``i``, ``a``
     - insert at beginning, append at end
     -

   * - ``I``, ``A``
     - insert before, append after
     -

   * - ``o``, ``O``
     - open line below, above
     -

   * - ``(``, ``[``
     - create symex with indicated delimiter
     -

   * - ``)``, ``]``
     - wrap symex with indicated delimiter
     -

   * - ``C-'``, ``C-,``, `````, ``C-```
     - cycle quoting, cycle unquoting, add quoting level, remove quoting level
     -

   * - ``w``, ``W``
     - wrap with parens and insert, wrap and append
     -

   * - ``x``, ``X``, ``D``
     - delete, delete backwards, delete remaining
     -

   * - ``c``, ``C``
     - change, change remaining
     -

   * - ``y``, ``Y``, ``p``, ``P``
     - yank (copy), yank remaining, paste after, paste before
     -

   * - ``C--``, ``s``
     - clear, replace/substitute
     -

   * - ``S``
     - change "surrounding" delimiter
     -

   * - ``H``, ``L``
     - move/shift symex backwards, forwards
     -

   * - ``M-H``, ``M-L``
     - move/shift symex backwards, forwards as far as possible on line or column
     - Remember that usually the Meta prefix ``M-`` means "the most" and the Shift prefix ``S-`` means an action or "to shift" in a direction

   * - ``K``
     - raise
     -

   * - ``C-S-j`` / ``C-{``, ``C-S-k`` / ``C-}``
     - emit backwards, forwards
     -

   * - ``C-S-h`` / ``C-(``, ``C-S-l`` / ``C-)``
     - capture backwards, forwards
     -

   * - ``z``, ``Z``
     - swallow head, swallow tail
     -

   * - ``|``, ``&``
     - split, join/merge
     -

   * - ``-``
     - splice
     - clip the delimiters, joining the symex to the containing expression

   * - ``>``, ``C->`` / ``C-S-o``
     - insert newline before, append newline after
     -

   * - ``<``,  ``J`` / ``C-<``
     - join with preceding line, join with next line
     -

   * - ``M-J`` / ``M-<``
     - collapse to a single line
     -

   * - ``M->``
     - unfurl across multiple lines
     -

   * - ``C-M-<``, ``C-M->``
     - collapse remaining, unfurl remaining
     -

   * - ``=``, ``<tab>``
     - tidy
     - indent and remove extraneous whitespace

   * - ``C-=``, ``C-<tab>``
     - tidy remaining
     - tidy remaining symexes at this level

   * - ``M-=`` / ``M-<tab>``
     - tidy recursively
     - tidies while traversing the symex from the highest branch to the root, for cases where a simple tidy isn't adequate

   * - ``;``, ``M-;``
     - comment out, comment out remaining
     -

Control
~~~~~~~

.. list-table::

   * - ``e``, ``E``, ``d``, ``M-e``, ``C-M-e``, ``T``
     - evaluate, evaluate remaining, evaluate definition, evaluate recursively, pretty evaluate, evaluate as "thunk"
     - ``T`` evaluates the indicated symex as if it were wrapped with parentheses, i.e. invoking it as a function, passing no arguments

   * - ``:``
     - eval-expression
     - evaluate an arbitrary expression in the minibuffer

   * - ``t``
     - switch to a scratch buffer
     -

   * - ``M``
     - display the messages buffer alongside
     -

   * - ``r``
     - go to REPL
     -

   * - ``R`` / ``X``
     - run/eval the buffer
     -

   * - ``C-;``
     - evaluate, and insert result
     -

   * - ``H-h``
     - toggle highlight
     -

   * - ``?``
     - describe / lookup documentation
     -

   * - ``<return>``
     - enter insertion state
     -

   * - ``<escape>``
     - exit
     -

Up and Down
-----------

The default keybindings in symex mode treat increasingly nested code as being "higher" and elements closer to the root as "lower." Think going "up" to the nest and "down" to the root. But symex allows you to modify these or any other keybindings to whatever you may find most natural.

Put something resembling this in your configuration *before* the call to ``(symex-initialize)``:

::

  (setq symex--user-evil-keyspec
        '(("j" . symex-go-up)
          ("k" . symex-go-down)
          ("C-j" . symex-climb-branch)
          ("C-k" . symex-descend-branch)
          ("M-j" . symex-goto-highest)
          ("M-k" . symex-goto-lowest)))

Branch Memory
-------------

When going up and down, the choice of initial position on the branch is arbitrary. By default, symex the squirrel remembers where it was on each branch as it goes up and down the tree, so you return to your last position when going up and down. If you'd like to move to the first or last position, you can use (for instance) ``0`` or ``$`` at each level, as usual, or traverse the tree using ``f`` and ``b`` instead. If, on the other hand, you'd like to start always at the first position when going up (as it was in older versions of Symex), disable the branch memory feature by adding this to the ``:custom`` `section <https://github.com/jwiegley/use-package#customizing-variables>`__ (not the ``:config`` section) of your ``use-package`` form:

::

   (symex-remember-branch-position-p nil)

Highlighting
------------

The current expression is highlighted by default (as of Jan 2023). If you'd like to disable highlighting, add this to the ``:custom`` `section <https://github.com/jwiegley/use-package#customizing-variables>`__ (not the ``:config`` section) of your ``use-package`` form:

::

   (symex-highlight-p nil)

Quoting Styles
--------------

By default, ``C-'`` and ``C-,`` cycle through standard quoting and unquoting prefixes (``'``, ````` and ``,``, ``,@``, respectively) recognizable to all Lisps. But some Lisps, such as Racket, provide additional quoting styles that you may want to add here. You could also technically add any prefixes here that you may find yourself using often, and they don't have to have anything to do with quoting. To add custom prefixes, add something like this to the ``:custom`` `section <https://github.com/jwiegley/use-package#customizing-variables>`__ (not the ``:config`` section) of your ``use-package`` form:

::

   (symex-quote-prefix-list (list "'" "`" "#'" "#`"))
   (symex-unquote-prefix-list (list "," ",@" "#,@"))

Lisp Flavors
------------
Symex supports the following lisps:

.. list-table::
   :header-rows: 1

   * - Flavor
     - Runtime and docs
   * - Racket
     - Racket Mode
   * - Emacs Lisp
     - Native/IELM
   * - Clojure
     - CIDER
   * - Common Lisp
     - Slime or Sly. This defaults to Slime, but you can use Sly by putting this in the ``:custom`` (not ``:config``) section of your ``use-package`` declaration: ``(symex-common-lisp-backend 'sly)``
   * - Scheme
     - Geiser
   * - Arc
     - Arc.el
   * - Fennel
     - fennel-mode.el
   * - Other
     - Structural editing only (no runtime). Please create an issue if you need additional support for your Lisp.

Tips
====

Escaping to Symex Instead of Normal State
-----------------------------------------

For evil users, when you "escape" from Insert state, you may prefer to enter Symex state rather than Normal state while in Lisp buffers. You could write one-off keybindings to do this (e.g. `this recipe <https://github.com/drym-org/symex.el/issues/24#issuecomment-815110143>`__ by user @tommy-mor), but if you'd like a more structured and flexible alternative, use `Rigpa <https://github.com/countvajhula/rigpa>`_.

Also see `Easy Entry Into Symex State`_, below, for another option.

Macros
------

When you define macros in symex mode (e.g. via ``q`` for evil users), make sure that the commands you use are those that have the same effect in every situation. For instance, the "up" and "down" motions (default: ``k`` and ``j``) could vary based on "branch memory" - up may sometimes move you to the first position on the higher level, but at other times it may move you to the third position, if that happens to be your most recent position. Using up and down in your macro would mean that it could have different results in each tree depending on your activities in the tree, unless you remember to reset the frame of reference by using something like ``0`` or ``$``. Instead, it may be more natural to use the "flow" traversal commands (default: ``f`` and ``b``), repeating them or prefixing them with count arguments if necessary, to move around in a fully deterministic way. This will ensure that your macros behave the same way in every case.

Mode Line Enhancements
----------------------

The vanilla mode line in Emacs does show some textual indication of your current evil state, e.g. ``<N>`` for Normal state, and ``<λ>`` for Symex state, and this kind of visual feedback is helpful, yet also subtle. If you'd like more pronounced visual feedback, you might try extensions such as `powerline <https://github.com/milkypostman/powerline>`_ or `telephone-line <https://github.com/dbordak/telephone-line>`_, which provide customizable color coded indicators for each evil state in the mode line. For example, for telephone-line, you could use the following config in the ``config`` section of the ``use-package`` declaration for telephone-line:

::

   (defface telephone-line-evil-symex
       '((t (:background "SlateBlue3" :inherit telephone-line-evil)))
       "Face used in evil color-coded segments when in Symex state."
       :group 'telephone-line-evil)


Keybindings
-----------

Easy Entry Into Symex State
~~~~~~~~~~~~~~~~~~~~~~~~~~~

User @doyougnu suggests binding your local leader to ``,`` (instead of the default, ``\``), which frees up ``\`` to be used as entry into Symex Mode. This is convenient as ``\`` feels like another ``Esc`` but dedicated to Symex state instead of Normal state. The drawback is that ``,`` is an otherwise useful key in Normal mode (for in-line repeat search backwards). Although, using it for the local leader is a widely used pattern by Vim and Evil users, and if you are one of them, then this might be a good option for you.

With this option, entering Symex from Normal state is convenient, but you'd still need to visit Normal state on your way to Symex state from Insert state. If you'd like to avoid this, see `Escaping to Symex Instead of Normal State`_, above.

Making Parentheses Convenient
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

In writing Lisp code, parentheses are among the most commonly typed characters, and yet, these require us to leave home position dramatically to type! I recommend a keybinding resembling the following to make it more efficient. Of course this applies only in Insert state (for Evil users) or in vanilla Emacs state, as you can insert and modulate delimiters in other ways while in Symex state:

::

   (define-key
     symex-mode-map
     (kbd "C-w")
     (lambda ()
       (interactive)
       (execute-kbd-macro (kbd "("))))

You could think of "w" as "wrap" in this context, as in, "to wrap with parentheses," and it matches a similar binding in symex state (i.e. ``w`` to wrap an expression and enter insert state). For the closing parenthesis, you could just use Emacs's ``C-f`` to move forward a character -- since symex (via paredit) ensures that parentheses are balanced, you rarely need to actually type a closing delimiter. The binding ``C-w`` would be fine for Evil users, but vanilla Emacs users may need to find something else here. Of course it goes without saying that the Control key should be conveniently accessible without having to leave home position. I have Control under my right thumb, and Escape in place of Caps Lock.

Splicing and Doom Emacs
~~~~~~~~~~~~~~~~~~~~~~~

If you're on Doom Emacs (or more generally if you're using ``evil-surround`` and ``evil-embrace`` together), you may run into an issue with splicing expressions (``-`` and ``C--``). See `this issue <https://github.com/drym-org/symex.el/issues/132>`__ for more details and a workaround.

Learn More
==========

Read the documentation for the `Symex DSL <https://github.com/drym-org/symex.el/blob/master/DSL-Docs.rst>`_.

Learn more about the implementation and see some usage examples in the video overview (given at an `Emacs SF <https://www.meetup.com/Emacs-SF/>`_ meetup in 2019):

.. raw:: html

  <p align="center">
    <a href="https://www.youtube.com/watch?v=a5s1ScTx8Zk">
      <img src="https://i.imgur.com/tk1x1p0.jpg" alt="Watch video" title="Watch video"/>
    </a>
  </p>

A Note on the Name
==================
A little while ago I was discussing Lisp syntax with `@apromessi <https://github.com/apromessi>`_:

    Me: "...And so we have these sex-puhs..."
    
    A: "Excuse me?"
    
    Me: "Oh, I mean ess expressions! It stands for symbolic expression."
    
    A: "Why not just call it sym-ex?"
    
    Me: [mindblown]
    
    A: "..."

Lisp has inherited a few oddball names from its deep prehistory, including the infamous ``car`` and ``cdr`` for the ``first`` and the ``rest`` of the `elements in a list <http://www.blogbyben.com/2011/04/best-bumper-sticker-ever.html>`_. But S-expression / sex-puh / symbolic expression are all somewhat of a mouthful too. Here are a few reasons why we might want to consider using "sym-ex" instead:

"Symbolic expression": 6 syllables, long in written form too

"S-expression": 4 syllables, I find this name confusing at least partially because it is a single-letter acronym which is unusual. In addition, it is long in written form.

"Sexpuh" / "sex-p" / "sexpr": 2 syllables, short in written form. But I mean, these are terrible.

"s-ex": Speaks for itself.

"Symex": 2 syllables, short in written form, has normal linguistic analogues like "complex/complexes," and it's fun to say! Symex also sounds like `Ibex <https://en.wikipedia.org/wiki/Ibex>`_, and that's obviously a plus.

Supporting this Project
=======================

Please make any financial contributions in one of the following ways:

- by Venmo to ``@Sid-K``
- by Paypal to skasivaj at gmail dot com

Please mention "Symex" in your message.

This project follows Attribution-Based Economics as described in `drym-org/foundation <https://github.com/drym-org/foundation>`_. Any financial contributions will be distributed to contributors and antecedents as agreed-upon in a collective process that anyone may participate in. To see the current distributions, take a look at `abe/attributions.txt <https://github.com/drym-org/symex.el/blob/main/abe/attributions.txt>`_. To see payments made into and out of the project, see the `abe <https://github.com/drym-org/symex.el/blob/main/abe/>`__ folder. If your payment is not reflected there within 3 days, or if you would prefer to, you are welcome to submit an issue or pull request to report the payment yourself -- all payments into and out of the repository are to be publicly reported (but may be anonymized if desired).

Additionally, if your voluntary payments exceed the agreed-upon "market price" of the project (see `price.txt <https://github.com/drym-org/symex.el/blob/main/abe/price.txt>`_), that additional amount will be treated as an investment, entitling you to a share in future revenues, including payments made to the project in the future or attributive revenue from other projects.

This project will distribute payments according to the ABE guidelines specified in the constitution. In particular, it may take up to 90 days to distribute the initial payments if DIA has not already been conducted for this project. After that, payments will be distributed to contributors (including investors) at each meeting of the `DIA congress <https://github.com/drym-org/dia-symex>`__ (e.g. approximately quarterly).

Non-Ownership
=============

This work is not owned by anyone. Please see the `Declaration of Non-Ownership <https://github.com/drym-org/foundation/blob/main/Declaration_of_Non_Ownership.md>`_.

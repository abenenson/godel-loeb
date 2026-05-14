/-
Copyright (c) 2026 Adam Benenson. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Adam Benenson
-/
import GodelLoeb.Diagonal
import GodelLoeb.Incompleteness
import GodelLoeb.Loeb
import GodelLoeb.Modal.Kripke
import GodelLoeb.Modal.Soundness
import GodelLoeb.ModalFormula
import GodelLoeb.Provable
import GodelLoeb.Substitution
import GodelLoeb.Worked

/-!
# GodelLoeb

Lean 4 formalization of the modal-axiomatic Goedel-Loeb substrate:
polymorphic modal syntax, a K4 Hilbert-style proof predicate, a
non-vacuous substitution-built Kreisel diagonal interface, Loeb's
theorem, and the modal second-incompleteness corollary.

The public namespace is `ModalLogic.GoedelLoeb`.
-/

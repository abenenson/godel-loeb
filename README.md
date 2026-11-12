# godel-loeb

[![Lean CI](https://github.com/abenenson/godel-loeb/actions/workflows/lean_action_ci.yml/badge.svg?branch=main)](https://github.com/abenenson/godel-loeb/actions/workflows/lean_action_ci.yml)

Lean 4 formalisation of the **modal-axiomatic** Loeb substrate, built
directly on Mathlib. The library derives Loeb's theorem from
intrinsic K4 plus a non-vacuous Kreisel diagonal interface, then
derives the modal second-incompleteness corollary.

This repository does **not** claim an arithmetic realisation of
Goedel's incompleteness theorems for Peano arithmetic or any other
concrete arithmetised theory. Arithmetic realisation requires a real
arithmetised provability predicate, concrete Hilbert-Bernays proofs for
that predicate, and a Solovay/PA-style derivation of the diagonal lemma.
This library ships a modal-axiomatic K4 layer that such a realisation can
target.

## Main objects

- `GodelLoeb.ModalFormula`: universe-polymorphic modal syntax with quotation,
  the modal-axiomatic `kreiselFixed` primitive, structural coding/decoding,
  and distinguished-slot substitution for the diagonal layer.
- `GodelLoeb.Provable`: Hilbert-style modal proof predicate with
  propositional tautologies, K, the K4 4-axiom, modus ponens,
  and necessitation over the `kreiselFixed` substrate.
- `GodelLoeb.Substitution`: syntactic substitution and coding
  witnesses, including the canonical fixed-point template.
- `GodelLoeb.Diagonal`: the non-vacuous Kreisel diagonal interface
  consumed by Loeb's theorem, the canonical substitution-backed
  instance, and structural fixed-point evidence.
- `GodelLoeb.Loeb`: `loeb`, derived from intrinsic K, intrinsic 4,
  and the diagonal interface.
- `GodelLoeb.Incompleteness`: `second_incompleteness`, the modal
  consistency corollary of Loeb.
- `GodelLoeb.Worked`: concrete sentence-level checks and a closed
  `workedLoeb` firing through the canonical diagonal instance.
- `GodelLoeb.Modal.Kripke`: elementary Kripke-frame semantics for K,
  T, 4, and 5, plus a project-level K4 forcing soundness bridge for
  `Provable`.

## Substrate scope

`ModalFormula.kreiselFixed` is the modal-axiomatic substrate's irreducible
postulate. Its `propEval` clause encodes `□(kreiselFixed phi) -> phi`
directly. The substitution and coding layer is a syntactic facade around that
primitive: `Substitution.code` emits `kreiselFixed` on the diagonal-template
arm and transparent `quote` wrappers elsewhere. Consequently, the canonical
`Diagonalisable` instance and theorem
`ModalFormula.canonicalDiagonalPostulateConsequence` are consequences of K4
plus this named postulate, not arithmetic-realisation coding theorems.

The diagonal interface is intentionally restricted to the Kreisel
family `x ↦ []x -> phi`, which is exactly the family needed in the
Loeb proof. An unrestricted `(ModalFormula α → ModalFormula α) → ModalFormula α`
diagonal operator over propositional modal formulas would include
liar-style operators such as `x ↦ ¬x`; that is not the arithmetic
diagonal lemma, where the variable ranges over codes.

The substitution layer exposes structural evidence for the canonical
fixed-point template. Its non-trivial coding content is restricted to the
template arm where the primitive is emitted; non-template inputs are
quote-wrapped and propositionally transparent under `propEval`. The
object-level proof substrate is therefore K4 plus propositional tautologies,
modus ponens, necessitation, and the `kreiselFixed` postulate already present
in formula evaluation.

## Building

```bash
lake exe cache get
lake build
scripts/verify.sh --lean GodelLoeb/ GodelLoeb.lean
```

Lean is pinned in `lean-toolchain`; Mathlib is pinned in
`lakefile.toml`.

CI builds the library with warnings treated as errors, runs the repository's
mechanical and Lean verifier checks, and compiles API documentation on pushes,
pull requests, and manual runs. Documentation is available as the `api-docs`
workflow artifact. Optional publication requires GitHub Pages to use GitHub
Actions and the repository variable `PUBLISH_DOCS` to be `true`; publication then
runs on pushes to `main`.

To inspect trusted dependencies of headline declarations, run a Lean
snippet such as:

```lean
import GodelLoeb
open ModalLogic.GoedelLoeb
#print axioms workedLoeb
#print axioms loeb
#print axioms second_incompleteness
```

## License

Dual-licensed under [Apache 2.0](LICENSE-APACHE) or
[MIT](LICENSE-MIT) at your option.

# Code Review: Algorithms of Discretion

Full-repo review, done as if this were a PR. Findings are tagged with an ID
(`DOC-#`, `R-#`, `DASH-#`, `PY-#`, `TS-#`) so we can turn any of them into a
diff by referencing the ID. Nothing has been changed yet — this is the
review pass. Say which IDs you want acted on and I'll make the edits.

Scope read: `README.md`, `DESIGN.md`, all of `duboisR/R/`, `duboisR/data-raw/`,
`duboisR/inst/scripts/`, `duboisR/tests/testthat/` (spot-checked), all of
`r_dashboard/`, all of `python/`, `Makefile`, `duboisR/DESCRIPTION`,
`duboisR/vignettes/wells-du-bois-protocol.Rmd`.

**Overall take:** the statistics is careful and the tests are real
(parameter-recovery tests, hand-verified daylight classifications — not just
"does it run"). The two actual bugs found are both narrow. The bulk of this
review is about prose density: the comments and docs are correct but
over-narrated in a specific, recognizable way, and trimming that is most of
the value here.

---

## Priority list

| ID | What | Why it matters |
|---|---|---|
| [R-1](#r-1-real-bug-prefix-collision-in-proxy-importance-attribution) | `startsWith()` prefix-collision bug in `proxy_diagnostics.R` | Silent misattribution if predictor names ever share a prefix |
| [DOC-1](#doc-1-the-datasheet-claims-no-license-the-package-has-one) | Grounding-experiment "ground truth" contradicts `duboisR`'s actual `LICENSE` | The LLM experiment's scoring is graded against a wrong fact |
| [DOC-2](#doc-2-stale-test-count) | "88 `test_that()` blocks" stated twice, actual count is 99 | Small, but it's the kind of AI-generated-doc drift the review was asked to catch |
| [R-2](#r-2-five-copies-of-the-same-load-duboisr-or-die-boilerplate) | 5 copies of identical "load duboisR or die" boilerplate | Real duplication, easy extract |
| [R-3](#r-3-duplicated-composite-group-key-logic) | Duplicated intersectional group-key logic | Same fix pattern, smaller |
| [DOC-3](#doc-3-the-not-x-it-is-y-tic) | The "X — not Y" antithesis construction, 27+ times across the two docs | The clearest single AI-prose tell in this repo |
| [DOC-4](#doc-4-em-dash-density) | 150 em-dashes across `DESIGN.md`/`README.md`/`duboisR/R/` | Same tell, different symptom |
| [DOC-5](#doc-5-volatile-facts-hardcoded-into-a-doc) | LLM pricing table with exact `$/1M token` prices "as of 2026-08-12" | Will be wrong within months; README shouldn't carry it |
| [R-4](#r-4-docstring-to-incident-report-ratio) | Internal-helper docstrings that narrate a whole debugging incident | `extract_answer_field()`, `api_error_body()` — 15–20 lines of prose for a 3-line function |

---

## A. Documentation (`README.md`, `DESIGN.md`)

### DOC-1: The datasheet claims no license — the package has one

`duboisR/inst/scripts/seed_demo_datasheet.R:175-181` (Distribution → licensing):

> "This project's own code does not yet carry an explicit license file —
> add one before any public redistribution beyond the demo."

`duboisR/data-raw/build_grounding_questions.R:223-228` turns this into a
scored question, `code_has_explicit_license`, `expected_answer = "FALSE"`.

But `duboisR/DESCRIPTION:15` says `License: MIT + file LICENSE`, and both
`duboisR/LICENSE` and `duboisR/LICENSE.md` exist on disk. So the "ground
truth" the grounding experiment scores every LLM's answer against is wrong
for the `duboisR/` package specifically — it's only true of the repo root
(which indeed has no top-level `LICENSE`). This is worth fixing precisely
*because* it's graded ground truth: a future run of `make grounding` would
mark a model "wrong" for correctly reading `duboisR/DESCRIPTION`.

**Fix:** either add a root `LICENSE` (making the claim fully true) or narrow
the datasheet answer/question to "the repo root" specifically. I'd lean
toward adding a root LICENSE (MIT, matching `duboisR/LICENSE`) since that's
the actually-missing piece, and it's a one-file change.

### DOC-2: Stale test count

`DESIGN.md:56-57` and `DESIGN.md:724` both say "88 `test_that()` blocks."
Actual count, as of this review:

```
$ grep -c "test_that(" duboisR/tests/testthat/test-*.R | awk -F: '{s+=$2} END{print s}'
99
```

Minor on its own, but it's exactly the failure mode of a design doc that
states precise numbers as prose: the number is correct at the moment it's
written and silently wrong the next time a test is added. Either drop the
specific count (say "a full `testthat` suite covering every exported
function") or don't restate it in two places — pick one and have the other
cross-reference it.

### DOC-3: The "X — not Y" tic

Both docs lean hard on one rhetorical move: state a claim, then negate its
opposite. A sample of actual instances:

- "not a metric you compute from a confusion matrix — it's a natural
  experiment" (DESIGN.md:693)
- "This is a genuine resolution ceiling... not a shortcut taken here"
  (DESIGN.md:355)
- "a design decision... not a bug"
- "not worth 18min of `make results`"
- "it is manufactured, not a finding" (DESIGN.md:553, repeated near-verbatim
  in `simulate_stops.R:21`)
- "not a choice made for convenience here" (`veil_of_darkness.R:31`)

27 instances of the literal `, not <word>` pattern between `README.md` and
`DESIGN.md` alone (`grep -c ", not [a-z]"`). Each one in isolation reads
fine; in aggregate it's the single most recognizable fingerprint of
LLM-drafted technical prose, and a reader notices the pattern before the
tenth instance regardless of whether any individual sentence is wrong.

**Recommendation:** keep the ones that correct an actual, likely
misconception a reader would otherwise have (e.g. "the fitted curve's
domain is [0,1], but real search rates never exceed ~13%" earns its
contrast). Cut the ones that are just restating the positive claim's
negation for cadence ("it's a design decision, not a bug" — just say "this
is deliberate" or nothing). I'd guess roughly half of the 27 survive that
bar.

### DOC-4: Em-dash density

150 em-dashes across `DESIGN.md` + `README.md` + `duboisR/R/*.R` combined.
Concentrated in the newest code:

```
30  duboisR/R/grounding_experiment.R
14  duboisR/R/llm_clients.R
 7  duboisR/R/threshold_test.R
 5  duboisR/R/veil_of_darkness.R
```

Not wrong, just a tell — normal technical writing (and the older files in
this same repo, `utils.R`, `duboisR-package.R`) uses periods and commas far
more than em-dashes. `grounding_experiment.R` and `llm_clients.R` being the
newest files and the heaviest offenders is the pattern to notice: this
scales with how recently something was drafted with an LLM in the loop, not
with the underlying content's complexity.

### DOC-5: Volatile facts hardcoded into a doc

`README.md:153-172`: a pricing table with exact `$/1M input`/`$/1M output`
token prices for four providers, "list pricing as of 2026-08-12." Provider
pricing changes on a timescale of months, and the README already
acknowledges this ("check each provider's current pricing page, since it
moves fast") right next to a table asserting exact numbers anyway. Either
drop the dollar figures and keep only the measured token counts (input/
output tokens per call — those are real, reproducible facts about this
project's own prompts) and a link to each provider's pricing page, or move
the table into a dated comment in `run_grounding_experiment.R` where "this
was true when I last ran it" is a more natural framing than in a README
someone reads as current instructions.

### DOC-6: Doc/docstring duplication

`DESIGN.md` §5.6 (Threshold Test, ~60 lines) and
`threshold_test.R`'s `fit_threshold_test()` roxygen block narrate the same
derivation almost paragraph-for-paragraph — the `qbeta`/closed-form-threshold
explanation, the "in the spirit of, not identical to" caveat, the numerical
`NaN` edge case. Same pattern for Veil of Darkness (DESIGN.md §5.5 vs.
`compute_daylight_status()`'s docstring) and the grounding experiment
(DESIGN.md §5.8 vs. `run_grounding_experiment()`'s docstring).

Pick one home. I'd put the mechanism explanation in the roxygen docstring
(closer to the code, shows up in `?fit_threshold_test`, less likely to
silently drift since a `devtools::check()` failure is at least *possible*
for a badly broken `@param`) and have `DESIGN.md` give the one-paragraph
gist plus a cross-reference, the way `DESIGN.md` already does well for
`dubois_relevel()`.

---

## B. R idioms in this codebase, explained for a TypeScript reader

You're fluent in TS and new to R — these are the patterns in this specific
codebase that don't have a direct TS equivalent, or that look like one but
aren't.

**`%||%` (`utils.R:2`) is `??`.** `x %||% y` → `x ?? y`. Not built into
base R (this file defines it), which is itself telling: R's `is.null(x)`
check for "absence" is doing the job `undefined`/`null` checks do in TS, but
R has no first-class syntax for it the way TS has had `??` since 3.7.

**`[[ ]]` vs `[ ]` vs `$` on a list/data.frame is nothing like TS property
access.** This is the single most foreign thing in the codebase to a TS
reader:
- `data[["subject_race"]]` — get one column, by a *computed* string key.
  Closest TS analog: `obj[key]` with `key: string`.
  See `glm_utils.R:137` (`data[[var]]` inside a `lapply` over a variable
  name).
- `data["subject_race"]` (single bracket) — get a **data.frame containing
  one column**, not the column itself. There's no TS equivalent to "the
  same index operator returns a different *kind* of container depending on
  bracket count." `audit_composition.R:39` uses this form deliberately
  (`data[weight_col]`) — worth knowing that's not a typo for `[[`.
- `data$subject_race` — like `obj.subject_race`, but with a footgun TS
  doesn't have: `$` does **partial matching** on lists (not data.frames) —
  `x$sub` can silently return `x$subject_race` if it's the only prefix
  match. Nothing in this codebase currently relies on that, but it's why
  the package consistently uses `[[` with a string variable rather than `$`
  wherever the column name is itself a parameter (e.g. every
  `abort_if_missing_cols()` caller).

**S3 classes are duck-typed dispatch by naming convention, not `class`.**
`glm_utils.R:93`: `structure(list(model=..., summary=...), class =
"duboisR_glm_fit")` creates a plain list with a string tag — there's no
class body, no constructor, nothing checked at creation time. Then
`print.duboisR_glm_fit()` (`glm_utils.R:164`) is picked up automatically
when you call `print(fit)` on an object with that class tag, purely because
R's `print()` generic does `get(paste0("print.", class(x)[1]))` under the
hood. The TS analogue is a discriminated union with a `kind` field plus a
big `switch` in one place — except here the "switch" is implicit
(name-based lookup across the whole loaded namespace) and **nothing
enforces that `print.duboisR_glm_fit` actually handles what `print()`
promises**, the way a TS `switch` over a union can be checked for
exhaustiveness. If you rename a class string in one place and not another,
you get a silent fallback to `print.default`, not a compile error.

**Formulas (`~`) are unevaluated, unchecked expression objects.**
`build_formula()` (`glm_utils.R:41-48`) builds `search_conducted ~
subject_race + poverty_rate` as a *string*, then `as.formula()` turns it
into an R language object that `glm()` evaluates later against whatever
data frame you pass it. There's no TS equivalent to a formula as a
first-class object — the closest mental model is a **template literal type
that isn't actually checked**: `col names` are just identifiers resolved at
call time against `data`'s column names, so a typo in `build_formula()`'s
`control_map` (e.g. `"factor(hour)"` misspelled) produces a runtime error
deep inside `glm()`, not a type error anywhere near the typo. This is why
`abort_if_missing_cols()` (`utils.R:54`) exists at all — it's a hand-rolled
substitute for the column-existence checking a typed schema would give you
for free.

**`vapply`/`lapply` are `Array.prototype.map`, but `vapply` has a return
*shape* contract `map` doesn't.** `grounding_experiment.R:288-292`:
`vapply(questions, `[[`, character(1), "type")` — the `character(1)`
argument isn't a default value, it's an assertion: "every element of the
result must be a length-1 character vector, or error." That's the closest
thing in base R to a TS generic type parameter constraining a `.map()`
call's return type — except it's enforced at runtime, once, on the actual
data, rather than at compile time on all possible inputs. `sapply` (used
nowhere in this codebase, worth noting as a good sign) is the unchecked
version — it guesses the output shape from the first result and can
silently return a different structure (a list instead of a vector) if a
later element doesn't match, which is exactly the kind of implicit `any`
downcast a TS codebase would ban a linter rule for.

**Implicit recycling has no TS equivalent and is silent.** `subpop_
disparities.R:82`: `TPR = TP / (TP + FN)` where both sides are numeric
vectors — fine here because they're the same length. But R will happily
compute `c(1,2,3) + c(1,2)` by recycling the shorter vector (with a warning
only if lengths aren't multiples of each other, no warning if they are).
Nothing in this codebase hits this by accident as far as I found, but it's
the R behavior most likely to produce a wrong-not-crashing result if a
future edit changes a vector's length without updating the ones it's
combined with — there's no type system here to catch a length mismatch the
way TS's tuple/array types (sometimes) can.

**`method = c("rf", "glm")` as a default, then `rlang::arg_match(method)`**
(`proxy_diagnostics.R:32,34`). This is R's idiom for a TS `method: "rf" |
"glm" = "rf"` parameter — but the *mechanism* is unusual: the default value
is the **entire allowed-values vector**, and `arg_match()` (called first
thing in the function body) both validates the caller's choice against that
same vector and, if the parameter was left at its default, silently takes
element 1. There's no `arg_match()`-free way to see from the signature
alone that `"rf"` is the default rather than "any of these three" — you
have to know the idiom.

**The native pipe `|>` (R ≥ 4.1) is closest to `fp-ts`'s `pipe()`, not
method chaining.** Used in `build_tx_county_centroids.R` and
`llm_clients.R` (`httr2::request(...) |> httr2::req_headers(...) |>
...`). Unlike TS method chaining (`foo().bar().baz()`, where each method
lives on the previous return value's prototype), `|>` just rewrites `x |>
f(y)` to `f(x, y)` — `f` doesn't need to "belong" to `x` at all, any
function taking `x` as its first argument works. The closest TS-world
analogue is exactly `pipe(x, f, g)` from `fp-ts`/RxJS, not `.then()`
chaining.

---

## C. `duboisR/R/` — package source

### R-1: Real bug — prefix collision in proxy importance attribution

`duboisR/R/proxy_diagnostics.R:140-143`, inside `.dubois_check_proxies_glm`:

```r
for (p in predictors) {
  matched <- z[startsWith(names(z), p)]
  if (length(matched) > 0) importance[[p]] <- max(importance[[p]], max(matched, na.rm = TRUE))
}
```

`z` holds `|z value|` coefficients from a one-vs-rest `glm()`, named by
`model.matrix()`'s convention (a factor predictor's coefficients are named
`"<varname><level>"`, e.g. `county_fips48201`). `startsWith(names(z), p)`
is trying to recover "which coefficients belong to predictor `p`" — but if
one predictor's name is a string-prefix of another's (e.g. `"hour"` and a
hypothetical `"hour_bucket"`, or `"search"` and `"search_basis"`), the
shorter predictor's `startsWith` match silently captures the longer
predictor's coefficients too, inflating the shorter one's reported
importance and never correctly isolating the longer one's.

Not currently triggered — the live predictor set (`county_fips`,
`poverty_rate`, `median_income`, `hour`) has no prefix collisions — but
it's a latent correctness bug in a function whose entire job is "tell the
researcher which covariate is the proxy." A future predictor added to
`check_proxies()`'s call site with a colliding name would misattribute
silently, no error, no warning.

**Suggested fix:** sort `predictors` longest-name-first and remove matched
`z` entries from the pool as each is claimed, so a shorter name can never
steal a longer name's coefficients:

```r
ordered_predictors <- predictors[order(-nchar(predictors))]
remaining <- z
for (p in ordered_predictors) {
  matched <- remaining[startsWith(names(remaining), p)]
  if (length(matched) > 0) {
    importance[[p]] <- max(matched, na.rm = TRUE)
    remaining <- remaining[!startsWith(names(remaining), p)]
  }
}
```

### R-2: Five copies of the same "load duboisR or die" boilerplate

Identical (or near-identical) 8–10 line block:

```r
if (requireNamespace("duboisR", quietly = TRUE)) {
  library(duboisR)
} else if (requireNamespace("devtools", quietly = TRUE)) {
  devtools::load_all(<path>, quiet = TRUE)
} else {
  stop("duboisR is not installed and devtools is unavailable...")
}
```

appears in:
- `duboisR/inst/scripts/precompute_audit.R:10-19`
- `duboisR/inst/scripts/run_grounding_experiment.R:14-23`
- `duboisR/inst/scripts/seed_demo_datasheet.R:14-23`
- `r_dashboard/dev/generate_synthetic_data.R:19-28`
- `r_dashboard/app.R:20-29`

only the `load_all()` path argument differs. These are all standalone
`Rscript` entry points (not part of the package's own `R/` namespace), so
they can't `@importFrom` a shared helper the normal package way — but they
can all `source()` one small file. Suggest a
`duboisR/inst/scripts/_load_duboisR.R`:

```r
load_duboisR_or_die <- function(pkg_path = "duboisR") {
  if (requireNamespace("duboisR", quietly = TRUE)) {
    library(duboisR)
  } else if (requireNamespace("devtools", quietly = TRUE)) {
    devtools::load_all(pkg_path, quiet = TRUE)
  } else {
    stop(
      "duboisR is not installed and devtools is unavailable to load it from ",
      "source. Run: Rscript -e 'install.packages(\"devtools\"); devtools::install(\"duboisR\")'"
    )
  }
}
```

and each caller becomes two lines: `source(...); load_duboisR_or_die(path)`.
Five copies of the same failure-mode logic is exactly the kind of
duplication where a fix in one place and not the others (which is how this
usually goes wrong) becomes a real bug later, not just a style complaint.

### R-3: Duplicated composite-group-key logic

`audit_composition.R:32-37`:
```r
grouped <- data
if (length(group_col) > 1) {
  grouped$.dubois_group <- do.call(paste, c(as.list(data[group_col]), sep = "_"))
} else {
  grouped$.dubois_group <- as.character(data[[group_col]])
}
```
vs. `subpop_disparities.R:69`:
```r
group <- do.call(paste, c(as.list(data[subgroup_cols]), sep = "_"))
```

Same operation (paste together one or more columns into an intersectional
key like `"black_female"`), implemented twice, slightly differently (one
special-cases the single-column case to skip `paste`, the other doesn't
bother — both produce the same output, `do.call(paste, ...)` on a
single-column list still works fine). Worth pulling into one internal
helper in `utils.R`, e.g. `dubois_group_key(data, cols)`, called from both
sites — same category of fix as R-2, smaller blast radius.

### R-4: Docstring-to-incident-report ratio

Two internal (`@keywords internal`, not exported) helpers carry roxygen
docs longer than the functions they document, narrating the exact crash
they were written to prevent:

- `llm_clients.R:85-115` — `api_error_body()`, a 3-line function, ~24 lines
  of docstring including a blow-by-blow of an actual crash ("`$message` on
  an atomic vector is a hard error... That crashed this function while it
  was handling an error response...").
- `grounding_experiment.R:164-187` — `extract_answer_field()`, a 2-line
  function, ~20 lines of docstring telling the same style of story.

The underlying fact each docstring protects ("a provider response can be a
bare scalar where the schema promised an object; guard with `is.list()`
before `[[`/`$`") is worth one sentence. The regression tests already carry
the "here's the exact incident this guards against" narrative in a place
that's supposed to have it —
`test-llm_clients.R:61-72`'s test is explicitly commented as a regression
test for this. The docstring doesn't need to duplicate that.

Suggested trim for `api_error_body()`:
```r
#' Extract a provider's own error message from a failed response
#'
#' All three providers return a JSON error body on 4xx/5xx with more detail
#' than httr2's default "HTTP 400 Bad Request." `is.list()` checks guard
#' every `$`/`[[` access below because at least one provider (xAI) returns
#' `error` as a bare string rather than a nested object, and `$` on an
#' atomic vector errors instead of returning NULL.
#'
#' @param resp An httr2 response object.
#' @return A character vector to append to the error message.
#' @keywords internal
```
Same idea for `extract_answer_field()`. This isn't a call to strip *all*
context-carrying comments — several of the longer ones earn their length
(the Veil of Darkness `match()` vs. `merge()` performance comment in
`veil_of_darkness.R:33-40`, with actual measured wall-clock numbers, is
exactly the kind of comment worth keeping at length, because it's citing a
measurement a future editor can't otherwise recover). The distinction is
"documents a measurement or a non-obvious invariant" (keep) vs. "narrates
the process of discovering the fix" (trim to the fix).

### Smaller notes

- `glm_utils.R:134`, `is_factor_wrapped()`'s regex
  (`^factor\\(\\s*%s\\s*\\)$`) only matches an exact `factor(var)` term. A
  future formula term like `factor(hour, levels = ...)` would silently fall
  through to the numeric-mean branch instead of the mode branch, which
  would then hit the `predict()` "has new levels" error the docstring
  above it specifically warns about. Not urgent (nothing in this repo
  writes that kind of term today), just noting the guard is narrower than
  the problem it's protecting against.
- `threshold_test.R` and `veil_of_darkness.R` are the two files where the
  long comments are consistently the "keep" kind (measured numbers,
  non-obvious invariants) rather than the "trim" kind (R-4). Calling this
  out because it's a useful contrast when deciding what to cut elsewhere —
  the bar those two files clear is the right bar.

---

## D. `r_dashboard/`

Generally the cleanest part of the repo — module headers explain
non-obvious caching/reactive-graph decisions (why `stops_data()` and
`audit_fit()` live in `app.R` and not a module; why the Veil of Darkness tab
excludes a "Time of Day" checkbox) that a reader genuinely needs and
wouldn't get from the code alone. No correctness issues found.

- **R-2 applies here too** — `r_dashboard/app.R:20-29` and
  `r_dashboard/dev/generate_synthetic_data.R:19-28` are 2 of the 5 copies.
- `mod_regression.R:22-29`'s comment about `fill = FALSE` and bslib's flex
  layout collapsing plot height to 0 is a good example of a comment that
  earns its length — it's documenting a real, non-obvious Shiny/bslib
  interaction that would otherwise get "fixed" by deleting `fill = FALSE`
  the next time someone touches this file and wonders what it's for.

---

## E. `python/`

Also clean. Three short, focused scripts, no dead code, no test suite
(flagged honestly in `DESIGN.md` §12 rather than pretended away). One
observation, not a bug:

- `02_clean_stops.py:67-68`: `pd.to_datetime(..., errors="coerce")` turns
  unparseable dates into `NaT`, and `NaT.dt.year.between(2015, 2017)` is
  `False` — so a row with a corrupt date is silently dropped rather than
  raising, indistinguishable downstream from a row that was legitimately
  outside 2015–2017. Given `_validate_columns()` already fails fast on a
  schema mismatch, the same instinct could extend to counting and logging
  how many rows got dropped for an unparseable (as opposed to
  out-of-range) date — cheap to add if this pipeline is ever pointed at a
  new state's file with different date formatting, per the README's own
  "Pointing the pipeline at a different state" section.

---

## Suggested order if we turn this into a diff

1. **DOC-1** — smallest, and it's a correctness fix (fixes what the LLM
   experiment is actually grading against), not just cleanup.
2. **R-1** — real latent bug, small fix, has no test today (worth adding
   one: two predictors with a shared prefix, assert importance isn't
   double-counted).
3. **R-2** — mechanical extraction, touches 5 files but each edit is
   trivial.
4. **R-3** — same category, 2 files.
5. **DOC-2** — one-line fix.
6. **R-4** — trim the two worst-offender docstrings.
7. **DOC-3 / DOC-4** — the prose pass. Bigger and more subjective than the
   above; I'd want to go section-by-section with you rather than rewrite
   `DESIGN.md` wholesale in one shot.
8. **DOC-5 / DOC-6** — doc restructuring, lowest urgency.

Tell me which numbers to start on, or say "all of them" and I'll work
through this list in order.

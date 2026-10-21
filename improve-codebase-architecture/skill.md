---
name: improve-codebase-architecture
description: Scan a codebase for deepening opportunities through a domain-driven design lens, present them as a visual report, then grill through whichever one you pick. Use this whenever the user wants to improve, refactor, restructure, or clean up a codebase's architecture, asks where the design is weak, mentions shallow modules, coupling, testability, bounded contexts, aggregates, ubiquitous language, or DDD, even if they don't ask for a "report".
---

# Improve Codebase Architecture

Surface architectural friction and propose **deepening opportunities**: refactors that turn shallow modules into deep ones, with module boundaries drawn along the **domain** rather than along technical layers. The aim is testability, AI-navigability, and code that speaks the language of the business.

Deep modules and domain-driven design (DDD) point the same way. A well-shaped **aggregate** is a deep module: a small interface (intention-revealing commands) hiding a lot of invariant enforcement. A **bounded context** is a natural seam: things inside change together, things outside talk through a narrow, explicit contract. Use DDD as the default vocabulary for *where* a seam belongs and *what* should sit behind it.

## Guiding principles

- **Domain first, technology second.** Prefer boundaries that match business concepts (Billing, Enrollment, Shipping) over boundaries that match technical roles (controllers, services, utils, helpers). A `utils/` folder or a `*Service` that touches five concepts is a smell.
- **Ubiquitous language.** Names in code should match the words domain experts use. Mismatches (code says `Record`, business says `Claim`) are findings in their own right, because they force translation on every reader, human or AI.
- **Rich over anemic.** Business rules belong on the domain objects that own the data, not scattered across services, controllers, or SQL. A model that is just getters and setters, with the logic living elsewhere, is a shallow module.
- **YAGNI still wins.** DDD is a lens, not a checklist. Don't propose repositories, factories, domain events, or extra layers unless they fail the deletion test in the right direction (deleting them would spread complexity back out). Simple CRUD areas with no real rules don't need tactical DDD; say so rather than inventing ceremony.

## Process

### 1. Explore

**Scope before you scan: YAGNI.** Deepening a module pays off by making future changes to it easier, so put extra weight on the parts of the codebase that have recently changed. Decide *where* to look before you look:

- If the user named a direction (a module, a subsystem, a pain point), take it, and skip the inference below.
- Otherwise, walk back a good stretch of the commit history (`git log --oneline`) to find the codebase's hot spots, the files and areas that keep coming up, and let those paths pull your attention first. If the changes are scattered with no clear hot spot, widen the net.

**Sketch the domain.** Before judging structure, build a rough domain map from names, folders, schemas, docs, tests, and commit messages: the core concepts (nouns), the key operations (verbs), the invariants that must always hold, and any natural clusters that look like bounded contexts. Note which area looks like the **core domain** (where the business differentiates) versus supporting or generic subdomains; deepening effort is worth most in the core.

Then spawn a sub-agent to walk the codebase with that map in hand. Don't follow rigid heuristics; explore organically and note where you experience friction:

**Module depth**
- Where does understanding one concept require bouncing between many small modules?
- Where are modules **shallow**, with an interface nearly as complex as the implementation?
- Where have pure functions been extracted just for testability, but the real bugs hide in how they're called (no **locality**)?
- Which parts of the codebase are untested, or hard to test through their current interface?

**Domain alignment**
- Where is the code organized by technical layer when it should be organized by domain concept?
- Where does domain logic leak into controllers, handlers, UI, ORM models, or database queries?
- Where is the domain model **anemic**, with rules enforced by whoever happens to call it?
- Where is an invariant enforced in several places (or nowhere), instead of by one aggregate that owns it?
- Where do primitives stand in for domain concepts (a `string` email, a `number` of cents, a `Date` pair meaning a period) that deserve a **value object**?
- Where does one term mean different things in different parts of the code, hinting at two contexts squashed into one model?
- Where do tightly-coupled modules or contexts leak across their seams, e.g. one context reaching into another's tables or internal types instead of going through a contract or an **anti-corruption layer**?
- Where does infrastructure (framework, ORM, HTTP clients, queues) bleed into domain code, making it hard to test without spinning up the world?

Apply the **deletion test** to anything you suspect is shallow: would deleting it concentrate complexity, or just move it? A "yes, concentrates" is the signal you want. Apply the same test to any DDD pattern you are tempted to propose.

### 2. Explain opportunities to user

Present all the opportunities as a visual report. Open with the domain map from step 1 (contexts, core concepts, and where the current code boundaries cut across them), since it frames every finding.

**Report format:** write the report as a single self-contained HTML file (inline CSS/SVG, no external requests) at `.architecture-reports/<YYYY-MM-DD>-architecture-review.html` in the root of the scanned repo, creating the hidden directory if needed. Never publish it with the Artifact tool or any claude.ai artifact/docs feature. After writing it, give the user the file path (and open it with `open <path>` on macOS) plus a short summary of the findings in the terminal.

For each finding, explain:

- **What the issue is**, with concrete file and symbol references.
- **Why it was flagged**: the friction observed and which principle it violates (shallow module, missing locality, anemic model, leaked invariant, language mismatch, context bleed, and so on).
- **How it could improve**, described in domain terms (e.g. "move pricing rules onto `Order` as an aggregate that owns its line items") without designing interfaces yet.
- **Domain placement**: which bounded context and subdomain it lives in, and whether that's core, supporting, or generic.
- **Payoff vs. cost**: how often this area changes and what gets easier or safer afterwards.

Every finding must be justified. If you can't produce a strong justification, the finding is probably not valid; drop it rather than padding the report. Likewise, don't flag something just because it isn't "textbook DDD".

Order findings by payoff, favoring core-domain hot spots.

Do NOT propose interfaces yet. After the report is written, ask the user: "Which of these would you like to explore?"

### 3. Grilling loop

Once the user picks a candidate, call the Skill tool with "grill-me" to walk the decision tree with them. Cover:

- Constraints and dependencies.
- The domain language: what are the right names, and do they match how the business talks?
- The shape of the deepened module: which aggregate or context owns it, what its invariants are, and what its small public interface looks like.
- What sits behind the seam: persistence, integrations, and other infrastructure pushed out of the domain core.
- How it talks to neighbouring contexts: shared contract, events, or an anti-corruption layer, and whether that's worth the cost.
- What tests survive, and how the domain can now be tested without infrastructure.

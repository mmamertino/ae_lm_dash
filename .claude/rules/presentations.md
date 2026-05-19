---
paths: ["presentations/**/*.qmd"]
---

# BGI Presentations (Quarto RevealJS)

## Format

- `format: bgi-revealjs` — custom extension vendored at `_extensions/bgi/`
- One `##` per slide (slide boundary); do not use `---` between slides
- Optional `### Sub-headline` directly under a `##` renders as a supporting headline

## Slide types

- **Title slide** — built automatically from YAML frontmatter (`title`, `subtitle`, `date`)
- **Section break** — `## Section Name {.section-slide}` → dark blue transition slide
- **Content slide** — starts with `## Headline` (short, conclusion-style, not descriptive)

## Emphasis

- Use `[word]{.emphasis}` — renders the word in BGI orange
- Do NOT use `**bold**` or `*italic*` for emphasis — use `.emphasis`
- Keep slides concise; prefer short bullets over paragraphs

## Components

### Standard columns

```
:::: columns
::: {.column width="55%"}
Left content
:::
::: {.column width="45%"}
Right content
:::
::::
```

### Callout box

```
::: callout-box
Annotation text, smaller than body text
:::
```

### Image placeholder

```
::: image-placeholder
*Insert chart here*
:::
```

### Tables

- Default (orange header): plain pipe table, no wrapper needed
- Red header variant: wrap the table in `::: table-red ... :::`

### Quote panel (red italic quote + supporting bullets)

```
::::: quote-panel
::: column
*Italic quote*
:::
::: column
- Supporting bullet 1
- Supporting bullet 2
:::
:::::
```

### Blue/white two-column panel

```
::::: columns-blue-white
::: column
### Heading on blue
Body text
:::
::: column
### Heading on white
Body text
:::
:::::
```

## BGI colors (for reference)

- Dark blue `#115780` — primary brand color, title/section backgrounds
- Orange `#e0732b` — emphasis
- Red `#c22036` — accent, quote panel left side
- Peach `#fed59f` — alternating table rows (orange variant)
- Charcoal `#333333` — body text

## Render

- Preview: `quarto preview presentations/slides.qmd`
- Render: `quarto render presentations/slides.qmd` → produces `slides.html`

## Don'ts

- Do NOT edit files in `_extensions/bgi/` — those are vendored from the central presentation template. Changes belong upstream.
- Do NOT override the logo, footer, or slide dimensions — they come from the extension.
- Do NOT add ad-hoc CSS in the `.qmd`. If a new component is needed, add it to the extension upstream so all decks benefit.

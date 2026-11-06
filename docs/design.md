# Design

Splt looks like a well-kept paper ledger: ink on warm paper, with big printed numbers. Every rule below serves one aim, which is to show who owes what and get out of the way.

## Rules

1. **Color means something.** Chrome is ink on paper. Color appears only for a person or for the direction of money. Nothing is colored for decoration.
2. **The number leads.** Each screen has at most one big figure, set in the serif face, on the paper itself. It doesn't sit in a card.
3. **Lines before boxes.** Inside a card, separate things with space first and a hairline second. A list's rows share one card, with hairlines between them, unless each row is a thing in its own right, like a group.
4. **Depth is stacked card stock under one light.** Light comes from above, so raised things have a lit top edge and a soft neutral shadow below. Use the helpers under Depth rather than new values. Colored glows, decorative gradients, sparkles and blur on content stay banned. The system's own bars and sheets keep their glass.
5. **One primary action per screen.** Everything else is plain text or sits in a menu.
6. **Removing beats restyling.** If a screen works without an element, take the element out.
7. **Motion confirms.** Things move because the user did something. Settling up is the one moment allowed to celebrate.

## Color

Use `Ink`, never raw colors or `systemGroupedBackground`.

| Token | Use |
| --- | --- |
| `Ink.paper` | Screen background, via `.paperBackground()` |
| `Ink.sheet` | The rare raised surface, via `.cardSurface()` or `.raisedRow()` |
| `Ink.text` | Primary text, primary button fill, app tint |
| `Ink.secondary` | Supporting text, at least 4.5:1 on paper |
| `Ink.tertiary` | Decorative marks only, never text |
| `Ink.hairline` | Dividers and control borders |
| `Ink.owed` | Money coming to you |
| `Ink.owe` | Money you owe, and destructive actions |

`PersonPalette` holds twelve muted pigments, one per person. Direction is never shown by color alone: always pair it with words or a sign.

## Type

Use `Typeface`. Serif is for figures and screen titles, and the system sans is for everything else.

| Token | Use |
| --- | --- |
| `Typeface.hero` | The one big number, through `HeroAmount` |
| `Typeface.figure` | Amounts in rows, tabular |
| `Typeface.heading` | Serif section or card heading |

Use Dynamic Type styles for all other text. Use two weights at most in a view.

## Components

- `PrimaryButtonStyle`: full width, a slab of ink with gentle corners that sinks when pressed. It lies flat while disabled. Use it once per screen.
- `QuietButtonStyle`: hairline outline, for a secondary action next to a primary one.
- `ShareStrip`: a thin bar of people's colors, and the app's one recurring mark. It replaces gradients as a group's identity.
- `AvatarView`: a small solid disc. A person's color goes on avatars and strips, never on large surfaces.

## Depth

Paper is the bottom level, cards sit on it, and system glass floats above both. `Splt/DesignSystem/CardSurface.swift` holds every value.

| Helper | Use |
| --- | --- |
| `.cardSurface()` | A raised card outside a List |
| `RaisedRows { }` | Several List rows on one card, with hairlines between them |
| `.raisedRow()` | A List row as its own card. List clips rows, so these helpers draw the card inside the row, with room for its shadow. In a grouped List, also use `.raisedSection()` |
| `.raisedContextMenuShape()` | Lifts only the card when a raised row's context menu opens |
| `.solidDisc(diameter:)` | A person's disc: a soft highlight and a small shadow |
| `.letterpress()` | Presses the one big number into the paper. `ShareStrip(isGrooved: true)` does the same for the strip beneath it |

Dark mode relies on a lighter sheet and a lit top edge, because shadows barely show there. Increase Contrast replaces the soft effects with a plain outline or a flat fill.

## Motion

Use `Motion`: `quick` for presses and toggles, `smooth` for layout, `settle` for things arriving. Numbers roll with `.numericText`. Every animation must respect Reduce Motion, which the `Motion` helpers handle.

## What users ask of this category

Research into competitors' reviews shaped these limits, and Splt keeps them permanently:

- Adding an expense has no caps, ads, countdowns or upsells.
- There's no account wall: the first screen is your groups.
- Amount, title and payer come first. Split options stay one step away.
- Balances read as one line per person.
- Settling up is one clear action and can be undone.

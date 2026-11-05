# Design

Splt looks like a well-kept paper ledger: ink on warm paper, with big printed numbers. Every rule below serves one aim, which is to show who owes what and get out of the way.

## Rules

1. **Color means something.** Chrome is ink on paper. Color appears only for a person or for the direction of money. Nothing is colored for decoration.
2. **The number leads.** Each screen has at most one big figure, set in the serif face, on the paper itself. It doesn't sit in a card.
3. **Lines before boxes.** Separate things with space first and a hairline second. Use a card only when content has to lift off the page.
4. **No gradients, shadows, glows or sparkles.** The system's own bars and sheets are the one exception.
5. **One primary action per screen.** Everything else is plain text or sits in a menu.
6. **Removing beats restyling.** If a screen works without an element, take the element out.
7. **Motion confirms.** Things move because the user did something. Settling up is the one moment allowed to celebrate.

## Color

Use `Ink`, never raw colors or `systemGroupedBackground`.

| Token | Use |
| --- | --- |
| `Ink.paper` | Screen background, via `.paperBackground()` |
| `Ink.sheet` | The rare raised surface |
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

- `PrimaryButtonStyle`: full width, ink fill, gentle corners. Use it once per screen.
- `QuietButtonStyle`: hairline outline, for a secondary action next to a primary one.
- `ShareStrip`: a thin bar of people's colors, and the app's one recurring mark. It replaces gradients as a group's identity.
- `AvatarView`: small and flat. A person's color goes on avatars and strips, never on large surfaces.

## Motion

Use `Motion`: `quick` for presses and toggles, `smooth` for layout, `settle` for things arriving. Numbers roll with `.numericText`. Every animation must respect Reduce Motion, which the `Motion` helpers handle.

## What users ask of this category

Research into competitors' reviews shaped these limits, and Splt keeps them permanently:

- Adding an expense has no caps, ads, countdowns or upsells.
- There's no account wall: the first screen is your groups.
- Amount, title and payer come first. Split options stay one step away.
- Balances read as one line per person.
- Settling up is one clear action and can be undone.

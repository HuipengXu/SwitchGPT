# ChatGPT UI foundations for SwitchGPT

Last reviewed: 2026-08-18

## Evidence and boundary

The installed ChatGPT desktop app is version `26.810.52044` (build `6662`). Direct
Computer Use inspection of `com.openai.codex` is blocked by the host safety policy,
so this document does not claim a pixel-by-pixel capture of private user pages. The
UI baseline instead comes from:

- read-only inspection of the installed app's packaged CSS, fonts, and shell assets;
- OpenAI's public documentation for the current desktop information architecture;
- a direct screenshot and accessibility-tree review of the current SwitchGPT build.

The official desktop documentation describes a global ChatGPT/Codex switcher, a
Chat/Work toggle inside ChatGPT, compact Recents and Projects navigation, and a
separate Codex history. Sources:

- <https://help.openai.com/en/articles/20001276>
- <https://help.openai.com/en/articles/20001275>
- <https://help.openai.com/en/articles/6825453-chatgpt-release-notes>

No OpenAI source code, font file, icon asset, or proprietary illustration is copied
into SwitchGPT. The implementation uses native macOS typography and SF Symbols.

## Measured design tokens

The current packaged desktop styles use a 4 pt base grid and a restrained neutral
palette:

| Role | Light | Dark |
| --- | --- | --- |
| Main surface | `#ffffff` | `#181818` |
| Sidebar / soft surface | cool gray with a very faint blue wash / `#f3f3f3` | neutral charcoal with a faint cool wash / `#282828` |
| Primary text | approximately `#1a1c1f` | `#dfdfdf` |
| Secondary text | about 65–70% of foreground | about 65–70% of foreground |
| Subtle border | 5% of foreground | 5% of foreground |
| Standard border | 8% of foreground | 8% of foreground |
| Strong border | 12% of foreground | 12% of foreground |

Semantic color is deliberately sparse rather than absent:

| Meaning | Color role | SwitchGPT use |
| --- | --- | --- |
| Action / active control | system blue | links, refresh, toggles, progress activity |
| Verified / successful | restrained green | current identity, successful completion |
| Caution / low quota | warm orange | experimental switching, 20% or less remaining |
| Destructive / critical | system red | failures, removal, 5% or less remaining |

Normal navigation, account identity, membership tiers, selection, panels, buttons,
and healthy quota bars stay neutral. Accounts never receive decorative colors.

Other stable tokens:

- base spacing: 4 pt;
- toolbar height: 46 pt, compact toolbar: 36 pt;
- navigation row: about 30–31 pt;
- desktop body: 14 pt; secondary labels: 12–13 pt;
- weights: 400 normal, 500 medium, 600 semibold;
- radii: 5, 7.5, 10, 12.5, 15, 20, and 25 pt after the desktop radius scale;
- motion: 150 ms for direct interaction, 300 ms for relaxed transitions;
- shadows are reserved for floating surfaces; ordinary rows use surface contrast.

The packaged app includes OpenAI Sans, but SwitchGPT intentionally uses the native
system font. This preserves platform rendering quality and avoids redistributing a
font that does not belong to this project.

## Product-level characteristics

1. **Shell first.** A compact sidebar and 46 pt content header establish the app.
   Navigation feels like a continuous surface, not a collection of cards.
2. **One dominant object.** A page shows one account or task once in the content
   area. Supporting metadata is attached to it instead of repeating the same title
   in a summary card, detail card, and banner.
3. **Neutral hierarchy with semantic color.** White, cool gray, near-black, and
   low-alpha foreground fills carry normal hierarchy. Blue marks actions and active
   controls; green confirms success; orange warns; red identifies destructive or
   critical states. Color never decorates account identity.
4. **Compact rows.** Sidebar actions and account rows are approximately 30–38 pt,
   with 8–12 pt horizontal insets and small SF Symbol-sized icons.
5. **Soft selection.** Selection uses a 5–8% foreground fill with a 10 pt radius,
   not a thick outline or saturated accent.
6. **Minimal borders.** Dividers separate structure. Panels use a 5–8% hairline only
   when the background alone cannot communicate grouping.
7. **Sentence-case labels.** Controls are short and direct: “Add account”, “Refresh”,
   “Switch account”. Technical implementation language belongs in help text.
8. **Progressive disclosure.** Safety detail remains available, but the normal usage
   page leads with quota and the next action instead of an engineering status report.
9. **Native, calm motion.** Hover and press feedback should settle in about 150 ms
   and must respect Reduce Motion. Structural sidebar transitions may use a slightly
   slower, non-bouncy 180 ms ease-in-out transition.

## SwitchGPT application rules

- The sidebar owns account navigation, account count, Add account, and a quiet local
  privacy note; it does not duplicate an app-wide Settings destination.
- Add account appears exactly once. While browser sign-in is pending, that row becomes
  Cancel sign-in and shows compact local progress; onboarding never masquerades as a
  quota refresh or disables unrelated dashboard controls.
- The detail pane has one header, one account identity block, one usage group, and
  one contextual action.
- Weekly quota is always shown. The 5-hour row and menu-bar segment only exist when
  the API returns that window.
- The current ChatGPT identity receives a quiet checkmark. A different real account
  gets the switch action; safety confirmation is required for every actual switch.
- Experimental status remains explicit in the confirmation itself, not as a large
  permanent warning card or a global settings toggle.
- Real-switch confirmation remains deliberately more prominent than ordinary UI;
  safety requirements are not weakened for visual similarity.
- The menu bar continues to display quota directly rather than an app icon.

## Problems in the previous UI

- The selected account appeared in the sidebar, introduction, summary strip, and
  large card at the same time.
- Large 14 pt-radius bordered cards made every region look equally important.
- The 900 × 620 minimum window and 40 pt content gutters made two metrics feel sparse.
- A toolbar, page header, and summary card repeated navigation and status controls.
- Permanent safety copy dominated the quota workflow and read like a validation tool.
- A global settings destination made a core account action feel optional and hidden.

These observations define the redesign acceptance criteria; they are not permission
to copy OpenAI branding or represent SwitchGPT as an official OpenAI product.

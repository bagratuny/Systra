# Systra — instrument-panel polish

Direction: a calm, precise macOS instrument for finding the cause of system load. Native SF Pro and SF Symbols, graphite surfaces, tabular figures. Metric colours identify data and sections; surfaces stay neutral. The live timestamp is the recurring signature. Existing logo, section order, features, large process rows and native glass tab navigation remain.

## Passes

1. Spacing: 4 pt rhythm, 12/16 pt grouping, 56 pt application rows and 52 pt process rows.
2. Colour: shared adaptive neutral canvas, surface, raised surface and hairline tokens.
3. Icons: native symbols; remove repeated decorative glyphs from dashboard stats, retain small semantic colour keys.
4. Copy: sentence case, shorter metric descriptions, shared units and decimal formatting for the selected Russian or English language.
5. Type: SF Pro, medium emphasis, readable metadata, tabular numeric figures.
6. Layout: complete 4×2 or 2×4 metric grid; CPU plot and ranked list share the remaining height. At narrower widths the plot precedes the list vertically.
7. Details: floating sortable headers, card hover feedback, chart scale, current plot value and actual last-sample timestamp.
8. Visuals: measured system data is the main visual. No generated artwork; the supplied Systra logo remains unchanged. Per-section history is retained.
9. Motion: a stable-width tab rail, one moving selection capsule, title-sized active tabs and clipped label reveals. A damped spring drives selection geometry; hover and text use short fades. Reduce Motion and the animation preference disable transitions.

Numeric formatting checks cover decimal separators, percentages, bytes, rates and unavailable readings. Aggregation, process identity, selection, temperature and uptime checks remain in test.sh.

Workflow adapted from **unslop by Damir Sokolovsky** ([@heydamir](https://x.com/heydamir), [unslop](https://heydamir.design/unslop)), licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). The native Systra implementation and product direction are specific to this project.

User refinement: dashboard tiles use a subtle section-colour fill and border, replacing the small underline. Their headings retain the existing neutral type treatment.

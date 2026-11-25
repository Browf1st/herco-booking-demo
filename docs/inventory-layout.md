# Stock-style staff screen layout

Reusable layout rules for Stock on Hand (`/inventory`) and similar staff screens. Linked from [F-013](features/F-013-inventory.md).

## Page layout

1. **Header.** Put the screen title and its page-level actions in the header. Give the main action the strongest treatment (primary button) and use secondary (ghost) styling for the others. Keep the main action first. On narrow screens, let the action group move below the title and wrap without sideways scrolling. For Stock on Hand the header actions, in order, are **Add supply** (primary), **Update existing stock**, and **Manage units and categories**.
2. **Summary.** Directly below the header, show **Total items**, **Healthy stock**, **Low stock**, and **Out of stock** in that order. One row of four tiles on desktop, two rows of two on phones. Include text labels and counts so each state is identifiable without colour.
3. **Search and filters.** Above the results. On desktop, a wide search field followed by Category and Stock status on the same row. On phones, full-width search above side-by-side Category and Stock status. Keep real field labels visible and the same choices across widths.
4. **Result count and pagination.** After the list: Previous, Page X of Y, and Next, with the buttons disabled at the ends. Same ordering, filters, status labels, permissions, and page size in both layouts. Include a clear empty state.
5. **Supporting sections.** Below the results. For Stock history show Item, From, Through, and Apply filters; align the button with the inputs when they share a row. On phones place the item filter above the date pair, with Apply filters below on the right. History pagination sits at the bottom right. No CSV download controls on this screen; the export endpoint remains available to authorized callers.

## Desktop table (Stock on Hand)

Left-to-right order:

| Column | Content |
| --- | --- |
| Item and details | Item name first, then storage location badge and any supplier, unit cost, and billing rate. |
| Category | Category name or Uncategorized. |
| Stock and capacity | On-hand quantity and unit first, then storage capacity. Add a meter and a percentage when capacity is positive. Show the actual quantity and percentage above capacity while keeping the bar within its track. |
| Status | A text badge for Healthy, Low stock, or Out of stock. |
| Reorder threshold | Threshold with its unit. |
| Inventory actions | Right-align Stock in, Stock out, and Edit in that order. Show this column only for staff who can manage inventory. Disable Stock out at zero stock. |

Use a real table with column headers. Give item names, quantities, and actions stable space so long values wrap within their columns.

## Phone cards (Stock on Hand)

One item per card, top to bottom:

1. **Item header.** Item name and optional location badge together. Category below the name, stock status badge on the right. Long names and categories wrap without pushing the badge off the card.
2. **Stock and capacity.** Quantity and unit, capacity, and the same meter and percentage rules as the desktop table.
3. **Other stock details.** Reorder threshold with its unit, then available supplier and pricing information with labels.
4. **Actions.** Stock in, Stock out, and Edit in the same order across the bottom when permitted. Keep controls at least 44px tall. Let labels wrap when needed.

## Opening full details (pattern for future screens)

A Details button, a "Tap to view more" prompt, and a tappable card are entry points to the same detail view. Provide a keyboard-accessible, clearly named Details control. If tapping the rest of the card also opens details, keep its individual action buttons independent so Stock out, Edit, or another action opens only its own workflow.

1. **Header.** Name or reference, status badge, and a labelled Close control. Side panel on desktop, bottom sheet on phones.
2. **Summary.** The facts staff need first, with short labels and visible values. For stock: category, storage location, on-hand quantity with unit, storage capacity and fill, reorder threshold.
3. **Grouped details.** For stock, group supplier and costs together and label Unit cost and Billing rate separately. Keep values and labels together when the layout stacks on phones.
4. **Notes and activity.** Relevant notes, then recent changes newest first. Each entry identifies the date and time, actor when available, action, and before/after values or reason when recorded. Plain empty state for expected-but-empty sections.
5. **Actions.** Main action first, then secondary actions, per the user's permissions. Keep read-only views read-only. Preserve existing confirmation or edit flows.

Use the same fields and order on desktop and phones. Keep the panel body scrollable, support Escape to close, and return focus to the control that opened it. Use clear loading, error, and empty messages when details are fetched.

> This details view is documentation for future screens. The current Stock on Hand screen does not add a View details button or a clickable Inventory card.

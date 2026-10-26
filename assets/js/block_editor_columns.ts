// Changing a row's column count, as a pure function so it can be tested without a browser.
//
// Every new column starts with one empty text block to type into. Shrinking a row used to move
// *all* blocks of the removed columns into the first column, empty placeholders included, so going
// from 8 columns to 4 left four empty cells piled on the first column to be deleted by hand.
// Now only blocks that hold something move; the placeholders go with their columns.

export interface ColBlock {
  id: string;
  type: string;
  content: any;
  media?: unknown[];
  [key: string]: any;
}

export interface Col {
  id: string;
  width: string;
  blocks: ColBlock[];
}

/** True for a text block with nothing in it (no words, no tags that carry anything). */
export function isEmptyBlock(block: ColBlock): boolean {
  if (block.type !== 'text') return false;
  if (block.media && block.media.length > 0) return false;
  const html = typeof block.content === 'string' ? block.content : '';
  if (/<(img|video|audio|iframe|embed|object|hr)\b/i.test(html)) return false;
  const text = html.replace(/<[^>]*>/g, '').replace(/&nbsp;|\s/gi, '');
  return text === '';
}

/**
 * The columns after the row is cut down to `newCount` (at least 1, fewer than now): the first
 * `newCount` columns, with the blocks that hold something from the dropped ones appended to the
 * first. A column left with nothing gets one empty text block, so it can still be typed in.
 */
export function shrinkColumns(columns: Col[], newCount: number, newId: () => string): Col[] {
  const keep = columns.slice(0, newCount);
  const moved: ColBlock[] = [];
  for (const dropped of columns.slice(newCount)) {
    moved.push(...dropped.blocks.filter((b) => !isEmptyBlock(b)));
  }

  if (moved.length > 0 && keep.length > 0) {
    // The first column's own empty placeholder would sit above the moved blocks for no reason.
    const first = keep[0];
    const onlyPlaceholders = first.blocks.every(isEmptyBlock);
    first.blocks = onlyPlaceholders ? [...moved] : [...first.blocks, ...moved];
  }

  for (const col of keep) {
    if (col.blocks.length === 0) col.blocks = [{ id: newId(), type: 'text', content: '' }];
  }
  return keep;
}

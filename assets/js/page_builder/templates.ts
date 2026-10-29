// What a new page or post can start from (the sheet an empty editor opens with). Each is rows of
// placeholder blocks, written in the saved format (model.ts), so the editor treats them like any
// page: click and type over them.

import { Doc, block, row, textBlock } from './model';

export interface Starter { id: string; name: string; blurb: string; icon: string; for: Array<'page' | 'post'>; make: () => Doc }

const p = (s: string) => `<p>${s}</p>`;
const doc = (...rows: ReturnType<typeof row>[]): Doc => ({ rows, version: 1 });

export const STARTERS: Starter[] = [
  {
    id: 'blank',
    name: 'Blank',
    blurb: 'Just start typing',
    icon: '✦',
    for: ['page', 'post'],
    make: () => doc(row([textBlock('')])),
  },
  {
    id: 'article',
    name: 'Article',
    blurb: 'A picture and words',
    icon: '📝',
    for: ['page', 'post'],
    make: () =>
      doc(
        row([block('image')], { width: 'wide' }),
        row([textBlock(p('Start with what matters most. Readers decide in the first two lines whether to keep going.'))]),
        row([block('heading', { content: 'A section heading' })]),
        row([textBlock(p('Write the rest here. Press + between rows to add a picture, a quote or a button.'))]),
      ),
  },
  {
    id: 'landing',
    name: 'Landing page',
    blurb: 'Headline, three points, a button',
    icon: '🚀',
    for: ['page'],
    make: () =>
      doc(
        row([block('heading', { content: 'Say what it is in one line', settings: { level: 1 } }), textBlock(p('One sentence on why anyone should care.')), block('button', { content: 'Get started' })], { width: 'wide', space: 'l', background: 'glass', align: 'center' }),
        row([], { width: 'wide' }, [
          [block('heading', { content: 'Fast', settings: { level: 3 } }), textBlock(p('The first reason, in a sentence or two.'))],
          [block('heading', { content: 'Simple', settings: { level: 3 } }), textBlock(p('The second reason.'))],
          [block('heading', { content: 'Yours', settings: { level: 3 } }), textBlock(p('The third reason.'))],
        ]),
        row([], { width: 'wide', align: 'center' }, [[block('image')], [block('heading', { content: 'Show it off' }), textBlock(p('A picture beside a few words works on every screen: on a phone they stack.'))]]),
        row([block('heading', { content: 'Ready?', settings: { level: 2 } }), block('button', { content: 'Sign up' })], { space: 'l', align: 'center' }),
      ),
  },
  {
    id: 'gallery',
    name: 'Gallery',
    blurb: 'A grid of pictures',
    icon: '🖼️',
    for: ['page', 'post'],
    make: () => doc(row([textBlock(p('A line about these pictures.'))]), row([block('gallery')], { width: 'wide' })),
  },
  {
    id: 'announcement',
    name: 'Announcement',
    blurb: 'News, with a callout',
    icon: '📣',
    for: ['page', 'post'],
    make: () =>
      doc(
        row([block('callout', { content: 'The news in one line.', settings: { calloutType: 'tip' } })]),
        row([textBlock(p('What is happening, when, and what it means for the reader.'))]),
        row([block('button', { content: 'Find out more' })]),
      ),
  },
  {
    id: 'patch',
    name: 'Patch notes',
    blurb: 'What changed in a game',
    icon: '🛠️',
    for: ['post'],
    make: () =>
      doc(
        row([textBlock(p('A short summary of this update.'))]),
        row([block('heading', { content: 'New' })]),
        row([textBlock('<ul><li>Something new</li><li>Something else new</li></ul>')]),
        row([block('heading', { content: 'Fixed' })]),
        row([textBlock('<ul><li>A bug that was squashed</li></ul>')]),
      ),
  },
];

export const startersFor = (kind: 'page' | 'post') => STARTERS.filter((s) => s.for.includes(kind));

// The image library picker of the block editor: a window over the pictures already added to other
// pages and posts. The server side is `Bacon8Web.ContentEditing.library/1` (`library-list`) and
// `library_use/3` (`library-use`); this module only draws the window and says what was picked.

export interface LibraryImage {
  url: string;
  filename: string;
}

export interface LibraryReply {
  images: LibraryImage[];
  more: boolean;
}

/** Asks the server for one page of the library. */
export type LibraryFetcher = (query: string, offset: number) => Promise<LibraryReply>;

/** The list after another page arrives: new pictures appended, ones already shown skipped. */
export function mergePage(shown: LibraryImage[], page: LibraryImage[]): LibraryImage[] {
  const seen = new Set(shown.map((image) => image.url));
  return shown.concat(page.filter((image) => !seen.has(image.url)));
}

/** Runs `fn` once `ms` after the last call. */
export function debounce<A extends unknown[]>(fn: (...args: A) => void, ms: number): (...args: A) => void {
  let timer: ReturnType<typeof setTimeout> | undefined;
  return (...args: A) => {
    if (timer) clearTimeout(timer);
    timer = setTimeout(() => fn(...args), ms);
  };
}

export interface LibraryOptions {
  fetch: LibraryFetcher;
  /** Called for each picture chosen. */
  onPick: (image: LibraryImage) => void;
  /** Keep the window open after a pick (a gallery takes several). */
  multiple?: boolean;
  title?: string;
}

/** Opens the picker. Returns a function that closes it. */
export function openLibrary(options: LibraryOptions): () => void {
  const overlay = document.createElement('div');
  overlay.className = 'b8-library-overlay';
  overlay.setAttribute('role', 'dialog');
  overlay.setAttribute('aria-modal', 'true');
  overlay.setAttribute('aria-label', options.title || 'Image library');

  const panel = document.createElement('div');
  panel.className = 'b8-library';

  const header = document.createElement('div');
  header.className = 'b8-library-header';
  const heading = document.createElement('strong');
  heading.textContent = options.title || 'Image library';
  const search = document.createElement('input');
  search.type = 'search';
  search.placeholder = 'Search by file name...';
  search.className = 'b8-library-search';
  const done = document.createElement('button');
  done.type = 'button';
  done.className = 'b8-library-close';
  done.textContent = options.multiple ? 'Done' : 'Close';
  header.append(heading, search, done);

  const grid = document.createElement('div');
  grid.className = 'b8-library-grid';
  const status = document.createElement('p');
  status.className = 'b8-library-status';
  const more = document.createElement('button');
  more.type = 'button';
  more.className = 'b8-library-more';
  more.textContent = 'Show more';
  more.hidden = true;

  panel.append(header, grid, status, more);
  overlay.append(panel);

  let shown: LibraryImage[] = [];
  let latest = 0; // a slow answer to an older search is ignored

  const draw = () => {
    grid.textContent = '';
    for (const image of shown) {
      const tile = document.createElement('button');
      tile.type = 'button';
      tile.className = 'b8-library-tile';
      tile.title = image.filename;
      const img = document.createElement('img');
      img.src = image.url;
      img.alt = image.filename;
      img.loading = 'lazy';
      tile.append(img);
      tile.addEventListener('click', () => {
        options.onPick(image);
        if (options.multiple) tile.classList.add('picked');
        else close();
      });
      grid.append(tile);
    }
  };

  const load = async (reset: boolean) => {
    const ticket = ++latest;
    status.textContent = 'Loading...';
    try {
      const reply = await options.fetch(search.value, reset ? 0 : shown.length);
      if (ticket !== latest) return;
      shown = reset ? reply.images : mergePage(shown, reply.images);
      draw();
      more.hidden = !reply.more;
      status.textContent = shown.length === 0 ? 'No pictures yet. Upload one into any block and it will be here.' : '';
    } catch {
      if (ticket === latest) status.textContent = 'The library could not be loaded.';
    }
  };

  const onKey = (event: KeyboardEvent) => {
    if (event.key === 'Escape') {
      event.stopPropagation();
      close();
    }
  };

  const close = () => {
    document.removeEventListener('keydown', onKey, true);
    overlay.remove();
  };

  search.addEventListener('input', debounce(() => load(true), 250));
  more.addEventListener('click', () => load(false));
  done.addEventListener('click', close);
  overlay.addEventListener('click', (event) => {
    if (event.target === overlay) close();
  });
  document.addEventListener('keydown', onKey, true);

  document.body.append(overlay);
  search.focus();
  load(true);
  return close;
}

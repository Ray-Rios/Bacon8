// The admin skill tree editor (/admin/bacon_world/skills, BaconWorldWeb.Admin.SkillTreeLive):
// the `BaconWorldSkillTreeEditor` LiveView hook. The tree on a canvas (skill-tree-canvas.ts)
// and the abilities in a palette:
//
//   - drag an ability onto a node to put it there (onto empty canvas: a new node there,
//     joined to the selected one);
//   - click a node to select it; drag it to move it (snaps to quarter rings);
//   - Shift-click another node to join it to the selected one (or unjoin);
//   - double-click empty canvas for a new empty node joined to the selected one;
//   - Delete removes the selected node (not the start);
//   - Save sends the whole tree (the server validates it); Reset puts the shipped tree back.
import { TREE_CSS, TreeCanvas, abilityLines, dragAbility, iconHTML, type Ability, type Catalog, type Tree, type TreeNode } from './skill-tree-canvas';

const CSS = `
${TREE_CSS}
.bwte{position:absolute;inset:0;display:flex;font:13px/1.35 system-ui,sans-serif;color:#ddd}
.bwte .pal{width:230px;flex:none;overflow-y:auto;border-right:1px solid rgba(255,255,255,.08);padding:10px;background:rgba(0,0,0,.25)}
.bwte .pal h3{font-size:11px;letter-spacing:.08em;text-transform:uppercase;color:#9aa;margin:12px 0 6px}
.bwte .ab{display:flex;align-items:center;gap:8px;padding:5px 6px;border-radius:6px;cursor:grab;user-select:none}
.bwte .ab:hover{background:rgba(255,255,255,.06)}
.bwte .ab .n{font-size:12px}.bwte .ab .n small{display:block;color:#889;font-size:10px}
.bwte .main{flex:1;position:relative;display:flex;flex-direction:column;min-width:0}
.bwte .bar{display:flex;gap:6px;align-items:center;padding:8px 10px;border-bottom:1px solid rgba(255,255,255,.08);flex-wrap:wrap}
.bwte button{font:inherit;font-size:12px;color:#eee;background:#2b3240;border:1px solid #445;border-radius:6px;padding:4px 10px;cursor:pointer}
.bwte button:hover{background:#38415a}.bwte button.pri{background:#2563eb;border-color:#3b82f6}.bwte button.dng{background:#5b1e1e;border-color:#933}
.bwte button:disabled{opacity:.4;cursor:default}
.bwte .st{margin-left:auto;font-size:12px;color:#9ab}
.bwte .cv{flex:1;position:relative;background:radial-gradient(circle at 50% 50%,#1b1712,#0b0a08 70%)}
.bwte .sel{padding:6px 10px;border-top:1px solid rgba(255,255,255,.08);font-size:12px;color:#bbc;min-height:30px}
.bwte .tip{position:fixed;display:none;pointer-events:none;max-width:260px;padding:6px 8px;background:rgba(10,10,14,.95);border:1px solid #445;border-radius:6px;font-size:12px;z-index:50}
.bwte .tip b{display:block;color:#f0d77a}
`;

const SNAP = 0.25;
const snap = (v: number) => Math.round(v / SNAP) * SNAP;

export const BaconWorldSkillTreeEditor = {
  mounted(this: any) {
    const el = this.el as HTMLElement;
    const catalog: Catalog = JSON.parse(el.dataset.catalog || '{}');
    const shipped: Tree = JSON.parse(el.dataset.default || '{}');
    let tree: Tree = JSON.parse(el.dataset.tree || '{}');
    let selected: string | null = tree.start;
    let dirty = false;

    const style = document.createElement('style');
    style.textContent = CSS;
    document.head.appendChild(style);
    const root = document.createElement('div');
    root.className = 'bwte';
    el.appendChild(root);
    const pal = document.createElement('div');
    pal.className = 'pal';
    const main = document.createElement('div');
    main.className = 'main';
    const bar = document.createElement('div');
    bar.className = 'bar';
    const cv = document.createElement('div');
    cv.className = 'cv';
    const sel = document.createElement('div');
    sel.className = 'sel';
    const tip = document.createElement('div');
    tip.className = 'tip';
    main.append(bar, cv, sel);
    root.append(pal, main, tip);

    const btn = (label: string, cls: string, fn: () => void) => {
      const b = document.createElement('button');
      b.textContent = label;
      if (cls) b.className = cls;
      b.onclick = fn;
      bar.appendChild(b);
      return b;
    };
    const status = document.createElement('span');
    status.className = 'st';

    const byId = (id: string | null) => (id ? tree.nodes.find((n) => n.id === id) : undefined);
    const nextId = () => {
      let i = tree.nodes.length;
      while (byId(`n${i}`)) i++;
      return `n${i}`;
    };
    const joined = (a: string, b: string) => tree.edges.some(([x, y]) => (x === a && y === b) || (x === b && y === a));
    const touch = (msg = 'Unsaved changes') => {
      dirty = true;
      status.textContent = msg;
      status.style.color = '#fbbf24';
      draw();
    };

    const canvas = new TreeCanvas(cv, {
      ring: 90,
      state: (n) => (n.id === selected ? 'selected' : n.id === tree.start ? 'learned' : 'edit'),
      onNodeDown: (n, e) => nodeDown(n, e),
      onNodeHover: (n, e) => {
        if (!n || !e) {
          tip.style.display = 'none';
          return;
        }
        const a = n.ability ? catalog[n.ability] : null;
        tip.innerHTML = `<b>${a ? a.name : 'Empty node'} <span style="color:#889;font-weight:400">${n.id}${n.id === tree.start ? ' · start' : ''}</span></b>${a ? abilityLines(a).slice(0, 2).map((l) => `<div>${l}</div>`).join('') : '<div>A path: drag an ability onto it.</div>'}`;
        tip.style.display = 'block';
        tip.style.left = `${e.clientX + 14}px`;
        tip.style.top = `${e.clientY + 10}px`;
      },
      onBackgroundDblClick: (x, y) => addNode(snap(x), snap(y), null),
    });

    function draw() {
      canvas.set(tree, catalog);
      const n = byId(selected);
      const a = n?.ability ? catalog[n.ability] : null;
      sel.textContent = n
        ? `Selected ${n.id}${n.id === tree.start ? ' (start)' : ''}: ${a ? `${a.name} (${a.kind})` : 'empty'} · joined to ${tree.edges.filter(([x, y]) => x === n.id || y === n.id).length} · at (${n.x}, ${n.y})`
        : 'Nothing selected.';
      for (const b of [clearBtn, startBtn, delBtn]) b.disabled = !n;
      delBtn.disabled = !n || n.id === tree.start;
      startBtn.disabled = !n || n.id === tree.start;
    }

    function addNode(x: number, y: number, ability: string | null) {
      const id = nextId();
      tree.nodes.push({ id, x, y, ability });
      if (selected && byId(selected)) tree.edges.push([selected, id]);
      selected = id;
      touch();
    }

    function nodeDown(n: TreeNode, e: PointerEvent) {
      e.stopPropagation();
      if (e.shiftKey && selected && selected !== n.id) {
        if (joined(selected, n.id)) tree.edges = tree.edges.filter(([x, y]) => !((x === selected && y === n.id) || (x === n.id && y === selected)));
        else tree.edges.push([selected, n.id]);
        touch();
        return;
      }
      selected = n.id;
      draw();
      const sx = e.clientX, sy = e.clientY;
      let moved = false;
      const move = (ev: PointerEvent) => {
        if (!moved && Math.hypot(ev.clientX - sx, ev.clientY - sy) < 5) return;
        moved = true;
        tip.style.display = 'none';
        const p = canvas.toTree(ev.clientX, ev.clientY);
        const node = byId(n.id)!;
        node.x = snap(p.x);
        node.y = snap(p.y);
        canvas.set(tree, catalog);
      };
      const up = () => {
        window.removeEventListener('pointermove', move);
        window.removeEventListener('pointerup', up);
        if (moved) touch();
      };
      window.addEventListener('pointermove', move);
      window.addEventListener('pointerup', up);
    }

    // the palette
    const groups: Array<[string, string]> = [['spell', 'Spells'], ['skill', 'Skills'], ['buff', 'Buffs']];
    for (const [kind, label] of groups) {
      const hd = document.createElement('h3');
      hd.textContent = label;
      pal.appendChild(hd);
      for (const a of Object.values(catalog).filter((x: Ability) => x.kind === kind)) {
        const row = document.createElement('div');
        row.className = 'ab';
        row.innerHTML = `${iconHTML(a, 30)}<div class="n">${a.name}<small>${a.summary}</small></div>`;
        row.onpointerdown = (e) => {
          e.preventDefault();
          dragAbility(a, e, (_drop, x, y) => {
            const r = cv.getBoundingClientRect();
            if (x < r.left || x > r.right || y < r.top || y > r.bottom) return;
            const node = canvas.nodeAt(x, y);
            if (node) {
              node.ability = a.id;
              selected = node.id;
              touch();
            } else {
              const p = canvas.toTree(x, y);
              addNode(snap(p.x), snap(p.y), a.id);
            }
          });
        };
        pal.appendChild(row);
      }
    }

    btn('Save', 'pri', () => {
      status.textContent = 'Saving…';
      status.style.color = '#9ab';
      this.pushEvent('save', { tree }, (res: any) => {
        if (res?.ok) {
          tree = res.tree;
          dirty = false;
          status.textContent = 'Saved.';
          status.style.color = '#4ade80';
          draw();
        } else {
          status.textContent = `Not saved: ${res?.error || 'unknown error'}`;
          status.style.color = '#f87171';
        }
      });
    });
    const clearBtn = btn('Clear ability', '', () => {
      const n = byId(selected);
      if (n) {
        n.ability = null;
        touch();
      }
    });
    const startBtn = btn('Make start', '', () => {
      if (selected) {
        tree.start = selected;
        touch();
      }
    });
    const delBtn = btn('Delete node', 'dng', () => deleteSelected());
    btn('Centre view', '', () => canvas.centre());
    btn('Undo all (reload saved)', '', () => {
      if (dirty && !confirm('Throw away your unsaved changes?')) return;
      tree = JSON.parse(el.dataset.tree || '{}');
      dirty = false;
      status.textContent = '';
      draw();
    });
    btn('Reset to shipped tree', 'dng', () => {
      if (!confirm('Replace the saved tree with the one the game ships with? Players keep their points: nodes that go away hand theirs back.')) return;
      this.pushEvent('reset', {}, (res: any) => {
        if (res?.ok) {
          tree = res.tree || shipped;
          dirty = false;
          status.textContent = 'The shipped tree is back.';
          status.style.color = '#4ade80';
          draw();
        }
      });
    });
    bar.appendChild(status);

    function deleteSelected() {
      if (!selected || selected === tree.start) return;
      const id = selected;
      tree.nodes = tree.nodes.filter((n) => n.id !== id);
      tree.edges = tree.edges.filter(([a, b]) => a !== id && b !== id);
      selected = tree.start;
      touch();
    }

    this.onKey = (e: KeyboardEvent) => {
      const t = e.target as HTMLElement;
      if (t && ['INPUT', 'TEXTAREA', 'SELECT'].includes(t.tagName)) return;
      if (e.key === 'Delete' || e.key === 'Backspace') {
        e.preventDefault();
        deleteSelected();
      }
    };
    window.addEventListener('keydown', this.onKey);
    this.onLeave = (e: BeforeUnloadEvent) => {
      if (dirty) e.preventDefault();
    };
    window.addEventListener('beforeunload', this.onLeave);
    this.cleanup = () => style.remove();
    draw();
    canvas.centre();
  },

  destroyed(this: any) {
    window.removeEventListener('keydown', this.onKey);
    window.removeEventListener('beforeunload', this.onLeave);
    this.cleanup?.();
  },
};

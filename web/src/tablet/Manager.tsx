import {
  Check,
  FolderPlus,
  Gauge,
  Hammer,
  Layers,
  MapPin,
  Package,
  Pencil,
  Plus,
  RotateCcw,
  ScrollText,
  Search,
  Trash2,
  X,
} from 'lucide-react';

import { useEffect, useMemo, useRef, useState } from 'react';
import { levelConfig, limits } from '../init';
import { locale } from '../locale';
import { itemImage, nui } from '../nui';
import { useTablet } from './context';
import { itemOption, useItems } from './items';

import type {
  BenchModel,
  CraftingBench,
  CraftingCategory,
  CraftingCooldown,
  CraftingData,
  CraftingIngredient,
  CraftingRecipe,
  CraftingType,
  GangOption,
  LevelEntry,
  Vec3,
} from '../types';

import {
  Button,
  Card,
  Combobox,
  ConfirmButton,
  ConfirmDialog,
  Empty,
  Field,
  Modal,
  MultiSelect,
  Pill,
  Select,
  Thumb,
  type Option,
} from './ui';

import { arr, cls } from '../util';

const NEW_DURATION = 10;
const COORDS_MS = 3000;
const SEARCH_MIN_LENGTH = 2;

type Load = { kind: 'loading' } | { kind: 'failed' } | { kind: 'ready'; data: CraftingData };
type Mutate = (action: string, payload: Record<string, unknown>) => Promise<boolean>;


interface Draft {
  item: string | null;
  count: number;
  duration: number;
  blueprint: string | null;
  limit: number;
  hours: number;
  xp: number | null;
  level: number;
  category: number | null;
  ingredients: CraftingIngredient[];
}

type Editing = { kind: 'recipe'; item: string; draft: Draft | null } | { kind: 'new'; draft: Draft };

interface Located {
  category: number;
  recipe: CraftingRecipe;
}

type TypeDialog =
  | { kind: 'rename' }
  | { kind: 'delete' }
  | { kind: 'addCategory' }
  | { kind: 'renameCategory'; index: number }
  | { kind: 'deleteCategory'; index: number };

type BenchDialog =
  { kind: 'place' } | { kind: 'edit'; bench: CraftingBench } | { kind: 'remove'; bench: CraftingBench };

interface BenchOptions {
  types: Option<string>[];
  gangs: Option<string>[];
  models: Option<string>[];
}

function toCooldown(value: unknown): CraftingCooldown | null {
  if (typeof value !== 'object' || value === null || !('limit' in value) || !('hours' in value)) {
    return null;
  }

  const { limit, hours } = value;

  if (typeof limit !== 'number' || typeof hours !== 'number' || limit < 1 || hours < 1) {
    return null;
  }

  return { limit, hours };
}

const fixData = (raw: CraftingData): CraftingData => ({
  types: arr<CraftingType>(raw.types).map((t) => ({
    ...t,
    categories: arr<CraftingCategory>(t.categories).map((c) => ({
      ...c,
      recipes: arr<CraftingRecipe>(c.recipes).map((r) => ({
        ...r,
        cooldown: toCooldown(r.cooldown),
        xp: typeof r.xp === 'number' ? r.xp : null,
        level: typeof r.level === 'number' && r.level > 1 ? r.level : null,
        ingredients: arr<CraftingIngredient>(r.ingredients),
      })),
    })),
  })),
  tables: arr<CraftingBench>(raw.tables).map((b) => ({ ...b, gangs: arr<string>(b.gangs) })),
  gangs: arr<GangOption>(raw.gangs),
  models: arr<BenchModel>(raw.models),
});

const plural = (n: number, key: string, ...rest: (string | number)[]) =>
  locale(n === 1 ? `${key}_one` : `${key}_many`, n.toLocaleString(), ...rest);
const digits = (value: string, max: number) => Math.min(max, Number(value.replace(/\D/g, '')) || 0);
const recipeCount = (t: CraftingType) => t.categories.reduce((n, c) => n + c.recipes.length, 0);
const distanceBetween = (a: Vec3, b: Vec3) => Math.hypot(a.x - b.x, a.y - b.y, a.z - b.z);
const distanceText = (m: number) =>
  m < 1000 ? locale('ui_metres', Math.round(m)) : locale('ui_kilometres', (m / 1000).toFixed(1));

const blank = (category: number | null): Draft => ({
  item: null,
  count: 1,
  duration: NEW_DURATION,
  blueprint: null,
  limit: 0,
  hours: 0,
  xp: null,
  level: 0,
  category,
  ingredients: [],
});

const toDraft = (r: CraftingRecipe): Draft => ({
  item: r.item,
  count: r.count,
  duration: r.duration,
  blueprint: r.blueprint || null,
  limit: r.cooldown?.limit ?? 0,
  hours: r.cooldown?.hours ?? 0,
  xp: r.xp ?? null,
  level: r.level ?? 0,
  category: null,
  ingredients: r.ingredients,
});

const same = (a: Draft, b: Draft) =>
  a.item === b.item &&
  a.count === b.count &&
  a.duration === b.duration &&
  a.blueprint === b.blueprint &&
  a.limit === b.limit &&
  a.hours === b.hours &&
  a.xp === b.xp &&
  a.level === b.level &&
  a.category === b.category &&
  a.ingredients.length === b.ingredients.length &&
  a.ingredients.every((i, n) => i.item === b.ingredients[n].item && i.count === b.ingredients[n].count);

function locate(categories: CraftingCategory[], item: string): Located | null {
  for (const [category, c] of categories.entries()) {
    const recipe = c.recipes.find((r) => r.item === item);

    if (recipe) {
      return { category, recipe };
    }
  }

  return null;
}

function placeRecipe(
  categories: CraftingCategory[],
  recipe: CraftingRecipe,
  target: number,
  original: string | null,
): CraftingCategory[] {
  return categories.map((c, i) => {
    const at = original === null ? -1 : c.recipes.findIndex((r) => r.item === original);

    if (i === target && at !== -1) {
      return { ...c, recipes: c.recipes.map((r, n) => (n === at ? recipe : r)) };
    }

    const kept = at === -1 ? c.recipes : c.recipes.filter((_, n) => n !== at);

    return { ...c, recipes: i === target ? [...kept, recipe] : kept };
  });
}

function problem({
  draft,
  type,
  original,
  target,
  known,
}: {
  draft: Draft;
  type: CraftingType;
  original: Located | null;
  target: number | null;
  known: Set<string> | null;
}) {
  const missing = [draft.item, draft.blueprint, ...draft.ingredients.map((i) => i.item)].find(
    (name) => name && known && !known.has(name),
  );

  if (!draft.item) {
    return locale('ui_issue_no_item');
  }

  if (missing) {
    return locale('ui_issue_unknown_item', missing);
  }

  if (draft.item !== original?.recipe.item && locate(type.categories, draft.item)) {
    return locale('ui_issue_duplicate');
  }

  if (draft.count < 1) {
    return locale('ui_issue_count');
  }

  if (draft.duration < 1) {
    return locale('ui_issue_duration');
  }

  if (draft.limit > 0 && draft.hours < 1) {
    return locale('ui_issue_hours');
  }

  if (draft.hours > 0 && draft.limit < 1) {
    return locale('ui_issue_limit');
  }

  if (draft.level > levelConfig.maxLevel) {
    return locale('ui_issue_level', levelConfig.maxLevel);
  }

  if (target === null || !type.categories[target]) {
    return locale('ui_pick_category');
  }

  if (target !== original?.category && type.categories[target].recipes.length >= limits.recipes) {
    return locale('ui_issue_category_full', limits.recipes);
  }

  if (draft.ingredients.length > limits.ingredients) {
    return locale('ui_issue_ingredients', limits.ingredients);
  }

  if (draft.ingredients.some((i) => i.count < 1)) {
    return locale('ui_issue_amount');
  }

  return null;
}

export default function Manager() {
  const { query } = useTablet();
  const [load, setLoad] = useState<Load>({ kind: 'loading' });
  const [reload, setReload] = useState(0);
  const lastSave = useRef(0);

  useEffect(() => {
    let live = true;

    query<CraftingData>('data').then((res) => {
      if (!live) return;

      if (res) {
        setLoad({ kind: 'ready', data: fixData(res) });
      } else {
        setLoad((cur) => (cur.kind === 'ready' ? cur : { kind: 'failed' }));
      }
    });

    return () => {
      live = false;
    };
  }, [query, reload]);

  useEffect(() => {
    let timer: ReturnType<typeof setTimeout> | undefined;

    const onMessage = (e: MessageEvent) => {
      if (e.data?.action !== 'dirty' || Date.now() - lastSave.current < 500) return;

      clearTimeout(timer);
      timer = setTimeout(() => setReload((n) => n + 1), 300);
    };

    window.addEventListener('message', onMessage);

    return () => {
      clearTimeout(timer);
      window.removeEventListener('message', onMessage);
    };
  }, []);

  const mutate: Mutate = async (action, payload) => {
    const res = await query<CraftingData>(action, payload);

    if (!res) return false;

    lastSave.current = Date.now();
    setLoad({ kind: 'ready', data: fixData(res) });

    return true;
  };

  if (load.kind !== 'ready') {
    return (
      <Card>
        <Empty icon={Hammer} className="fill">
          {load.kind === 'loading' ? locale('ui_loading') : locale('ui_load_failed')}
        </Empty>
      </Card>
    );
  }

  return (
    <div className="craft-page">
      <Recipes data={load.data} mutate={mutate} />
    </div>
  );
}

function Recipes({ data, mutate }: { data: CraftingData; mutate: Mutate }) {
  const [selected, setSelected] = useState<string | null>(null);
  const [page, setPage] = useState<'types' | 'levels'>('types');
  const type = data.types.find((t) => t.name === selected) ?? null;

  const benches = useMemo(() => {
    const byType = new Map<string, CraftingBench[]>();

    for (const b of data.tables) {
      byType.set(b.type, [...(byType.get(b.type) ?? []), b]);
    }

    return byType;
  }, [data.tables]);

  const orphans = data.tables.filter((b) => !data.types.some((t) => t.name === b.type));

  const options = useMemo<BenchOptions>(
    () => ({
      types: data.types.map((t) => ({ value: t.name, label: t.label, hint: t.name })),
      gangs: data.gangs.filter((g) => g.name !== 'none').map((g) => ({ value: g.name, label: g.label })),
      models: data.models.map((m) => ({ value: m.model, label: m.label, hint: m.model })),
    }),
    [data.types, data.gangs, data.models],
  );

  if (selected !== null && type === null) {
    setSelected(null);
  }

  const select = (name: string) => {
    setSelected(name);
    setPage('types');
  };

  const create = async (name: string, label: string) => {
    const ok = await mutate('saveType', { name, type: { label, categories: [] }, isNew: true });

    if (ok) {
      select(name);
    }

    return ok;
  };

  const openLevels = () => {
    setSelected(null);
    setPage('levels');
  };

  return (
    <div className="craft-recipes">
      <TypeList
        types={data.types}
        benches={benches}
        orphans={orphans}
        options={options}
        selected={selected}
        onSelect={select}
        onCreate={create}
        mutate={mutate}
        levelsOpen={page === 'levels'}
        onLevels={openLevels}
      />
      {page === 'levels' ? (
        <Levels />
      ) : type ? (
        <Workspace
          key={type.name}
          type={type}
          benches={benches.get(type.name) ?? []}
          options={options}
          mutate={mutate}
        />
      ) : (
        <>
          <Card>
            <Empty icon={Hammer} className="fill">
              {data.types.length > 0 ? locale('ui_pick_type') : locale('ui_create_first_type')}
            </Empty>
          </Card>
          <Card>
            <Empty icon={Package} className="fill">
              {locale('ui_pick_recipe')}
            </Empty>
          </Card>
        </>
      )}
    </div>
  );
}

function TypeList({
  types,
  benches,
  orphans,
  options,
  selected,
  onSelect,
  onCreate,
  mutate,
  levelsOpen,
  onLevels,
}: {
  types: CraftingType[];
  benches: Map<string, CraftingBench[]>;
  orphans: CraftingBench[];
  options: BenchOptions;
  selected: string | null;
  onSelect(name: string): void;
  onCreate(name: string, label: string): Promise<boolean>;
  mutate: Mutate;
  levelsOpen: boolean;
  onLevels(): void;
}) {
  const [creating, setCreating] = useState(false);

  return (
    <Card
      title={
        <>
          {locale('ui_bench_types')} <span className="title-count">{types.length}</span>
        </>
      }
      actions={
        <Button size="sm" variant="ghost" icon={Plus} onClick={() => setCreating(true)}>
          {locale('ui_new_type')}
        </Button>
      }
      bodyClassName="flush scroll"
    >
      {levelConfig.enabled && (
        <button type="button" className={cls('plist-row', levelsOpen && 'is-active')} onClick={onLevels}>
          <span className="plist-main">
            <span className="plist-name">{locale('ui_levels')}</span>
            <span className="plist-sub">{locale('ui_levels_sub')}</span>
          </span>
        </button>
      )}
      {types.length === 0 && <Empty icon={Hammer}>{locale('ui_no_types')}</Empty>}
      {types.map((t) => (
        <button
          key={t.name}
          type="button"
          className={cls('plist-row', t.name === selected && 'is-active')}
          onClick={() => onSelect(t.name)}
        >
          <span className="plist-main">
            <span className="plist-name">
              {t.label}
              <span className="mono craft-key">{t.name}</span>
            </span>
            <span className="plist-sub">
              {plural(t.categories.length, 'ui_category')} · {plural(recipeCount(t), 'ui_recipe')} ·{' '}
              {locale('ui_n_placed', (benches.get(t.name)?.length ?? 0).toLocaleString())}
            </span>
          </span>
        </button>
      ))}
      {orphans.length > 0 && (
        <div className="craft-orphans">
          <BenchGroup title={locale('ui_orphan_benches')} benches={orphans} options={options} mutate={mutate} />
        </div>
      )}
      {creating && (
        <NewTypeDialog
          taken={(name) => types.some((t) => t.name === name)}
          onCreate={onCreate}
          onClose={() => setCreating(false)}
        />
      )}
    </Card>
  );
}

function Workspace({
  type,
  benches,
  options,
  mutate,
}: {
  type: CraftingType;
  benches: CraftingBench[];
  options: BenchOptions;
  mutate: Mutate;
}) {
  const [editing, setEditing] = useState<Editing | null>(null);
  const at = editing?.kind === 'recipe' ? locate(type.categories, editing.item) : null;
  const saved = editing?.kind === 'new' ? blank(editing.draft.category) : at && toDraft(at.recipe);

  if (editing?.kind === 'recipe' && at === null) {
    setEditing(null);
  }

  const save = (next: CraftingType) =>
    mutate('saveType', {
      name: next.name,
      type: { label: next.label, categories: next.categories },
      isNew: false,
    });

  const open = (item: string) => {
    if (editing?.kind !== 'recipe' || editing.item !== item) {
      setEditing({ kind: 'recipe', item, draft: null });
    }
  };

  const categoryDeleted = (removed: number) =>
    setEditing((e) => {
      if (!e?.draft) {
        return e;
      }

      const c = e.draft.category;

      return { ...e, draft: { ...e.draft, category: c === null || c < removed ? c : c === removed ? null : c - 1 } };
    });

  const discard = () =>
    setEditing((e) =>
      e?.kind === 'new' ? { kind: 'new', draft: blank(e.draft.category) } : e && { ...e, draft: null },
    );

  const saveRecipe = async (draft: Draft) => {
    const { item } = draft;
    const target = draft.category ?? at?.category;

    if (!item || target === undefined) return false;

    const recipe: CraftingRecipe = {
      item,
      count: draft.count,
      duration: draft.duration,
      ingredients: draft.ingredients,
      ...(draft.blueprint ? { blueprint: draft.blueprint } : {}),
      ...(draft.limit > 0 && draft.hours > 0 ? { cooldown: { limit: draft.limit, hours: draft.hours } } : {}),
      ...(draft.xp !== null ? { xp: draft.xp } : {}),
      ...(draft.level > 1 ? { level: draft.level } : {}),
    };

    const ok = await save({
      ...type,
      categories: placeRecipe(type.categories, recipe, target, at?.recipe.item ?? null),
    });

    if (ok) {
      setEditing({ kind: 'recipe', item, draft: null });
    }

    return ok;
  };

  const deleteRecipe = (item: string) =>
    save({
      ...type,
      categories: type.categories.map((c) => ({ ...c, recipes: c.recipes.filter((r) => r.item !== item) })),
    });

  return (
    <>
      <TypePanel
        type={type}
        benches={benches}
        options={options}
        mutate={mutate}
        active={editing?.kind === 'recipe' ? editing.item : null}
        onOpen={open}
        onAdd={(category) => setEditing({ kind: 'new', draft: blank(category) })}
        onSave={save}
        onDelete={() => mutate('deleteType', { name: type.name })}
        onCategoryDeleted={categoryDeleted}
      />
      {editing && saved ? (
        <Editor
          key={editing.kind === 'recipe' ? editing.item : 'new'}
          type={type}
          original={at}
          saved={saved}
          draft={editing.draft ?? saved}
          onDraft={(draft) => setEditing((e) => e && { ...e, draft })}
          onDiscard={discard}
          onSave={saveRecipe}
          onDelete={deleteRecipe}
        />
      ) : (
        <Card>
          <Empty icon={Package} className="fill">
            {locale('ui_pick_or_add')}
          </Empty>
        </Card>
      )}
    </>
  );
}

function TypePanel({
  type,
  benches,
  options,
  mutate,
  active,
  onOpen,
  onAdd,
  onSave,
  onDelete,
  onCategoryDeleted,
}: {
  type: CraftingType;
  benches: CraftingBench[];
  options: BenchOptions;
  mutate: Mutate;
  active: string | null;
  onOpen(item: string): void;
  onAdd(category: number): void;
  onSave(next: CraftingType): Promise<boolean>;
  onDelete(): Promise<boolean>;
  onCategoryDeleted(index: number): void;
}) {
  const items = useItems();
  const labels = useMemo(() => new Map((items ?? []).map((i) => [i.name, i.label])), [items]);
  const [dialog, setDialog] = useState<TypeDialog | null>(null);
  const close = () => setDialog(null);
  const withCategories = (categories: CraftingCategory[]) => onSave({ ...type, categories });

  const renderDialog = (d: TypeDialog) => {
    switch (d.kind) {
      case 'rename':
        return (
          <LabelDialog
            title={locale('ui_rename_x', type.label)}
            initial={type.label}
            submit={locale('ui_save')}
            onSubmit={(label) => onSave({ ...type, label })}
            onClose={close}
          />
        );
      case 'delete': {
        const recipes = recipeCount(type);
        const placed = benches.length;

        return (
          <ConfirmDialog
            title={locale('ui_delete_x', type.label)}
            confirm={locale('ui_delete_type')}
            onConfirm={onDelete}
            onClose={close}
          >
            {type.categories.length > 0 &&
              `${locale('ui_delete_type_contents', plural(type.categories.length, 'ui_category'), plural(recipes, 'ui_recipe'))} `}
            {placed === 0 ? locale('ui_delete_type_no_benches') : plural(placed, 'ui_delete_type_benches')}
          </ConfirmDialog>
        );
      }
      case 'addCategory':
        return (
          <LabelDialog
            title={locale('ui_add_category')}
            submit={locale('ui_add_category')}
            onSubmit={(label) => withCategories([...type.categories, { label, recipes: [] }])}
            onClose={close}
          />
        );
      case 'renameCategory': {
        const { index } = d;
        const category = type.categories[index];

        if (!category) return null;

        return (
          <LabelDialog
            title={locale('ui_rename_x', category.label)}
            initial={category.label}
            submit={locale('ui_save')}
            onSubmit={(label) => withCategories(type.categories.map((c, i) => (i === index ? { ...c, label } : c)))}
            onClose={close}
          />
        );
      }
      case 'deleteCategory': {
        const { index } = d;
        const category = type.categories[index];

        if (!category) return null;

        const n = category.recipes.length;

        return (
          <ConfirmDialog
            title={locale('ui_delete_category_x', category.label)}
            confirm={locale('ui_delete_category')}
            onConfirm={async () => {
              const ok = await withCategories(type.categories.filter((_, i) => i !== index));

              if (ok) {
                onCategoryDeleted(index);
              }

              return ok;
            }}
            onClose={close}
          >
            {n === 0 ? locale('ui_category_empty') : plural(n, 'ui_category_recipes_deleted')}
          </ConfirmDialog>
        );
      }
      default: {
        const _exhaustive: never = d;

        return _exhaustive;
      }
    }
  };

  return (
    <Card
      className="craft-type"
      title={
        <>
          {type.label}
          <span className="mono craft-key">{type.name}</span>
        </>
      }
      actions={
        <>
          <Button size="sm" variant="ghost" icon={Pencil} onClick={() => setDialog({ kind: 'rename' })}>
            {locale('ui_rename')}
          </Button>
          <Button size="sm" variant="ghost" icon={Trash2} onClick={() => setDialog({ kind: 'delete' })}>
            {locale('ui_delete')}
          </Button>
        </>
      }
      bodyClassName="craft-type-body"
    >
      <div className="craft-cats scroll grow">
        <BenchGroup title={locale('ui_placed_benches')} benches={benches} place={type} options={options} mutate={mutate} />
        {type.categories.length === 0 && <Empty icon={Layers}>{locale('ui_no_categories')}</Empty>}
        {type.categories.map((c, i) => (
          <div key={i} className="craft-cat">
            <div className="craft-cat-head">
              <span className="craft-cat-name">{c.label}</span>
              <span className="craft-cat-count">{c.recipes.length}</span>
              <button
                type="button"
                className="tiny-btn owned-btn"
                title={locale('ui_add_recipe')}
                disabled={c.recipes.length >= limits.recipes}
                onClick={() => onAdd(i)}
              >
                <Plus size={13} />
              </button>
              <button
                type="button"
                className="tiny-btn owned-btn"
                title={locale('ui_rename_category')}
                onClick={() => setDialog({ kind: 'renameCategory', index: i })}
              >
                <Pencil size={13} />
              </button>
              <button
                type="button"
                className="tiny-btn owned-btn"
                title={locale('ui_delete_category')}
                onClick={() => setDialog({ kind: 'deleteCategory', index: i })}
              >
                <Trash2 size={13} />
              </button>
            </div>
            {c.recipes.length === 0 ? (
              <div className="craft-none">{locale('ui_no_recipes')}</div>
            ) : (
              c.recipes.map((r) => (
                <button
                  key={r.item}
                  type="button"
                  className={cls('plist-row', r.item === active && 'is-active')}
                  onClick={() => onOpen(r.item)}
                >
                  <Thumb src={itemImage(r.item)} icon={Package} />
                  <span className="plist-main">
                    <span className="plist-name">{labels.get(r.item) ?? r.item}</span>
                    <span className="plist-sub mono">{r.item}</span>
                  </span>
                  {r.blueprint && (
                    <span className="craft-blueprint" title={locale('ui_needs_x', labels.get(r.blueprint) ?? r.blueprint)}>
                      <ScrollText size={14} />
                    </span>
                  )}
                  <span className="plist-ping">
                    {locale('ui_recipe_summary', r.count.toLocaleString(), r.duration.toLocaleString())}
                    {r.cooldown &&
                      ` · ${locale('ui_recipe_cooldown', r.cooldown.limit.toLocaleString(), r.cooldown.hours)}`}
                    {levelConfig.enabled && r.level && ` · ${locale('ui_level_short', r.level)}`}
                  </span>
                </button>
              ))
            )}
          </div>
        ))}
      </div>
      <div className="craft-type-foot">
        <Button
          size="sm"
          variant="ghost"
          icon={FolderPlus}
          disabled={type.categories.length >= limits.categories}
          onClick={() => setDialog({ kind: 'addCategory' })}
        >
          {locale('ui_add_category')}
        </Button>
      </div>
      {dialog && renderDialog(dialog)}
    </Card>
  );
}

function Editor({
  type,
  original,
  saved,
  draft,
  onDraft,
  onDiscard,
  onSave,
  onDelete,
}: {
  type: CraftingType;
  original: Located | null;
  saved: Draft;
  draft: Draft;
  onDraft(draft: Draft): void;
  onDiscard(): void;
  onSave(draft: Draft): Promise<boolean>;
  onDelete(item: string): Promise<boolean>;
}) {
  const items = useItems();
  const options = useMemo(() => (items ?? []).map(itemOption), [items]);
  const labels = useMemo(() => new Map((items ?? []).map((i) => [i.name, i.label])), [items]);
  const known = useMemo(() => (items ? new Set(items.map((i) => i.name)) : null), [items]);
  const [pick, setPick] = useState<string | null>(null);
  const [amount, setAmount] = useState(1);
  const [busy, setBusy] = useState(false);
  const [confirming, setConfirming] = useState(false);

  const isNew = original === null;
  const dirty = !same(draft, saved);
  const target = draft.category ?? original?.category ?? null;
  const issue = problem({ draft, type, original, target, known });
  const update = (patch: Partial<Draft>) => onDraft({ ...draft, ...patch });
  const setIngredients = (ingredients: CraftingIngredient[]) => update({ ingredients });

  const addIngredient = () => {
    if (!pick || amount < 1) return;

    setIngredients(
      draft.ingredients.some((i) => i.item === pick)
        ? draft.ingredients.map((i) => (i.item === pick ? { ...i, count: Math.min(limits.ingredientCount, i.count + amount) } : i))
        : [...draft.ingredients, { item: pick, count: amount }],
    );

    setPick(null);
    setAmount(1);
  };

  const save = async () => {
    setBusy(true);
    await onSave(draft);
    setBusy(false);
  };

  return (
    <Card
      title={isNew ? locale('ui_new_recipe') : locale('ui_edit_recipe')}
      actions={dirty && <Pill tone="warn">{locale('ui_unsaved')}</Pill>}
      bodyClassName="craft-editor"
    >
      <Field label={locale('ui_result_item')}>
        <Combobox
          size="sm"
          icon={Package}
          value={draft.item}
          options={options}
          onChange={(item) => update({ item })}
          loading={items === null}
          placeholder={locale('ui_pick_result')}
        />
      </Field>
      <div className="form-3">
        <Field label={locale('ui_amount_produced')}>
          <input
            className="input input--sm"
            inputMode="numeric"
            value={draft.count || ''}
            onChange={(e) => update({ count: digits(e.target.value, limits.recipeCount) })}
          />
        </Field>
        <Field label={locale('ui_craft_time')}>
          <input
            className="input input--sm"
            inputMode="numeric"
            value={draft.duration || ''}
            onChange={(e) => update({ duration: digits(e.target.value, limits.duration) })}
          />
        </Field>
        <Field label={locale('ui_category_label')}>
          <Select
            size="sm"
            value={target}
            options={type.categories.map((c, i) => ({ value: i, label: c.label }))}
            onChange={(i) => update({ category: i === original?.category ? null : i })}
            placeholder={locale('ui_pick_category')}
          />
        </Field>
      </div>
      <div className="form-2">
        <Field label={locale('ui_cooldown_limit')}>
          <input
            className="input input--sm"
            inputMode="numeric"
            placeholder={locale('ui_no_limit')}
            value={draft.limit || ''}
            onChange={(e) => update({ limit: digits(e.target.value, limits.cooldownLimit) })}
          />
        </Field>
        <Field label={locale('ui_cooldown_hours')}>
          <input
            className="input input--sm"
            inputMode="numeric"
            placeholder={locale('ui_none')}
            value={draft.hours || ''}
            onChange={(e) => update({ hours: digits(e.target.value, limits.cooldownHours) })}
          />
        </Field>
      </div>
      {levelConfig.enabled && (
        <div className="form-2">
          <Field label={locale('ui_xp_per_craft')}>
            <input
              className="input input--sm"
              inputMode="numeric"
              placeholder={locale('ui_xp_default', levelConfig.defaultXp)}
              value={draft.xp ?? ''}
              onChange={(e) => update({ xp: /\d/.test(e.target.value) ? digits(e.target.value, limits.xp) : null })}
            />
          </Field>
          <Field label={locale('ui_required_level')}>
            <input
              className="input input--sm"
              inputMode="numeric"
              placeholder={locale('ui_none')}
              value={draft.level || ''}
              onChange={(e) => update({ level: digits(e.target.value, limits.level) })}
            />
          </Field>
        </div>
      )}
      <Field label={locale('ui_blueprint')}>
        <div className="craft-pick">
          <Combobox
            size="sm"
            icon={ScrollText}
            value={draft.blueprint}
            options={options}
            onChange={(blueprint) => update({ blueprint })}
            loading={items === null}
            placeholder={locale('ui_none_needed')}
          />
          {draft.blueprint && (
            <button
              type="button"
              className="tiny-btn"
              title={locale('ui_no_blueprint')}
              aria-label={locale('ui_no_blueprint')}
              onClick={() => update({ blueprint: null })}
            >
              <X size={13} />
            </button>
          )}
        </div>
      </Field>
      <Field label={locale('ui_ingredients_n', draft.ingredients.length, limits.ingredients)}>
        <div className="comp-add">
          <Combobox
            size="sm"
            icon={Package}
            value={pick}
            options={options}
            onChange={setPick}
            loading={items === null}
            placeholder={locale('ui_pick_ingredient')}
          />
          <input
            className="input input--sm count-input craft-count"
            inputMode="numeric"
            title={locale('ui_amount')}
            value={amount || ''}
            onChange={(e) => setAmount(digits(e.target.value, limits.ingredientCount))}
          />
          <Button
            size="sm"
            icon={Plus}
            disabled={!pick || amount < 1 || draft.ingredients.length >= limits.ingredients}
            onClick={addIngredient}
          >
            {locale('ui_add')}
          </Button>
        </div>
      </Field>
      {draft.ingredients.length === 0 ? (
        <Empty icon={Package} className="comp-items-empty">
          {locale('ui_no_ingredients')}
        </Empty>
      ) : (
        <div className="comp-items">
          {draft.ingredients.map((i) => (
            <div key={i.item} className="comp-item">
              <Thumb src={itemImage(i.item)} icon={Package} />
              <div className="comp-item-main">
                <span className="comp-item-label">{labels.get(i.item) ?? i.item}</span>
                <span className="comp-item-sub mono">{i.item}</span>
              </div>
              <input
                className="input input--sm count-input craft-count"
                inputMode="numeric"
                title={locale('ui_amount')}
                value={i.count || ''}
                onChange={(e) =>
                  setIngredients(
                    draft.ingredients.map((x) =>
                      x.item === i.item ? { ...x, count: digits(e.target.value, limits.ingredientCount) } : x,
                    ),
                  )
                }
              />
              <ConfirmButton
                size="sm"
                variant="ghost"
                icon={Trash2}
                confirmText={locale('ui_remove_confirm')}
                aria-label={locale('ui_remove_x', i.item)}
                onConfirm={() => setIngredients(draft.ingredients.filter((x) => x.item !== i.item))}
              />
            </div>
          ))}
        </div>
      )}
      {issue && <p className="hint">{issue}</p>}
      {!issue && draft.ingredients.length === 0 && (
        <p className="hint warn-text">{locale('ui_free_warning')}</p>
      )}
      {!issue && draft.limit > 0 && (
        <p className="hint">
          {plural(draft.limit, 'ui_cooldown_hint', draft.hours, draft.hours)}
        </p>
      )}
      <div className="craft-foot">
        {original && (
          <Button variant="ghost" icon={Trash2} onClick={() => setConfirming(true)}>
            {locale('ui_delete_recipe')}
          </Button>
        )}
        <span className="grow" />
        {dirty && (
          <Button variant="ghost" icon={RotateCcw} onClick={onDiscard}>
            {locale('ui_discard')}
          </Button>
        )}
        <Button
          variant="primary"
          icon={Check}
          disabled={issue !== null || (!isNew && !dirty)}
          loading={busy}
          onClick={save}
        >
          {isNew ? locale('ui_create_recipe') : locale('ui_save_recipe')}
        </Button>
      </div>
      {confirming && original && (
        <ConfirmDialog
          title={locale('ui_delete_recipe_x', labels.get(original.recipe.item) ?? original.recipe.item)}
          confirm={locale('ui_delete_recipe')}
          onConfirm={() => onDelete(original.recipe.item)}
          onClose={() => setConfirming(false)}
        >
          {locale('ui_delete_recipe_body', type.label)}
        </ConfirmDialog>
      )}
    </Card>
  );
}

function useMyCoords(active: boolean) {
  const [me, setMe] = useState<Vec3 | null>(null);

  useEffect(() => {
    if (!active) return;

    let live = true;

    const tick = () =>
      nui<Vec3>('myCoords')
        .then((c) => live && c && setMe(c))
        .catch(() => undefined);

    tick();

    const timer = setInterval(tick, COORDS_MS);

    return () => {
      live = false;
      clearInterval(timer);
    };
  }, [active]);

  return me;
}

function BenchGroup({
  title,
  benches,
  place,
  options,
  mutate,
}: {
  title: string;
  benches: CraftingBench[];
  place?: CraftingType;
  options: BenchOptions;
  mutate: Mutate;
}) {
  const { run } = useTablet();
  const me = useMyCoords(benches.length > 0);
  const [dialog, setDialog] = useState<BenchDialog | null>(null);
  const gangLabels = useMemo(() => new Map(options.gangs.map((g) => [g.value, g.label])), [options.gangs]);
  const typeLabels = useMemo(() => new Map(options.types.map((t) => [t.value, t.label])), [options.types]);

  const rows = benches
    .map((bench) => ({ bench, metres: me && distanceBetween(me, bench.coords) }))
    .sort((a, b) => (a.metres ?? 0) - (b.metres ?? 0));

  const close = () => setDialog(null);

  return (
    <div className="craft-cat">
      <div className="craft-cat-head">
        <span className="craft-cat-name">{title}</span>
        <span className="craft-cat-count">{benches.length}</span>
        {place && (
          <button
            type="button"
            className="tiny-btn owned-btn"
            title={locale('ui_place_a_bench')}
            onClick={() => setDialog({ kind: 'place' })}
          >
            <Plus size={13} />
          </button>
        )}
      </div>
      {rows.length === 0 ? (
        <div className="craft-none">{locale('ui_no_benches')}</div>
      ) : (
        rows.map(({ bench, metres }) => (
          <div key={bench.id} className="craft-bench">
            <span className="craft-id">#{bench.id}</span>
            <span className="craft-bench-main">
              {!place && <Pill tone="danger">{bench.type || locale('ui_no_type')}</Pill>}
              {bench.gangs.length === 0 ? (
                <span className="muted">{locale('ui_anyone')}</span>
              ) : (
                bench.gangs.map((g) => (
                  <Pill key={g} tone="muted">
                    {gangLabels.get(g) ?? g}
                  </Pill>
                ))
              )}
            </span>
            <span className="craft-distance">{metres === null ? '…' : distanceText(metres)}</span>
            <button
              type="button"
              className="tiny-btn owned-btn"
              title={locale('ui_teleport')}
              onClick={() => run('teleport', { id: bench.id })}
            >
              <MapPin size={13} />
            </button>
            <button
              type="button"
              className="tiny-btn owned-btn"
              title={locale('ui_edit_bench')}
              onClick={() => setDialog({ kind: 'edit', bench })}
            >
              <Pencil size={13} />
            </button>
            <button
              type="button"
              className="tiny-btn owned-btn"
              title={locale('ui_remove_bench')}
              onClick={() => setDialog({ kind: 'remove', bench })}
            >
              <Trash2 size={13} />
            </button>
          </div>
        ))
      )}
      {dialog?.kind === 'place' && place && (
        <PlaceDialog type={place} gangs={options.gangs} models={options.models} onClose={close} />
      )}
      {dialog?.kind === 'edit' && (
        <EditBench
          bench={dialog.bench}
          types={options.types}
          gangs={options.gangs}
          models={options.models}
          onSave={(type, gangs, model) => mutate('updateTable', { id: dialog.bench.id, type, gangs, model })}
          onClose={close}
        />
      )}
      {dialog?.kind === 'remove' && (
        <ConfirmDialog
          title={locale('ui_remove_bench_x', dialog.bench.id)}
          confirm={locale('ui_remove_bench')}
          onConfirm={() => mutate('deleteTable', { id: dialog.bench.id })}
          onClose={close}
        >
          {locale('ui_remove_bench_body', typeLabels.get(dialog.bench.type) ?? dialog.bench.type)}
        </ConfirmDialog>
      )}
    </div>
  );
}

function Levels() {
  const { query } = useTablet();
  const [results, setResults] = useState<LevelEntry[] | null>(null);
  const [picked, setPicked] = useState<LevelEntry | null>(null);
  const [term, setTerm] = useState('');
  const [busy, setBusy] = useState(false);
  const ready = term.trim().length >= SEARCH_MIN_LENGTH;

  const search = async () => {
    if (!ready || busy) return;

    setBusy(true);

    const found = await query<LevelEntry[]>('searchLevels', { term: term.trim() });

    setBusy(false);

    if (found !== null || results === null) {
      setResults(arr<LevelEntry>(found));
    }
  };

  const save = async (level: number) => {
    if (!picked) return false;

    const updated = await query<LevelEntry>('setLevel', { citizenid: picked.citizenid, level });

    if (!updated) return false;

    setPicked(updated);
    setResults((list) => list && list.map((p) => (p.citizenid === updated.citizenid ? updated : p)));

    return true;
  };

  return (
    <>
      <Card title={locale('ui_find_player')} bodyClassName="flush craft-levels">
        <div className="craft-level-search">
          <input
            autoFocus
            className="input input--sm"
            placeholder={locale('ui_search_players')}
            maxLength={limits.key}
            value={term}
            onChange={(e) => setTerm(e.target.value)}
            onKeyDown={(e) => e.key === 'Enter' && search()}
          />
          <Button size="sm" variant="ghost" icon={Search} disabled={!ready} loading={busy} onClick={search}>
            {locale('ui_search_go')}
          </Button>
        </div>
        <div className="scroll grow">
          {results === null && <Empty icon={Gauge}>{locale('ui_search_hint')}</Empty>}
          {results?.length === 0 && <Empty icon={Gauge}>{locale('ui_no_results')}</Empty>}
          {results?.map((p) => (
            <button
              key={p.citizenid}
              type="button"
              className={cls('plist-row', p.citizenid === picked?.citizenid && 'is-active')}
              onClick={() => setPicked(p)}
            >
              <span className="plist-main">
                <span className="plist-name">{p.name}</span>
                <span className="plist-sub mono">{p.citizenid}</span>
              </span>
              <span className="plist-ping">{locale('ui_level_n', p.level)}</span>
            </button>
          ))}
        </div>
      </Card>
      {picked ? (
        <LevelEditor key={`${picked.citizenid}:${picked.level}`} player={picked} onSave={save} />
      ) : (
        <Card>
          <Empty icon={Gauge} className="fill">
            {locale('ui_pick_player')}
          </Empty>
        </Card>
      )}
    </>
  );
}

function LevelEditor({ player, onSave }: { player: LevelEntry; onSave(level: number): Promise<boolean> }) {
  const [level, setLevel] = useState(player.level);
  const [busy, setBusy] = useState(false);
  const valid = level >= 1 && level <= levelConfig.maxLevel;
  const progress = locale('ui_xp_progress', player.xp.toLocaleString(), player.next.toLocaleString());

  const save = async () => {
    if (!valid || busy) return;

    setBusy(true);
    await onSave(level);
    setBusy(false);
  };

  return (
    <Card title={player.name} bodyClassName="craft-editor">
      <div className="form-2">
        <Field label={locale('ui_citizenid')}>
          <input className="input input--sm mono" readOnly value={player.citizenid} />
        </Field>
        <Field label={locale('ui_current_level')}>
          <input
            className="input input--sm"
            readOnly
            value={`${player.level} · ${player.next > 0 ? progress : locale('ui_max_level')}`}
          />
        </Field>
      </div>
      <Field label={locale('ui_new_level', levelConfig.maxLevel)}>
        <input
          className={cls('input', !valid && 'is-invalid')}
          inputMode="numeric"
          value={level || ''}
          onChange={(e) => setLevel(digits(e.target.value, limits.level))}
          onKeyDown={(e) => e.key === 'Enter' && save()}
        />
      </Field>
      <p className="hint">{locale('ui_level_hint')}</p>
      <span className="grow" />
      <div className="craft-foot">
        <span className="grow" />
        <Button variant="primary" icon={Check} disabled={!valid} loading={busy} onClick={save}>
          {locale('ui_set_level')}
        </Button>
      </div>
    </Card>
  );
}

function PlaceDialog({
  type,
  gangs,
  models,
  onClose,
}: {
  type: CraftingType;
  gangs: Option<string>[];
  models: Option<string>[];
  onClose(): void;
}) {
  const { run } = useTablet();
  const [locked, setLocked] = useState<string[]>([]);
  const [model, setModel] = useState<string | null>(models[0]?.value ?? null);
  const [busy, setBusy] = useState(false);

  const place = async () => {
    setBusy(true);

    const ok = await run('place', { type: type.name, gangs: locked, ...(model ? { model } : {}) });

    setBusy(false);

    if (ok) {
      onClose();
    }
  };

  return (
    <Modal
      title={locale('ui_place_x', type.label)}
      onClose={onClose}
      foot={
        <>
          <Button variant="ghost" onClick={onClose}>
            {locale('ui_cancel')}
          </Button>
          <Button variant="primary" icon={Hammer} loading={busy} onClick={place}>
            {locale('ui_place_bench')}
          </Button>
        </>
      }
    >
      {models.length > 1 && (
        <Field label={locale('ui_bench_prop')}>
          <Select value={model} options={models} onChange={setModel} />
        </Field>
      )}
      <Field label={locale('ui_gang_lock')}>
        <MultiSelect value={locked} options={gangs} onChange={setLocked} placeholder={locale('ui_anyone_can_use')} />
      </Field>
      <p className="hint">
        {locale('ui_place_hint')}
      </p>
    </Modal>
  );
}

function EditBench({
  bench,
  types,
  gangs,
  models,
  onSave,
  onClose,
}: {
  bench: CraftingBench;
  types: Option<string>[];
  gangs: Option<string>[];
  models: Option<string>[];
  onSave(type: string, gangs: string[], model?: string): Promise<boolean>;
  onClose(): void;
}) {
  const current = bench.model ?? models[0]?.value ?? null;
  const [type, setType] = useState(bench.type);
  const [locked, setLocked] = useState(bench.gangs);
  const [model, setModel] = useState(current);
  const [busy, setBusy] = useState(false);

  const options = [
    ...gangs,
    ...bench.gangs.filter((g) => !gangs.some((o) => o.value === g)).map((g) => ({ value: g, label: g })),
  ];

  const valid = types.some((t) => t.value === type);

  const modelOptions =
    current && !models.some((m) => m.value === current) ? [...models, { value: current, label: current }] : models;

  const modelChanged = model !== current && models.some((m) => m.value === model);

  const changed =
    modelChanged ||
    type !== bench.type ||
    locked.length !== bench.gangs.length ||
    locked.some((g) => !bench.gangs.includes(g));

  const save = async () => {
    setBusy(true);

    const ok = await onSave(type, locked, modelChanged && model ? model : undefined);

    setBusy(false);

    if (ok) {
      onClose();
    }
  };

  return (
    <Modal
      title={locale('ui_edit_bench_x', bench.id)}
      onClose={onClose}
      foot={
        <>
          <Button variant="ghost" onClick={onClose}>
            {locale('ui_cancel')}
          </Button>
          <Button variant="primary" icon={Check} disabled={!valid || !changed} loading={busy} onClick={save}>
            {locale('ui_save')}
          </Button>
        </>
      }
    >
      <Field label={locale('ui_bench_type')}>
        <Select value={type} options={types} onChange={setType} placeholder={locale('ui_pick_type')} />
      </Field>
      {modelOptions.length > 1 && (
        <Field label={locale('ui_bench_prop')}>
          <Select value={model} options={modelOptions} onChange={setModel} />
        </Field>
      )}
      <Field label={locale('ui_gang_lock')}>
        <MultiSelect value={locked} options={options} onChange={setLocked} placeholder={locale('ui_anyone')} />
      </Field>
    </Modal>
  );
}

function LabelDialog({
  title,
  initial = '',
  submit,
  onSubmit,
  onClose,
}: {
  title: string;
  initial?: string;
  submit: string;
  onSubmit(label: string): Promise<boolean>;
  onClose(): void;
}) {
  const [label, setLabel] = useState(initial);
  const [busy, setBusy] = useState(false);
  const clean = label.trim();
  const ready = clean !== '' && clean !== initial;

  const go = async () => {
    if (!ready || busy) return;

    setBusy(true);

    const ok = await onSubmit(clean);

    setBusy(false);

    if (ok) {
      onClose();
    }
  };

  return (
    <Modal
      title={title}
      onClose={onClose}
      foot={
        <>
          <Button variant="ghost" onClick={onClose}>
            {locale('ui_cancel')}
          </Button>
          <Button variant="primary" icon={Check} disabled={!ready} loading={busy} onClick={go}>
            {submit}
          </Button>
        </>
      }
    >
      <Field label={locale('ui_label')}>
        <input
          autoFocus
          className="input"
          maxLength={limits.label}
          value={label}
          onChange={(e) => setLabel(e.target.value)}
          onKeyDown={(e) => e.key === 'Enter' && go()}
        />
      </Field>
    </Modal>
  );
}

function NewTypeDialog({
  taken,
  onCreate,
  onClose,
}: {
  taken(name: string): boolean;
  onCreate(name: string, label: string): Promise<boolean>;
  onClose(): void;
}) {
  const [name, setName] = useState('');
  const [label, setLabel] = useState('');
  const [busy, setBusy] = useState(false);
  const clash = taken(name);
  const ready = name !== '' && !clash && label.trim() !== '';

  const go = async () => {
    if (!ready || busy) return;

    setBusy(true);

    const ok = await onCreate(name, label.trim());

    setBusy(false);

    if (ok) {
      onClose();
    }
  };

  return (
    <Modal
      title={locale('ui_new_bench_type')}
      onClose={onClose}
      foot={
        <>
          <Button variant="ghost" onClick={onClose}>
            {locale('ui_cancel')}
          </Button>
          <Button variant="primary" icon={Check} disabled={!ready} loading={busy} onClick={go}>
            {locale('ui_create_type')}
          </Button>
        </>
      }
    >
      <Field label={locale('ui_key')}>
        <input
          autoFocus
          className={cls('input mono', clash && 'is-invalid')}
          placeholder={locale('ui_key_example')}
          maxLength={limits.key}
          value={name}
          onChange={(e) =>
            setName(
              e.target.value
                .toLowerCase()
                .replace(/[^a-z0-9_]/g, '')
                .slice(0, limits.key),
            )
          }
          onKeyDown={(e) => e.key === 'Enter' && go()}
        />
      </Field>
      <Field label={locale('ui_label')}>
        <input
          className="input"
          placeholder={locale('ui_label_example')}
          maxLength={limits.label}
          value={label}
          onChange={(e) => setLabel(e.target.value)}
          onKeyDown={(e) => e.key === 'Enter' && go()}
        />
      </Field>
      <p className="hint">
        {clash
          ? locale('ui_key_taken') : locale('ui_key_hint')}
      </p>
    </Modal>
  );
}

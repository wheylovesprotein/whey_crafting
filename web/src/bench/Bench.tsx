import { useCallback, useEffect, useMemo, useState, type SyntheticEvent } from 'react';
import { locale } from '../locale';
import { itemImage, nui } from '../nui';
import { arr, cls } from '../util';
import { renderBanners, type BannerType } from './banner';

interface BenchItem {
  name: string;
  label: string;
  weight: number;
  image: string;
  count: number;
}

interface BenchRecipe extends BenchItem {
  duration: number;
  ingredients: BenchItem[];
  blueprint?: BenchItem;
  xp?: number;
  level?: number;
}

interface BenchCategory {
  label: string;
  recipes: BenchRecipe[];
}

interface QueueView {
  id: number;
  item: string;
  count: number;
  remaining: number;
}

interface CooldownView {
  wait?: number;
  limit?: number;
  left?: number;
}

interface LevelView {
  level: number;
  xp: number;
  next: number;
}

interface ActionResult {
  queue: unknown;
  level?: LevelView | null;
  cooldowns?: Record<string, CooldownView>;
  counts?: Record<string, number>;
}

interface OpenMessage extends ActionResult {
  action: 'open';
  title: string;
  categories: unknown;
  maxWeight: number;
  queueSize: number;
}

interface QueueEntry extends QueueView {
  endsAt: number;
}

interface Cooldown {
  left?: number;
  limit?: number;
  endsAt: number;
}

interface Menu {
  title: string;
  categories: BenchCategory[];
  recipes: Map<string, BenchRecipe>;
  maxWeight: number;
  queueSize: number;
}

const MAX_UNWEIGHTED_AMOUNT = 9999;

const hideBroken = (event: SyntheticEvent<HTMLImageElement>) => {
  event.currentTarget.style.visibility = 'hidden';
};

function formatTime(seconds: number) {
  const total = Math.max(0, Math.ceil(seconds));
  const minutes = Math.floor(total / 60);

  return `${String(minutes).padStart(2, '0')}:${String(total % 60).padStart(2, '0')}`;
}

function formatWait(seconds: number) {
  const total = Math.max(0, Math.ceil(seconds));
  const hours = Math.floor(total / 3600);

  if (hours >= 24) {
    return locale('time_days_hours', Math.floor(hours / 24), hours % 24);
  }

  if (hours > 0) {
    const minutes = Math.floor((total % 3600) / 60);

    return `${hours}:${String(minutes).padStart(2, '0')}:${String(total % 60).padStart(2, '0')}`;
  }

  return formatTime(total);
}

function toCooldowns(views: Record<string, CooldownView> | undefined, now: number) {
  const cooldowns: Record<string, Cooldown> = {};

  for (const [name, view] of Object.entries(views ?? {})) {
    cooldowns[name] = {
      left: view.left,
      limit: view.limit,
      endsAt: view.wait && view.wait > 0 ? now + view.wait * 1000 : 0,
    };
  }

  return cooldowns;
}

const toQueue = (queue: unknown, now: number): QueueEntry[] =>
  arr<QueueView>(queue).map((entry) => ({ ...entry, endsAt: now + entry.remaining }));

function toMenu(message: OpenMessage): Menu {
  const categories = arr<BenchCategory>(message.categories).map((category) => ({
    label: category.label,
    recipes: arr<BenchRecipe>(category.recipes).map((recipe) => ({
      ...recipe,
      ingredients: arr<BenchItem>(recipe.ingredients),
    })),
  }));

  const recipes = new Map<string, BenchRecipe>();

  for (const category of categories) {
    for (const recipe of category.recipes) {
      recipes.set(recipe.name, recipe);
    }
  }

  return {
    title: message.title,
    categories,
    recipes,
    maxWeight: message.maxWeight,
    queueSize: message.queueSize,
  };
}

function Thumb({ src, large }: { src: string; large?: boolean }) {
  return (
    <span className={large ? 'thumb thumb--lg' : 'thumb'}>
      <img src={src} alt="" onError={hideBroken} />
    </span>
  );
}

function Need({ item, needed, owned }: { item: BenchItem; needed: number; owned: number }) {
  const short = owned < needed;

  return (
    <div className={short ? 'need is-short' : 'need'} title={locale('ui_you_have', owned, needed)}>
      <Thumb src={item.image} />
      <span className="need-name">{item.label}</span>
      <span className="need-count">
        <b>{owned.toLocaleString()}</b> / {needed.toLocaleString()}
      </span>
      <span className="need-bar">
        <i style={{ width: `${Math.min(100, (owned / needed) * 100)}%` }} />
      </span>
    </div>
  );
}

function Quantity({ amount, disabled, onCommit }: { amount: number; disabled: boolean; onCommit(amount: number): void }) {
  return (
    <input
      key={amount}
      className="qty"
      type="number"
      min="1"
      defaultValue={amount}
      disabled={disabled}
      onBlur={(event) => onCommit(Math.floor(Number(event.currentTarget.value)) || 1)}
      onKeyDown={(event) => {
        if (event.key === 'Enter') {
          event.currentTarget.blur();
        }
      }}
    />
  );
}

function Slot({
  entry,
  recipe,
  now,
  busy,
  onCollect,
  onCancel,
}: {
  entry: QueueEntry;
  recipe: BenchRecipe | undefined;
  now: number;
  busy: boolean;
  onCollect(): void;
  onCancel(): void;
}) {
  const [armed, setArmed] = useState(false);
  const left = (entry.endsAt - now) / 1000;
  const ready = left <= 0;

  return (
    <div className="slot-wrap">
      <button
        className={ready ? 'slot is-ready' : 'slot is-busy'}
        title={recipe ? recipe.label : entry.item}
        disabled={!ready || busy}
        onClick={onCollect}
      >
        <img src={recipe ? recipe.image : itemImage(entry.item)} alt="" onError={hideBroken} />
        <span className="slot-count">x{entry.count}</span>
        <span className="slot-status">{ready ? '✓' : formatTime(left)}</span>
      </button>
      <button
        className={armed ? 'slot-cancel is-armed' : 'slot-cancel'}
        title={locale('ui_cancel_order')}
        hidden={ready}
        disabled={busy}
        onMouseLeave={() => setArmed(false)}
        onClick={() => {
          if (armed) {
            onCancel();
          } else {
            setArmed(true);
          }
        }}
      >
        {armed ? locale('ui_cancel_confirm') : '✕'}
      </button>
    </div>
  );
}

export default function Bench() {
  const [menu, setMenu] = useState<Menu | null>(null);
  const [open, setOpen] = useState(false);
  const [counts, setCounts] = useState<Record<string, number>>({});
  const [queue, setQueue] = useState<QueueEntry[]>([]);
  const [cooldowns, setCooldowns] = useState<Record<string, Cooldown>>({});
  const [level, setLevel] = useState<LevelView | null>(null);
  const [selected, setSelected] = useState<string | null>(null);
  const [amount, setAmount] = useState(1);
  const [busy, setBusy] = useState(false);
  const [collapsed, setCollapsed] = useState<Set<number>>(new Set());
  const [now, setNow] = useState(() => performance.now());

  const apply = useCallback((result: ActionResult | null) => {
    if (!result) return;

    const at = performance.now();

    if (result.counts) {
      setCounts(result.counts);
    }

    setCooldowns(toCooldowns(result.cooldowns, at));
    setLevel(result.level ?? null);
    setQueue(toQueue(result.queue, at));
    setNow(at);
  }, []);

  const close = useCallback(() => {
    setOpen(false);
    nui('close');
  }, []);

  useEffect(() => {
    const onMessage = (event: MessageEvent) => {
      const data = event.data;

      if (data?.action === 'open') {
        const message = data as OpenMessage;
        const next = toMenu(message);

        setMenu(next);
        setSelected((current) =>
          current && next.recipes.has(current) ? current : (next.categories[0]?.recipes[0]?.name ?? null),
        );
        setCounts(message.counts ?? {});
        setAmount(1);
        setBusy(false);
        apply(message);
        setOpen(true);
      } else if (data?.action === 'close') {
        setOpen(false);
      } else if (data?.action === 'banners') {
        renderBanners(arr<BannerType>(data.types));
      }
    };

    window.addEventListener('message', onMessage);
    nui('mounted');

    return () => window.removeEventListener('message', onMessage);
  }, [apply]);

  useEffect(() => {
    if (!open) return;

    const timer = setInterval(() => setNow(performance.now()), 1000);

    const onKey = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        close();
      }
    };

    window.addEventListener('keydown', onKey);

    return () => {
      clearInterval(timer);
      window.removeEventListener('keydown', onKey);
    };
  }, [open, close]);

  const recipe = useMemo(() => (selected && menu ? menu.recipes.get(selected) : undefined), [menu, selected]);
  const owned = (name: string) => counts[name] ?? 0;
  const isLocked = (target: BenchRecipe) => level !== null && (target.level ?? 1) > level.level;

  const cooldownWait = (name: string) => {
    const cooldown = cooldowns[name];

    return cooldown?.endsAt ? Math.max(0, (cooldown.endsAt - now) / 1000) : 0;
  };

  const craftsLeft = (name: string) => {
    const cooldown = cooldowns[name];

    if (!cooldown) return Infinity;
    if (cooldown.endsAt) return cooldownWait(name) > 0 ? 0 : (cooldown.limit ?? Infinity);

    return cooldown.left ?? Infinity;
  };

  const recipeMax = (target: BenchRecipe) => {
    const perCraft = (target.weight ?? 0) * (target.count ?? 1);
    const left = craftsLeft(target.name);

    if (perCraft > 0 && menu) {
      return Math.min(Math.floor(menu.maxWeight / perCraft), left);
    }

    const affordable = target.ingredients.map((item) => Math.floor(owned(item.name) / item.count));

    return Math.min(Math.max(1, Math.min(...affordable, MAX_UNWEIGHTED_AMOUNT)), left);
  };

  const act = async (endpoint: string, payload: Record<string, unknown>) => {
    if (busy) return;

    setBusy(true);

    const result = await nui<ActionResult | false>(endpoint, payload);

    setBusy(false);
    apply(result || null);
  };

  const select = (name: string) => {
    setSelected(name);
    setAmount(1);
  };

  const toggle = (index: number) =>
    setCollapsed((current) => {
      const next = new Set(current);

      if (!next.delete(index)) {
        next.add(index);
      }

      return next;
    });

  const renderDetail = () => {
    if (!recipe || !menu) {
      return <p className="bench-empty">{locale('ui_no_recipes_available')}</p>;
    }

    const wait = cooldownWait(recipe.name);
    const onCooldown = wait > 0;
    const queueFull = queue.length >= menu.queueSize;
    const max = recipeMax(recipe);
    const tooHeavy = max < 1;
    const hasBlueprint = !recipe.blueprint || owned(recipe.blueprint.name) >= 1;
    const hasMaterials = recipe.ingredients.every((item) => owned(item.name) >= item.count * amount);
    const locked = isLocked(recipe);

    const label = locked
      ? locale('ui_requires_level', recipe.level ?? 1)
      : onCooldown
        ? locale('ui_on_cooldown')
        : queueFull
          ? locale('ui_queue_full')
          : tooHeavy
            ? locale('ui_too_heavy')
            : locale('ui_craft');

    const commit = (next: number) => setAmount(Math.min(max, Math.max(1, next)));

    return (
      <>
        <div className="recipe-head">
          <Thumb src={recipe.image} large />
          <div className="recipe-title">
            <h2>{recipe.label}</h2>
            <p>{locale('ui_item_count', (recipe.count * amount).toLocaleString(), recipe.label)}</p>
          </div>
          {level && (recipe.xp ?? 0) > 0 && (
            <span className="time-pill xp-pill">
              {locale('ui_xp_gain', ((recipe.xp ?? 0) * amount).toLocaleString())}
            </span>
          )}
          <span className="time-pill">
            <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round">
              <circle cx="8" cy="8" r="6.2" />
              <path d="M8 4.6V8l2.3 1.5" />
            </svg>
            {formatTime(recipe.duration * amount)}
          </span>
        </div>
        <div className="needs">
          <div className="needs-label">{locale('ui_ingredients')}</div>
          {recipe.ingredients.map((item) => (
            <Need key={item.name} item={item} needed={item.count * amount} owned={owned(item.name)} />
          ))}
          {recipe.blueprint && (
            <>
              <div className="needs-label">{locale('ui_blueprints')}</div>
              <Need item={recipe.blueprint} needed={1} owned={owned(recipe.blueprint.name)} />
            </>
          )}
        </div>
        <div className="craft-bar">
          <div className="stepper">
            <button disabled={onCooldown || amount <= 1} onClick={() => commit(amount - 1)}>
              −
            </button>
            <Quantity amount={amount} disabled={onCooldown} onCommit={commit} />
            <button disabled={onCooldown || amount >= max} onClick={() => commit(amount + 1)}>
              +
            </button>
          </div>
          {onCooldown && <span className="wait">{locale('ui_craft_again_in', formatWait(wait))}</span>}
          <button
            className="craft-btn"
            disabled={busy || locked || onCooldown || queueFull || tooHeavy || !hasBlueprint || !hasMaterials}
            onClick={() => act('craft', { recipe: recipe.name, amount })}
          >
            {label}
          </button>
        </div>
      </>
    );
  };

  const slots = Math.max(menu?.queueSize ?? 0, queue.length);

  return (
    <div id="bench" className={open ? 'open' : undefined}>
      <div className="bench-panel">
        <header className="bench-head">
          <div className="bench-title">
            <h1>{locale('ui_crafting')}</h1>
            <span className="bench-type">{menu?.title}</span>
          </div>
          <div className="bench-tools">
            {level && (
              <div className="bench-level">
                <span className="level-name">{locale('ui_level_n', level.level)}</span>
                <span className="level-bar">
                  <i style={{ width: `${level.next > 0 ? Math.min(100, (level.xp / level.next) * 100) : 100}%` }} />
                </span>
                <span className="level-xp">
                  {level.next > 0
                    ? locale('ui_xp_progress', level.xp.toLocaleString(), level.next.toLocaleString())
                    : locale('ui_max_level')}
                </span>
              </div>
            )}
            <button className="bench-key" onClick={close}>
              {locale('ui_esc')}
            </button>
          </div>
        </header>
        <div className="bench-body">
          <aside className="bench-list">
            {menu?.categories.map((category, index) => (
              <section key={index} className={collapsed.has(index) ? 'group is-collapsed' : 'group'}>
                <button className="group-head" onClick={() => toggle(index)}>
                  <span className="group-name">{category.label}</span>
                  <span className="group-count">{category.recipes.length}</span>
                  <span className="group-chevron" />
                </button>
                <div className="group-items">
                  {category.recipes.map((entry) => (
                    <button
                      key={entry.name}
                      className={cls('row', entry.name === selected && 'is-active', isLocked(entry) && 'is-locked')}
                      onClick={() => select(entry.name)}
                    >
                      <Thumb src={entry.image} />
                      <span className="row-name">{entry.label}</span>
                      {isLocked(entry) && (
                        <span className="row-lock">{locale('ui_level_short', entry.level ?? 1)}</span>
                      )}
                    </button>
                  ))}
                </div>
              </section>
            ))}
          </aside>
          <main className="bench-detail">{renderDetail()}</main>
        </div>
        <footer className="bench-queue">
          <span className="queue-label">
            {locale('ui_queue')}
            <em>
              {queue.length}/{menu?.queueSize ?? 0}
            </em>
          </span>
          <div className="queue-slots">
            {Array.from({ length: slots }, (_, index) => {
              const entry = queue[index];

              if (!entry) {
                return <div key={`empty-${index}`} className="slot" />;
              }

              return (
                <Slot
                  key={entry.id}
                  entry={entry}
                  recipe={menu?.recipes.get(entry.item)}
                  now={now}
                  busy={busy}
                  onCollect={() => act('collect', { id: entry.id })}
                  onCancel={() => act('cancel', { id: entry.id })}
                />
              );
            })}
          </div>
        </footer>
      </div>
    </div>
  );
}

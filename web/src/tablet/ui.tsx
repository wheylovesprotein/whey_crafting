import { Check, ChevronDown, Loader2, Search, Trash2, type LucideIcon } from 'lucide-react';

import {
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
  type ButtonHTMLAttributes,
  type CSSProperties,
  type KeyboardEvent,
  type ReactNode,
} from 'react';

import { createPortal } from 'react-dom';
import { locale } from '../locale';
import { cls } from '../util';

export function IconTile({
  icon: Icon,
  tone = 'accent',
  size = 'md',
}: {
  icon: LucideIcon;
  tone?: 'accent' | 'danger' | 'muted';
  size?: 'sm' | 'md';
}) {
  return (
    <span className={cls('icon-tile', `icon-tile--${tone}`, `icon-tile--${size}`)}>
      <Icon size={size === 'sm' ? 14 : 16} strokeWidth={2.2} />
    </span>
  );
}

export function Card({
  title,
  icon,
  actions,
  className,
  bodyClassName,
  children,
  style,
}: {
  title?: ReactNode;
  icon?: LucideIcon;
  actions?: ReactNode;
  className?: string;
  bodyClassName?: string;
  children?: ReactNode;
  style?: CSSProperties;
}) {
  return (
    <section className={cls('card', className)} style={style}>
      {title !== undefined && (
        <header className="card-head">
          {icon && <IconTile icon={icon} />}
          <h2>{title}</h2>
          {actions && <div className="card-actions">{actions}</div>}
        </header>
      )}
      <div className={cls('card-body', bodyClassName)}>{children}</div>
    </section>
  );
}

type ButtonProps = ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: 'primary' | 'outline' | 'ghost' | 'danger' | 'subtle';
  size?: 'sm' | 'md';
  icon?: LucideIcon;
  loading?: boolean;
};

export function Button({
  variant = 'outline',
  size = 'md',
  icon: Icon,
  loading,
  className,
  children,
  disabled,
  ...rest
}: ButtonProps) {
  return (
    <button
      className={cls('btn', `btn--${variant}`, `btn--${size}`, className)}
      disabled={disabled || loading}
      {...rest}
    >
      {loading ? <Loader2 size={14} className="spin" /> : Icon && <Icon size={14} strokeWidth={2.4} />}
      {children}
    </button>
  );
}

export function ConfirmButton({
  onConfirm,
  children,
  confirmText = locale('ui_sure'),
  ...rest
}: ButtonProps & { onConfirm(): void; confirmText?: string }) {
  const [armed, setArmed] = useState(false);

  useEffect(() => {
    if (!armed) return;

    const t = setTimeout(() => setArmed(false), 3000);

    return () => clearTimeout(t);
  }, [armed]);

  return (
    <Button
      {...rest}
      variant={armed ? 'danger' : rest.variant}
      onClick={() => {
        if (armed) {
          setArmed(false);
          onConfirm();
        } else {
          setArmed(true);
        }
      }}
    >
      {armed ? confirmText : children}
    </Button>
  );
}

export function Modal({
  title,
  foot,
  onClose,
  children,
}: {
  title: string;
  foot: ReactNode;
  onClose(): void;
  children: ReactNode;
}) {
  const box = useRef<HTMLDivElement>(null);
  const root = document.getElementById('tablet-root');

  useEffect(() => {
    if (!box.current?.contains(document.activeElement)) {
      box.current?.focus();
    }
  }, []);

  const body = (
    <div className="modal-back" onMouseDown={(e) => e.target === e.currentTarget && onClose()}>
      <div
        ref={box}
        className="modal craft-modal"
        tabIndex={-1}
        onKeyDown={(e) => {
          if (e.key !== 'Escape') return;

          e.stopPropagation();
          onClose();
        }}
      >
        <h3>{title}</h3>
        {children}
        <div className="modal-foot">{foot}</div>
      </div>
    </div>
  );

  return root ? createPortal(body, root) : body;
}

export function ConfirmDialog({
  title,
  confirm,
  icon = Trash2,
  onConfirm,
  onClose,
  children,
}: {
  title: string;
  confirm: string;
  icon?: LucideIcon;
  onConfirm(): Promise<boolean>;
  onClose(): void;
  children: ReactNode;
}) {
  const [busy, setBusy] = useState(false);

  const go = async () => {
    setBusy(true);

    const ok = await onConfirm();

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
          <Button variant="danger" icon={icon} loading={busy} onClick={go}>
            {confirm}
          </Button>
        </>
      }
    >
      <p className="craft-confirm">{children}</p>
    </Modal>
  );
}

export function Field({ label, children, className }: { label: string; children: ReactNode; className?: string }) {
  return (
    <label className={cls('field', className)}>
      <span className="field-label">{label}</span>
      {children}
    </label>
  );
}

export interface Option<T extends string | number> {
  value: T;
  label: string;
  hint?: string;
}

export function Select<T extends string | number>({
  value,
  options,
  onChange,
  placeholder = locale('ui_select'),
  className,
  size = 'md',
  disabled,
}: {
  value: T | null;
  options: Option<T>[];
  onChange(value: NoInfer<T>): void;
  placeholder?: string;
  className?: string;
  size?: 'sm' | 'md';
  disabled?: boolean;
}) {
  const [open, setOpen] = useState(false);
  const [pos, setPos] = useState<CSSProperties>({});
  const trigger = useRef<HTMLButtonElement>(null);
  const menu = useRef<HTMLDivElement>(null);
  const root = document.getElementById('tablet-root');
  const selected = options.find((o) => o.value === value);

  useLayoutEffect(() => {
    if (!open || !trigger.current || !root) return;

    const r = trigger.current.getBoundingClientRect();
    const rr = root.getBoundingClientRect();
    const scale = rr.width / root.offsetWidth || 1;
    const menuHeight = Math.min(260, options.length * 34 + 10);
    const below = (r.bottom - rr.top) / scale + 4;
    const flip = below + menuHeight > root.offsetHeight - 8;

    setPos({
      left: (r.left - rr.left) / scale,
      top: flip ? (r.top - rr.top) / scale - menuHeight - 4 : below,
      minWidth: r.width / scale,
      maxHeight: menuHeight,
    });
  }, [open, options.length, root]);

  useEffect(() => {
    if (!open) return;

    const onDown = (e: MouseEvent) => {
      const t = e.target as Node;

      if (!trigger.current?.contains(t) && !menu.current?.contains(t)) {
        setOpen(false);
      }
    };

    const onScroll = (e: Event) => {
      if (!menu.current?.contains(e.target as Node)) {
        setOpen(false);
      }
    };

    document.addEventListener('mousedown', onDown);
    document.addEventListener('scroll', onScroll, true);

    return () => {
      document.removeEventListener('mousedown', onDown);
      document.removeEventListener('scroll', onScroll, true);
    };
  }, [open]);

  return (
    <>
      <button
        type="button"
        ref={trigger}
        className={cls('select', `select--${size}`, open && 'is-open', className)}
        onClick={() => setOpen((o) => !o)}
        disabled={disabled}
      >
        <span className={cls('select-value', !selected && 'is-placeholder')}>{selected?.label ?? placeholder}</span>
        <ChevronDown size={15} className="select-chevron" />
      </button>
      {open &&
        root &&
        createPortal(
          <div className="select-menu" ref={menu} style={pos}>
            {options.length === 0 && <div className="select-empty">{locale('ui_nothing_to_pick')}</div>}
            {options.map((o) => (
              <button
                type="button"
                key={String(o.value)}
                className={cls('select-option', o.value === value && 'is-selected')}
                onClick={() => {
                  onChange(o.value);
                  setOpen(false);
                }}
              >
                <span>{o.label}</span>
                {o.hint && <span className="select-hint">{o.hint}</span>}
                {o.value === value && <Check size={14} />}
              </button>
            ))}
          </div>,
          root,
        )}
    </>
  );
}

export function MultiSelect<T extends string | number>({
  value,
  options,
  onChange,
  placeholder = locale('ui_select'),
  className,
  size = 'md',
  disabled,
}: {
  value: T[];
  options: Option<T>[];
  onChange(value: NoInfer<T>[]): void;
  placeholder?: string;
  className?: string;
  size?: 'sm' | 'md';
  disabled?: boolean;
}) {
  const [open, setOpen] = useState(false);
  const [pos, setPos] = useState<CSSProperties>({});
  const trigger = useRef<HTMLButtonElement>(null);
  const menu = useRef<HTMLDivElement>(null);
  const root = document.getElementById('tablet-root');
  const picked = options.filter((o) => value.includes(o.value));

  useLayoutEffect(() => {
    if (!open || !trigger.current || !root) return;

    const r = trigger.current.getBoundingClientRect();
    const rr = root.getBoundingClientRect();
    const scale = rr.width / root.offsetWidth || 1;
    const menuHeight = Math.min(260, options.length * 34 + 10);
    const below = (r.bottom - rr.top) / scale + 4;
    const flip = below + menuHeight > root.offsetHeight - 8;

    setPos({
      left: (r.left - rr.left) / scale,
      top: flip ? (r.top - rr.top) / scale - menuHeight - 4 : below,
      minWidth: r.width / scale,
      maxHeight: menuHeight,
    });
  }, [open, options.length, root]);

  useEffect(() => {
    if (!open) return;

    const onDown = (e: MouseEvent) => {
      const t = e.target as Node;

      if (!trigger.current?.contains(t) && !menu.current?.contains(t)) {
        setOpen(false);
      }
    };

    const onScroll = (e: Event) => {
      if (!menu.current?.contains(e.target as Node)) {
        setOpen(false);
      }
    };

    document.addEventListener('mousedown', onDown);
    document.addEventListener('scroll', onScroll, true);

    return () => {
      document.removeEventListener('mousedown', onDown);
      document.removeEventListener('scroll', onScroll, true);
    };
  }, [open]);

  const toggle = (v: T) => onChange(value.includes(v) ? value.filter((x) => x !== v) : [...value, v]);

  return (
    <>
      <button
        type="button"
        ref={trigger}
        className={cls('select', `select--${size}`, open && 'is-open', className)}
        onClick={() => setOpen((o) => !o)}
        disabled={disabled}
      >
        <span className={cls('select-value', picked.length === 0 && 'is-placeholder')}>
          {picked.length > 0 ? picked.map((o) => o.label).join(', ') : placeholder}
        </span>
        <ChevronDown size={15} className="select-chevron" />
      </button>
      {open &&
        root &&
        createPortal(
          <div className="select-menu" ref={menu} style={pos}>
            {options.length === 0 && <div className="select-empty">{locale('ui_nothing_to_pick')}</div>}
            {options.map((o) => {
              const on = value.includes(o.value);

              return (
                <button
                  type="button"
                  key={String(o.value)}
                  className={cls('select-option', on && 'is-selected')}
                  onClick={() => toggle(o.value)}
                >
                  <span>{o.label}</span>
                  {o.hint && <span className="select-hint">{o.hint}</span>}
                  {on && <Check size={14} />}
                </button>
              );
            })}
          </div>,
          root,
        )}
    </>
  );
}

export function Thumb({ src, icon: Icon, className }: { src?: string | null; icon: LucideIcon; className?: string }) {
  const [broken, setBroken] = useState(false);

  useEffect(() => setBroken(false), [src]);

  return (
    <span className={cls('thumb', src && !broken && 'has-image', className)}>
      {src && !broken ? (
        <img src={src} alt="" loading="lazy" onError={() => setBroken(true)} />
      ) : (
        <Icon size={15} strokeWidth={2} />
      )}
    </span>
  );
}

export interface ComboOption {
  value: string;
  label: string;
  sub?: string;
  tag?: string;
  image?: string | null;
}

const COMBO_LIMIT = 120;

export function Combobox({
  value,
  options,
  onChange,
  icon,
  placeholder = locale('ui_search'),
  loading,
  size = 'md',
  className,
}: {
  value: string | null;
  options: ComboOption[];
  onChange(value: string): void;
  icon: LucideIcon;
  placeholder?: string;
  loading?: boolean;
  size?: 'sm' | 'md';
  className?: string;
}) {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState('');
  const [active, setActive] = useState(0);
  const [pos, setPos] = useState<CSSProperties>({});
  const trigger = useRef<HTMLButtonElement>(null);
  const menu = useRef<HTMLDivElement>(null);
  const list = useRef<HTMLDivElement>(null);
  const root = document.getElementById('tablet-root');
  const selected = options.find((o) => o.value === value);

  const q = query.trim().toLowerCase();

  const matches = q
    ? options.filter(
        (o) =>
          o.label.toLowerCase().includes(q) ||
          o.value.toLowerCase().includes(q) ||
          o.sub?.toLowerCase().includes(q) ||
          o.tag?.toLowerCase().includes(q),
      )
    : options;

  const shown = matches.slice(0, COMBO_LIMIT);

  useLayoutEffect(() => {
    if (!open || !trigger.current || !root) return;

    const r = trigger.current.getBoundingClientRect();
    const rr = root.getBoundingClientRect();
    const scale = rr.width / root.offsetWidth || 1;
    const menuHeight = 360;
    const below = (r.bottom - rr.top) / scale + 4;
    const flip = below + menuHeight > root.offsetHeight - 8;

    setPos({
      left: (r.left - rr.left) / scale,
      top: flip ? Math.max(8, (r.top - rr.top) / scale - menuHeight - 4) : below,
      width: Math.max(r.width / scale, 320),
      height: menuHeight,
    });
  }, [open, root]);

  useEffect(() => {
    if (!open) return;

    const onDown = (e: MouseEvent) => {
      const t = e.target as Node;

      if (!trigger.current?.contains(t) && !menu.current?.contains(t)) {
        setOpen(false);
      }
    };

    const onScroll = (e: Event) => {
      if (!menu.current?.contains(e.target as Node)) {
        setOpen(false);
      }
    };

    document.addEventListener('mousedown', onDown);
    document.addEventListener('scroll', onScroll, true);

    return () => {
      document.removeEventListener('mousedown', onDown);
      document.removeEventListener('scroll', onScroll, true);
    };
  }, [open]);

  useEffect(() => setActive(0), [query, open]);

  useEffect(() => {
    list.current?.querySelector<HTMLElement>(`[data-index="${active}"]`)?.scrollIntoView({ block: 'nearest' });
  }, [active]);

  const pick = (o: ComboOption) => {
    onChange(o.value);
    setOpen(false);
    setQuery('');
  };

  const onKey = (e: KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'ArrowDown') {
      setActive((i) => Math.min(i + 1, shown.length - 1));
    } else if (e.key === 'ArrowUp') {
      setActive((i) => Math.max(i - 1, 0));
    } else if (e.key === 'Enter' && shown[active]) {
      pick(shown[active]);
    } else if (e.key === 'Escape') {
      setOpen(false);
    } else {
      return;
    }

    e.preventDefault();
    e.stopPropagation();
  };

  return (
    <>
      <button
        type="button"
        ref={trigger}
        className={cls('select combo', `select--${size}`, open && 'is-open', className)}
        onClick={() => setOpen((o) => !o)}
        disabled={loading}
      >
        {selected ? <Thumb src={selected.image} icon={icon} className="thumb--sm" /> : null}
        <span className={cls('select-value', !selected && 'is-placeholder')}>
          {loading ? locale('ui_loading') : (selected?.label ?? placeholder)}
        </span>
        {selected?.sub && <span className="combo-sub mono">{selected.sub}</span>}
        <ChevronDown size={15} className="select-chevron" />
      </button>
      {open &&
        root &&
        createPortal(
          <div className="select-menu combo-menu" ref={menu} style={pos}>
            <label className="search combo-search">
              <Search size={14} />
              <input
                autoFocus
                placeholder={locale('ui_search_n', options.length.toLocaleString())}
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                onKeyDown={onKey}
              />
            </label>
            <div className="combo-list" ref={list}>
              {shown.length === 0 && <div className="select-empty">{locale('ui_no_matches')}</div>}
              {shown.map((o, i) => (
                <button
                  type="button"
                  key={o.value}
                  data-index={i}
                  className={cls('combo-option', o.value === value && 'is-selected', i === active && 'is-active')}
                  onMouseEnter={() => setActive(i)}
                  onClick={() => pick(o)}
                >
                  <Thumb src={o.image} icon={icon} />
                  <span className="combo-text">
                    <span className="combo-label">{o.label}</span>
                    {o.sub && <span className="combo-option-sub mono">{o.sub}</span>}
                  </span>
                  {o.tag && <span className="select-hint">{o.tag}</span>}
                  {o.value === value && <Check size={14} />}
                </button>
              ))}
            </div>
            {matches.length > shown.length && (
              <div className="combo-more">
                {locale('ui_showing_n', shown.length, matches.length.toLocaleString())}
              </div>
            )}
          </div>,
          root,
        )}
    </>
  );
}

export function Empty({
  icon: Icon,
  children,
  className,
}: {
  icon?: LucideIcon;
  children: ReactNode;
  className?: string;
}) {
  return (
    <div className={cls('empty', className)}>
      {Icon && <Icon size={22} strokeWidth={1.8} />}
      <span>{children}</span>
    </div>
  );
}

export function Pill({
  tone = 'accent',
  children,
}: {
  tone?: 'accent' | 'danger' | 'warn' | 'ok' | 'muted';
  children: ReactNode;
}) {
  return <span className={cls('pill', `pill--${tone}`)}>{children}</span>;
}


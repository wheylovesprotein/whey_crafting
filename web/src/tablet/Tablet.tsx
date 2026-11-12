import { Check, X } from 'lucide-react';
import { useCallback, useEffect, useMemo, useState } from 'react';
import { locale } from '../locale';
import { nui } from '../nui';
import type { Result } from '../types';
import { cls } from '../util';
import { Ctx, type Payload, type TabletContext, type Tone } from './context';
import Manager from './Manager';

const DESIGN_W = 1560;
const DESIGN_H = 900;
const TOAST_MS = 3200;

interface Toast {
  id: number;
  text: string;
  tone: Tone;
  leaving?: boolean;
}

async function request<T>(action: string, payload: Payload): Promise<Result<T>> {
  const response = await nui<Result<T>>('request', { action, payload });

  return response ?? { ok: false, error: locale('ui_no_response') };
}

const isField = (target: EventTarget | null) =>
  target instanceof HTMLElement && (target.tagName === 'INPUT' || target.tagName === 'TEXTAREA');

export default function Tablet() {
  const [visible, setVisible] = useState(false);
  const [toasts, setToasts] = useState<Toast[]>([]);
  const [scale, setScale] = useState(1);
  const [away, setAway] = useState(false);

  const dismiss = useCallback((id: number) => {
    setToasts((list) => list.map((entry) => (entry.id === id ? { ...entry, leaving: true } : entry)));
    setTimeout(() => setToasts((list) => list.filter((entry) => entry.id !== id)), 200);
  }, []);

  const toast = useCallback(
    (text: string, tone: Tone = 'ok') => {
      const id = Date.now() + Math.random();

      setToasts((list) => {
        const same = list.find((entry) => !entry.leaving && entry.text === text && entry.tone === tone);

        if (same) {
          return list.map((entry) => (entry === same ? { ...entry, id } : entry));
        }

        return [...list.filter((entry) => !entry.leaving).slice(-2), { id, text, tone }];
      });

      setTimeout(() => dismiss(id), TOAST_MS);
    },
    [dismiss],
  );

  const run = useCallback<TabletContext['run']>(
    async (action, payload = {}) => {
      const response = await request<unknown>(action, payload);

      if (response.ok) {
        if (response.message) {
          toast(response.message);
        }
      } else {
        toast(response.error, 'error');
      }

      return response.ok;
    },
    [toast],
  );

  const query = useCallback(
    async <T,>(action: string, payload: Payload = {}): Promise<T | null> => {
      const response = await request<T>(action, payload);

      if (!response.ok) {
        toast(response.error, 'error');

        return null;
      }

      if (response.message) {
        toast(response.message);
      }

      return response.result ?? null;
    },
    [toast],
  );

  const close = useCallback(() => {
    nui('closeTablet');
  }, []);

  useEffect(() => {
    const onMessage = (event: MessageEvent) => {
      if (event.data?.action === 'tablet') {
        setVisible(event.data.visible === true);
      }
    };

    window.addEventListener('message', onMessage);

    return () => window.removeEventListener('message', onMessage);
  }, []);

  useEffect(() => {
    const onIn = (event: FocusEvent) => isField(event.target) && nui('typing', { typing: true });
    const onOut = (event: FocusEvent) => isField(event.target) && nui('typing', { typing: false });

    document.addEventListener('focusin', onIn);
    document.addEventListener('focusout', onOut);

    return () => {
      document.removeEventListener('focusin', onIn);
      document.removeEventListener('focusout', onOut);
    };
  }, []);

  useEffect(() => {
    if (!visible) return;

    const onKey = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        close();
      }
    };

    window.addEventListener('keydown', onKey);

    return () => window.removeEventListener('keydown', onKey);
  }, [visible, close]);

  useEffect(() => {
    const fit = () => {
      const { innerWidth: width, innerHeight: height } = window;
      const relative = Math.min(width / 1920, height / 1080);

      setScale(Math.min(relative, width / (DESIGN_W + 40), height / (DESIGN_H + 40)));
    };

    fit();
    window.addEventListener('resize', fit);

    return () => window.removeEventListener('resize', fit);
  }, []);

  const ctx = useMemo<TabletContext>(() => ({ run, query, toast }), [run, query, toast]);

  if (!visible) return null;

  return (
    <div className="stage">
      <div
        className={cls('tablet', away && 'is-away')}
        id="tablet-root"
        style={{ width: DESIGN_W, height: DESIGN_H, transform: `scale(${scale})` }}
        onMouseEnter={() => setAway(false)}
        onMouseLeave={() => setAway(true)}
      >
        <div className="screen">
          <Ctx.Provider value={ctx}>
            <div className="main">
              <header className="main-head">
                <div className="main-title">
                  <h1>{locale('ui_title')}</h1>
                  <p>{locale('ui_subtitle')}</p>
                </div>
                <div className="main-tools">
                  <button className="key-btn" onClick={close}>
                    {locale('ui_esc')}
                  </button>
                </div>
              </header>
              <main className="content">
                <Manager />
              </main>
            </div>
          </Ctx.Provider>
        </div>
        <div className="toasts">
          {toasts.map((entry) => (
            <div key={entry.id} className={cls('toast', `toast--${entry.tone}`, entry.leaving && 'is-leaving')}>
              <span className="toast-icon">
                {entry.tone === 'ok' ? <Check size={15} strokeWidth={3} /> : <X size={15} strokeWidth={3} />}
              </span>
              <div className="toast-body">
                <div className="toast-title">{locale(entry.tone === 'ok' ? 'ui_toast_ok' : 'ui_toast_error')}</div>
                <div className="toast-text">{entry.text}</div>
              </div>
              <button className="toast-close" onClick={() => dismiss(entry.id)} aria-label={locale('ui_dismiss')}>
                <X size={13} />
              </button>
              <span className="toast-bar" style={{ animationDuration: `${TOAST_MS}ms` }} />
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

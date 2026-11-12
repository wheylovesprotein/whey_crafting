import { createContext, useContext } from 'react';

export type Tone = 'ok' | 'error';
export type Payload = Record<string, unknown>;

export interface TabletContext {
  run(action: string, payload?: Payload): Promise<boolean>;
  query<T>(action: string, payload?: Payload): Promise<T | null>;
  toast(text: string, tone?: Tone): void;
}

export const Ctx = createContext<TabletContext | null>(null);

export function useTablet() {
  const ctx = useContext(Ctx);

  if (!ctx) {
    throw new Error('useTablet outside provider');
  }

  return ctx;
}

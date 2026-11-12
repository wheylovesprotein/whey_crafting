import { setLocale } from './locale';
import { nui } from './nui';

export interface Limits {
  key: number;
  label: number;
  categories: number;
  recipes: number;
  ingredients: number;
  recipeCount: number;
  duration: number;
  ingredientCount: number;
  cooldownLimit: number;
  cooldownHours: number;
  model: number;
  props: number;
}

interface Init {
  locale: Record<string, string>;
  limits: Limits;
  key: string;
  showKey: boolean;
}

export const limits: Limits = {
  key: 50,
  label: 50,
  categories: 50,
  recipes: 100,
  ingredients: 20,
  recipeCount: 10000,
  duration: 86400,
  ingredientCount: 1000000,
  cooldownLimit: 10000,
  cooldownHours: 720,
  model: 64,
  props: 5000,
};

export const interact = { key: 'E', showKey: true };

const RETRY_MS = 1000;

export async function loadInit(): Promise<void> {
  for (;;) {
    const init = await nui<Init>('ready');

    if (init && typeof init === 'object' && init.locale) {
      setLocale(init.locale);
      Object.assign(limits, init.limits);
      interact.key = init.key;
      interact.showKey = init.showKey;

      return;
    }

    await new Promise((resolve) => setTimeout(resolve, RETRY_MS));
  }
}

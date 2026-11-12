export interface CraftingIngredient {
  item: string;
  count: number;
}

export interface CraftingCooldown {
  limit: number;
  hours: number;
}

export interface CraftingRecipe {
  item: string;
  count: number;
  duration: number;
  blueprint?: string | null;
  cooldown?: CraftingCooldown | null;
  ingredients: CraftingIngredient[];
}

export interface CraftingCategory {
  label: string;
  recipes: CraftingRecipe[];
}

export interface CraftingType {
  name: string;
  label: string;
  categories: CraftingCategory[];
}

export interface Vec3 {
  x: number;
  y: number;
  z: number;
}

export interface CraftingBench {
  id: number;
  type: string;
  coords: Vec3;
  heading: number;
  gangs: string[];
}

export interface CraftingProp {
  id: number;
  model: string;
  coords: Vec3;
  heading: number;
}

export interface GangOption {
  name: string;
  label: string;
}

export interface CraftingData {
  types: CraftingType[];
  tables: CraftingBench[];
  props: CraftingProp[];
  gangs: GangOption[];
}

export interface InventoryItem {
  name: string;
  label: string;
  kind: 'item' | 'weapon' | 'ammo' | 'component';
}

export type Result<T> = { ok: true; message?: string; result?: T } | { ok: false; error: string };

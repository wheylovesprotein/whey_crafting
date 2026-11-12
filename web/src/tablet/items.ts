import { useEffect, useState } from 'react';
import { locale } from '../locale';
import { itemImage } from '../nui';
import type { InventoryItem } from '../types';
import { arr } from '../util';
import { useTablet } from './context';
import type { ComboOption } from './ui';

export const itemOption = (item: InventoryItem): ComboOption => ({
  value: item.name,
  label: item.label,
  sub: item.name,
  tag: locale(`ui_kind_${item.kind}`),
  image: itemImage(item.name),
});

const RETRY_MS = 2000;

let itemCache: InventoryItem[] | null = null;
let inFlight: Promise<InventoryItem[]> | null = null;

export function useItems() {
  const { query } = useTablet();
  const [items, setItems] = useState<InventoryItem[] | null>(itemCache);

  useEffect(() => {
    if (itemCache) return;

    let live = true;
    let timer: ReturnType<typeof setTimeout> | undefined;

    const load = () => {
      inFlight ??= query<InventoryItem[]>('items').then((list) => {
        const got = arr<InventoryItem>(list);

        if (got.length > 0) {
          itemCache = got;
        }

        inFlight = null;

        return got;
      });

      inFlight.then((got) => {
        if (!live) return;

        if (got.length > 0) {
          setItems(got);
        } else {
          timer = setTimeout(load, RETRY_MS);
        }
      });
    };

    load();

    return () => {
      live = false;
      clearTimeout(timer);
    };
  }, [query]);

  return items;
}

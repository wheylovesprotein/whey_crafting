const resource = window.GetParentResourceName?.() ?? 'whey_crafting';

export async function nui<T>(endpoint: string, data?: unknown): Promise<T | null> {
  try {
    const response = await fetch(`https://${resource}/${endpoint}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(data ?? {}),
    });

    return (await response.json()) as T;
  } catch {
    return null;
  }
}

export const itemImage = (name: string) => `nui://ox_inventory/web/images/${name}.png`;

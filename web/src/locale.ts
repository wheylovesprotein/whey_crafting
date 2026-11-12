let strings: Record<string, string> = {};

export function setLocale(next: Record<string, string>) {
  strings = next;
}

export function locale(key: string, ...args: (string | number)[]) {
  let index = 0;

  return (strings[key] ?? key).replace(/%[sd]/g, () => String(args[index++] ?? ''));
}

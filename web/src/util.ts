export const cls = (...parts: (string | false | null | undefined)[]) => parts.filter(Boolean).join(' ');

export const arr = <T>(value: unknown): T[] => (Array.isArray(value) ? (value as T[]) : []);

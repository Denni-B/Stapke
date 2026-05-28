export function env(name, fallback = undefined) {
  const value = process.env[name];
  if (value === undefined || value === '') {
    if (fallback !== undefined) return fallback;
    throw new Error(`Missing env var: ${name}`);
  }
  return value;
}


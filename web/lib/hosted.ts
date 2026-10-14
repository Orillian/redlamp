/**
 * Files kept outside the repository that the site serves at paths of their own, such as the ones
 * release builds of the app fetch (README.md, Hosted files). Each is a numbered pair from the
 * Vercel project's environment, `HOSTED_<n>_PATH`, where the site serves it, and `HOSTED_<n>_URL`,
 * where it's kept, so the repository names neither.
 */
export type HostedFile = { source: string; destination: string };

/** The pairs from 1 up to the first number with neither set; a pair half set or malformed stops the build. */
export function hostedFiles(env: Record<string, string | undefined> = process.env): HostedFile[] {
  const files: HostedFile[] = [];
  for (let n = 1; env[`HOSTED_${n}_PATH`] || env[`HOSTED_${n}_URL`]; n++) {
    const source = env[`HOSTED_${n}_PATH`] ?? "";
    const destination = env[`HOSTED_${n}_URL`] ?? "";
    // Only plain paths: a rewrite's source reads `:`, `*` and brackets as patterns.
    if (!/^\/[\w./-]+$/.test(source)) {
      throw new Error(`HOSTED_${n}_PATH must be a path from the site's root, such as /files/name.bin`);
    }
    if (!/^https:\/\/[^/\s]+\/\S*$/.test(destination)) {
      throw new Error(`HOSTED_${n}_URL must be the https address where the file is kept`);
    }
    files.push({ source, destination });
  }
  return files;
}

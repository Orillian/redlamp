/**
 * The edit a Redlamp export carries in its XMP (docs/recipes/sidecar-format.md, Edits embedded in
 * exports), read from the file's bytes as text, as a sidecar that holds only its recipe; `null` when
 * the file carries none. Relative imports only, so `node --test` can load it.
 */
export function editFromXMP(text: string): string | null {
  // ImageIO writes the property as an attribute of rdf:Description; other writers as an element.
  const match = text.match(/redlamp:Recipe="([^"]*)"/) ?? text.match(/<redlamp:Recipe>([\s\S]*?)<\/redlamp:Recipe>/);
  if (!match) return null;
  const json = match[1]
    .replace(/&#x([0-9a-f]+);/gi, (_, hex: string) => String.fromCodePoint(parseInt(hex, 16)))
    .replace(/&#(\d+);/g, (_, decimal: string) => String.fromCodePoint(Number(decimal)))
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&amp;/g, "&");
  try {
    const recipe: unknown = JSON.parse(json);
    if (typeof recipe !== "object" || recipe === null) return null;
    return JSON.stringify({ format: "app.redlamp.edit", embedded: true, recipe });
  } catch {
    return null;
  }
}

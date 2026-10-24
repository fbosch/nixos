import assert from "node:assert/strict";
import { join } from "node:path";
import { test } from "node:test";
import { pathToFileURL } from "node:url";

const packageRoot = process.env.PI_TEST_PACKAGE;
assert.ok(packageRoot, "PI_TEST_PACKAGE must point to the installed Pi package");
const modulePath = process.env.PI_MARKDOWN_MODULE ?? join(packageRoot, "../pi-tui/dist/components/markdown.js");
const { Markdown, lexMarkdownForTest, setMarkdownCachingForTest } = await import(pathToFileURL(modulePath).href);
const baselinePath = process.env.PI_MARKDOWN_REFERENCE;
const ReferenceMarkdown = baselinePath ? (await import(pathToFileURL(baselinePath).href)).Markdown : Markdown;

function theme(observeCode = () => {}) {
  let color = 36;
  const paint = text => `\x1b[${color}m${text}\x1b[0m`;
  const result = Object.fromEntries([
    "heading", "link", "linkUrl", "code", "codeBlock", "codeBlockBorder", "quote", "quoteBorder", "hr", "listBullet",
    "bold", "italic", "strikethrough", "underline",
  ].map(name => [name, paint]));
  result.highlightCode = code => { observeCode(); return code.split("\n").map(paint); };
  return { value: result, change: () => { color = 35; } };
}

function fullRender(text, width, colors, style, options = {}, paddingX = 1, paddingY = 0) {
  setMarkdownCachingForTest(false);
  try {
    return new ReferenceMarkdown(text, paddingX, paddingY, colors, style, options).render(width);
  } finally {
    setMarkdownCachingForTest(true);
  }
}

const fixtures = [
  ["mixed", "# Heading æøå\n\nParagraph with **bold**, _italic_, ~~strike~~, `code`, [link](https://example.com) and 😀 中文.\n\n```js\nconst value = \"æøå\";\n```\n\n## Next\n\nTail paragraph."],
  ["lists", "# Lists\n\n- [x] one\n- [ ] two\n  - nested **bold**\n\n1. first\n2. second\n\nParagraph\n2. Install\n   continuation\n\nEnd."],
  ["quotes", "# Quotes\n\n> outer\n>\n> > nested\n> >\n> > ```ts\n> > const x = 1;\n> > ```\n\nEnd."],
  ["tables", "# Table\n\n| Name | Value |\n| :--- | ---: |\n| æøå | **wide 中文** |\n| second | `a` |\n\nEnd."],
  ["references", "# Links\n\nRead [later][ref] and [missing].\n\nOther paragraph.\n\n[ref]: https://example.com \"Title\"\n\nEnd."],
  ["math", "# Math\n\nFirst paragraph\n\n$$\nx^2 + \\frac{1}{2}\n\n+ y_1\n$$\n\nInline $\\alpha + \\beta$ and \\(x^2\\).\n\nEnd."],
  ["unfinished block math", "\n$$\n\nparagraph\nline\n2. next\n    code\n\n   continuation\n\n```\nx\n```\n\n<script"],
  ["setext", "# Before\n\nA paragraph\ncontinued\n---\n\nAnother\n===\n\nEnd."],
  ["line endings and tabs", "# Tabs\r\n\r\nalpha\tbeta æøå\r\n\r\n```\r\n\tx\r\n```\r\n\r\nEnd.\r\n"],
  ["HTML and escapes", "# Escapes\n\n\\*literal\\* <https://example.com>\n\n<div>\nraw *HTML*\n</div>\n\n![alt](https://example.com/image.png)\n\nEnd."],
];

for (const [name, text] of fixtures) {
  test(`streamed ${name} matches full rendering byte for byte`, () => {
    const colors = theme().value;
    for (const width of [1, 3, 24, 80]) {
      for (const chunk of [1, 7, 128]) {
        const markdown = new Markdown("", 1, 0, colors);
        for (let end = chunk; end < text.length + chunk; end += chunk) {
          const partial = text.slice(0, end);
          markdown.setText(partial);
          assert.deepEqual(markdown.render(width), fullRender(partial, width, colors), `${name}: width=${width}, chunk=${chunk}, end=${end}`);
        }
        assert.deepEqual(new Markdown(text, 1, 0, colors, undefined, { complete: true }).render(width), fullRender(text, width, colors));
      }
    }
  });
}

test("completed blocks reuse lexing and highlighting across growing component instances", () => {
  let highlights = 0;
  const colors = theme(() => highlights++).value;
  const source = "# Reuse\n\n```js\nconst reusable = 1;\n```\n\n## Next\n\nThe tail";
  const before = lexMarkdownForTest(source);
  new Markdown(source, 1, 0, colors).render(80);
  const initial = highlights;
  const after = lexMarkdownForTest(source + " grows");
  assert.equal(after[0], before[0]);
  new Markdown(source + " grows", 1, 0, colors).render(80);
  assert.equal(highlights, initial);
  assert.equal(initial, 1);
});

test("resize, mutable theme invalidation, padding and default styles refresh cached blocks", () => {
  const colors = theme();
  const text = fixtures[0][1];
  const style = { color: value => `\x1b[32m${value}\x1b[0m`, bgColor: value => `\x1b[44m${value}\x1b[49m`, italic: true };
  const markdown = new Markdown(text, 2, 1, colors.value, style);
  for (const width of [80, 24, 3, 120, 80]) {
    assert.deepEqual(markdown.render(width), fullRender(text, width, colors.value, style, {}, 2, 1));
  }
  const old = markdown.render(80);
  colors.change();
  markdown.invalidate();
  const changed = markdown.render(80);
  assert.notDeepEqual(changed, old);
  assert.deepEqual(changed, fullRender(text, 80, colors.value, style, {}, 2, 1));
  const recreated = new Markdown(text, 2, 1, colors.value, style);
  assert.deepEqual(recreated.render(80), changed);
});

test("replacements, reference definitions and interleaved messages do not reuse stale output", () => {
  const colors = theme().value;
  const components = [new Markdown("", 1, 0, colors), new Markdown("", 1, 0, colors)];
  const a = "# A\n\n[link][ref]\n\nFirst\n\nNext";
  const b = "# B\n\n```js\nconst b = 2;\n```\n\nOther";
  for (const [index, text] of [[0, a], [1, b], [0, a + " grows"], [1, b + " grows"], [0, a + "\n\n[ref]: https://example.com"], [0, "replacement æøå"], [0, a], [1, ""], [1, " \n\t"]]) {
    components[index].setText(text);
    assert.deepEqual(components[index].render(48), fullRender(text, 48, colors));
  }
});

test("transforms, preserved escapes and list markers remain width sensitive", () => {
  const colors = theme().value;
  const options = {
    preserveOrderedListMarkers: true, preserveBackslashEscapes: true, renderLatex: false,
    transform: (text, width) => `# Width ${width}\n\n${text}`,
  };
  const markdown = new Markdown("", 1, 0, colors, undefined, options);
  for (const text of ["4. first", "4. first\n8. second\n\n\\*literal\\* and $x^2$"]) {
    markdown.setText(text);
    for (const width of [24, 80, 24]) {
      assert.deepEqual(markdown.render(width), fullRender(text, width, colors, undefined, options));
    }
  }
});

test("assistant completion reparses text and thinking while preserving transformer context", async () => {
  const load = path => import(pathToFileURL(join(packageRoot, "dist", path)).href);
  const { AssistantMessageComponent } = await load("modes/interactive/components/assistant-message.js");
  const { initTheme } = await load("modes/interactive/theme/theme.js");
  initTheme("dark");
  const contexts = [];
  const component = new AssistantMessageComponent(undefined, false, theme().value, "Thinking...", 1,
    [(text, context) => { contexts.push(context); return text; }], "message-id", "2026-01-01T00:00:00Z");
  const message = { role: "assistant", content: [{ type: "thinking", thinking: "# Reasoning\n\nSome thought" }, { type: "text", text: "# Reply\n\nSome answer" }], stopReason: "stop" };
  function markdownNodes(node) {
    if (node.options && typeof node.setText === "function") return [node];
    return [...(node.children ?? []), ...(node.child ? [node.child] : [])].flatMap(markdownNodes);
  }
  for (const streaming of [true, false]) {
    contexts.length = 0;
    component.updateContent(message, streaming);
    const nodes = markdownNodes(component);
    assert.equal(nodes.length, 2);
    assert.deepEqual(nodes.map(node => node.options.complete), [!streaming, !streaming]);
    component.render(80);
    assert.equal(contexts.length, 2);
    for (const context of contexts) {
      assert.equal(context.isStreaming, streaming);
      assert.equal(context.messageId, "message-id");
      assert.equal(context.timestamp, "2026-01-01T00:00:00Z");
    }
  }
});

test("seeded mixed-block streams match a full parse at every rendered prefix", () => {
  const colors = theme().value;
  const blocks = [
    "# Heading\n\n", "paragraph\n\n", "paragraph\nline\n", "$$\nx\n\n", "\n$$\n\n",
    "1. item\n\n", "2. next\n", "   continuation\n\n", "---\n\n", "[ref]: https://example.com\n\n",
    "```\nx\n```\n\n", "> quote\n\n", "    code\n\n", "| a | b |\n| --- | --- |\n| x | y |\n\n",
    "<script>\nraw\n\n", "</script>\n\n", "[ref] and **bold**\n\n",
  ];
  let seed = 48271;
  function random(max) { seed = (seed * 16807) % 2147483647; return seed % max; }
  for (let trial = 0; trial < 300; trial++) {
    const available = trial % 2 === 0 ? blocks : blocks.filter(block => !block.includes("$$") && !block.includes("[ref]:"));
    const text = Array.from({ length: 12 }, () => available[random(available.length)]).join("");
    const markdown = new Markdown("", 1, 0, colors);
    const chunk = 1 + random(25);
    for (let end = chunk; end < text.length + chunk; end += chunk) {
      const partial = text.slice(0, end);
      markdown.setText(partial);
      assert.deepEqual(markdown.render(80), fullRender(partial, 80, colors), `trial=${trial}, end=${end}`);
    }
  }
});

# Design lint (no hardcoded colours or sizes)

The pre-commit `lint` step runs eslint. Add the Tailwind rules once per project:

    npm i -D eslint-plugin-better-tailwindcss

`eslint.config.mjs`:

    import tailwind from "eslint-plugin-better-tailwindcss";
    export default [
      // ...existing config
      { files: ["**/*.{ts,tsx,jsx}"], plugins: { "better-tailwindcss": tailwind },
        settings: { "better-tailwindcss": { entryPoint: "src/app/globals.css" } },
        rules: { "better-tailwindcss/no-unregistered-classes": "error", "better-tailwindcss/no-restricted-classes": ["error", { restrict: ["^(text|bg|w|h|p|m|gap|rounded|border)-\\[(?!var\\(--|--)"] }] } },
    ];

Tokens live in `globals.css` / `DESIGN.md`; `src/components/ui/*` may be exempted with an `ignores` entry.

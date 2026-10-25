import js from "@eslint/js";
import tseslint from "typescript-eslint";
import globals from "globals";

const frontend = ["test/js/*.mjs"];

export default [
  {
    ignores: [
      "node_modules/**",
      "priv/static/assets/js/vendor/**",
      "priv/static/assets/js/live/catalog.js",
    ],
  },
  {
    ...js.configs.recommended,
    files: frontend,
    languageOptions: { globals: { ...globals.browser, ...globals.node } },
  },
  ...tseslint.configs.recommended.map((config) => ({
    ...config,
    files: ["assets/**/*.ts"],
    languageOptions: { ...config.languageOptions, globals: globals.browser },
  })),
  {
    files: ["assets/js/**/*.ts"],
    // Dynamic event bodies and form models still have open shapes at the UI boundary.
    rules: { "@typescript-eslint/no-explicit-any": "off" },
  },
];

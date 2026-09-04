const js = require("@eslint/js");
const tsPlugin = require("@typescript-eslint/eslint-plugin");
const tsParser = require("@typescript-eslint/parser");
const importPlugin = require("eslint-plugin-import-x");
const google = require("eslint-config-google");
const globals = require("globals");
const {builtinRules} = require("eslint/use-at-your-own-risk");

const supportedGoogleRules = Object.fromEntries(
  Object.entries(google.rules).filter(([ruleName]) => builtinRules.has(ruleName)),
);

module.exports = [
  {
    ignores: ["eslint.config.js", "lib/**/*", "src/**/*.test.ts"],
  },
  js.configs.recommended,
  {
    files: ["**/*.{js,ts}"],
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: "module",
      globals: {
        ...globals.es2021,
        ...globals.node,
      },
      parser: tsParser,
      parserOptions: {
        project: ["tsconfig.json", "tsconfig.dev.json"],
      },
    },
    plugins: {
      "@typescript-eslint": tsPlugin,
      "import-x": importPlugin,
    },
    rules: {
      ...importPlugin.flatConfigs.errors.rules,
      ...importPlugin.flatConfigs.warnings.rules,
      ...importPlugin.flatConfigs.typescript.rules,
      ...supportedGoogleRules,
      ...tsPlugin.configs.recommended.rules,
      quotes: ["error", "double"],
      "import-x/no-unresolved": 0,
      indent: ["error", 2],
    },
  },
];

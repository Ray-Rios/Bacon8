const plugin = require("tailwindcss/plugin")

module.exports = {
  content: [
    './js/**/*.{js,ts}',
    '../lib/bacon8_web.ex',
    '../lib/bacon8_web/**/*.{ex,heex,html.heex}',
    // Installed plugins' templates and hooks (BACON8.md §9)
    '../plugins/*/lib/**/*.{ex,heex}',
    '../plugins/*/assets/js/**/*.{js,ts}'
  ],
  theme: {
    extend: {
      colors: {
        brand: "#247DF1",
      },
    },
  },
  plugins: [
    require('@tailwindcss/forms'), // Temporarily disabled until package is properly installed
    plugin(({ addVariant }) => addVariant("phx-no-feedback", [".phx-no-feedback&", ".phx-no-feedback &"])),
    plugin(({ addVariant }) => addVariant("phx-click-loading", [".phx-click-loading&", ".phx-click-loading &"])),
    plugin(({ addVariant }) => addVariant("phx-submit-loading", [".phx-submit-loading&", ".phx-submit-loading &"])),
    plugin(({ addVariant }) => addVariant("phx-change-loading", [".phx-change-loading&", ".phx-change-loading &"]))
  ]
}
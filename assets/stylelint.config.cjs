module.exports = {
  extends: [
    'stylelint-config-recommended',
    'stylelint-config-standard',
    'stylelint-config-tailwindcss'
  ],
  rules: {
    // Allow Tailwind's arbitrary properties and selectors
    'selector-class-pattern': null,
    'no-descending-specificity': null
    ,
    // stricter rules
    'declaration-block-no-duplicate-properties': true,
    'no-duplicate-selectors': true,
    'block-no-empty': true,
    'property-no-unknown': true,
    'color-named': 'never'
  }
};

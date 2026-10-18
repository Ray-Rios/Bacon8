#!/usr/bin/env node
/**
 * Script: check-no-css-imports.js
 * Purpose: Block and report any '.css' imports from JS/TS files under assets/js
 * Usage: node ./scripts/check-no-css-imports.js
 * Exits with non-zero code if any occurrences are found
 */

const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const JS_ROOT = path.join(ROOT, 'js');

const extensions = ['.js', '.ts', '.jsx', '.tsx'];

const importCssRegex = /\bimport\s+(?:[^;]+?from\s+)?['"`]([^'"`]+\.css)['"`]/;
const dynamicImportCssRegex = /\bimport\(\s*['"`]([^'"`]+\.css)['"`]\s*\)/;
const requireCssRegex = /\brequire\(\s*['"`]([^'"`]+\.css)['"`]\s*\)/;

const allowMarker = 'allow-css-import';

function walk(dir) {
  const results = [];
  const list = fs.readdirSync(dir);
  list.forEach((file) => {
    const full = path.join(dir, file);
    const stat = fs.statSync(full);
    if (stat && stat.isDirectory()) {
      if (file === 'node_modules' || file === 'dist' || file === 'build') return;
      results.push(...walk(full));
    } else {
      results.push(full);
    }
  });
  return results;
}

function checkFile(filePath) {
  const ext = path.extname(filePath);
  if (!extensions.includes(ext)) return [];
  const data = fs.readFileSync(filePath, 'utf8');
  const lines = data.split(/\r?\n/);
  const issues = [];
  let inBlockComment = false;
  lines.forEach((line, idx) => {
    // suppression marker default: if marker present anywhere on line, allow it
    if (line.includes(allowMarker)) return; // suppression marker

    // remove single-line comments and ignore block comments content
    let codeLine = line;
    // Handle block comments start/end within this single line
    if (inBlockComment) {
      if (codeLine.includes('*/')) {
        codeLine = codeLine.substring(codeLine.indexOf('*/') + 2);
        inBlockComment = false;
      } else {
        // whole line is within block comment; skip
        return;
      }
    }
    // If this line opens a block comment, only keep the code before it
    if (codeLine.includes('/*')) {
      const parts = codeLine.split('/*');
      codeLine = parts[0];
      if (!codeLine.includes('*/')) {
        inBlockComment = true;
      } else {
        // if it contains a close marker in the same line, keep the remaining part
        const after = parts[1].split('*/');
        codeLine = parts[0] + after[1];
        inBlockComment = false;
      }
    }
    // Remove trailing single-line comments
    if (codeLine.includes('//')) {
      codeLine = codeLine.split('//')[0];
    }

    if (importCssRegex.test(codeLine) || requireCssRegex.test(codeLine) || dynamicImportCssRegex.test(codeLine)) {
      issues.push({ line: idx + 1, text: line.trim() });
    }
  });
  return issues;
}

function main() {
  if (!fs.existsSync(JS_ROOT)) {
    console.log('No assets/js directory found — skipping CSS import check.');
    process.exit(0);
  }

  const files = walk(JS_ROOT);
  const offenders = [];
  files.forEach((f) => {
    const found = checkFile(f);
    if (found.length > 0) offenders.push({ file: f, occurrences: found });
  });

  if (offenders.length > 0) {
    console.error('\nERROR: Forbidden CSS import(s) found in JS/TS source files:');
    offenders.forEach((o) => {
      console.error(`\n  File: ${path.relative(ROOT, o.file)}`);
      o.occurrences.forEach((occ) => {
        console.error(`    ${occ.line}: ${occ.text}`);
      });
    });

    console.error('\nPlease move CSS imports into `assets/css/app.css` (PostCSS) or mark lines with `// allow-css-import` if unusual explicit import is required.');
    process.exit(1);
  } else {
    console.log('No forbidden CSS imports detected.');
  }
}

main();

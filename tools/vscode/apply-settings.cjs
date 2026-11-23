#!/usr/bin/env node
'use strict';

const fs = require('node:fs');
const { isDeepStrictEqual } = require('node:util');
const {
  applyEdits, createScanner, getNodeValue, modify, parseTree, printParseErrorCode, SyntaxKind,
} = require('jsonc-parser');

function parseDocument(text, label) {
  const errors = [];
  const tree = parseTree(text, errors, { allowTrailingComma: true });
  if (errors.length || !tree) {
    const first = errors[0];
    throw new Error(`${label}: invalid JSONC${first ? ` (${printParseErrorCode(first.error)} at offset ${first.offset})` : ''}`);
  }
  // Duplicate properties are ambiguous: JSONC reads the last, edits target the first.
  function checkDuplicates(node) {
    if (node.type === 'object') {
      const keys = new Set();
      for (const property of node.children) {
        const key = property.children[0].value;
        if (keys.has(key)) throw new Error(`${label}: duplicate property ${JSON.stringify(key)}`);
        keys.add(key);
      }
    }
    for (const child of node.children || []) checkDuplicates(child);
  }
  checkDuplicates(tree);
  return { tree, value: getNodeValue(tree) };
}

function isObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function merge(base, patch) {
  if (!isObject(base) || !isObject(patch)) return patch;
  const result = Object.assign(Object.create(null), base);
  for (const key of Object.keys(patch)) result[key] = merge(base[key], patch[key]);
  return result;
}

function formatting(text) {
  const indent = text.match(/(?:\r?\n)([ \t]+)"/)?.[1];
  return {
    insertSpaces: !indent?.includes('\t'),
    tabSize: indent && !indent.includes('\t') ? indent.length : 4,
    eol: text.includes('\r\n') ? '\r\n' : '\n',
  };
}

function removeTopLevel(text, key) {
  const { tree } = parseDocument(text, 'settings');
  const property = tree.children.find(node => node.children[0].value === key);
  if (!property) return text;
  // Retain explanations inside obsolete arrays/objects as standalone comments.
  const commentScanner = createScanner(text.slice(property.offset, property.offset + property.length), false);
  const comments = [];
  for (let kind = commentScanner.scan(); kind !== SyntaxKind.EOF; kind = commentScanner.scan()) {
    if ([SyntaxKind.LineCommentTrivia, SyntaxKind.BlockCommentTrivia].includes(kind)) {
      comments.push(commentScanner.getTokenValue());
    }
  }
  const indent = text.slice(0, property.offset).match(/(?:^|[\r\n])([ \t]*)$/)?.[1] || '';
  const separator = `${formatting(text).eol}${indent}`;
  const content = comments.length ? comments.join(separator) + separator : '';
  const edits = [{ offset: property.offset, length: property.length, content }];
  // Removing only property tokens and their next comma keeps adjacent comments.
  // An earlier comma may remain as a valid JSONC trailing comma.
  const scanner = createScanner(text, false);
  scanner.setPosition(property.offset + property.length);
  const trivia = new Set([
    SyntaxKind.Trivia, SyntaxKind.LineBreakTrivia, SyntaxKind.LineCommentTrivia, SyntaxKind.BlockCommentTrivia,
  ]);
  let token;
  do { token = scanner.scan(); } while (trivia.has(token));
  if (token === SyntaxKind.CommaToken) {
    edits.push({ offset: scanner.getTokenOffset(), length: scanner.getTokenLength(), content: '' });
  }
  return applyEdits(text, edits);
}

function applySettings(liveText, patchText, removeKeysText) {
  const live = parseDocument(liveText, 'live settings').value;
  const patch = parseDocument(patchText, 'settings patch').value;
  const removeKeys = parseDocument(removeKeysText, 'removed settings').value;
  if (!isObject(live) || !isObject(patch)) throw new Error('Live settings and settings patch must be JSONC objects');
  if (!Array.isArray(removeKeys) || removeKeys.some(key => typeof key !== 'string')) {
    throw new Error('Removed settings must be an array of top-level key names');
  }

  let result = liveText;
  const removals = new Set(removeKeys);
  const options = { formattingOptions: formatting(liveText) };
  function update(path, current, next) {
    if (isDeepStrictEqual(current, next)) return;
    if (isObject(current) && isObject(next)) {
      for (const key of Object.keys(next)) update([...path, key], current[key], next[key]);
    } else {
      result = applyEdits(result, modify(result, path, next, options));
    }
  }

  for (const key of removals) result = removeTopLevel(result, key);
  for (const key of Object.keys(patch)) {
    if (!removals.has(key)) update([key], live[key], merge(live[key], patch[key]));
  }
  parseDocument(result, 'merged settings');
  return result;
}

module.exports = { applySettings };

if (require.main === module) {
  const paths = process.argv.slice(2);
  if (paths.length !== 3) {
    console.error('Usage: node apply-settings.cjs <live-settings-path> <repo-patch-path> <remove-keys-json-path>');
    process.exitCode = 2;
  } else {
    try {
      let liveText;
      try { liveText = fs.readFileSync(paths[0], 'utf8'); }
      catch (error) {
        if (error.code !== 'ENOENT') throw error;
        liveText = '{}\n';
      }
      const patchText = fs.readFileSync(paths[1], 'utf8');
      const removeKeysText = fs.readFileSync(paths[2], 'utf8');
      process.stdout.write(applySettings(liveText, patchText, removeKeysText));
    } catch (error) {
      console.error(`VS Code settings merge failed: ${error.message}`);
      process.exitCode = 1;
    }
  }
}

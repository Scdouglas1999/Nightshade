// Minimal DOM good enough to EXECUTE the two static surfaces' render paths.
//
// Both surfaces are vanilla scripts with no module boundary, so the only way
// to test what they actually paint — rather than how their source is spelled —
// is to give them a document. This shim implements the handful of DOM features
// `applySnapshot` / `renderLinkState` / `renderGuidingPanel` /
// `renderOpsWeatherPanel` touch: element lookup by id, textContent, classList,
// attributes, and enough of the child API for the list renderers.
//
// It is deliberately not a browser. Anything a surface starts relying on that
// is missing here fails loudly rather than silently passing.
'use strict';

class ClassList {
  constructor(el) {
    this._el = el;
    this._set = new Set();
  }
  _sync() {
    this._el._className = [...this._set].join(' ');
  }
  _load(value) {
    this._set = new Set(String(value || '').split(/\s+/).filter(Boolean));
  }
  add(...names) { names.forEach((n) => this._set.add(n)); this._sync(); }
  remove(...names) { names.forEach((n) => this._set.delete(n)); this._sync(); }
  contains(name) { return this._set.has(name); }
  toggle(name, force) {
    const want = force === undefined ? !this._set.has(name) : Boolean(force);
    if (want) this._set.add(name); else this._set.delete(name);
    this._sync();
    return want;
  }
}

class Element {
  constructor(tagName, doc) {
    this.tagName = String(tagName || 'div').toUpperCase();
    this._doc = doc;
    this._className = '';
    this._classList = new ClassList(this);
    this.textContent = '';
    this.title = '';
    this.hidden = false;
    this.style = {};
    this.children = [];
    this.attributes = new Map();
    this.id = '';
  }
  get className() { return this._className; }
  set className(value) {
    this._className = String(value || '');
    this._classList._load(this._className);
  }
  get classList() { return this._classList; }
  setAttribute(name, value) { this.attributes.set(name, String(value)); }
  getAttribute(name) {
    return this.attributes.has(name) ? this.attributes.get(name) : null;
  }
  removeAttribute(name) { this.attributes.delete(name); }
  hasAttribute(name) { return this.attributes.has(name); }
  appendChild(child) { this.children.push(child); return child; }
  removeChild(child) {
    const i = this.children.indexOf(child);
    if (i >= 0) this.children.splice(i, 1);
    return child;
  }
  insertBefore(child, ref) {
    const i = ref ? this.children.indexOf(ref) : -1;
    if (i < 0) this.children.unshift(child); else this.children.splice(i, 0, child);
    return child;
  }
  remove() {
    for (const el of this._doc._byId.values()) {
      const i = el.children.indexOf(this);
      if (i >= 0) el.children.splice(i, 1);
    }
  }
  get firstChild() { return this.children[0] || null; }
  get lastChild() { return this.children[this.children.length - 1] || null; }
  set innerHTML(value) {
    if (value !== '') throw new Error('dom_shim: innerHTML only supports clearing');
    this.children = [];
  }
  get innerHTML() { return ''; }
  querySelector() { return null; }
  querySelectorAll() { return []; }
  addEventListener() {}
}

class Document {
  constructor(ids) {
    this._byId = new Map();
    for (const id of ids) {
      const el = new Element('div', this);
      el.id = id;
      this._byId.set(id, el);
    }
    this.documentElement = new Element('html', this);
  }
  getElementById(id) { return this._byId.get(id) || null; }
  createElement(tag) { return new Element(tag, this); }
  addEventListener() {}
  // No selector engine here: a surface that looks up an element by CSS
  // selector gets the same "not present" answer it would get on a page where
  // that element is missing, which every caller has to survive anyway.
  querySelector() { return null; }
  querySelectorAll() { return []; }
}

/** Build a document that answers for exactly `ids` and nothing else. */
function makeDocument(ids) { return new Document(ids); }

module.exports = { makeDocument, Element, Document };

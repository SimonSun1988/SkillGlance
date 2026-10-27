#!/usr/bin/env python3
"""Check static search metadata and CSP without network access or dependencies."""

import base64
import hashlib
import json
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit
from xml.etree import ElementTree


class Page(HTMLParser):
    def __init__(self, path):
        super().__init__()
        self.metas = {}
        self.links = []
        self.scripts = []
        self.script = None
        self.title = ""
        self.in_title = False
        self.headings = 0
        self.questions = 0
        self.examples = 0
        self.lang = None
        self.feed(path.read_text(encoding="utf-8"))

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "html":
            self.lang = attrs.get("lang")
        elif tag == "title":
            self.in_title = True
        elif tag == "meta":
            key = attrs.get("name", attrs.get("property", attrs.get("http-equiv")))
            self.metas.setdefault(key, []).append(attrs.get("content", ""))
        elif tag == "link":
            self.links.append(attrs)
        elif tag == "script":
            self.script = {"attrs": attrs, "text": ""}
        self.headings += tag == "h1"
        self.questions += tag == "details"
        self.examples += "data-nosnippet" in attrs

    def handle_data(self, data):
        if self.in_title:
            self.title += data
        if self.script is not None:
            self.script["text"] += data

    def handle_endtag(self, tag):
        if tag == "title":
            self.in_title = False
        elif tag == "script" and self.script is not None:
            self.scripts.append(self.script)
            self.script = None

    def meta(self, key):
        values = self.metas.get(key, [])
        assert len(values) == 1, f"Expected one {key} meta tag"
        return values[0]


root = Path(__file__).resolve().parents[1] / "site"
base = "https://simonsun1988.github.io/SkillGlance/"
urls = {"en": base, "zh-Hans": base + "zh-Hans/", "zh-Hant": base + "zh-Hant/"}
alternates = {**urls, "x-default": base}
titles = set()

for lang, url in urls.items():
    path = root / ("" if lang == "en" else lang) / "index.html"
    page = Page(path)
    assert page.lang == lang and page.headings == 1, lang
    assert "SkillGlance" in page.title and page.title not in titles, lang
    titles.add(page.title)
    assert page.meta("description") and page.meta("og:title") == page.title, lang
    assert page.meta("og:description") == page.meta("description"), lang
    assert page.meta("og:url") == url, lang
    assert "noindex" not in page.meta("robots"), lang
    assert [link["href"] for link in page.links if link.get("rel") == "canonical"] == [url], lang
    language_links = [link for link in page.links if link.get("rel") == "alternate"]
    assert len(language_links) == 4, lang
    assert {link["hreflang"]: link["href"] for link in language_links} == alternates, lang
    assert page.questions >= 10 and page.examples == 4, lang
    image = base + "assets/social-card.jpg"
    assert page.meta("og:image") == page.meta("twitter:image") == image, lang
    assert page.meta("og:image:alt") and page.meta("twitter:image:alt"), lang
    assert page.meta("og:image:width") == "1200" and page.meta("og:image:height") == "630", lang
    assert page.meta("twitter:card") == "summary_large_image", lang
    blocks = [script for script in page.scripts if script["attrs"].get("type") == "application/ld+json"]
    assert len(blocks) == 1, lang
    block = blocks[0]["text"]
    graph = json.loads(block)["@graph"]
    webpage, app = graph
    assert webpage["@type"] == "WebPage" and webpage["url"] == url, lang
    assert webpage["inLanguage"] == lang and webpage["description"] == page.meta("description"), lang
    assert app["@type"] == "SoftwareApplication" and app["name"] == "SkillGlance", lang
    assert app["softwareVersion"] == "0.2.0" and app["image"] == image, lang
    assert set(app["inLanguage"]) == set(urls), lang
    assert webpage["mainEntity"]["@id"] == app["@id"], lang
    digest = base64.b64encode(hashlib.sha256(block.encode()).digest()).decode()
    csp = page.meta("Content-Security-Policy")
    assert f"'sha256-{digest}'" in csp and "'unsafe-inline'" not in csp, lang

tree = ElementTree.parse(root / "sitemap.xml")
namespace = {"s": "http://www.sitemaps.org/schemas/sitemap/0.9", "x": "http://www.w3.org/1999/xhtml"}
entries = tree.findall("s:url", namespace)
assert len(entries) == 3
assert {entry.findtext("s:loc", namespaces=namespace) for entry in entries} == set(urls.values())
for entry in entries:
    links = entry.findall("x:link", namespace)
    assert len(links) == 4
    assert {link.attrib["hreflang"]: link.attrib["href"] for link in links} == alternates
    url = entry.findtext("s:loc", namespaces=namespace)
    relative = urlsplit(url).path.removeprefix("/SkillGlance/")
    assert (root / relative / "index.html").is_file()

assert (root / "assets/social-card.jpg").read_bytes().startswith(b"\xff\xd8")
print("PASS: three languages, canonical/hreflang, sitemap, JSON-LD, CSP hashes and sharing metadata.")

"""Offline extraction tests. Run with Python 3 from any working directory."""
import importlib.util
import json
from pathlib import Path
import sys
import unittest

sys.dont_write_bytecode = True
root = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('generate_completion', root / 'generate-completion.py')
generator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(generator)


class ExtractionTest(unittest.TestCase):
    def test_schema_refs_branches_and_deprecation(self):
        url = 'https://example.invalid/schema.json'
        external = 'https://example.invalid/child.json'
        document = {
            'properties': {
                'old': {'deprecated': True, 'properties': {'leak': {}}},
                'services': {'patternProperties': {'.*': {'$ref': '#/$defs/service'}}},
                'shared': {'$ref': 'child.json'},
            },
            '$defs': {'service': {'allOf': [{'properties': {'image': {'type': 'string'}}},
                        {'properties': {'mode': {'anyOf': [{'enum': ['a', 'b']},
                         {'deprecated': True, 'enum': ['obsolete']}]}}}],
                        'properties': {'loop': {'$ref': '#/$defs/service'}}}},
        }
        entries, cycles = generator.schema_entries({url: document, external: {'properties': {'port': {'type': 'integer'}}}}, url)
        by_key = {(e['word'], e['context']): e for e in entries}
        self.assertNotIn('old', {e['word'] for e in entries})
        self.assertNotIn('leak', {e['word'] for e in entries})
        self.assertIn(('image', 'services.*'), by_key)
        self.assertEqual(by_key['mode', 'services.*']['values'], ['a', 'b'])
        self.assertIn(('port', 'shared'), by_key)
        self.assertEqual(len(cycles), 1)
        with self.assertRaisesRegex(ValueError, 'pinned schema'):
            generator.schema_entries({url: document}, url)

    def test_nginx_commercial_filter_and_syntax(self):
        tree = generator.parse_xml('''<module name="Module test" link="/en/docs/test.html">
          <directive name="keep"><syntax>on | off</syntax><context>http</context>
            <para>Sets caching.</para><para>Some parameters require a commercial subscription.</para></directive>
          <directive name="paid"><para>This directive is available as part of our
            <commercial_version>commercial subscription</commercial_version>.</para></directive></module>''')
        entries = generator.nginx_entries(tree)
        self.assertEqual([e['word'] for e in entries], ['keep'])
        self.assertEqual(entries[0]['syntax'], 'keep on | off')

    def test_systemd_parameters_sections_and_versions(self):
        tree = generator.parse_xml('''<refentry xmlns:xi="http://www.w3.org/2001/XInclude">
          <refsect1><title>Options</title><variablelist><varlistentry>
            <term><varname>MemoryMax=<replaceable>bytes</replaceable></varname></term>
            <listitem><para>Memory limit.</para><xi:include href="version-info.xml" xpointer="v231"/></listitem>
          </varlistentry></variablelist></refsect1></refentry>''')
        entry = generator.systemd_entries(tree, 'systemd.resource-control.xml')[0]
        self.assertEqual((entry['word'], entry['context'], entry['version']), ('MemoryMax', 'Service', '231'))

    def test_real_snapshots(self):
        for name, required in {
            'opencode': {'providers', 'agents', 'permissions'},
            'compose': {'services', 'image', 'ports', 'healthcheck'},
            'nginx': {'proxy_pass', 'ssl_certificate', 'limit_req'},
            'systemd-service': {'ExecStart', 'MemoryMax', 'LimitNOFILE', 'WantedBy'},
            'tomcat': {'Server', 'Connector', 'SSLHostConfig', 'Certificate', 'maxThreads', 'port'},
            'redis': {'bind', 'port', 'maxmemory', 'appendonly', 'replicaof', 'include'},
            'dockerd-cli': {'--data-root', '--host', '-H', '--validate', '--log-opt'},
            'docker-daemon': {'data-root', 'hosts', 'log-opts', 'runtimes', 'proxies', 'builder'},
            'http-headers': {'Content-Type', 'Authorization', 'Cache-Control', 'X-Forwarded-For', 'Access-Control-Allow-Origin'},
        }.items():
            entries = json.loads((root / 'completion/generated' / (name + '.json')).read_text())['entries']
            self.assertLessEqual(required, {e['word'] for e in entries})
            self.assertEqual(len(entries), len({(e['word'], e.get('context'), e.get('module')) for e in entries}))

    def test_tomcat_element_and_attribute_roles(self):
        doc = generator.parse_xml('''<document url="http.html"><body>
          <section name="Introduction"><p>HTTP Connector.</p></section>
          <section name="Attributes"><attribute name="maxThreads"><p>Threads.</p></attribute>
            <attribute name="old"><p>This attribute is deprecated.</p></attribute></section>
          <section name="SSL Support - Certificate"><attribute name="certificateFile"><p>PEM file.</p></attribute></section>
        </body></document>''')
        entries = generator.tomcat_entries(doc, {'component': 'Connector', 'ref': '10.1.61', 'file': 'http.xml'})
        words = {e['word']: e for e in entries}
        self.assertEqual(words['Connector']['kind'], 'element')
        self.assertEqual(words['maxThreads']['kind'], 'attribute')
        self.assertEqual(words['certificateFile']['context'], 'Certificate / SSL Support - Certificate')
        self.assertNotIn('old', words)

    def test_redis_registry_intersection(self):
        registry = 'createIntConfig("port", ...)\ncreateIntConfig("maxmemory", ...)\n!strcasecmp(argv[0],"include")'
        text = '# prose is not a config\n# maxmemory is a setting\n# include /etc/redis/*.conf\nport 6379\n# maxmemory 2gb\n# GET mykey\n'
        entries = generator.redis_entries(text, registry, {'ref': 'test', 'url': 'https://example.invalid/redis.conf'})
        words = {e['word']: e for e in entries}
        self.assertEqual(set(words), {'port', 'maxmemory', 'include'})
        self.assertEqual(words['maxmemory']['syntax'], 'maxmemory 2gb')

    def test_dockerd_help_wrapping_defaults_and_aliases(self):
        text = '''Options:
  -H, --host list          Daemon sockets
                          to listen on (default [])
      --log-level string  Log level ("debug"|"info") (default "info")
      --debug             Enable debug mode
'''
        entries = generator.dockerd_help_entries(text, {'ref': 'test', 'url': 'local:fixture'})
        words = {e['word']: e for e in entries}
        self.assertEqual(words['--host']['default'], '[]')
        self.assertEqual(words['-H']['default'], '[]')
        self.assertIn('to listen on', words['-H']['description'])
        self.assertEqual(words['--log-level']['values'], ['debug', 'info'])
        self.assertEqual(words['--log-level']['default'], '"info"')
        self.assertEqual(words['--debug']['type'], ['boolean'])
        self.assertNotIn('default', words['--debug'])

    def test_docker_struct_public_fields_and_nested_context(self):
        text = '''type Config struct {
    Common
    Hidden string `json:"internal"`
    Ignored string `json:"-"`
    Proxies Proxy `json:"proxies"`
    Runtimes map[string]*Runtime `json:"runtimes"`
}
type Common struct {
    Hosts []string `json:"hosts"`
}
type Proxy struct {
    HTTP string `json:"http-proxy"`
}
type Runtime struct {
    Path string `json:"path"`
}
'''
        entries = generator.docker_daemon_entries(
            [({'package': 'config', 'url': 'fixture'}, text)],
            [{'word': '--host', 'description': 'Listen'}, {'word': '--add-runtime', 'description': 'Runtime'}])
        keys = {(e['word'], e['context']) for e in entries}
        self.assertIn(('hosts', '$'), keys)
        self.assertIn(('http-proxy', 'proxies'), keys)
        self.assertIn(('path', 'runtimes.*'), keys)
        self.assertFalse({'internal', '-'} & {e['word'] for e in entries})

    def test_mdn_headers_and_status(self):
        source = {'header': 'X-Test', 'file': 'fixture.md', 'ref': 'fixed'}
        text = '''---
slug: Web/HTTP/Reference/Headers/X-Test
status:
  - non-standard
---

The **X-Test** {{Glossary("request header")}} carries a [value](https://example.invalid/).

<table><tr><th scope="row">Header type</th><td>{{Glossary("Request header")}}</td></tr></table>

## Syntax

```http
X-Test: <value>
Other: wrong
```

## Examples

```http
X-Test: example
```
'''
        entry = generator.mdn_header_entries(text, source)[0]
        self.assertEqual(entry['word'], 'X-Test')
        self.assertEqual(entry['context'], 'Request header')
        self.assertEqual(entry['syntax'], 'X-Test: <value>')
        self.assertEqual(entry['description'], 'The X-Test request header carries a value.')
        self.assertIn('非标准', entry['module'])
        for status in ('experimental', 'deprecated'):
            self.assertEqual(generator.mdn_header_entries(text.replace('non-standard', status), source), [])
        with self.assertRaisesRegex(ValueError, 'slug mismatch'):
            generator.mdn_header_entries(text, {**source, 'header': 'Other'})

    def test_real_http_header_snapshots(self):
        entries = json.loads((root / 'completion/generated/http-headers.json').read_text())['entries']
        words = {e['word']: e for e in entries}
        self.assertEqual(len(words), 74)
        self.assertFalse({'X-XSS-Protection', 'Expect-CT', 'No-Vary-Search', 'Permissions-Policy', ':authority'} & words.keys())
        custom = json.loads((root / 'completion/custom/http-headers.json').read_text())
        self.assertEqual(set(words), {e['word'] for e in custom}, 'custom must not reintroduce filtered MDN headers')
        for entry in entries:
            self.assertTrue(entry['description'] and entry['syntax'] and entry['context'])
            self.assertNotIn('{{', entry['description'])
        self.assertIn('非标准', words['X-Forwarded-For']['module'])
        self.assertIn('Content-Type: <media-type>', words['Content-Type']['syntax'])

    def test_real_docker_boundaries(self):
        import re
        entries = json.loads((root / 'completion/generated/dockerd-cli.json').read_text())['entries']
        help_text = (root / 'completion/sources/dockerd/dockerd-help.txt').read_text()
        headers = set(re.findall(r'^\s*(?:-\w,\s*)?(--[a-z][a-z0-9-]*)\b', help_text, re.M))
        self.assertEqual(headers, {e['word'] for e in entries if e['word'].startswith('--')})
        daemon = json.loads((root / 'completion/generated/docker-daemon.json').read_text())['entries']
        keys = {(e['word'], e['context']) for e in daemon}
        self.assertLessEqual({('gc', 'builder'), ('base', 'default-address-pools[]'),
                             ('path', 'runtimes.*'), ('http-proxy', 'proxies')}, keys)
        self.assertFalse({'help', 'version', 'validate', 'config-file', 'host', 'log-opt', 'add-runtime'}
                         & {e['word'] for e in daemon})


if __name__ == '__main__':
    unittest.main()

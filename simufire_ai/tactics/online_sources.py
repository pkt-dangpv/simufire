"""Explicit online primary-source lookup. Downloads are untrusted candidates only.

No browser scripts, model prompts or source instructions are executed. Search is
limited to publisher indexes, not a general web engine. No simulation data is sent.
"""
import hashlib
import http.client
import ipaddress
import json
import socket
import ssl
import time
from datetime import datetime, timezone
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urljoin, urlsplit

ALLOWED_HOSTS = frozenset({
    'www.godiva.co.uk','www.rosenbauer.com','awg-fittings.com',
    'www.awg-fittings.com','products.awg-fittings.com','produkte.awg-fittings.com',
    'gollmer-hummel.com','www.leader-group.company','www.nist.gov',
    'nvlpubs.nist.gov','tsapps.nist.gov','www.ceisguadalajara.es','ceis.antiun.net',
    'guiatacticavisual.wordpress.com',
})
INDEXES = {
    'godiva':'https://www.godiva.co.uk/resource-center/?documenttype=all&productcategory=all&refine=prima',
    'rosenbauer':'https://www.rosenbauer.com/en/products/fire-fighting-systems-and-body-components/built-in-extinguishing-systems/truck-mounted-pumps',
    'awg':'https://awg-fittings.com/en/services-en/downloads-en',
    'hose':'https://gollmer-hummel.com/en/fire-hoses',
    'leader':'https://www.leader-group.company/fr/materiel-lutte-incendie/ventilateurs-lutte-incendie',
    'nist':'https://www.nist.gov/el/fire-research-division-73300/firegov-fire-service',
    'guadalajara':'https://www.ceisguadalajara.es/documentacion/domcumentacion-2/',
    'gtv':'https://guiatacticavisual.wordpress.com/',
}
MAX_BYTES = 16*1024*1024
TIMEOUT_S = 25
MAX_REDIRECTS = 3


def validate_url(url):
    if not isinstance(url,str) or len(url)>2048 or any(ord(c)<33 or ord(c)>126 for c in url):
        raise ValueError('URL inválida; se requiere HTTPS y URL ASCII codificada')
    try:
        parts = urlsplit(url)
        port = parts.port
    except ValueError as error: raise ValueError('URL inválida') from error
    if (parts.scheme!='https' or parts.hostname not in ALLOWED_HOSTS or
        port not in (None,443) or parts.username is not None or parts.password is not None or
        parts.fragment or '\\' in url):
        raise ValueError('URL fuera de las fuentes públicas autorizadas')
    return parts


def public_addresses(host):
    addresses = list(dict.fromkeys(info[4][0] for info in socket.getaddrinfo(host,443,type=socket.SOCK_STREAM)))
    if not addresses or any(not ipaddress.ip_address(a).is_global or ipaddress.ip_address(a).is_multicast for a in addresses):
        raise ValueError('La fuente no resuelve exclusivamente a direcciones públicas')
    return addresses


class _PublicHTTPS(http.client.HTTPSConnection):
    def __init__(self,host,addresses,timeout):
        super().__init__(host,timeout=timeout,context=ssl.create_default_context())
        self.addresses = addresses

    def connect(self):
        # Connect to the checked IP, preserve hostname for TLS verification and SNI.
        # Do not inherit proxies, cookies or credentials from the environment.
        last_error = None
        for address in self.addresses:
            try:
                raw = socket.create_connection((address,443),timeout=self.timeout)
                try: self.sock = self._context.wrap_socket(raw,server_hostname=self.host)
                except BaseException:
                    raw.close(); raise
                return
            except OSError as error: last_error = error
        raise OSError('No se pudo conectar a la fuente pública') from last_error


def _download(url):
    started = time.monotonic()
    for hop in range(MAX_REDIRECTS+1):
        parts = validate_url(url)
        addresses = public_addresses(parts.hostname)
        remaining = TIMEOUT_S-(time.monotonic()-started)
        if remaining<=0: raise ValueError('Tiempo de consulta agotado')
        connection = _PublicHTTPS(parts.hostname,addresses,remaining)
        try:
            path = parts.path or '/'
            if parts.query: path += '?'+parts.query
            connection.request('GET',path,headers={'User-Agent':'SimuFireAI-reference-reader/0.1',
                'Accept':'text/html,application/pdf','Accept-Encoding':'identity'})
            response = connection.getresponse()
            if response.status in (301,302,303,307,308):
                location = response.getheader('Location')
                if not location or hop==MAX_REDIRECTS: raise ValueError('Redirección sin destino o límite excedido')
                url = urljoin(url,location)
                validate_url(url)
                continue
            if response.status!=200: raise ValueError('La fuente devolvió HTTP '+str(response.status))
            media_type = response.getheader('Content-Type','').split(';')[0].strip().lower()
            if media_type not in ('text/html','application/pdf'): raise ValueError('Tipo de documento no admitido')
            if response.getheader('Content-Encoding','identity').lower() not in ('','identity'):
                raise ValueError('Documento comprimido no admitido')
            chunks = []; total = 0
            while True:
                remaining = TIMEOUT_S-(time.monotonic()-started)
                if remaining<=0: raise ValueError('Tiempo de descarga agotado')
                if connection.sock is not None: connection.sock.settimeout(remaining)
                chunk = response.read(min(65536,MAX_BYTES+1-total))
                if not chunk: break
                chunks.append(chunk); total += len(chunk)
                if total>MAX_BYTES: raise ValueError('Documento demasiado grande')
            return url,media_type,b''.join(chunks)
        finally: connection.close()
    raise ValueError('Redirecciones agotadas')


def fetch_document(url,*,online=False,evidence_dir=None):
    if not online: raise ValueError('Internet desactivado: activar online explícitamente')
    validate_url(url)
    if evidence_dir is None: raise ValueError('Se requiere directorio de evidencias')
    final_url,media_type,data = _download(url)
    validate_url(final_url)
    if not data: raise ValueError('Documento vacío')
    if media_type=='application/pdf' and not data.startswith(b'%PDF-'):
        raise ValueError('La respuesta no contiene un PDF')
    digest = hashlib.sha256(data).hexdigest()
    receipt = {'status':'unverified_candidate','requested_url':url,'final_url':final_url,
        'retrieved_at_utc':datetime.now(timezone.utc).isoformat(),'media_type':media_type,
        'bytes':len(data),'sha256':digest,'usable_for_calculation':False,
        'automatic_tactical_rule':False,'untrusted_content':True,'body_file':digest+'.bin'}
    directory = Path(evidence_dir)
    directory.mkdir(parents=True,exist_ok=True)
    body = directory/receipt['body_file']
    try:
        with body.open('xb') as stream: stream.write(data)
    except FileExistsError:
        if body.read_bytes()!=data: raise ValueError('Conflicto en evidencia archivada')
    # Every fetch has its own receipt; repeated retrievals preserve their dates.
    filename = digest+'_'+str(time.time_ns())+'.json'
    with (directory/filename).open('x',encoding='utf-8') as stream:
        json.dump(receipt,stream,ensure_ascii=False,indent=2)
    return receipt,data


class _Links(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.links = []; self.current = None; self.ignored = 0
    def handle_starttag(self,tag,attrs):
        if tag in ('script','style'): self.ignored += 1
        if not self.ignored and tag=='a':
            self.current = [dict(attrs).get('href',''),[]]
    def handle_endtag(self,tag):
        if tag in ('script','style'): self.ignored = max(0,self.ignored-1)
        if tag=='a' and self.current is not None:
            self.links.append((self.current[0],' '.join(self.current[1])))
            self.current = None
    def handle_data(self,data):
        if not self.ignored and self.current is not None: self.current[1].append(data)


def matching_links(html,base_url,query):
    from tactics.catalogue import words
    tokens = words(query)
    if not tokens: raise ValueError('Consulta sin términos de búsqueda')
    parser = _Links(); parser.feed(html)
    found = []; seen = set()
    for href,title in parser.links:
        url = urljoin(base_url,href).split('#')[0]
        try: validate_url(url)
        except ValueError: continue
        title = ' '.join(title.split())[:300]
        haystack = words(title+' '+unquote(urlsplit(url).path))
        if url in seen or not all(t in haystack for t in tokens): continue
        seen.add(url)
        found.append({'title':title or urlsplit(url).path[-1],'url':url,
                      'status':'unverified_candidate','usable_for_calculation':False})
    return found[:20]


def search_primary_index(query,source,*,online=False,evidence_dir=None):
    if source not in INDEXES: raise ValueError('Índice de fuente desconocido')
    if not isinstance(query,str) or not query.strip() or len(query)>160:
        raise ValueError('La consulta debe contener entre 1 y 160 caracteres')
    receipt,data = fetch_document(INDEXES[source],online=online,evidence_dir=evidence_dir)
    if receipt['media_type']!='text/html': raise ValueError('El índice no es HTML')
    matches = matching_links(data.decode('utf-8',errors='replace'),receipt['final_url'],query)
    return {'query':query,'source':source,'search_scope':'links_on_publisher_index',
            'status':'candidates_found' if matches else 'no_index_matches',
            'coverage':'One index page; no JavaScript, pagination or whole-web search. No matches does not prove absence.',
            'receipt':receipt,'matches':matches,'catalog_modified':False,
            'usable_for_calculation':False,'expert_review_required':True}

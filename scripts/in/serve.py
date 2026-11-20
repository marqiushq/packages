#!/usr/bin/env python3
"""The repositories' stand-in host for tests before publishing: serves a site folder over HTTPS
at the root of a host or under a path (https://packages.marqius.com/, or
https://marqiushq.github.io/packages/) to containers that resolve the host name to this one
and trust the test certificate authority.

    serve.py ROOT PREFIX CERT KEY       (PREFIX is / for a host's root)

ROOT may be a link; it is followed on every request, so a test can switch the site it serves
(an older release, then a newer one) while clients keep running. Every request is logged.
"""
import http.server
import os
import ssl
import sys

root, prefix, cert, key = sys.argv[1:5]
prefix = "/" + prefix.strip("/")
if prefix == "/":
    prefix = ""


class Handler(http.server.SimpleHTTPRequestHandler):
    protocol_version = "HTTP/1.1"  # keep-alive, as a real host does

    def translate_path(self, path):
        path = path.split("?", 1)[0].split("#", 1)[0]
        if path != prefix and not path.startswith(prefix + "/"):
            return "/nonexistent"
        self.directory = os.path.realpath(root)
        return super().translate_path(path[len(prefix):] or "/")

    def log_message(self, fmt, *args):
        sys.stderr.write("%s %s\n" % (self.address_string(), fmt % args))


class Server(http.server.ThreadingHTTPServer):
    def shutdown_request(self, request):
        # end TLS properly (close_notify): OpenSSL 3 clients, apt 3 among them, treat a bare
        # close as an error
        try:
            request.unwrap()
        except (OSError, ValueError):
            pass
        super().shutdown_request(request)


context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain(cert, key)
server = Server(("0.0.0.0", 443), Handler)
server.socket = context.wrap_socket(server.socket, server_side=True)
server.serve_forever()

"""
Filters stdin to stdout, replacing any arguments with values supplied on the command line.
E.g.: template foo=bar will translate "$foo" to "bar" wherever it appears in the input.
"""

from string import Template
import sys

args = {}
for a in sys.argv[1:]:
    name, value = a.split("=")
    args[name] = value

try:
    while 1:
        line = input()
        print(Template(line).safe_substitute(args))  # noqa: T201
except EOFError:
    pass

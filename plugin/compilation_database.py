import vim
import re
import json
from os import path


def get_entry_by_filename(entries, fn, key=None):
    """Search for an entry in entries where key(entry['file']) matches
    key(fn) and returns it. If key is None than file names are compared
    directly. Returns None if none is found."""

    if key is None:
        key = lambda x: x

    for e in entries:
        if key(fn) == key(e['file']):
            return e

    return None

def find_entry(entries, fn):
    """Find an entry that matches the given filename fn more or less."""

    entry = get_entry_by_filename(entries, curr_file)
    if entry is not None:
        return entry

    key = lambda fn: path.splitext(fn)[0]
    entry = get_entry_by_filename(entries, curr_file, key)
    if entry is not None:
        return entry

    key = lambda fn: path.basename(path.splitext(fn)[0])
    entry = get_entry_by_filename(entries, curr_file, key)
    if entry is not None:
        return entry

    return None

def option(match, directory):
    return match.group(0) if match.group(1) != 'I' else '-I' + path.join(directory, match.group(2))

def arguments(input):
    return lambda e: map(re.compile(e).match, input)

def command(input):
    return lambda e: re.finditer(e, input)


ccd = vim.eval("l:ccd")
with open(ccd) as database:
    entries = json.load(database)

    curr_file = vim.eval("expand('%:p')")
    entry = find_entry(entries, curr_file)

    if entry is not None:
        input = arguments(entry['arguments']) if 'arguments' in entry else command(entry['command'])

        filter_expr = r'-(D|I|std|isystem)\s*([^\s]+)'
        opts = [option(x, entry['directory']) for x in input(filter_expr) if x]

        vim.command("let l:clang_options = '" + ' '.join(opts) + "'")

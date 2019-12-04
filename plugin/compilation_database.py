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

def parse_arguments(arguments_list, directory):
    match = re.compile(r'-(D|I|std|isystem)\s*([^\s]+)').match
    return [x.group(0) if x.group(1) != 'I' else '-I' + path.join(directory, x.group(2))
            for x in map(match, arguments_list) if x]

def parse_command(command_string, directory):
    opts = []

    for result in re.finditer(r'-D\s*[^\s]+', command_string):
        opts.append(result.group(0))
    for result in re.finditer(r'-std\s*[^\s]+', command_string):
        opts.append(result.group(0))
    for result in re.finditer(r'-isystem\s*[^\s]+', command_string):
        opts.append(result.group(0))
    for result in re.finditer(r'-I\s*([^\s]+)', command_string):
        opts.append('-I' + path.join(directory, result.group(1)))

    return opts


ccd = vim.eval("l:ccd")
with open(ccd) as database:
    entries = json.load(database)

    curr_file = vim.eval("expand('%:p')")
    entry = find_entry(entries, curr_file)

    if entry is not None:
        if 'arguments' in entry:
            opts = parse_arguments(entry['arguments'], entry['directory'])
        else:
            opts = parse_command(entry['command'], entry['directory'])

        vim.command("let l:clang_options = '" + ' '.join(opts) + "'")

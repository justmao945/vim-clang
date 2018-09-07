import vim
import re
import json
from os import path

curr_file = vim.eval("expand('%:p')")
curr_file_noext = path.splitext(curr_file)[0]

ccd = vim.eval("l:ccd")
opts = []

with open(ccd) as database:
    # Search for the right entry in the database matching file names
    for d in json.load(database):
        # This is an entry without a file attribute
        if 'file' not in d:
            continue

        # This entry is about a different file. We consider file names
        # without extension to handle header files which do not have
        # an entry in the database.
        d_file_noext = path.splitext(d['file'])[0]
        if d_file_noext != curr_file_noext:
            continue

        for result in re.finditer(r'-D\s*[^\s]+', d['command']):
            opts.append(result.group(0))
        for result in re.finditer(r'-isystem\s*[^\s]+', d['command']):
            opts.append(result.group(0))
        for result in re.finditer(r'-I\s*([^\s]+)', d['command']):
            opts.append('-I' + path.join(d['directory'], result.group(1)))
        break

vim.command("let l:clang_options = '" + ' '.join(opts) + "'")

import vim
import re
import json
from os import path

current = vim.eval("expand('%:p')")
ccd = vim.eval("l:ccd")
opts = []

with open(ccd) as database:
    data = json.load(database)

    for d in data:
        # hax for headers
        fmatch = re.search(r'(.*)\.(\w+)$', current)
        dmatch = re.search(r'(.*)\.(\w+)$', d['file'])

        if fmatch.group(1) == dmatch.group(1):
            for result in re.finditer(r'-D\s*[^\s]+', d['command']):
                opts.append(result.group(0))
            for result in re.finditer(r'-isystem\s*[^\s]+', d['command']):
                opts.append(result.group(0))
            for result in re.finditer(r'-I\s*([^\s]+)', d['command']):
                opts.append('-I' + path.join(d['directory'], result.group(1)))
            break

vim.command("let l:clang_options = '" + ' '.join(opts) + "'")

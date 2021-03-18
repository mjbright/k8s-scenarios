#!/usr/bin/env python3

import sys
import subprocess

# -- functions: --------------------------------------

def die(msg):
    sys.stderr.write(f'die: {msg}\n')
    sys.exit(1)

# -- args: -------------------------------------------

DEBUG=False
resource=None

for a in range( 1, len(sys.argv) ):
    arg = sys.argv[a]
    if arg == "-d":
        DEBUG=True
        continue
    resource = arg

if not resource:
    die("Missing <resource> argument")


# -- main: -------------------------------------------

#command = ['ls', '-l']
#command = f'kubectl explain {resource} --recursive'

#command = ('echo "this echo command' + ' has subquotes, spaces,\n\n" && echo "and newlines!"')
command = f'kubectl explain {resource} --recursive'

print(command)
p = subprocess.Popen(command, universal_newlines=True, 
        shell=True, stdout=subprocess.PIPE, 
        stderr=subprocess.PIPE)

text = p.stdout.read()
retcode = p.wait()

IN_FIELDS_LIST=False

TEXT_TAB=3

lastLine=''
lineno=0
parents=['']
lastFieldname=''
field=''
fieldName=''

def show_parents(indent):
    parents_str = get_parents(indent)
    return f'parents[:indent]:{parents_str}'

def get_parents(indent):
    parents_str = '.'.join(parents[:indent])
    parents_str = parents_str.lstrip(".")
    if parents_str != '':
        parents_str += '.'
    return parents_str
    #return '.'.join(parents[:indent])

for line in text.split('\n'):
    lineno += 1

    if len(line) == 0:
        continue

    if line.find('FIELD') == 0:
        IN_FIELDS_LIST=True
        lastLine=''
        lastIndent=1
        continue

    if IN_FIELDS_LIST:
        if DEBUG: print(f"<{line}")
        field = line.lstrip()
        lastFieldname=fieldName

        tab_pos = field.find('\t')
        fieldName = field[ : tab_pos ]
        line_indent_pos = len(line) - len(field)
        indent = int( line_indent_pos / TEXT_TAB )

        if indent < lastIndent:
            parents_str = get_parents(indent)
            parents = parents[:indent] # shorten list
        elif indent == lastIndent:
            parents_str = get_parents(indent)
        elif indent > lastIndent:
            if indent > lastIndent+1:
                print("----")
                print(f"lastline: {lastLine}")
                print(f"line:     {line}")
                die(f"TO IMPLEMENT[indent spaces:{indent_sp}] indent:{indent} lastIndent:{lastIndent} on line {lineno}")

            if indent > (len(parents)-1):
                if DEBUG: print(f"Adding indent:{indent} last:{lastIndent} {lastFieldname} onto parent list")
                parents.append(lastFieldname)
                if DEBUG: show_parents(indent)
            else:
                if DEBUG: print(f"Updating indent:{indent} last:{lastIndent} {lastFieldname} on parent list")
                parents[indent] = lastFieldname
                parents = parents[:indent] # shorten list
                if DEBUG: show_parents(indent)

            parents_str = get_parents(indent)
        else:
            parents_str = get_parents(lastIndent)

        beg='-- '
        if DEBUG: beg=f'-[{indent}]- '
        print(f'{beg}{parents_str}{field}')

        lastLine=line
        lastIndent=indent

#print(text);
if retcode != 0:
    print(f'Command exited with code {retcode}\n')



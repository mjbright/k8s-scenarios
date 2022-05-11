#!/usr/bin/env python3

import sys
import subprocess

DEBUG=False
resource=None
grep=None
#command = ['ls', '-l']
#command = f'kubectl explain {resource} --recursive'
#command = ('echo "this echo command' + ' has subquotes, spaces,\n\n" && echo "and newlines!"')

# -- Function definitions: -------------------------------------------

def die(msg):
    sys.stderr.write(f'die: {msg}\n')
    sys.exit(1)


def show_parents(parents, indent):
    parents_str = get_parents(parents, indent)
    return f'parents[:indent]:{parents_str}'

def get_parents(parents, indent):
    parents_str = '.'.join(parents[:indent])
    parents_str = parents_str.lstrip(".")
    if parents_str != '':
        parents_str += '.'
    return parents_str
    #return '.'.join(parents[:indent])

def get_all_resources():
    command = f'kubectl api-resources -o name'
    if DEBUG: print(command)

    p = subprocess.Popen(command, universal_newlines=True, 
            shell=True, stdout=subprocess.PIPE, 
            stderr=subprocess.PIPE)

    text = p.stdout.read()
    retcode = p.wait()
    return text.split('\n')

def explain_resource(resource, grep=None):
    command = f'kubectl explain {resource} --recursive'
    if DEBUG: print(command)

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
                parents_str = get_parents(parents, indent)
                parents = parents[:indent] # shorten list
            elif indent == lastIndent:
                parents_str = get_parents(parents, indent)
            elif indent > lastIndent:
                if indent > lastIndent+1:
                    print("----")
                    print(f"lastline: {lastLine}")
                    print(f"line:     {line}")
                    die(f"TO IMPLEMENT[indent spaces:{indent_sp}] indent:{indent} lastIndent:{lastIndent} on line {lineno}")
    
                if indent > (len(parents)-1):
                    if DEBUG: print(f"Adding indent:{indent} last:{lastIndent} {lastFieldname} onto parent list")
                    parents.append(lastFieldname)
                    if DEBUG: show_parents(parents, indent)
                else:
                    if DEBUG: print(f"Updating indent:{indent} last:{lastIndent} {lastFieldname} on parent list")
                    parents[indent] = lastFieldname
                    parents = parents[:indent] # shorten list
                    if DEBUG: show_parents(parents, indent)
    
                parents_str = get_parents(parents, indent)
            else:
                parents_str = get_parents(parents, lastIndent)
    
            beg=f'[{resource:20s}] -- '
            full_path=(f'{parents_str}{field}')

            # Pass to next line before outputting current match:
            lastLine=line
            lastIndent=indent

            # Skip non-matching lines if -grep specified:
            if grep and full_path.find(grep.lower()) == -1:
                continue

            if DEBUG: beg=f'-[{indent}]- '
            print(f'{beg}{full_path}')
    
    
    #print(text);
    if retcode != 0:
        print(f'Command exited with code {retcode}\n')
    
# -- Args: -----------------------------------------------------------

#for a in range( 1, len(sys.argv) ):

a=0
while a < (len(sys.argv)-1):
    a+=1
    arg = sys.argv[a]
    if DEBUG: print(f'sys.argv[{a}]={arg}')

    if arg == "-d":
        DEBUG=True
        continue

    if arg == "-grep":
        a+=1
        grep=sys.argv[a]
        continue

    print(f'resource = "{arg}"')
    resource = arg

#if not resource:
    #die("Missing <resource> argument")


# -- Main: -----------------------------------------------------------

if resource:
    explain_resource(resource, grep)
else:
    for resource in get_all_resources():
        explain_resource(resource, grep)
    

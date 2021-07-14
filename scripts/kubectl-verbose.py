#!/usr/bin/env python3

import os,sys
import subprocess
import json

STRIP_DATE=True

def do(cmd):
    p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    (std, err) = p.communicate()
    # rc = p.returncode

    output = std.decode("utf-8"); lines = output.split('\n'); ret_stdout = '\n'.join(lines)
    stderr = err.decode("utf-8"); lines = stderr.split('\n'); ret_stderr = '\n'.join(lines)

    return (ret_stdout, ret_stderr)

def writefile(path, mode='w', text='hello world\n'):
    ofd = open(path, mode)
    ofd.write(text)
    ofd.close()

#os.system('clear')
#os.system('date')
#op = do('ls -al')
#print(op)

command = f'kubectl -v 10 {" ".join(sys.argv[1:])}'
#print(f'-- {command}')
(op, err) = do(command)

HOME=os.getenv('HOME')
writefile(f'{HOME}/tmp/kubectl-verbose.py.op', 'w', str(op))
writefile(f'{HOME}/tmp/kubectl-verbose.py.err', 'w', str(err))

IN_HEADERS=0
IN_BODY=0

for line in err.split('\n'):

    if STRIP_DATE:
        oline=line[ 2+line.find('] '): ]
    else:
        oline=line

    if "] Config loaded from file" in line: print(oline)
    if "] curl -k -v"              in line: print(oline)
    if "] GET https://"            in line: print(oline)

    if "] Response Headers:"       in line:
        print()
        IN_HEADERS=1
        IN_BODY=0

    if "] Response Body: "         in line:
        print()
        print("Response Body:")
        IN_BODY=1
        IN_HEADERS=0
        body = err[ 17+err.find("] Response Body: "): ]
        #print(body[:20])
        body_json = json.loads( body )
        #body = json.dumps(body_json, skipkeys = True, allow_nan = True, indent = 6, separators =(". ", " = "))
        body = json.dumps(body_json, allow_nan = True, indent = 4)
        print(body)
        pass

    if IN_HEADERS == 1:
        print(oline)

print()
print(op)

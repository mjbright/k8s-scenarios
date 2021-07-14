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

def dump_resource( resource, prefix='' ):
    for key in resource:
        #print(f'KEY: {key}')
        if prefix == '':
            new_key=key
        else:
            new_key=f'{prefix}.{key}'

        value = resource[key]
        if isinstance(value, type(None)):
            print(f'{new_key}: {value}')
        elif isinstance(value, str):
            print(f'{new_key}: {value}')
        elif isinstance(value, bool):
            print(f'{new_key}: {value}')
        elif isinstance(value, int):
            print(f'{new_key}: {value}')
        elif isinstance(value, dict):
            dump_resource( value, prefix=new_key )
        elif isinstance(value, list):
            count=0
            for item in value:
                dump_resource( item, prefix=f'{new_key}[{count}]' )
                count=count+1
        else:
            print(f'??? {type(value)} - {new_key}: {value}')
            sys.exit(1)

#os.system('clear')
#os.system('date')
#op = do('ls -al')
#print(op)

#command = f'kubectl -v 10 {" ".join(sys.argv[1:])}'
command = f'kubectl get {" ".join(sys.argv[1:])} -o json'
print(f'-- {command}')
(op, err) = do(command)

HOME=os.getenv('HOME')
writefile(f'{HOME}/tmp/kubectl-paths.py.op', 'w', str(op))
writefile(f'{HOME}/tmp/kubectl-paths.py.err', 'w', str(err))

#print(op)
json_obj = json.loads( op )
if 'items' in json_obj:
    for item in json_obj['items']:
        print('---')
        dump_resource(item)
else:
    dump_resource( json_obj )

sys.exit(1)


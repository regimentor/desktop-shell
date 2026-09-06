"""Read-only Hyprland IPC summaries; omits titles, addresses and device IDs."""
import json
import os
import socket

socket_path = os.path.join(os.environ['XDG_RUNTIME_DIR'], 'hypr', os.environ['HYPRLAND_INSTANCE_SIGNATURE'], '.socket.sock')

for request in ['j/version', 'j/monitors', 'j/monitors all', 'j/activewindow', 'j/clients', 'j/workspaces']:
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
        connection.settimeout(3)
        connection.connect(socket_path)
        connection.sendall(request.encode())
        parts = []
        while chunk := connection.recv(65536):
            parts.append(chunk)
    response = b''.join(parts).decode()
    try:
        data = json.loads(response)
    except json.JSONDecodeError:
        print(json.dumps({'request': request, 'nonJson': response[:160]}))
        continue
    result = {'request': request, 'type': type(data).__name__}
    if request == 'j/version':
        result['version'] = {key: data.get(key) for key in ['tag', 'version', 'branch', 'commit']}
    elif isinstance(data, list):
        result['count'] = len(data)
        result['keys'] = sorted(data[0]) if data else []
        if 'monitors' in request:
            result['monitors'] = [{key: item.get(key) for key in ['id', 'name', 'focused', 'activeWorkspace']} for item in data]
        elif request == 'j/clients':
            result['monitorIds'] = sorted(set(item.get('monitor', -1) for item in data))
    else:
        result['keys'] = sorted(data)
        result['hasAddress'] = bool(data.get('address'))
    print(json.dumps(result))

"""UDP proxy adding one-way delay + jitter in both directions.
Usage: python3 tools/net/lag_proxy.py LISTEN_PORT SERVER_PORT DELAY_MS JITTER_MS"""
import asyncio, random, sys

listen_port, server_port, delay_ms, jitter_ms = map(int, sys.argv[1:5])

def later(loop, fn):
    d = max(0.0, (delay_ms + random.uniform(-jitter_ms, jitter_ms)) / 1000.0)
    loop.call_later(d, fn)

class ToServer(asyncio.DatagramProtocol):
    def __init__(self, client_addr, front):
        self.client_addr, self.front = client_addr, front
    def connection_made(self, transport):
        self.transport = transport
    def datagram_received(self, data, addr):
        loop = asyncio.get_running_loop()
        later(loop, lambda: self.front.transport.sendto(data, self.client_addr))

class Front(asyncio.DatagramProtocol):
    def __init__(self):
        self.links = {}
    def connection_made(self, transport):
        self.transport = transport
    def datagram_received(self, data, addr):
        loop = asyncio.get_running_loop()
        async def send():
            if addr not in self.links:
                t, p = await loop.create_datagram_endpoint(
                    lambda: ToServer(addr, self), remote_addr=("127.0.0.1", server_port))
                self.links[addr] = p
            self.links[addr].transport.sendto(data)
        later(loop, lambda: asyncio.ensure_future(send()))

async def main():
    loop = asyncio.get_running_loop()
    await loop.create_datagram_endpoint(Front, local_addr=("127.0.0.1", listen_port))
    await asyncio.sleep(3600)

asyncio.run(main())

"""Read the KMDF version from the actual x64 PE, not just build settings."""
import pathlib
import struct
import sys


def get_kmdf_version(data):
    if data[:2] != b'MZ':
        raise ValueError('Driver is not a PE binary')
    pe = struct.unpack_from('<I', data, 60)[0]
    if data[pe:pe + 4] != b'PE\0\0' or struct.unpack_from('<H', data, pe + 4)[0] != 0x8664:
        raise ValueError('Driver must be a native x64 PE')
    count = struct.unpack_from('<H', data, pe + 6)[0]
    optional_size = struct.unpack_from('<H', data, pe + 20)[0]
    image_base = struct.unpack_from('<Q', data, pe + 48)[0]
    name = 'KmdfLibrary\0'.encode('utf-16le')
    name_offset = data.find(name)
    if name_offset < 0:
        raise ValueError('KMDF library name not found')
    for index in range(count):
        section = pe + 24 + optional_size + index * 40
        _, rva, raw_size, raw_offset = struct.unpack_from('<IIII', data, section + 8)
        if raw_offset <= name_offset < raw_offset + raw_size:
            address = image_base + rva + name_offset - raw_offset
            break
    else:
        raise ValueError('Cannot map KMDF library name into the image')
    pointer = struct.pack('<Q', address)
    versions = set()
    for offset in range(8, len(data) - 24, 8):
        if data[offset:offset + 8] == pointer and struct.unpack_from('<I', data, offset - 8)[0] in (48, 88):
            major, minor, build, functions = struct.unpack_from('<IIII', data, offset + 8)
            if major == 1 and functions > 0:
                versions.add((major, minor))
    if len(versions) != 1:
        raise ValueError(f'Expected one KMDF binding version; found {versions}')
    return versions.pop()


if __name__ == '__main__':
    actual = get_kmdf_version(pathlib.Path(sys.argv[1]).read_bytes())
    expected = tuple(map(int, sys.argv[2].split('.')))
    if actual != expected:
        raise SystemExit(f'Incompatible driver: binary requires KMDF {actual}, expected {expected}. Rebuild the driver and DMF.')
    print(f'PASS: native x64 driver actually binds to KMDF {actual[0]}.{actual[1]}')
